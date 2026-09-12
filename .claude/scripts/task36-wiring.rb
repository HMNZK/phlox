#!/usr/bin/env ruby
# task-36 配線検査: AgentConsoleNavigationModel に列挙と選択が集約され、
# 対象 Picker・19 経路・状態ペイン先頭の StatusSummary と CLI 詳細が接続され、
# 既存設定行・reload・messageBar が固定 SHA から欠落していないこと。
ng = []
nav_path = "macos/Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleNavigationModel.swift"
section_path = "macos/App/AgentConsole/AgentConsoleSection.swift"
window_path = "macos/App/AgentConsole/AgentConsoleWindowView.swift"
claude_pane = "macos/App/AgentConsole/Claude/ClaudeStatusPane.swift"
codex_pane = "macos/App/AgentConsole/Codex/CodexStatusPane.swift"
cursor_pane = "macos/App/AgentConsole/Cursor/CursorStatusPane.swift"
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

baseline = ENV["TASK36_BASELINE"]
if baseline.nil? || baseline.empty?
  ng << "TASK36_BASELINE が未設定（HEAD にフォールバックしない）"
  baseline = nil
end

def compact(s)
  s.gsub(/\s+/, "")
end

def strip_comments(src)
  src.gsub(/\/\/[^\n]*/, "")
end

def extract_balanced(src, open_idx, open_ch, close_ch)
  depth = 0
  i = open_idx
  while i < src.length
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

