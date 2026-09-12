#!/usr/bin/env ruby
# task-36 配線検査: AgentConsoleNavigationModel に列挙と選択が集約され、
# 対象 Picker・19 経路が接続され、reload / init / .task / messageBar が
# TASK36_BASELINE（task-35 完了後 SHA）から欠落していないこと。

def compact(s)
  s.gsub(/\s+/, "")
end

def index_after_string(src, i)
  return i + 1 if i >= src.length
  if src[i, 3] == '"""'
    j = i + 3
    while j < src.length
      return j + 3 if src[j, 3] == '"""'
      j += 1
    end
    return src.length
  end
  return i unless src[i] == '"'
  j = i + 1
  while j < src.length
    if src[j] == "\\"
      j += 2
      next
    end
    return j + 1 if src[j] == '"'
    j += 1
  end
  src.length
end

def protect_strings(src)
  out = +""
  strings = []
  i = 0
  while i < src.length
    if src[i, 3] == '"""' || src[i] == '"'
      j = index_after_string(src, i)
      strings << src[i...j]
      out << "__STR#{strings.length - 1}__"
      i = j
    else
      out << src[i]
      i += 1
    end
  end
  [out, strings]
end

def restore_strings(src, strings)
  src.gsub(/__STR(\d+)__/) { strings[Regexp.last_match(1).to_i] }
end