def extract_initializer_body(src)
  m = src.match(/(?:^|\n)[ \t]*(?:private\s+|public\s+|fileprivate\s+|internal\s+)?init\s*\(/)
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

def first_disclosure(src)
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
  { args: args, body: body, before: src[0...m.begin(0)], after: src[close..] }
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
  unless nav_src =~ /\bstruct\s+AgentConsoleStatusSummary\b/
    ng << "AgentConsoleNavigationModel.swift に struct AgentConsoleStatusSummary が無い"
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
    unless ext_c.include?("case.claude:returnDSColor.accent")
      ng << "tint に case .claude: return DSColor.accent が無い"
    end
    unless ext_c.include?("case.codex:returnDSColor.statusCompleted")
      ng << "tint に case .codex: return DSColor.statusCompleted が無い"
    end
    unless ext_c.include?("case.cursor:returnDSColor.statusRunning")
      ng << "tint に case .cursor: return DSColor.statusRunning が無い"
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
    unless side_c.include?(".pickerStyle(.menu)")
      ng << "sidebar に .pickerStyle(.menu) が無い"
    end
    unless side_c.include?('accessibilityIdentifier("agent-console-agent-picker")')
      ng << 'sidebar に accessibilityIdentifier("agent-console-agent-picker") が無い'
    end
    unless side_c.include?("selection:nil")
      ng << "Picker の set が make(..., selection: nil) を呼んでいない"
    end
    unless side_c.include?("AgentConsoleNavigationModel.make(agent:")
      ng << "Picker の set に AgentConsoleNavigationModel.make(agent: が無い"
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
    unless row_c.include?(".accessibilityAddTraits")
      ng << "AgentConsoleSectionRow に .accessibilityAddTraits が無い"
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
    unless msg_c.include?("claude.errorMessage")
      ng << "messageBar に claude.errorMessage が無い"
    end
    unless msg_c.include?("codex.errorMessage")
      ng << "messageBar に codex.errorMessage が無い"
    end
    unless msg_c.include?("cursor.errorMessage")
      ng << "messageBar に cursor.errorMessage が無い"
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

  initializer = extract_initializer_body(window_src)
  if initializer.nil?
    ng << "init の本文を括弧対応で切り出せない"
  else
    init_c = compact(initializer)
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

# --- 状態ペイン ---
status_specs = [
  {
    path: claude_pane,
    name: "ClaudeStatusPane",
    available: "model.isClaudeAvailable",
    config: "model.status.settingsFileExists",
    version_value: "model.status.claudeVersion??\"—\"",
    path_mono: "model.status.claudeExecutablePath",
    extra_needles: [
      "summaryTiles",
      'AgentConsoleStatusSection(title:"設定"',
      'AgentConsoleStatusSection(title:"メモリ"',
      "settings.json",
      "model.status.memoryFiles",
      "model.loadSettings()",
      "model.loadVersion()",
      "model.loadPlugins()",
      "installedPluginCount",
      "marketplaceCount",
      "permissionRuleCount",
      "hookCount",
    ],
  },
  {
    path: codex_pane,
    name: "CodexStatusPane",
    available: "model.isAvailable",
    config: "model.status.configFileExists",
    version_value: "model.status.codexVersion??\"—\"",
    path_mono: "model.status.codexExecutablePath",
    extra_needles: [
      "summaryTiles",
      'AgentConsoleStatusSection(title:"設定"',
      'AgentConsoleStatusSection(title:"メモリ"',
      "config.toml",
      "model.status.memoryFiles",
      "model.loadConfig()",
      "model.loadVersion()",
      "installedPluginCount",
      "mcpServerCount",
      "trustedProjectCount",
    ],
  },
  {
    path: cursor_pane,
    name: "CursorStatusPane",
    available: "model.isAvailable",
    config: "model.status.configFileExists",
    version_value: "model.status.cursorVersion??\"—\"",
    path_mono: "model.status.cursorExecutablePath",
    extra_needles: [
      "summaryTiles",
      'AgentConsoleStatusSection(title:"設定"',
      "cli-config.json",
      "mcp.json",
      "model.loadSettings()",
      "model.loadVersionAndModels()",
      "allowRuleCount",
      "denyRuleCount",
      "mcpServerCount",
      "認証情報とキャッシュは画面に出さず、書き込みでも触りません。",
    ],
  },
]

status_specs.each do |spec|
  unless File.exist?(spec[:path])
    ng << "#{spec[:path]} が存在しない"
    next
  end
  src = strip_comments(File.read(spec[:path]))
  body = extract_struct_body(src, spec[:name])
  if body.nil?
    ng << "#{spec[:name]} の struct 本文を括弧対応で切り出せない"
    next
  end
  body_c = compact(body)

  unless body_c.include?("@StateprivatevarshowsCLIDetails=false") || body_c.include?("@StateprivatevarshowsCLIDetails:Bool=false")
    ng << "#{spec[:name]} に @State private var showsCLIDetails = false が無い"
  end

  make_args = extract_call_args(body, "AgentConsoleStatusSummary.make")
  if make_args.nil?
    ng << "#{spec[:name]} に AgentConsoleStatusSummary.make( が無い"
  else
    make_c = compact(make_args)
    unless make_c.include?("isAvailable:#{spec[:available]}")
      ng << "#{spec[:name]} の make に isAvailable: #{spec[:available]} が無い"
    end
    unless make_c.include?("configFileExists:#{spec[:config]}")
      ng << "#{spec[:name]} の make に configFileExists: #{spec[:config]} が無い"
    end
  end

  %w[
    summary.availabilityText
    summary.availabilityDetail
    summary.configurationText
    summary.configurationDetail
  ].each do |needle|
    ng << "#{spec[:name]} に #{needle} が無い" unless body_c.include?(needle)
  end

  i_avail = body_c.index("summary.availabilityText")
  i_tiles = body_c.index("summaryTiles")
  if i_avail.nil? || i_tiles.nil?
    ng << "#{spec[:name]} の先頭表示順検査に availabilityText / summaryTiles が足りない"
  elsif !(i_avail < i_tiles)
    ng << "#{spec[:name]} で summary.availabilityText が summaryTiles より後にある"
  end

  dg = first_disclosure(body)
  if dg.nil?
    ng << "#{spec[:name]} の DisclosureGroup を括弧対応で切り出せない"
  else
    joined = compact([dg[:args], dg[:body]].compact.join)
    unless compact(dg[:args].to_s).include?("$showsCLIDetails") || joined.include?("isExpanded:$showsCLIDetails")
      ng << "#{spec[:name]} の DisclosureGroup に isExpanded: $showsCLIDetails が無い"
    end
    unless compact(dg[:args].to_s).include?("summary.cliDetailsTitle") || compact(dg[:body]).include?("summary.cliDetailsTitle")
      ng << "#{spec[:name]} の DisclosureGroup に summary.cliDetailsTitle が無い"
    end
    dg_c = compact(dg[:body])
    unless dg_c.include?('label:"バージョン"')
      ng << "#{spec[:name]} の DisclosureGroup 内に label: \"バージョン\" が無い"
    end
    unless dg_c.include?('label:"実行ファイル"')
      ng << "#{spec[:name]} の DisclosureGroup 内に label: \"実行ファイル\" が無い"
    end
    unless dg_c.include?(spec[:version_value])
      ng << "#{spec[:name]} の DisclosureGroup 内に #{spec[:version_value]} が無い"
    end
    unless dg_c.include?(spec[:path_mono])
      ng << "#{spec[:name]} の DisclosureGroup 内に #{spec[:path_mono]} が無い"
    end
    outside = compact(dg[:before].to_s + dg[:after].to_s)
    if outside.include?('label:"バージョン"') || outside.include?('AgentConsoleStatusSection(title:"CLI"')
      ng << "#{spec[:name]} で CLI の 2 行が DisclosureGroup の外にも残っている"
    end
  end

  spec[:extra_needles].each do |needle|
    ng << "#{spec[:name]} に #{needle} が無い" unless body_c.include?(compact(needle)) || body.include?(needle)
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
      prev_detail = extract_var_body(prev_src, "detail")
      cur_detail = File.exist?(window_path) ? extract_var_body(strip_comments(File.read(window_path)), "detail") : nil
      if prev_detail.nil? || cur_detail.nil?
        ng << "baseline または HEAD の detail switch を切り出せない"
      else
        prev_map = switch_case_mappings(prev_detail)
        cur_map = switch_case_mappings(cur_detail)
        unless prev_map.map { |sid, pane, args| [sid, pane, args] } == cur_map.map { |sid, pane, args| [sid, pane, args] }
          ng << "detail switch の 19 case→Pane→引数が #{baseline} から変化している"
        end
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