def strip_comments(src)
  protected, strings = protect_strings(src)
  protected = protected.gsub(%r{/\*.*?\*/}m, "")
  protected = protected.gsub(%r{//[^\n]*}, "")
  restore_strings(protected, strings)
end

def extract_balanced(src, open_idx, open_ch, close_ch)
  depth = 0
  i = open_idx
  while i < src.length
    if src[i, 3] == '"""' || src[i] == '"'
      i = index_after_string(src, i)
      next
    end
    case src[i]
    when open_ch then depth += 1
    when close_ch
      depth -= 1
      return src[(open_idx + 1)...i] if depth == 0
    end
    i += 1
  end
  nil
end

def extract_struct_body(src, name)
  m = src.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?struct\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_func_body(src, name)
  m = src.match(/(?:^|\n)[ \t]*(?:@\w+[ \t]*)*(?:private\s+|public\s+|fileprivate\s+|internal\s+)?(?:static\s+)?func\s+#{Regexp.escape(name)}\s*\(/)
  return nil unless m
  paren = src.index("(", m.begin(0))
  return nil unless paren
  params = extract_balanced(src, paren, "(", ")")
  return nil if params.nil?
  after = paren + 1 + params.length + 1
  brace = src.index("{", after)
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_var_body(src, name)
  m = src.match(/(?:^|\n)[ \t]*(?:@[A-Za-z_][\w.]*[ \t]*)*(?:private\s+|public\s+|fileprivate\s+|internal\s+)?(?:static\s+)?var\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.end(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_extension_body(src, name)
  m = src.match(/\bextension\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_call_args(src, callee)
  m = src.match(/#{Regexp.escape(callee)}\s*\(/)
  return nil unless m
  extract_balanced(src, m.end(0) - 1, "(", ")")
end

def extract_init(src)
  m = src.match(/(?:^|\n)[ \t]*(?:private\s+|public\s+|fileprivate\s+|internal\s+)?init\s*\(/)
  return nil unless m
  paren = src.index("(", m.begin(0))
  return nil unless paren
  params = extract_balanced(src, paren, "(", ")")
  return nil if params.nil?
  after = paren + 1 + params.length + 1
  brace = src.index("{", after)
  return nil unless brace
  body = extract_balanced(src, brace, "{", "}")
  return nil if body.nil?
  { params: params, body: body }
end

def git_show(rev, path)
  text = IO.popen(["git", "show", "#{rev}:#{path}"], err: [:child, :out], &:read)
  return text if $?.success?
  nil
end

def git_unchanged?(rev, path)
  system("git", "diff", "--quiet", rev, "--", path)
end

def count_enum(root, name)
  n = 0
  Dir.glob(File.join(root, "**", "*.swift")).each do |path|
    src = strip_comments(File.read(path))
    n += src.scan(/\benum\s+#{Regexp.escape(name)}\b/).size
  end
  n
end

def switch_case_mappings(switch_body)
  mappings = []
  pos = 0
  while (m = switch_body.match(/case\s+\.(\w+)\s*:/, pos))
    after = m.end(0)
    nxt = switch_body.index(/case\s+\./, after) || switch_body.length
    chunk = switch_body[after...nxt]
    pane_m = chunk.match(/\b([A-Z][A-Za-z0-9]*)\s*\(/)
    pane = pane_m && pane_m[1]
    args = nil
    if pane_m
      args = extract_balanced(chunk, pane_m.end(0) - 1, "(", ")")
    end
    mappings << [m[1], pane, args && compact(args)]
    pos = after
  end
  mappings
end

def message_bar_case_bindings(switch_body)
  mappings = []
  pos = 0
  while (m = switch_body.match(/case\s+\.(\w+)\s*:/, pos))
    after = m.end(0)
    nxt = switch_body.index(/case\s+\./, after) || switch_body.length
    chunk_c = compact(switch_body[after...nxt])
    error = chunk_c[/error:([A-Za-z0-9_.]+)/, 1]
    info = chunk_c[/info:([A-Za-z0-9_.]+)/, 1]
    dismiss = chunk_c[/\{([A-Za-z0-9_.]+)\(\)\}/, 1]
    mappings << [m[1], error, info, dismiss]
    pos = after
  end
  mappings
end

def parse_disclosure(src)
  m = src.match(/\bDisclosureGroup\b/)
  return nil unless m
  i = m.end(0)
  i += 1 while i < src.length && src[i] =~ /\s/
  args = nil
  if src[i] == "("
    args = extract_balanced(src, i, "(", ")")
    return nil if args.nil?
    i = i + 1 + args.length + 1
  end
  i += 1 while i < src.length && src[i] =~ /\s/
  return nil unless src[i] == "{"
  body = extract_balanced(src, i, "{", "}")
  return nil if body.nil?
  close = i + 1 + body.length + 1
  j = close
  j += 1 while j < src.length && src[j] =~ /\s/
  label_body = nil
  rest = src[j..]
  if rest && rest.start_with?("label:")
    k = src.index(":", j) + 1
    k += 1 while k < src.length && src[k] =~ /\s/
    if src[k] == "{"
      label_body = extract_balanced(src, k, "{", "}")
      close = k + 1 + label_body.length + 1 if label_body
    end
  end
  { args: args, body: body, label: label_body, before: src[0...m.begin(0)], after: src[close..] }
end

def has_case_value(src_c, case_name, value)
  src_c.include?("case.#{case_name}:return#{value}") || src_c.include?("case.#{case_name}:#{value}")
end

def picker_set_assignment?(src)
  compact(src).include?("selection=AgentConsoleNavigationModel.make(agent:newAgent,selection:nil).selectedSection")
end

def traits_include_is_selected?(src)
  args = extract_call_args(src, ".accessibilityAddTraits") || extract_call_args(src, "accessibilityAddTraits")
  args && args.include?(".isSelected")
end

def menu_picker_style?(src)
  c = compact(src)
  c.include?(".pickerStyle(.menu)") || c.include?(".pickerStyle(MenuPickerStyle())")
end

def selftest_assert(cond, msg)
  unless cond
    puts "task36-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def run_selftest
  url = %(let url = "https://example.com" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://example.com"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert !strip_comments("let a = 1 /* x */ let b = 2").include?("x"), "正例: /* */ を除去する"

  good_set = <<~SWIFT
    Picker(navigation.agentPickerLabel, selection: Binding(
      get: { navigation.agent },
      set: { newAgent in
        selection = AgentConsoleNavigationModel.make(agent: newAgent, selection: nil).selectedSection
      }
    ))
  SWIFT
  selftest_assert picker_set_assignment?(good_set), "正例: Picker set が selectedSection を代入する"

  discarded = <<~SWIFT
    set: { newAgent in
      AgentConsoleNavigationModel.make(agent: newAgent, selection: nil)
    }
  SWIFT
  selftest_assert !picker_set_assignment?(discarded), "負例: make の結果を捨てる"

  good_traits = '.accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)'
  selftest_assert traits_include_is_selected?(good_traits), "正例: .isSelected を含む条件式"
  selftest_assert !traits_include_is_selected?(".accessibilityAddTraits(.isButton)"), "負例: .isButton だけ"

  selftest_assert menu_picker_style?(".pickerStyle(.menu)"), "正例: .pickerStyle(.menu)"
  selftest_assert menu_picker_style?(".pickerStyle(MenuPickerStyle())"), "正例: MenuPickerStyle()"
  selftest_assert !menu_picker_style?(".pickerStyle(.segmented)"), "負例: segmented"

  dg = parse_disclosure(<<~SWIFT)
    DisclosureGroup(isExpanded: $showsCLIDetails) {
      Text("version")
    } label: {
      Text(summary.cliDetailsTitle)
    }
  SWIFT
  selftest_assert !dg.nil?, "正例: DisclosureGroup(isExpanded:) { } label: { } を切り出せる"
  selftest_assert compact(dg[:args].to_s).include?("$showsCLIDetails"), "正例: isExpanded を読む"
  selftest_assert compact(dg[:label].to_s).include?("summary.cliDetailsTitle"), "正例: label クロージャを読む"

  tint = compact(<<~SWIFT)
    switch self {
    case .claude: DSColor.accent
    case .codex: DSColor.statusCompleted
    case .cursor: DSColor.statusRunning
    }
  SWIFT
  selftest_assert has_case_value(tint, "claude", "DSColor.accent"), "正例: return 省略 switch"
  with_return = compact("case .claude: return DSColor.accent")
  selftest_assert has_case_value(with_return, "claude", "DSColor.accent"), "正例: return 付き switch"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task36-wiring --selftest: OK"
  exit 0
end

ng = []
nav_path = "macos/Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleNavigationModel.swift"
section_path = "macos/App/AgentConsole/AgentConsoleSection.swift"
window_path = "macos/App/AgentConsole/AgentConsoleWindowView.swift"
settings_path = "macos/App/SettingsView.swift"
custom_path = "macos/Packages/AgentDomain/Sources/AgentDomain/CustomAgentDefinition.swift"
composition_path = "macos/App/CompositionRoot.swift"

DETAIL_CASES = [
  ["claudeStatus", "ClaudeStatusPane", "model:claude"],
  ["claudePlugins", "ClaudePluginsPane", "model:claude"],
  ["claudeSkills", "ClaudeSkillsPane", "model:claude"],
  ["claudePermissions", "ClaudePermissionsPane", "model:claude"],
  ["claudeMemory", "ClaudeMemoryPane", "model:claude"],
  ["claudeHooks", "ClaudeHooksPane", "model:claude"],
  ["claudeStatusLine", "ClaudeStatusLinePane", "model:claude"],
  ["claudeOutputStyle", "ClaudeOutputStylePane", "model:claude"],
  ["codexStatus", "CodexStatusPane", "model:codex"],
  ["codexSettings", "CodexSettingsPane", "model:codex"],
  ["codexPlugins", "CodexPluginsPane", "model:codex"],
  ["codexMCP", "CodexMCPPane", "model:codex"],
  ["codexMemory", "CodexMemoryPane", "model:codex"],
  ["codexTrust", "CodexTrustPane", "model:codex"],
  ["cursorStatus", "CursorStatusPane", "model:cursor"],
  ["cursorPermissions", "CursorPermissionsPane", "model:cursor"],
  ["cursorModel", "CursorModelPane", "model:cursor"],
  ["cursorMCP", "CursorMCPPane", "model:cursor"],
  ["cursorSettings", "CursorSettingsPane", "model:cursor"],
]

EXPECTED_MESSAGE_BAR = [
  ["claude", "claude.errorMessage", "claude.infoMessage", "claude.clearMessages"],
  ["codex", "codex.errorMessage", "codex.infoMessage", "codex.clearMessages"],
  ["cursor", "cursor.errorMessage", "cursor.infoMessage", "cursor.clearMessages"],
]

UNCHANGED_PATHS = [
  settings_path,
  custom_path,
  composition_path,
  "macos/App/AgentConsole/Claude/ClaudeConsoleModel.swift",
  "macos/App/AgentConsole/Codex/CodexConsoleModel.swift",
  "macos/App/AgentConsole/Cursor/CursorConsoleModel.swift",
  "macos/App/AgentConsole/Claude/ClaudePluginsPane.swift",
  "macos/App/AgentConsole/Claude/ClaudeSkillsPane.swift",
  "macos/App/AgentConsole/Claude/ClaudePermissionsPane.swift",
  "macos/App/AgentConsole/Claude/ClaudeMemoryPane.swift",
  "macos/App/AgentConsole/Claude/ClaudeHooksPane.swift",
  "macos/App/AgentConsole/Claude/ClaudeStatusLinePane.swift",
  "macos/App/AgentConsole/Claude/ClaudeOutputStylePane.swift",
  "macos/App/AgentConsole/Codex/CodexSettingsPane.swift",
  "macos/App/AgentConsole/Codex/CodexPluginsPane.swift",
  "macos/App/AgentConsole/Codex/CodexMCPPane.swift",
  "macos/App/AgentConsole/Codex/CodexMemoryPane.swift",
  "macos/App/AgentConsole/Codex/CodexTrustPane.swift",
  "macos/App/AgentConsole/Cursor/CursorPermissionsPane.swift",
  "macos/App/AgentConsole/Cursor/CursorModelPane.swift",
  "macos/App/AgentConsole/Cursor/CursorMCPPane.swift",
  "macos/App/AgentConsole/Cursor/CursorSettingsPane.swift",
]

TASK_SNIPPET = ".task(id:claudeExecutablePath){awaitreload()}"

baseline = ENV["TASK36_BASELINE"]
if baseline.nil? || baseline.empty?
  ng << "TASK36_BASELINE が未設定（HEAD にフォールバックしない）"
  baseline = nil
end

# --- 列挙の所在 ---
kit_root = "macos/Packages/AgentConfigKit/Sources"
app_root = "macos/App"
agent_enum_kit = File.exist?(kit_root) ? count_enum(kit_root, "AgentConsoleAgent") : 0
section_enum_kit = File.exist?(kit_root) ? count_enum(kit_root, "AgentConsoleSection") : 0
agent_enum_app = File.exist?(app_root) ? count_enum(app_root, "AgentConsoleAgent") : 0
section_enum_app = File.exist?(app_root) ? count_enum(app_root, "AgentConsoleSection") : 0
ng << "AgentConfigKit の enum AgentConsoleAgent が #{agent_enum_kit} 個（期待 1）" unless agent_enum_kit == 1
ng << "AgentConfigKit の enum AgentConsoleSection が #{section_enum_kit} 個（期待 1）" unless section_enum_kit == 1
ng << "App 側に enum AgentConsoleAgent が残っている" unless agent_enum_app == 0
ng << "App 側に enum AgentConsoleSection が残っている" unless section_enum_app == 0

# --- NavigationModel.swift ---
unless File.exist?(nav_path)
  ng << "#{nav_path} が存在しない"
else
  nav_src = strip_comments(File.read(nav_path))
  nav_c = compact(nav_src)
  ng << "AgentConsoleNavigationModel.swift が SwiftUI を import している" if nav_src =~ /^\s*import\s+SwiftUI\b/
  ng << "AgentConsoleNavigationModel.swift が AppKit を import している" if nav_src =~ /^\s*import\s+AppKit\b/
  ng << "AgentConsoleNavigationModel.swift に Color がある" if nav_src =~ /\bColor\b/
  ng << "AgentConsoleNavigationModel.swift に View がある" if nav_src =~ /\bView\b/
  ng << "AgentConsoleNavigationModel.swift に Observable がある" if nav_src =~ /\bObservable\b/
  ng << "AgentConsoleNavigationModel.swift に @State がある" if nav_src =~ /@State\b/
  ng << "AgentConsoleNavigationModel.swift に UserDefaults がある" if nav_src =~ /\bUserDefaults\b/
  ng << "AgentConsoleNavigationModel.swift に FileManager がある" if nav_src =~ /\bFileManager\b/
  ng << "AgentConsoleNavigationModel.swift に Process がある" if nav_src =~ /\bProcess\b/
  unless nav_src =~ /\bstruct\s+AgentConsoleNavigationModel\b/
    ng << "AgentConsoleNavigationModel.swift に struct AgentConsoleNavigationModel が無い"
  end
  unless nav_src =~ /\bstatic\s+func\s+make\s*\(\s*agent\s*:/
    ng << "AgentConsoleNavigationModel.swift に static func make(agent: が無い"
  end
end

# --- App 側 tint extension ---
unless File.exist?(section_path)
  ng << "#{section_path} が存在しない"
else
  section_src = strip_comments(File.read(section_path))
  unless section_src =~ /^\s*import\s+AgentConfigKit\b/
    ng << "AgentConsoleSection.swift が AgentConfigKit を import していない"
  end
  ext = extract_extension_body(section_src, "AgentConsoleAgent")
  if ext.nil?
    ng << "AgentConsoleSection.swift に extension AgentConsoleAgent が無い"
  else
    ext_c = compact(ext)
    unless has_case_value(ext_c, "claude", "DSColor.accent")
      ng << "tint に case .claude: DSColor.accent が無い"
    end
    unless has_case_value(ext_c, "codex", "DSColor.statusCompleted")
      ng << "tint に case .codex: DSColor.statusCompleted が無い"
    end
    unless has_case_value(ext_c, "cursor", "DSColor.statusRunning")
      ng << "tint に case .cursor: DSColor.statusRunning が無い"
    end
  end
end

# --- WindowView ---
unless File.exist?(window_path)
  ng << "#{window_path} が存在しない"
else
  window = File.read(window_path)
  window_src = strip_comments(window)
  window_c = compact(window_src)

  unless window_c.include?("AgentConsoleNavigationModel.make(agent:selection?.agent??.claude,selection:selection)")
    ng << "WindowView に AgentConsoleNavigationModel.make(agent: selection?.agent ?? .claude, selection: selection) が無い"
  end

  ng << "WindowView に独立した selectedAgent 状態がある" if window_src =~ /\bselectedAgent\b/
  ng << "WindowView に agentGroup が残っている" if window_src =~ /\bagentGroup\b/
  ng << "WindowView に AgentConsoleSection.sections(for: が残っている" if window_c.include?("AgentConsoleSection.sections(for:")

  unless window_c.include?(TASK_SNIPPET)
    ng << "WindowView に .task(id: claudeExecutablePath) { await reload() } が無い"
  end

  sidebar = extract_var_body(window_src, "sidebar")
  if sidebar.nil?
    ng << "sidebar の本文を括弧対応で切り出せない"
  else
    side_c = compact(sidebar)
    unless side_c.include?("ForEach(navigation.sections)")
      ng << "sidebar に ForEach(navigation.sections) が無い"
    end
    unless side_c.include?("Picker(")
      ng << "sidebar に Picker( が無い"
    end
    unless side_c.include?("navigation.agentPickerLabel")
      ng << "sidebar に navigation.agentPickerLabel が無い"
    end
    unless side_c.include?("AgentConsoleAgent.allCases")
      ng << "sidebar に AgentConsoleAgent.allCases が無い"
    end
    unless menu_picker_style?(sidebar)
      ng << "sidebar に .pickerStyle(.menu) も .pickerStyle(MenuPickerStyle()) も無い"
    end
    unless side_c.include?('accessibilityIdentifier("agent-console-agent-picker")')
      ng << 'sidebar に accessibilityIdentifier("agent-console-agent-picker") が無い'
    end
    unless picker_set_assignment?(sidebar)
      ng << "Picker の set が selection = AgentConsoleNavigationModel.make(agent: newAgent, selection: nil).selectedSection ではない"
    end
    unless side_c.include?("navigation.selectedSection==section") || side_c.include?("section==navigation.selectedSection")
      ng << "sidebar に navigation.selectedSection == section が無い"
    end
    unless side_c.include?("selection=section")
      ng << "sidebar に selection = section が無い"
    end
  end

  row = extract_struct_body(window_src, "AgentConsoleSectionRow")
  if row.nil?
    ng << "AgentConsoleSectionRow の struct 本文を括弧対応で切り出せない"
  else
    row_c = compact(row)
    unless row_c.include?("Text(section.title)")
      ng << "AgentConsoleSectionRow に Text(section.title) が無い"
    end
    unless row_c.include?(".help(section.detail)")
      ng << "AgentConsoleSectionRow に .help(section.detail) が無い"
    end
    if row_c.include?("Text(section.detail)")
      ng << "AgentConsoleSectionRow に常時表示の Text(section.detail) が残っている"
    end
    unless traits_include_is_selected?(row)
      ng << "AgentConsoleSectionRow の .accessibilityAddTraits に .isSelected が無い"
    end
    unless row.include?('accessibilityIdentifier("agent-console-section-\\(section.rawValue)")')
      ng << 'AgentConsoleSectionRow に accessibilityIdentifier("agent-console-section-\\(section.rawValue)") が無い'
    end
  end

  unless window_c.include?("Text(navigation.locationText)")
    ng << "WindowView に Text(navigation.locationText) が無い"
  end
  unless window_c.include?('accessibilityIdentifier("agent-console-location")')
    ng << 'WindowView に accessibilityIdentifier("agent-console-location") が無い'
  end

  detail = extract_var_body(window_src, "detail")
  if detail.nil?
    ng << "detail の本文を括弧対応で切り出せない"
  else
    unless compact(detail).include?("switchnavigation.selectedSection") || detail =~ /\bswitch\s+navigation\.selectedSection\b/
      ng << "detail の switch が navigation.selectedSection ではない"
    end
    mappings = switch_case_mappings(detail)
    if mappings.size != 19
      ng << "detail switch の case 数が #{mappings.size}（期待 19）"
    end
    DETAIL_CASES.each_with_index do |(sid, pane, model_arg), i|
      got = mappings[i]
      if got.nil?
        ng << "detail switch の #{i} 番目 case .#{sid} が無い"
        next
      end
      ng << "detail switch の #{i} 番目が case .#{got[0]}（期待 .#{sid}）" unless got[0] == sid
      ng << "detail switch の .#{sid} の Pane が #{got[1].inspect}（期待 #{pane}）" unless got[1] == pane
      unless got[2] && got[2].include?(model_arg)
        ng << "detail switch の .#{sid} の引数が #{got[2].inspect}（期待 #{model_arg}）"
      end
    end
  end

  message = extract_var_body(window_src, "messageBar")
  if message.nil?
    ng << "messageBar の本文を括弧対応で切り出せない"
  else
    msg_c = compact(message)
    unless message =~ /\bswitch\s+navigation\.agent\b/ || msg_c.include?("switchnavigation.agent")
      ng << "messageBar の switch が navigation.agent ではない"
    end
    got_bar = message_bar_case_bindings(message)
    unless got_bar == EXPECTED_MESSAGE_BAR
      ng << "messageBar の case ごとの error/info/dismiss が #{got_bar.inspect}（期待 #{EXPECTED_MESSAGE_BAR.inspect}）"
    end
  end

  banner = extract_func_body(window_src, "banner")
  if banner.nil?
    ng << "banner の本文を括弧対応で切り出せない"
  else
    unless compact(banner).include?("isError:true")
      ng << "banner に isError: true が無い"
    end
  end

  reload = extract_func_body(window_src, "reload")
  if reload.nil?
    ng << "reload の本文を括弧対応で切り出せない"
  else
    rel_c = compact(reload)
    unless rel_c.include?("claude.loadSettings()")
      ng << "reload に claude.loadSettings() が無い"
    end
    unless rel_c.include?("codex.loadConfig()")
      ng << "reload に codex.loadConfig() が無い"
    end
    unless rel_c.include?("cursor.loadSettings()")
      ng << "reload に cursor.loadSettings() が無い"
    end
  end

  initializer = extract_init(window_src)
  if initializer.nil?
    ng << "init の引数・本文を括弧対応で切り出せない"
  else
    init_c = compact(initializer[:body])
    unless compact(initializer[:params]).include?("claudeExecutablePath:String?")
      ng << "init 引数に claudeExecutablePath: String? が無い"
    end
    unless compact(initializer[:params]).include?("pathEnvironment:String")
      ng << "init 引数に pathEnvironment: String が無い"
    end
    unless compact(initializer[:params]).include?("projectDirectory:URL?")
      ng << "init 引数に projectDirectory: URL? が無い"
    end
    unless init_c.include?("ClaudeConsoleModel(")
      ng << "init に ClaudeConsoleModel( が無い"
    end
    unless init_c.include?("CodexConsoleModel(")
      ng << "init に CodexConsoleModel( が無い"
    end
    unless init_c.include?("CursorConsoleModel(")
      ng << "init に CursorConsoleModel( が無い"
    end
  end
end

# --- 固定 SHA ---
if baseline
  UNCHANGED_PATHS.each do |path|
    unless git_unchanged?(baseline, path)
      ng << "#{path} が #{baseline} から差分あり"
    end
  end

  if File.exist?(window_path)
    previous = git_show(baseline, window_path)
    if previous.nil?
      ng << "git show #{baseline}:#{window_path} に失敗"
    else
      prev_src = strip_comments(previous)
      cur_src = strip_comments(File.read(window_path))

      prev_detail = extract_var_body(prev_src, "detail")
      cur_detail = extract_var_body(cur_src, "detail")
      if prev_detail.nil? || cur_detail.nil?
        ng << "baseline または HEAD の detail switch を切り出せない"
      else
        prev_map = switch_case_mappings(prev_detail)
        cur_map = switch_case_mappings(cur_detail)
        unless prev_map.map { |sid, pane, args| [sid, pane, args] } == cur_map.map { |sid, pane, args| [sid, pane, args] }
          ng << "detail switch の 19 case→Pane→引数が #{baseline} から変化している"
        end
      end

      prev_reload = extract_func_body(prev_src, "reload")
      cur_reload = extract_func_body(cur_src, "reload")
      if prev_reload.nil? || cur_reload.nil?
        ng << "baseline または HEAD の reload 本文を切り出せない"
      elsif compact(prev_reload) != compact(cur_reload)
        ng << "reload 本文が #{baseline} から変化している"
      end

      prev_init = extract_init(prev_src)
      cur_init = extract_init(cur_src)
      if prev_init.nil? || cur_init.nil?
        ng << "baseline または HEAD の init を切り出せない"
      elsif compact(prev_init[:params]) != compact(cur_init[:params]) || compact(prev_init[:body]) != compact(cur_init[:body])
        ng << "init 引数または本文が #{baseline} から変化している"
      end

      unless compact(prev_src).include?(TASK_SNIPPET) && compact(cur_src).include?(TASK_SNIPPET)
        ng << ".task(id: claudeExecutablePath) { await reload() } が #{baseline} または HEAD に無い"
      end

      prev_message = extract_var_body(prev_src, "messageBar")
      cur_message = extract_var_body(cur_src, "messageBar")
      if prev_message.nil? || cur_message.nil?
        ng << "baseline または HEAD の messageBar を切り出せない"
      elsif message_bar_case_bindings(prev_message) != message_bar_case_bindings(cur_message)
        ng << "messageBar の case ごとの error/info/dismiss が #{baseline} から変化している"
      end
    end
  end
end

if ng.empty?
  puts "task36-wiring: OK"
else
  ng.each { |m| puts "task36-wiring: NG #{m}" }
  exit 1
end
