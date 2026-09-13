#!/usr/bin/env ruby
# task-50 配線検査: 権限説明が UIWording+Permissions 正本へ接続され、
# App の各権限ペインと ComposerSettingsControls の直書き説明文が置換され、
# Binding / tag / 既定値 / action / 起動引数 / task-48 一般文言は
# TASK50_BASELINE から変わらないこと。
# コメントと文字列は同時識別する（task48-wiring.rb / task43-wiring.rb と同じ字句走査）。
# 比較対象は git show <TASK50_BASELINE>:<path> と作業ファイル。HEAD blob は使わない。

def compact(s)
  s.gsub(/\s+/, "")
end

def skip_block_comment(src, i)
  depth = 1
  j = i + 2
  while j < src.length
    if src[j, 2] == "/*"
      depth += 1
      j += 2
    elsif src[j, 2] == "*/"
      depth -= 1
      j += 2
      return j if depth == 0
    else
      j += 1
    end
  end
  src.length
end

def skip_interpolation(src, open_paren_idx)
  depth = 0
  i = open_paren_idx
  while i < src.length
    n = comment_or_string_end(src, i)
    if n
      i = n
      next
    end
    case src[i]
    when "(" then depth += 1
    when ")"
      depth -= 1
      return i + 1 if depth == 0
    end
    i += 1
  end
  src.length
end

def index_after_string(src, i)
  return i + 1 if i >= src.length
  if src[i, 3] == '"""'
    return skip_string_content(src, i + 3, true)
  end
  return i unless src[i] == '"'
  skip_string_content(src, i + 1, false)
end

def skip_string_content(src, j, triple)
  while j < src.length
    if triple && src[j, 3] == '"""'
      return j + 3
    end
    if !triple && src[j] == '"'
      return j + 1
    end
    if src[j] == "\\"
      if j + 1 < src.length && src[j + 1] == "("
        j = skip_interpolation(src, j + 1)
        next
      end
      j += 2
      next
    end
    j += 1
  end
  src.length
end

def comment_or_string_end(src, i)
  return nil if i >= src.length
  if src[i, 2] == "//"
    j = i + 2
    j += 1 while j < src.length && src[j] != "\n"
    return j
  end
  return skip_block_comment(src, i) if src[i, 2] == "/*"
  return index_after_string(src, i) if src[i, 3] == '"""' || src[i] == '"'
  nil
end

def each_lexeme(src)
  i = 0
  code_start = nil
  flush_code = lambda do
    if code_start
      yield :code, code_start, i
      code_start = nil
    end
  end
  while i < src.length
    n = comment_or_string_end(src, i)
    if n
      flush_code.call
      kind = (src[i, 2] == "//" || src[i, 2] == "/*") ? :comment : :string
      yield kind, i, n
      i = n
    else
      code_start ||= i
      i += 1
    end
  end
  flush_code.call
end

def protect_strings(src)
  out = +""
  strings = []
  each_lexeme(src) do |kind, a, b|
    if kind == :string
      strings << src[a...b]
      out << "__STR#{strings.length - 1}__"
    else
      out << src[a...b]
    end
  end
  [out, strings]
end

def restore_strings(src, strings)
  src.gsub(/__STR(\d+)__/) { strings[Regexp.last_match(1).to_i] }
end

def strip_comments(src)
  out = +""
  each_lexeme(src.to_s) do |kind, a, b|
    out << src[a...b] unless kind == :comment
  end
  out
end

def mask_strings_and_comments(src)
  out = +""
  each_lexeme(src.to_s) do |kind, a, b|
    case kind
    when :code then out << src[a...b]
    when :string then out << (" " * (b - a))
    end
  end
  out
end

def normalize_code(src)
  stripped = strip_comments(src)
  protected, strings = protect_strings(stripped)
  restore_strings(protected.gsub(/\s+/, ""), strings)
end

def extract_balanced(src, open_idx, open_ch, close_ch)
  depth = 0
  i = open_idx
  while i < src.length
    n = comment_or_string_end(src, i)
    if n
      i = (n > i) ? n : i + 1
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

def skip_ws(src, i)
  i += 1 while i < src.length && src[i] =~ /\s/
  i
end

def extract_struct_body(src, name)
  m = src.to_s.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?struct\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_enum_body(src, name)
  m = src.to_s.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?enum\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_func_body(src, name)
  m = src.to_s.match(/(?:^|\n)[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]*)*(?:(?:private|public|fileprivate|internal|open|override|final|static|nonisolated)\s+)*func\s+#{Regexp.escape(name)}\s*\(/)
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

def extract_func_params(src, name)
  m = src.to_s.match(/(?:^|\n)[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]*)*(?:(?:private|public|fileprivate|internal|open|override|final|static|nonisolated)\s+)*func\s+#{Regexp.escape(name)}\s*\(/)
  return nil unless m
  paren = src.index("(", m.begin(0))
  return nil unless paren
  extract_balanced(src, paren, "(", ")")
end

def extract_var_body(src, name)
  m = src.to_s.match(/(?:^|\n)[ \t]*(?:@[A-Za-z_][\w.]*[ \t]*)*(?:private\s+|public\s+|fileprivate\s+|internal\s+)?(?:static\s+)?var\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  i = skip_ws(src, m.end(0))
  if i < src.length && src[i] == ":"
    depth_a = 0
    depth_p = 0
    while i < src.length
      n = comment_or_string_end(src, i)
      if n
        i = n
        next
      end
      break if depth_a == 0 && depth_p == 0 && (src[i] == "{" || src[i] == "=" || src[i] == "\n")
      depth_a += 1 if src[i] == "<"
      depth_a -= 1 if src[i] == ">"
      depth_p += 1 if src[i] == "("
      depth_p -= 1 if src[i] == ")"
      i += 1
    end
    i = skip_ws(src, i)
  end
  return nil unless i < src.length && src[i] == "{"
  extract_balanced(src, i, "{", "}")
end

def extract_call_args(src, callee)
  m = src.to_s.match(/#{Regexp.escape(callee)}\s*\(/)
  return nil unless m
  extract_balanced(src, m.end(0) - 1, "(", ")")
end

def git_show(rev, path)
  text = IO.popen(["git", "show", "#{rev}:#{path}"], err: [:child, :out], &:read)
  return text if $?.success?
  nil
end

def git_full_sha(rev)
  text = IO.popen(["git", "rev-parse", "--verify", "#{rev}^{commit}"], err: [:child, :out], &:read)
  return text.strip if $?.success?
  nil
end

def git_is_ancestor?(anc, desc)
  system("git", "merge-base", "--is-ancestor", anc, desc, out: File::NULL, err: File::NULL)
end

def workdir_matches_git_blob?(workdir_text, git_blob)
  return false if git_blob.nil? || workdir_text.nil?
  workdir_text == git_blob
end

def read_if_exist(path)
  File.exist?(path) ? File.read(path) : nil
end

def erase_if_false(src)
  result = src.dup
  loop do
    m = result.match(/\bif\s*\(\s*false\s*\)\s*\{/) || result.match(/\bif\s+false\s*\{/)
    break unless m
    brace = result.index("{", m.begin(0))
    break unless brace
    body = extract_balanced(result, brace, "{", "}")
    break if body.nil?
    close = brace + 1 + body.length + 1
    result = result[0...m.begin(0)] + result[close..]
  end
  result.gsub(/#if\s+false\b.*?#endif/m, "")
end

SWIFTUI_SKIP = %w[
  Form Section Text Label Toggle Picker Button ForEach TabView Binding Image Link
  LabeledContent Color View EmptyView Spacer Divider Group VStack HStack ZStack
  Tab Item TextField Bool String Int Double Optional true false nil some any body
  Task URL Bundle GeometryReader RoundedRectangle Circle Capsule Overlay alignment
  ChatComposerFooter IMESafeTextView TeamComposerTextInput DSFont DSColor DSSpacing
  DSRadius Menu Image SettingsMenuRow ComposerControlChip HoverableComposerControl
  DisclosureCard ScrollView Locale language languageCode identifier
].freeze

def code_idents(src)
  mask_strings_and_comments(src.to_s).scan(/\b([A-Za-z_][A-Za-z0-9_]*)\b/).flatten.uniq
end

def collect_reachable(src, start_blob, skip: [])
  cleaned_src = erase_if_false(src.to_s)
  start = erase_if_false(start_blob.to_s)
  result = start.dup
  seen = {}
  skip.each { |n| seen[n] = true }
  queue = [start]
  while (blob = queue.shift)
    code_idents(blob).each do |name|
      next if SWIFTUI_SKIP.include?(name)
      next if seen[name]
      seen[name] = true
      helper = extract_var_body(cleaned_src, name) || extract_func_body(cleaned_src, name)
      next if helper.nil?
      helper = erase_if_false(helper)
      result << "\n" << helper
      queue << helper
    end
  end
  result
end

def reachable_from(src, name = "body", skip: [])
  return :unparseable if src.nil?
  stripped = strip_comments(src)
  cleaned = erase_if_false(stripped)
  start = extract_var_body(cleaned, name) || extract_func_body(cleaned, name)
  return :unparseable if start.nil?
  collect_reachable(cleaned, start, skip: skip)
end

def reachable_in_struct(src, struct_name, start = "body", skip: [])
  return :unparseable if src.nil?
  struct = extract_struct_body(strip_comments(src), struct_name)
  return :unparseable if struct.nil?
  reachable_from(struct, start, skip: skip)
end

def code_has_ident?(src, name)
  mask_strings_and_comments(src.to_s).match?(/\b#{Regexp.escape(name)}\b/)
end

def string_literal_values(src)
  vals = []
  text = src.to_s
  each_lexeme(text) do |kind, a, b|
    next unless kind == :string
    raw = text[a...b]
    inner = if raw.start_with?('"""') && raw.end_with?('"""') && raw.length >= 6
      raw[3...-3]
    elsif raw.start_with?('"') && raw.end_with?('"') && raw.length >= 2
      raw[1...-1]
    else
      raw
    end
    vals << inner
  end
  vals
end

def leftover_in_literals(src, leftovers)
  vals = string_literal_values(src)
  leftovers.select do |lit|
    vals.any? { |v| v == lit || v.start_with?("#{lit} ") || v.start_with?("#{lit}\\") }
  end
end

def has_locale_environment?(src)
  compact(src.to_s).include?("@Environment(\\.locale)") || compact(src.to_s).include?("@Environment(.locale)")
end

def language_code_pinned?(src)
  compact(strip_comments(src.to_s)).match?(/languageCode:"(?:en|ja|en-US|ja-JP|en_US|ja_JP)"/)
end

def same_code?(a, b)
  normalize_code(a.to_s) == normalize_code(b.to_s)
end

def language_code_from_locale?(src)
  compact(src.to_s).include?("locale.language.languageCode")
end

def passes_env_language_code?(src)
  c = compact(erase_if_false(src.to_s))
  has_locale_environment?(src) &&
    language_code_from_locale?(src) &&
    (c.include?("languageCode:languageCode") || c.include?("languageCode: languageCode")) &&
    !language_code_pinned?(src)
end

def option_value_sequence(src)
  composer_options_src(src).scan(/ComposerModeOption\(\s*value:\s*("[^"]*"|nil)/).flatten
end

def tag_sequence(src)
  compact(src.to_s).scan(/\.tag\(([^)]*)\)/).flatten
end

def appstorage_signature(src)
  row = extract_struct_body(src.to_s, "BypassToggleRow").to_s
  return nil if row.empty?
  m = compact(row).match(/AppStorage\([^)]*\)/)
  m && m[0]
end

def on_appear_perform_names(src)
  compact(src.to_s).scan(/\.onAppear\(perform:([A-Za-z_][A-Za-z0-9_]*)\)/).flatten
end

def each_on_appear_closure_body(src)
  text = src.to_s
  i = 0
  bodies = []
  while i < text.length
    m = text.match(/\.?onAppear\s*\{/, i)
    break unless m
    brace = text.index("{", m.begin(0))
    break unless brace
    body = extract_balanced(text, brace, "{", "}")
    bodies << body if body
    i = brace + 1
  end
  bodies
end

def contains_save_call?(blob)
  c = compact(blob.to_s)
  c.include?("applyConfig") || c.include?("applySettings")
end

def on_appear_saves?(src)
  return false if src.nil?
  return true if each_on_appear_closure_body(src).any? { |b| contains_save_call?(b) }
  on_appear_perform_names(src).any? do |name|
    body = extract_func_body(src, name)
    body && contains_save_call?(body)
  end
end

def wording_displayed?(src)
  cleaned = erase_if_false(strip_comments(src.to_s))
  c = compact(cleaned)
  c.match?(/Text\((?:w|wording)\.(?:title|explanation|rowLabel|offExplanation|onExplanation)/) ||
    c.include?("option.explanation") ||
    c.match?(/Text\(UIWording\.(?:permission|launchPermission|settingsPermissionFooter)/) ||
    c.match?(/Label\((?:w|wording)\.(?:title|rowLabel)/) ||
    c.match?(/Label\(UIWording\./) ||
    c.match?(/ComposerControlChip\(title:[^;]*UIWording/) ||
    c.include?("AgentConsolePane(") && c.include?("UIWording.permission") ||
    c.include?("AgentConsoleGroupHeader(title:w.title") ||
    (c.include?("SettingsMenuRow(title:option.title") && c.include?("explanation:option.explanation"))
end

def truncation_kind(blob)
  c = compact(blob.to_s)
  return :line_limit if c.match?(/lineLimit\([12]\)/) || c.match?(/lineLimit:[12]/)
  return :fixed_height if c.match?(/\.frame\(height:\d+/)
  return :shrunk if c.include?("minimumScaleFactor") || c.match?(/scaleEffect\(0\./)
  nil
end

def truncation_message(kind, label)
  case kind
  when :line_limit then "#{label} の説明が行数制限されている"
  when :fixed_height then "#{label} の説明が固定高で切断されている"
  when :shrunk then "#{label} の説明が縮小されている"
  end
end

def extract_switch_body(src, header)
  idx = src.to_s.index(header)
  return nil unless idx
  brace = src.index("{", idx)
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def launch_fingerprint(key, src)
  return :missing if src.nil?
  case key
  when :spawn
    body = extract_func_body(src, "appServerPolicies")
    return :unparseable if body.nil?
    extra = src.to_s.scan(/isFullAccessEnabled[^?\n]*\?[^\n]+/).join("\n")
    normalize_code(body + extra)
  when :planner
    body = extract_func_body(src, "profile")
    return :unparseable if body.nil?
    normalize_code(body)
  when :app_env
    hits = src.to_s.scan(/permissionMode:\s*[^\n]+|runMode:\s*[^\n]+/)
    return :unparseable if hits.empty?
    normalize_code(hits.join("\n"))
  when :descriptor
    body = extract_enum_body(src, "AgentRegistry")
    return :unparseable if body.nil?
    args = body.scan(/bypassArgs:[^\n]+|restrictedArgs:[^\n]+/)
    return :unparseable if args.empty?
    normalize_code(args.join("\n"))
  when :cursor_chat
    body = extract_switch_body(src, "switch runMode")
    return :unparseable if body.nil?
    normalize_code(body)
  when :composition_root
    body = extract_func_body(src, "writeClaudeSettings")
    return :unparseable if body.nil?
    normalize_code(body)
  else
    normalize_code(src)
  end
end

def named_body(src, struct_name, name)
  struct = extract_struct_body(src.to_s, struct_name).to_s
  return nil if struct.empty?
  extract_var_body(struct, name) || extract_func_body(struct, name) || extract_var_body(src.to_s, name) || extract_func_body(src.to_s, name)
end

def locale_injection_ok?(src)
  return false if src.nil?
  compact(src).include?("environment(\\.locale,appLanguage.locale)") ||
    src.include?(".environment(\\.locale, appLanguage.locale)")
end

CONTRACT_PATH = "tasks/task-50.md"
WIRING_RB_PATH = ".claude/scripts/task50-wiring.rb"
TEST_PATH = "macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptancePermissionWordingTests.swift"

PATHS = {
  permissions: "macos/Packages/DesignSystem/Sources/DesignSystem/UIWording+Permissions.swift",
  uiwording: "macos/Packages/DesignSystem/Sources/DesignSystem/UIWording.swift",
  settings: "macos/Packages/SessionFeature/Sources/SessionFeature/ComposerSettingsControls.swift",
  settings_view: "macos/App/SettingsView.swift",
  claude_perm: "macos/App/AgentConsole/Claude/ClaudePermissionsPane.swift",
  cursor_perm: "macos/App/AgentConsole/Cursor/CursorPermissionsPane.swift",
  codex_settings: "macos/App/AgentConsole/Codex/CodexSettingsPane.swift",
  cursor_settings: "macos/App/AgentConsole/Cursor/CursorSettingsPane.swift",
  planner: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/AgentLaunchPlanner.swift",
  spawn: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift",
  app_env: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Environment/AppEnvironment.swift",
  descriptor: "macos/Packages/AgentDomain/Sources/AgentDomain/AgentDescriptor.swift",
  cursor_chat: "macos/Packages/CursorAgentKit/Sources/CursorAgentKit/CursorChatClient.swift",
  composition_root: "macos/App/CompositionRoot.swift",
  phlox_app: "macos/App/PhloxApp.swift",
}.freeze

PRODUCT_KEYS = %i[permissions settings settings_view claude_perm cursor_perm codex_settings cursor_settings].freeze
PROTECTED_KEYS = %i[planner spawn app_env descriptor cursor_chat composition_root].freeze

FORBIDDEN_PERMISSIONS_IO = [
  "Locale.current",
  "Locale.autoupdatingCurrent",
  "UserDefaults",
  "ProcessInfo",
  "getenv",
  "URLSession",
  "NotificationCenter",
  "FileManager",
  "NSCache",
  "@AppStorage",
  "String(localized",
  "NSLocalizedString",
  "TranslationSession",
].freeze

COMPOSER_LEFTOVER = [
  "Accept Edits",
  "Don't Ask",
  "Full Access",
  "Read Only",
  "承認が要る操作は確認されずスキップされます",
  "フルアクセス（bypass）",
].freeze

SETTINGS_LEFTOVER = [
  "フルアクセス（bypass）",
  "OFF は通常の安全モード",
  "承認なしのフルアクセス",
].freeze

REQUIRED_AX = {
  settings: ["claudePermissionMenu", "cursorModeMenu"],
}.freeze

CONTRACT_BASELINE_PLACEHOLDER_RE = /PM|凍結|設定|TBD|TODO|FIXME|placeholder|未設定/i
CONTRACT_BASELINE_LINE_RE = /^baseline_commit:\s*(?:"([^"]*)"|'([^']*)'|(\S+))/

def match_contract_baseline_line(text)
  return nil if text.nil?
  m = text.match(CONTRACT_BASELINE_LINE_RE)
  return nil unless m
  m[1] || m[2] || m[3]
end

def parse_contract_baseline_text(text)
  return :missing if text.nil?
  raw = match_contract_baseline_line(text)
  return :missing unless raw
  value = raw.strip
  return :missing if value.empty?
  return :placeholder if value.match?(CONTRACT_BASELINE_PLACEHOLDER_RE)
  return :invalid unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
  value
end

def contract_baseline_errors(contract_text, env_sha)
  parsed = parse_contract_baseline_text(contract_text)
  case parsed
  when :missing
    ["契約 frontmatter に baseline_commit が無い"]
  when :placeholder
    ["契約 baseline_commit がプレースホルダ（凍結時に実 SHA へ置換する）"]
  when :invalid
    raw = match_contract_baseline_line(contract_text)
    ["契約 baseline_commit が不正: #{raw}"]
  else
    errs = []
    contract_full = git_full_sha(parsed)
    if contract_full.nil?
      errs << "契約 baseline_commit が無効なコミット: #{parsed}"
    elsif env_sha
      env_full = git_full_sha(env_sha)
      if env_full && env_full != contract_full
        errs << "TASK50_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK50_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK50_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK50_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
    return [nil, errs]
  end
  [value, errs]
end

def frozen_artifact_errors(label, blob, now)
  if blob.nil?
    ["基準時点の#{label}を git show できない"]
  elsif !workdir_matches_git_blob?(now, blob)
    ["基準時点の#{label}が現在と同一ではない"]
  else
    []
  end
end

def implementation_in_baseline_errors(permissions_blob)
  if permissions_blob
    ["基準時点に UIWording+Permissions.swift がある（実装前の凍結ではない）"]
  else
    []
  end
end

def task48_canonical_errors(uiwording_blob, settings_blob)
  ng = []
  if uiwording_blob.nil?
    ng << "基準時点に UIWording.swift が無い（task-48 完成実装を含まない）"
    return ng
  end
  unless code_has_ident?(uiwording_blob, "planOption") && code_has_ident?(uiwording_blob, "permissionLabel")
    ng << "基準時点の UIWording.swift が task-48 正本として接続できない"
  end
  params = extract_func_params(uiwording_blob, "text")
  if params.nil? || !compact(params).include?("languageCode")
    msg = "基準時点の UIWording.swift が task-48 正本として接続できない"
    ng << msg unless ng.include?(msg)
  end
  if settings_blob
    sc = compact(settings_blob)
    unless sc.include?("UIWording.text(.planOption") || sc.include?("UIWording.text(.permissionLabel")
      ng << "基準時点の ComposerSettingsControls が task-48 正本へ接続していない"
    end
  else
    ng << "基準時点の ComposerSettingsControls が task-48 正本へ接続していない"
  end
  ng
end

def check_frozen_baseline(baseline, opts = {})
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK50_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  unless git_is_ancestor?(full, "HEAD")
    ng << "TASK50_BASELINE が HEAD の祖先ではない"
  end
  perm_blob = opts.key?(:permissions_blob) ? opts[:permissions_blob] : git_show(full, PATHS[:permissions])
  ng.concat(implementation_in_baseline_errors(perm_blob))
  ui_blob = opts.key?(:uiwording_blob) ? opts[:uiwording_blob] : git_show(full, PATHS[:uiwording])
  settings_base = opts.key?(:settings_blob) ? opts[:settings_blob] : git_show(full, PATHS[:settings])
  ng.concat(task48_canonical_errors(ui_blob, settings_base))
  test_blob = opts.key?(:test_blob) ? opts[:test_blob] : git_show(full, TEST_PATH)
  rb_blob = opts.key?(:rb_blob) ? opts[:rb_blob] : git_show(full, WIRING_RB_PATH)
  test_now = opts.key?(:test_now) ? opts[:test_now] : read_if_exist(TEST_PATH)
  rb_now = opts.key?(:rb_now) ? opts[:rb_now] : read_if_exist(WIRING_RB_PATH)
  ng.concat(frozen_artifact_errors("受け入れテスト", test_blob, test_now))
  ng.concat(frozen_artifact_errors("rb 自身", rb_blob, rb_now))
  ng
end

def missing_file(files, key)
  files[key].nil? ? ["#{PATHS[key]} が存在しない"] : []
end

def leftover_errors(src, path, leftovers)
  return [] if src.nil?
  hits = leftover_in_literals(src, leftovers)
  hits.map { |lit| "#{path} に権限文言の直値 #{lit.inspect} が残っている" }
end

def uses_permission_api?(src)
  masked = mask_strings_and_comments(erase_if_false(src.to_s))
  c = compact(masked)
  code_has_ident?(src, "UIWording") && c.include?("UIWording.permission") && c.include?("languageCode")
end

def uses_launch_api?(src)
  masked = mask_strings_and_comments(erase_if_false(src.to_s))
  c = compact(masked)
  code_has_ident?(src, "UIWording") && c.include?("launchPermission") && c.include?("languageCode")
end

def explanation_truncated?(src)
  row = extract_struct_body(src.to_s, "SettingsMenuRow")
  return false if row.nil?
  !truncation_kind(row).nil?
end

def check_permissions_api(src)
  ng = []
  if src.nil?
    ng << "#{PATHS[:permissions]} が存在しない"
    return ng
  end
  ng << "UIWording の権限拡張を括弧対応で切り出せない" unless src.match?(/extension\s+UIWording\b/) || extract_enum_body(src, "UIWording")
  ng << "PermissionAgent が無い" unless code_has_ident?(src, "PermissionAgent")
  ng << "PermissionKind が無い" unless code_has_ident?(src, "PermissionKind")
  ng << "PermissionWording が無い" unless code_has_ident?(src, "PermissionWording")
  ng << "LaunchPermissionWording が無い" unless code_has_ident?(src, "LaunchPermissionWording")
  params = extract_func_params(src, "permission")
  if params.nil?
    ng << "UIWording.permission を括弧対応で切り出せない"
  else
    pc = compact(params)
    ng << "UIWording.permission が agent を受け取らない" unless pc.include?("agent")
    ng << "UIWording.permission が kind を受け取らない" unless pc.include?("kind")
    ng << "UIWording.permission が value を受け取らない" unless pc.include?("value")
    ng << "UIWording.permission が languageCode を受け取らない" unless pc.include?("languageCode")
  end
  launch_params = extract_func_params(src, "launchPermission")
  if launch_params.nil?
    ng << "UIWording.launchPermission が無い"
  else
    lc = compact(launch_params)
    ng << "UIWording.launchPermission が displayName を受け取らない" unless lc.include?("displayName")
    ng << "UIWording.launchPermission が languageCode を受け取らない" unless lc.include?("languageCode")
  end
  footer_params = extract_func_params(src, "settingsPermissionFooter")
  if footer_params.nil?
    ng << "UIWording.settingsPermissionFooter が無い"
  elsif !compact(footer_params).include?("languageCode")
    ng << "UIWording.settingsPermissionFooter が languageCode を受け取らない"
  end
  %w[claudePermissionMode codexApprovalPolicy codexSandboxMode codexProfile cursorApprovalMode cursorSandboxMode cursorOperationMode claudeRuleBucket cursorRuleBucket settingKeyTitle permissionsPaneIntro].each do |name|
    ng << "PermissionKind.#{name} が無い" unless src.match?(/\bcase\s+#{Regexp.escape(name)}\b/)
  end
  %w[claude codex cursor custom].each do |name|
    ng << "PermissionAgent.#{name} が無い" unless src.match?(/\bcase\s+#{Regexp.escape(name)}\b/)
  end
  masked = mask_strings_and_comments(src)
  FORBIDDEN_PERMISSIONS_IO.each do |snip|
    ng << "UIWording+Permissions が禁止語 #{snip} を使っている" if masked.include?(snip)
  end
  ng
end

def composer_options_src(src)
  extract_func_body(src.to_s, "composerModeOptions").to_s
end

def menu_explains?(blob)
  return false if blob.nil?
  c = compact(blob)
  code_has_ident?(blob, "composerModeOptions") && c.include?("option.explanation")
end

def check_named_menu(src, struct_name, name, message)
  blob = named_body(src, struct_name, name)
  return [] if blob.nil?
  ok = menu_explains?(blob) && compact(blob).include?("composerModeOptions(for:viewModel.agentRef")
  ok ? [] : [message]
end

def check_named_permission_site(src, struct_name, name, kind_token, message)
  blob = named_body(src, struct_name, name)
  return [] if blob.nil?
  uses_permission_api?(blob) && compact(blob).include?(kind_token) ? [] : [message]
end

def check_locale_chain(src, missing_msg, env_msg, pinned_msg)
  if !has_locale_environment?(src)
    [missing_msg]
  elsif language_code_pinned?(src)
    [pinned_msg]
  elsif !passes_env_language_code?(src)
    [env_msg]
  else
    []
  end
end

def check_composer(src)
  ng = []
  if src.nil?
    ng << "#{PATHS[:settings]} が存在しない"
    return ng
  end
  options = composer_options_src(src)
  if options.empty?
    ng << "composerModeOptions を括弧対応で切り出せない"
    return ng
  end
  opt_c = compact(options)
  unless uses_permission_api?(options) && opt_c.include?("kind:.claudePermissionMode")
    ng << "通常メニューが UIWording.permission に接続していない"
  end
  unless opt_c.include?("kind:.codexProfile") && opt_c.include?("kind:.cursorOperationMode") && opt_c.include?("kind:.claudePermissionMode") && opt_c.include?("codexProfileIDs")
    unless uses_permission_api?(options) && opt_c.include?("kind:.claudePermissionMode") && opt_c.include?("codexProfileIDs") && opt_c.include?("kind:.codexProfile")
      ng << "通常メニューが UIWording.permission に接続していない" unless ng.include?("通常メニューが UIWording.permission に接続していない")
    end
  end
  regular = extract_struct_body(src, "ComposerSettingsControlsView").to_s
  overflow = extract_struct_body(src, "ComposerSettingsOverflowMenu").to_s
  if regular.empty?
    ng << "ComposerSettingsControlsView を括弧対応で切り出せない"
  else
    reach = reachable_from(regular, "body")
    if reach == :unparseable
      ng << "ComposerSettingsControlsView の body を括弧対応で切り出せない"
    else
      unless menu_explains?(reach)
        ng << "通常メニューが UIWording.permission に接続していない" unless ng.include?("通常メニューが UIWording.permission に接続していない")
      end
      unless wording_displayed?(reach)
        ng << "通常メニューが UIWording.permission に接続していない" unless ng.include?("通常メニューが UIWording.permission に接続していない")
      end
      chip = compact(mask_strings_and_comments(reach.to_s))
      unless chip.include?("ComposerControlChip") && chip.include?("kind:.claudePermissionMode")
        ng << "選択中ラベルが UIWording.permission に接続していない"
      end
      unless chip.include?("ComposerControlChip") && chip.include?("kind:.cursorOperationMode")
        ng << "Cursor の選択中ラベルが UIWording.permission に接続していない"
      end
      unless chip.include?("ComposerControlChip") && chip.include?("kind:.codexProfile")
        ng << "Codex の選択中ラベルが UIWording.permission に接続していない"
      end
    end
    ng.concat(check_locale_chain(
      regular,
      "ComposerSettingsControls が locale を受け取っていない",
      "ComposerSettingsControls が環境 locale から languageCode を渡していない",
      "ComposerSettingsControls が表示言語を languageCode リテラルへ固定している"
    ))
  end
  if overflow.empty?
    ng << "ComposerSettingsOverflowMenu を括弧対応で切り出せない"
  else
    over_reach = reachable_from(overflow, "body")
    if over_reach == :unparseable
      ng << "ComposerSettingsOverflowMenu の body を括弧対応で切り出せない"
    else
      unless menu_explains?(over_reach)
        ng << "省略メニューが UIWording.permission に接続していない"
      end
      unless wording_displayed?(over_reach)
        ng << "省略メニューが UIWording.permission に接続していない" unless ng.include?("省略メニューが UIWording.permission に接続していない")
      end
    end
    ng << "ComposerSettingsOverflowMenu が環境 locale から languageCode を渡していない" unless passes_env_language_code?(overflow)
  end
  ng.concat(check_named_menu(src, "ComposerSettingsControlsView", "claudePermissionMenu", "Claude の通常メニューが UIWording.permission に接続していない"))
  ng.concat(check_named_menu(src, "ComposerSettingsControlsView", "cursorModeMenu", "Cursor の通常メニューが UIWording.permission に接続していない"))
  ng.concat(check_named_menu(src, "ComposerSettingsControlsView", "permissionMenu", "Codex の通常メニューが UIWording.permission に接続していない"))
  ng.concat(check_named_menu(src, "ComposerSettingsOverflowMenu", "spawnPermissionItems", "Claude の省略メニューが UIWording.permission に接続していない"))
  ng.concat(check_named_menu(src, "ComposerSettingsOverflowMenu", "cursorModeItems", "Cursor の省略メニューが UIWording.permission に接続していない"))
  ng.concat(check_named_menu(src, "ComposerSettingsOverflowMenu", "codexPermissionItems", "Codex の省略メニューが UIWording.permission に接続していない"))
  if opt_c.include?('value:"default"')
    ng << "composerModeOptions に default 項目が増えている"
  end
  if compact(src).include?('option.value=="dontAsk"') || compact(src).include?("dontAskModeCaption")
    ng << "dontAsk だけが説明付きで他選択肢の説明が無い"
  end
  if opt_c.match(/ComposerModeOption\(value:"dontAsk".{0,800}?kind:\.claudePermissionMode,value:"bypassPermissions"/)
    ng << "Claude の dontAsk 説明が bypassPermissions に接続している"
  end
  if opt_c.include?("kind:.cursorApprovalMode") || !opt_c.include?("kind:.cursorOperationMode")
    ng << "Cursor の動作モードが承認方式の正本へ接続している"
  end
  title_fn = extract_func_body(src, "composerPermissionTitle").to_s
  title_blob = title_fn.empty? ? options : title_fn
  if compact(title_blob).include?("kind:.codexSandboxMode") || compact(title_blob).include?("kind:.codexApprovalPolicy")
    ng << "Codex のプロフィールが実行制限の正本へ接続している"
  end
  unless compact(src).include?("kind:.codexProfile") && opt_c.include?("kind:.codexProfile") && opt_c.include?("codexProfileIDs")
    ng << "Codex のプロフィールが実行制限の正本へ接続している" unless ng.include?("Codex のプロフィールが実行制限の正本へ接続している")
  end
  row = extract_struct_body(src.to_s, "SettingsMenuRow")
  if row
    kind = truncation_kind(row)
    ng << truncation_message(kind, "SettingsMenuRow") if kind
  end
  unless compact(src).include?("UIWording.text(.planOption") || compact(src).include?("UIWording.text(.planOption,")
    ng << "Plan の正本参照が巻き戻っている"
  end
  ng.concat(leftover_errors(src, PATHS[:settings], COMPOSER_LEFTOVER))
  ng.uniq
end

def check_settings_view(src)
  ng = []
  if src.nil?
    ng << "#{PATHS[:settings_view]} が存在しない"
    return ng
  end
  row = extract_struct_body(src, "BypassToggleRow").to_s
  if row.empty?
    ng << "BypassToggleRow を括弧対応で切り出せない"
    return ng
  end
  reach = reachable_from(row, "body")
  if reach == :unparseable
    ng << "BypassToggleRow の body を括弧対応で切り出せない"
  else
    rc = compact(reach)
    unless uses_launch_api?(reach)
      ng << "設定の権限行が UIWording.launchPermission に接続していない"
    end
    displayed = wording_displayed?(reach) || (rc.include?("wording.onExplanation") && rc.include?("wording.offExplanation"))
    unless displayed && rc.include?("wording.rowLabel")
      ng << "設定の権限行が UIWording.launchPermission に接続していない" unless ng.include?("設定の権限行が UIWording.launchPermission に接続していない")
    end
    has_off = rc.include?("Text(wording.offExplanation")
    has_on = rc.include?("Text(wording.onExplanation")
    ternary = rc.include?("isEnabled?wording.onExplanation:wording.offExplanation") ||
      rc.include?("isEnabled?wording.offExplanation:wording.onExplanation")
    if ternary || !(has_off && has_on)
      ng << "設定の権限行が ON/OFF 説明を同時に描画していない"
    end
    if rc.match?(/launchPermission\(agent:\.(claude|codex|cursor)/)
      ng << "設定の権限行が agent を固定している"
    end
    kind = truncation_kind(row)
    ng << truncation_message(kind, "BypassToggleRow") if kind
  end
  view = extract_struct_body(src, "SettingsView").to_s
  view_reach = view.empty? ? :unparseable : reachable_from(view, "body")
  if view_reach == :unparseable || view.empty?
    unless compact(src).include?("Text(UIWording.settingsPermissionFooter")
      ng << "設定の footer が UIWording.settingsPermissionFooter に接続していない"
    end
  else
    unless compact(view_reach).include?("Text(UIWording.settingsPermissionFooter")
      ng << "設定の footer が UIWording.settingsPermissionFooter に接続していない"
    end
    body_var = extract_var_body(view, "body").to_s
    fk = truncation_kind(body_var)
    ng << truncation_message(fk, "SettingsView") if fk
  end
  unless compact(src).include?("agentCatalog.allDescriptors")
    ng << "動的エージェント一覧が固定3行になっている"
  end
  if leftover_in_literals(src, ["フルアクセス（bypass）", "Full Access"]).any? || compact(row).include?("フルアクセス")
    ng << "カスタムエージェントをフルアクセス扱いしている"
  end
  ng.concat(leftover_errors(src, PATHS[:settings_view], SETTINGS_LEFTOVER))
  if language_code_pinned?(src)
    ng << "SettingsView が表示言語を languageCode リテラルへ固定している"
  elsif !(passes_env_language_code?(row) || passes_env_language_code?(src))
    ng << "SettingsView が環境 locale から languageCode を渡していない"
  end
  ng.uniq
end

def check_pane(src, struct, kind_token, message)
  ng = []
  if src.nil?
    ng << message.sub("が UIWording.permission に接続していない", "が存在しない")
    return ng
  end
  body = extract_struct_body(src, struct).to_s
  if body.empty?
    ng << "#{struct} を括弧対応で切り出せない"
    return ng
  end
  reach = reachable_from(body, "body")
  if reach == :unparseable
    ng << "#{struct} の body を括弧対応で切り出せない"
    return ng
  end
  unless uses_permission_api?(reach) && compact(reach).include?(kind_token) && wording_displayed?(reach)
    ng << message
  end
  if language_code_pinned?(src)
    ng << "#{struct} が表示言語を languageCode リテラルへ固定している"
  elsif !passes_env_language_code?(src)
    ng << "#{struct} が環境 locale から languageCode を渡していない"
  end
  ng
end

def check_management(files)
  ng = []
  ng.concat(check_pane(files[:claude_perm], "ClaudePermissionsPane", "kind:.claudeRuleBucket", "ClaudePermissionsPane の権限説明が UIWording.permission に接続していない"))
  ng.concat(check_pane(files[:cursor_perm], "CursorPermissionsPane", "kind:.cursorRuleBucket", "CursorPermissionsPane の権限説明が UIWording.permission に接続していない"))
  ng.concat(check_pane(files[:claude_perm], "ClaudePermissionsPane", "kind:.permissionsPaneIntro", "ClaudePermissionsPane の権限説明が UIWording.permission に接続していない")) unless files[:claude_perm].nil?
  if files[:claude_perm]
    ng.concat(check_named_permission_site(files[:claude_perm], "ClaudePermissionsPane", "editor", "kind:.claudeRuleBucket", "ClaudePermissionsPane の editor が UIWording.permission に接続していない"))
    ng.concat(check_named_permission_site(files[:claude_perm], "ClaudePermissionsPane", "bucketSection", "kind:.claudeRuleBucket", "ClaudePermissionsPane の bucketSection が UIWording.permission に接続していない"))
    bsec = named_body(files[:claude_perm], "ClaudePermissionsPane", "bucketSection")
    if bsec && (k = truncation_kind(bsec))
      ng << truncation_message(k, "ClaudePermissionsPane")
    end
  end
  if files[:cursor_perm]
    ng.concat(check_named_permission_site(files[:cursor_perm], "CursorPermissionsPane", "editor", "kind:.cursorRuleBucket", "CursorPermissionsPane の editor が UIWording.permission に接続していない"))
    ng.concat(check_named_permission_site(files[:cursor_perm], "CursorPermissionsPane", "bucketSection", "kind:.cursorRuleBucket", "CursorPermissionsPane の bucketSection が UIWording.permission に接続していない"))
    unless compact(files[:cursor_perm]).include?("kind:.permissionsPaneIntro")
      ng << "CursorPermissionsPane の導入文が UIWording.permission に接続していない"
    end
    cbsec = named_body(files[:cursor_perm], "CursorPermissionsPane", "bucketSection")
    if cbsec && (k = truncation_kind(cbsec))
      ng << truncation_message(k, "CursorPermissionsPane")
    end
  end
  if files[:codex_settings]
    src = files[:codex_settings]
    reach = reachable_in_struct(src, "CodexSettingsPane", "body")
    if reach == :unparseable
      ng << "CodexSettingsPane の body を括弧対応で切り出せない"
    else
      rc = compact(reach)
      wired = uses_permission_api?(reach)
      if wired && rc.include?("kind:.codexSandboxMode") && !rc.include?("kind:.codexApprovalPolicy")
        ng << "Codex の承認方針が実行制限の正本へ接続している"
      elsif !(wired && rc.include?("kind:.codexApprovalPolicy") && rc.include?("kind:.codexSandboxMode"))
        ng << "CodexSettingsPane の承認方針が正本へ接続していない"
      end
      unless code_has_ident?(reach, "displayName") && compact(reach).include?("key.displayName")
        ng << "権限以外の設定行が従来の供給元を失っている"
      end
      unless compact(reach).include?("options(current:") || compact(reach).include?("options(current:")
        ng << "未知値の選択肢保持が失われている"
      end
      unless compact(src).include?("successMessage")
        ng << "成功通知の生成経路が変わっている"
      end
    end
    setting_row = named_body(src, "CodexSettingsPane", "settingRow")
    if setting_row
      sr = compact(setting_row)
      unless sr.include?("kind:.settingKeyTitle") && sr.include?("kind:.codexApprovalPolicy") && sr.include?("kind:.codexSandboxMode")
        ng << "CodexSettingsPane の承認方針が正本へ接続していない" unless ng.include?("CodexSettingsPane の承認方針が正本へ接続していない") || ng.include?("Codex の承認方針が実行制限の正本へ接続している")
      end
      sk = truncation_kind(setting_row)
      ng << truncation_message(sk, "CodexSettingsPane") if sk
    end
    choice = named_body(src, "CodexSettingsPane", "choiceControl")
    if choice
      masked_choice = compact(mask_strings_and_comments(choice))
      unless uses_permission_api?(choice) && !masked_choice.include?("Text(option)")
        ng << "CodexSettingsPane の choiceControl が UIWording.permission に接続していない"
      end
    end
  else
    ng << "#{PATHS[:codex_settings]} が存在しない"
  end
  if files[:cursor_settings]
    src = files[:cursor_settings]
    reach = reachable_in_struct(src, "CursorSettingsPane", "body")
    if reach == :unparseable
      ng << "CursorSettingsPane の body を括弧対応で切り出せない"
    else
      unless uses_permission_api?(reach) && compact(reach).include?("kind:.cursorApprovalMode") && compact(reach).include?("kind:.cursorSandboxMode")
        ng << "CursorSettingsPane の承認方式が正本へ接続していない"
      end
      unless compact(reach).include?("key.displayName")
        ng << "権限以外の設定行が従来の供給元を失っている" unless ng.include?("権限以外の設定行が従来の供給元を失っている")
      end
      unless compact(reach).include?("options(current:")
        ng << "未知値の選択肢保持が失われている" unless ng.include?("未知値の選択肢保持が失われている")
      end
      unless compact(src).include?("successMessage")
        ng << "成功通知の生成経路が変わっている" unless ng.include?("成功通知の生成経路が変わっている")
      end
    end
    ctrl = named_body(src, "CursorSettingsPane", "control")
    if ctrl
      unless uses_permission_api?(ctrl) && compact(ctrl).include?("kind:.cursorSandboxMode") && compact(ctrl).include?("kind:.cursorApprovalMode")
        ng << "CursorSettingsPane の control が UIWording.permission に接続していない"
      end
    end
    crow = named_body(src, "CursorSettingsPane", "settingRow")
    if crow && (k = truncation_kind(crow))
      ng << truncation_message(k, "CursorSettingsPane")
    end
  else
    ng << "#{PATHS[:cursor_settings]} が存在しない"
  end
  ng.uniq
end

def check_product(files)
  ng = []
  PRODUCT_KEYS.each { |key| ng.concat(missing_file(files, key)) }
  ng.concat(check_permissions_api(files[:permissions])) unless files[:permissions].nil?
  ng.concat(check_composer(files[:settings])) unless files[:settings].nil?
  ng.concat(check_settings_view(files[:settings_view])) unless files[:settings_view].nil?
  if PRODUCT_KEYS.all? { |k| k == :permissions || files[k] }
    ng.concat(check_management(files))
  end
  if files.key?(:phlox_app)
    if files[:phlox_app].nil?
      ng << "#{PATHS[:phlox_app]} が存在しない"
    elsif !locale_injection_ok?(files[:phlox_app])
      ng << "PhloxApp が環境 locale を注入していない"
    end
  end
  ng.uniq
end

def plan_values(src)
  compact(src.to_s).scan(/ComposerModeOption\(value:("[^"]*"|nil)/).flatten
end

def check_plan_order(src)
  ng = []
  options = composer_options_src(src)
  return ["composerModeOptions を括弧対応で切り出せない"] if options.empty?
  chunks = options.split("case .builtin")
  chunks.each do |chunk|
    next unless chunk.include?("isPlan:true") || chunk.include?("isPlan: true")
    last_plan = chunk.rindex("isPlan:true") || chunk.rindex("isPlan: true")
    later_value = chunk[last_plan..]
    if later_value =~ /ComposerModeOption\(value:/ && later_value.include?("isPlan:false")
      ng << "Plan の項目順序が TASK50_BASELINE から変化している"
    end
  end
  ng
end

def launch_tokens(src)
  src.to_s.scan(/bypassPermissions|--sandbox|--force|--auto-review|permissionMode|danger-full-access|workspace-write/).sort
end

def check_invariants(current, previous)
  ng = []
  return ng if previous.nil?

  if current[:settings]
    unless compact(mask_strings_and_comments(current[:settings])).include?("option.isPlan&&!viewModel.isPlanModeAvailable")
      ng << "Plan の排他条件が TASK50_BASELINE から変化している"
    end
    ng.concat(check_plan_order(current[:settings]))
    selected = masked_compact_func(current[:settings], "modeOptionIsSelected")
    if selected && !(selected.include?("ifoption.isPlan") && selected.include?("!viewModel.isPlanMode"))
      ng << "Plan の排他条件が TASK50_BASELINE から変化している"
    end
    REQUIRED_AX[:settings].each do |lit|
      vals = string_literal_values(current[:settings])
      unless vals.any? { |v| v.include?(lit) }
        ng << "#{PATHS[:settings]} の tag #{lit.inspect} が TASK50_BASELINE から変化している"
      end
    end
    sc = compact(current[:settings])
    unless sc.include?("setSpawnPermission(option.value)") && sc.include?("setSpawnAgentPermission")
      ng << "action が TASK50_BASELINE から変化している"
    end
    unless compact(current[:settings]).include?("UIWording.text(.planOption") || compact(current[:settings]).include?("UIWording.text(.permissionLabel")
      ng << "task-48 の一般文言が巻き戻っている"
    end
  end

  if current[:settings_view]
    row = extract_struct_body(current[:settings_view], "BypassToggleRow").to_s
    unless compact(row).include?("AppStorage(wrappedValue:true,descriptor.bypassKey)") || compact(row).include?('AppStorage(wrappedValue: true, descriptor.bypassKey)')
      ng << "BypassToggleRow の Binding が TASK50_BASELINE から変化している"
    end
    unless compact(current[:settings_view]).include?("buttonStyle(.bordered)")
      ng << "tag が TASK50_BASELINE から変化している"
    end
    if compact(current[:settings_view]).include?("onAppear") && compact(extract_struct_body(current[:settings_view], "BypassToggleRow").to_s).include?("applySettings")
      ng << "表示時に保存処理が追加されている"
    end
  end

  %i[claude_perm cursor_perm].each do |key|
    src = current[key]
    next if src.nil?
    unless compact(src).include?(".tag(") || compact(src).include?(".tag(bucket)")
      ng << "tag が TASK50_BASELINE から変化している"
    end
    unless compact(src).include?("applySettings")
      ng << "action が TASK50_BASELINE から変化している"
    end
    prev = previous[key]
    if prev && tag_sequence(src) != tag_sequence(prev)
      ng << "tag が TASK50_BASELINE から変化している"
    end
  end

  %i[codex_settings cursor_settings].each do |key|
    src = current[key]
    next if src.nil?
    if on_appear_saves?(src)
      ng << "表示時に保存処理が追加されている"
    end
  end

  PROTECTED_KEYS.each do |key|
    now = current[key]
    prev = previous[key]
    if now.nil?
      ng << "#{PATHS[key]} が存在しない"
      next
    end
    if prev.nil?
      ng << "基準時点の #{PATHS[key]} を git show できない"
      next
    end
    fp_now = launch_fingerprint(key, now)
    fp_prev = launch_fingerprint(key, prev)
    if fp_now == :unparseable || fp_prev == :unparseable
      ng << "起動処理を括弧対応で切り出せない"
    elsif fp_now != fp_prev
      ng << "起動引数が TASK50_BASELINE から変化している"
    end
  end

  if current[:settings] && previous[:settings]
    now_opts = composer_options_src(current[:settings])
    prev_opts = composer_options_src(previous[:settings])
    if now_opts.empty? || prev_opts.empty?
      if now_opts.empty?
        ng << "コントロールが削除されている"
      else
        ng << "composerModeOptions を括弧対応で切り出せない"
      end
    elsif option_value_sequence(current[:settings]) != option_value_sequence(previous[:settings])
      ng << "メニューの項目集合・順序が TASK50_BASELINE から変化している"
    end
    %w[setSpawnPermission setSpawnAgentPermission].each do |fn|
      now_call = extract_call_args(current[:settings], fn)
      prev_call = extract_call_args(previous[:settings], fn)
      if now_call && prev_call && !same_code?(now_call, prev_call)
        ng << "action が TASK50_BASELINE から変化している"
      end
    end
    if tag_sequence(current[:settings]) != tag_sequence(previous[:settings])
      ng << "tag が TASK50_BASELINE から変化している"
    end
  end

  if current[:settings_view] && previous[:settings_view]
    now_sig = appstorage_signature(current[:settings_view])
    prev_sig = appstorage_signature(previous[:settings_view])
    now_row = extract_struct_body(current[:settings_view], "BypassToggleRow")
    prev_row = extract_struct_body(previous[:settings_view], "BypassToggleRow")
    if now_row && prev_row
      if now_sig.nil? || prev_sig.nil?
        ng << "BypassToggleRow を括弧対応で切り出せない"
      elsif now_sig != prev_sig
        ng << "BypassToggleRow の Binding が TASK50_BASELINE から変化している"
      end
    end
  end

  ng.uniq
end

def masked_compact_func(src, name)
  body = extract_func_body(src.to_s, name)
  return nil if body.nil?
  compact(mask_strings_and_comments(body))
end

def worktree_files
  files = {}
  PATHS.each { |key, path| files[key] = read_if_exist(path) }
  files
end

def baseline_files(rev)
  files = {}
  PATHS.each { |key, path| files[key] = git_show(rev, path) }
  files
end

def with_file(files, key)
  copy = files.dup
  copy[key] = yield(files[key].dup)
  copy
end

def selftest_assert(cond, msg)
  unless cond
    puts "task50-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task50-wiring --selftest: FAIL #{msg}"
    puts "  expected: #{expected.inspect}"
    puts "  actual:   #{actual.inspect}"
    exit 1
  end
end

def locale_and_code
  <<~SWIFT
        @Environment(\\.locale) private var locale
        private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }
  SWIFT
end

def good_permissions_src
  <<~SWIFT
    extension UIWording {
      public enum PermissionAgent: String, CaseIterable, Equatable, Hashable, Sendable {
        case claude
        case codex
        case cursor
        case custom
      }
      public enum PermissionKind: String, CaseIterable, Equatable, Hashable, Sendable {
        case claudePermissionMode
        case codexApprovalPolicy
        case codexSandboxMode
        case codexProfile
        case cursorApprovalMode
        case cursorSandboxMode
        case cursorOperationMode
        case claudeRuleBucket
        case cursorRuleBucket
        case settingKeyTitle
        case permissionsPaneIntro
      }
      public struct PermissionWording: Equatable, Hashable, Sendable {
        public let title: String
        public let explanation: String
      }
      public struct LaunchPermissionWording: Equatable, Hashable, Sendable {
        public let rowLabel: String
        public let offExplanation: String
        public let onExplanation: String
      }
      public static func permission(agent: PermissionAgent, kind: PermissionKind, value: String?, languageCode: String) -> PermissionWording {
        PermissionWording(title: "t", explanation: "e")
      }
      public static func launchPermission(agent: PermissionAgent, displayName: String, languageCode: String) -> LaunchPermissionWording {
        LaunchPermissionWording(rowLabel: "r", offExplanation: "off", onExplanation: "on")
      }
      public static func settingsPermissionFooter(languageCode: String) -> String { "f" }
    }
  SWIFT
end

def good_settings_src
  <<~SWIFT
    struct ComposerModeOption {
      let value: String?
      let title: String
      let explanation: String
      let isPlan: Bool
    }
    func composerModeOptions(for agentRef: AgentRef, codexProfileIDs: [String], languageCode: String) -> [ComposerModeOption] {
      switch agentRef {
      case .builtin(.codex):
        codexProfileIDs.map {
          let w = UIWording.permission(agent: .codex, kind: .codexProfile, value: $0, languageCode: languageCode)
          ComposerModeOption(value: $0, title: w.title, explanation: w.explanation, isPlan: false)
        } + [
          ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), explanation: UIWording.permission(agent: .codex, kind: .codexProfile, value: "plan", languageCode: languageCode).explanation, isPlan: true),
        ]
      case .builtin(.claudeCode):
        [
          ComposerModeOption(value: "acceptEdits", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "acceptEdits", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "acceptEdits", languageCode: languageCode).explanation, isPlan: false),
          ComposerModeOption(value: "auto", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "auto", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "auto", languageCode: languageCode).explanation, isPlan: false),
          ComposerModeOption(value: "bypassPermissions", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "bypassPermissions", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "bypassPermissions", languageCode: languageCode).explanation, isPlan: false),
          ComposerModeOption(value: "manual", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "manual", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "manual", languageCode: languageCode).explanation, isPlan: false),
          ComposerModeOption(value: "dontAsk", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "dontAsk", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "dontAsk", languageCode: languageCode).explanation, isPlan: false),
          ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "plan", languageCode: languageCode).explanation, isPlan: true),
        ]
      case .builtin(.cursor):
        [
          ComposerModeOption(value: nil, title: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: nil, languageCode: languageCode).title, explanation: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: nil, languageCode: languageCode).explanation, isPlan: false),
          ComposerModeOption(value: "ask", title: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: "ask", languageCode: languageCode).title, explanation: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: "ask", languageCode: languageCode).explanation, isPlan: false),
          ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), explanation: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: "plan", languageCode: languageCode).explanation, isPlan: true),
        ]
      default:
        []
      }
    }
    func composerPermissionTitle(for id: String?, languageCode: String) -> String {
      UIWording.permission(agent: .codex, kind: .codexProfile, value: id, languageCode: languageCode).title
    }
    struct SettingsMenuRow: View {
      let title: String
      let isSelected: Bool
      let explanation: String
      var body: some View {
        VStack {
          Text(title)
          Text(explanation).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    struct ComposerSettingsControlsView: View {
    #{locale_and_code}
      var body: some View {
        Menu(UIWording.text(.permissionLabel, languageCode: languageCode)) {
          ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode), id: \\.self) { option in
            Button {
              setSpawnPermission(option.value)
            } label: {
              SettingsMenuRow(title: option.title, isSelected: modeOptionIsSelected(option, currentValue: selectedClaudePermission), explanation: option.explanation)
            }
            .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
          }
        }
        ComposerControlChip(title: viewModel.isPlanMode ? UIWording.text(.planOption, languageCode: languageCode) : UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: selectedClaudePermission, languageCode: languageCode).title)
          .accessibilityIdentifier("ChatComposer.claudePermissionMenu")
        ComposerControlChip(title: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: viewModel.selectedPermissionProfile, languageCode: languageCode).title)
          .accessibilityIdentifier("ChatComposer.cursorModeMenu")
        ComposerControlChip(title: UIWording.permission(agent: .codex, kind: .codexProfile, value: viewModel.selectedPermissionProfile, languageCode: languageCode).title)
        claudePermissionMenu
        cursorModeMenu
        permissionMenu
      }
      private var claudePermissionMenu: some View {
        Menu {
          ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode), id: \\.self) { option in
            Button {
              setSpawnPermission(option.value)
            } label: {
              SettingsMenuRow(title: option.title, isSelected: false, explanation: option.explanation)
            }
          }
        } label: { Text("claude") }
      }
      private var cursorModeMenu: some View {
        Menu {
          ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode), id: \\.self) { option in
            Button {
              setSpawnPermission(option.value)
            } label: {
              SettingsMenuRow(title: option.title, isSelected: false, explanation: option.explanation)
            }
          }
        } label: { Text("cursor") }
      }
      private var permissionMenu: some View {
        Menu {
          ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode), id: \\.self) { option in
            Button {
              setSpawnPermission(option.value)
            } label: {
              SettingsMenuRow(title: option.title, isSelected: false, explanation: option.explanation)
            }
          }
        } label: { Text("codex") }
      }
      private func modeOptionIsSelected(_ option: ComposerModeOption, currentValue: String?) -> Bool {
        if option.isPlan {
          return viewModel.isPlanMode
        }
        return !viewModel.isPlanMode && option.value == currentValue
      }
      private func setSpawnPermission(_ value: String?) {}
    }
    struct ComposerSettingsOverflowMenu: View {
    #{locale_and_code}
      var body: some View {
        Menu {
          ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: viewModel.permissionProfiles.map(\\.id), languageCode: languageCode), id: \\.self) { option in
            Button {
              Task { await viewModel.setSpawnAgentPermission(option.value) }
            } label: {
              SettingsMenuRow(title: option.title, isSelected: false, explanation: option.explanation)
            }
            .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
          }
          spawnPermissionItems
          cursorModeItems
          codexPermissionItems
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
      private var spawnPermissionItems: some View {
          ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: viewModel.permissionProfiles.map(\\.id), languageCode: languageCode), id: \\.self) { option in
          SettingsMenuRow(title: option.title, isSelected: false, explanation: option.explanation)
        }
      }
      private var cursorModeItems: some View {
          ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: viewModel.permissionProfiles.map(\\.id), languageCode: languageCode), id: \\.self) { option in
          SettingsMenuRow(title: option.title, isSelected: false, explanation: option.explanation)
        }
      }
      private var codexPermissionItems: some View {
          ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: viewModel.permissionProfiles.map(\\.id), languageCode: languageCode), id: \\.self) { option in
          SettingsMenuRow(title: option.title, isSelected: false, explanation: option.explanation)
        }
      }
    }
  SWIFT
end

def good_settings_view_src
  <<~SWIFT
    struct SettingsView: View {
    #{locale_and_code}
      var body: some View {
        Section {
          ForEach(agentCatalog.allDescriptors, id: \\.ref) { descriptor in
            BypassToggleRow(descriptor: descriptor)
          }
        } footer: {
          Text(UIWording.settingsPermissionFooter(languageCode: languageCode))
            .fixedSize(horizontal: false, vertical: true)
        }
        Button {
          openWindow(id: AgentConsoleCommands.windowID)
        } label: {
          Label("エージェント管理を開く", systemImage: "wrench.and.screwdriver")
        }
        .buttonStyle(.bordered)
      }
      private struct BypassToggleRow: View {
        let descriptor: AgentDescriptor
        @AppStorage private var isEnabled: Bool
        init(descriptor: AgentDescriptor) {
          self.descriptor = descriptor
          _isEnabled = AppStorage(wrappedValue: true, descriptor.bypassKey)
        }
    #{locale_and_code}
        private var agentKind: UIWording.PermissionAgent {
          switch descriptor.ref { default: .custom }
        }
        var body: some View {
          let wording = UIWording.launchPermission(agent: agentKind, displayName: descriptor.displayName, languageCode: languageCode)
          Toggle(isOn: $isEnabled) {
            VStack {
              Label(wording.rowLabel, systemImage: descriptor.symbolName)
              Text(wording.offExplanation).fixedSize(horizontal: false, vertical: true)
              Text(wording.onExplanation).fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }
  SWIFT
end

def good_claude_perm_src
  <<~SWIFT
    struct ClaudePermissionsPane: View {
    #{locale_and_code}
      var body: some View {
        AgentConsolePane(
          title: UIWording.permission(agent: .claude, kind: .permissionsPaneIntro, value: nil, languageCode: languageCode).title,
          subtitle: UIWording.permission(agent: .claude, kind: .permissionsPaneIntro, value: nil, languageCode: languageCode).explanation,
          controls: AnyView(editor)
        ) {
          ForEach(ClaudePermissionBucket.allCases) { bucket in
            bucketSection(bucket)
            let w = UIWording.permission(agent: .claude, kind: .claudeRuleBucket, value: bucket.rawValue, languageCode: languageCode)
            Text(w.title)
            Text(w.explanation).fixedSize(horizontal: false, vertical: true)
            Label(w.title, systemImage: bucket.symbolName).tag(bucket)
          }
        }
      }
      private var editor: some View {
        Picker("", selection: $draftBucket) {
          ForEach(ClaudePermissionBucket.allCases) { bucket in
            let w = UIWording.permission(agent: .claude, kind: .claudeRuleBucket, value: bucket.rawValue, languageCode: languageCode)
            Label(w.title, systemImage: bucket.symbolName).tag(bucket)
          }
        }
      }
      private func bucketSection(_ bucket: ClaudePermissionBucket) -> some View {
        let w = UIWording.permission(agent: .claude, kind: .claudeRuleBucket, value: bucket.rawValue, languageCode: languageCode)
        VStack {
          Text(w.title)
          Text(w.explanation).fixedSize(horizontal: false, vertical: true)
        }
      }
      func addRule() {
        model.applySettings(updated.apply(to:), successMessage: "「\\(rule)」を\\(draftBucket.displayName)に追加しました。")
      }
    }
  SWIFT
end

def good_cursor_perm_src
  <<~SWIFT
    struct CursorPermissionsPane: View {
    #{locale_and_code}
      var body: some View {
        AgentConsolePane(
          title: UIWording.permission(agent: .cursor, kind: .permissionsPaneIntro, value: nil, languageCode: languageCode).title,
          subtitle: UIWording.permission(agent: .cursor, kind: .permissionsPaneIntro, value: nil, languageCode: languageCode).explanation,
          controls: AnyView(editor)
        ) {
          ForEach(CursorPermissionBucket.allCases) { bucket in
            bucketSection(bucket)
            let w = UIWording.permission(agent: .cursor, kind: .cursorRuleBucket, value: bucket.rawValue, languageCode: languageCode)
            Text(w.title)
            Text(w.explanation).fixedSize(horizontal: false, vertical: true)
            Label(w.title, systemImage: bucket.symbolName).tag(bucket)
          }
        }
      }
      private var editor: some View {
        Picker("", selection: $draftBucket) {
          ForEach(CursorPermissionBucket.allCases) { bucket in
            let w = UIWording.permission(agent: .cursor, kind: .cursorRuleBucket, value: bucket.rawValue, languageCode: languageCode)
            Label(w.title, systemImage: bucket.symbolName).tag(bucket)
          }
        }
      }
      private func bucketSection(_ bucket: CursorPermissionBucket) -> some View {
        let w = UIWording.permission(agent: .cursor, kind: .cursorRuleBucket, value: bucket.rawValue, languageCode: languageCode)
        VStack {
          Text(w.title)
          Text(w.explanation).fixedSize(horizontal: false, vertical: true)
        }
      }
      func addRule() {
        model.applySettings(updated.apply(to:), successMessage: "「\\(rule)」を\\(draftBucket.displayName)に追加しました。")
      }
    }
  SWIFT
end

def good_codex_settings_src
  <<~SWIFT
    struct CodexSettingsPane: View {
    #{locale_and_code}
      var body: some View {
        ForEach(CodexGeneralSettings.editableKeys) { key in
          settingRow(key)
        }
        .onAppear(perform: syncModelDraft)
      }
      func syncModelDraft() { modelDraft = current }
      func settingRow(_ key: CodexSettingKey) -> some View {
        let current = CodexGeneralSettings.value(key, in: model.config)
        if key == .approvalPolicy {
          Text(UIWording.permission(agent: .codex, kind: .settingKeyTitle, value: "approval_policy", languageCode: languageCode).title)
          Text(UIWording.permission(agent: .codex, kind: .codexApprovalPolicy, value: current, languageCode: languageCode).explanation)
          choiceControl(key, current, kind: .codexApprovalPolicy)
        } else if key == .sandboxMode {
          Text(UIWording.permission(agent: .codex, kind: .settingKeyTitle, value: "sandbox_mode", languageCode: languageCode).title)
          Text(UIWording.permission(agent: .codex, kind: .codexSandboxMode, value: current, languageCode: languageCode).explanation)
          choiceControl(key, current, kind: .codexSandboxMode)
        } else {
          Text(key.displayName)
          Text(key.explanation)
        }
      }
      func choiceControl(_ key: CodexSettingKey, _ current: String?, kind: UIWording.PermissionKind) -> some View {
        Picker("", selection: Binding(get: { current ?? "" }, set: { newValue in
          model.applyConfig({ CodexGeneralSettings.setValue(newValue, for: key, in: &$0) }, successMessage: "\\(key.displayName)を「\\(newValue)」にしました。")
        })) {
          ForEach(key.options(current: current), id: \\.self) { option in
            if kind == .codexSandboxMode {
              Text(UIWording.permission(agent: .codex, kind: .codexSandboxMode, value: option, languageCode: languageCode).title).tag(option)
            } else {
              Text(UIWording.permission(agent: .codex, kind: .codexApprovalPolicy, value: option, languageCode: languageCode).title).tag(option)
            }
          }
        }
      }
    }
  SWIFT
end

def good_cursor_settings_src
  <<~SWIFT
    struct CursorSettingsPane: View {
    #{locale_and_code}
      var body: some View {
        ForEach(CursorGeneralSettings.keys(in: group)) { key in
          settingRow(key)
        }
      }
      func settingRow(_ key: CursorSettingKey) -> some View {
        let current = CursorGeneralSettings.string(key, in: model.settings)
        if key == .approvalMode {
          Text(UIWording.permission(agent: .cursor, kind: .settingKeyTitle, value: "approvalMode", languageCode: languageCode).title)
          Text(UIWording.permission(agent: .cursor, kind: .cursorApprovalMode, value: current, languageCode: languageCode).explanation)
          control(key)
        } else if key == .sandboxMode {
          Text(UIWording.permission(agent: .cursor, kind: .settingKeyTitle, value: "sandbox.mode", languageCode: languageCode).title)
          Text(UIWording.permission(agent: .cursor, kind: .cursorSandboxMode, value: current, languageCode: languageCode).explanation)
          control(key)
        } else {
          Text(key.displayName)
          if let explanation = key.explanation { Text(explanation) }
          Toggle("", isOn: Binding(get: { false }, set: { _ in }))
        }
      }
      func control(_ key: CursorSettingKey) -> some View {
        let current = CursorGeneralSettings.string(key, in: model.settings)
        if key == .approvalMode {
          Picker("", selection: Binding(get: { current ?? "" }, set: { newValue in
            model.applySettings({ CursorGeneralSettings.setString(newValue, for: key, in: $0) }, successMessage: "\\(key.displayName)を「\\(newValue)」にしました。")
          })) {
            ForEach(key.options(current: current), id: \\.self) { option in
              Text(UIWording.permission(agent: .cursor, kind: .cursorApprovalMode, value: option, languageCode: languageCode).title).tag(option)
            }
          }
        } else if key == .sandboxMode {
          Picker("", selection: Binding(get: { current ?? "" }, set: { _ in })) {
            ForEach(key.options(current: current), id: \\.self) { option in
              Text(UIWording.permission(agent: .cursor, kind: .cursorSandboxMode, value: option, languageCode: languageCode).title).tag(option)
            }
          }
        }
      }
    }
  SWIFT
end

def good_planner_src
  <<~SWIFT
    enum AgentLaunchPlanner {
      static func profile(spec: AgentLaunchSpec, bypassEnabled: Bool) -> [String] {
        let bypassArgs = ["--force", "--sandbox", "disabled"]
        return bypassEnabled ? bypassArgs : spec.restrictedArgs
      }
    }
  SWIFT
end

def good_spawn_src
  <<~SWIFT
    enum SessionSpawnService {
      static func appServerPolicies(fullAccess: Bool) -> String {
        fullAccess ? "never" : "on-request"
      }
    }
  SWIFT
end

def good_app_env_src
  <<~SWIFT
    struct AppEnvironment {
      func make(fullAccess: Bool) {
        Spec(
          permissionMode: fullAccess ? "bypassPermissions" : "auto",
          runMode: fullAccess ? .runEverything : .autoReview
        )
      }
    }
  SWIFT
end

def good_uiwording_src
  <<~SWIFT
    public enum UIWording {
      public enum Key: String, CaseIterable { case planOption, permissionLabel, modeLabel }
      public static func text(_ key: Key, languageCode: String) -> String { key.rawValue }
    }
  SWIFT
end

def good_descriptor_src
  <<~SWIFT
    public enum AgentRegistry {
      public static let allDescriptors: [AgentDescriptor] = [
        AgentDescriptor(kind: .codex, launchSpec: AgentLaunchSpec(bypassArgs: ["--dangerously-bypass-approvals-and-sandbox"], restrictedArgs: [])),
        AgentDescriptor(kind: .cursor, launchSpec: AgentLaunchSpec(bypassArgs: ["--force", "--sandbox", "disabled"], restrictedArgs: ["--auto-review", "--sandbox", "enabled"])),
      ]
    }
  SWIFT
end

def good_cursor_chat_src
  <<~SWIFT
    switch runMode {
    case .configured: break
    case .autoReview: arguments.append(contentsOf: ["--auto-review", "--sandbox", "enabled"])
    case .runEverything: arguments.append(contentsOf: ["--force", "--sandbox", "disabled"])
    }
  SWIFT
end

def good_composition_root_src
  <<~SWIFT
    static func writeClaudeSettings(bypass: Bool, statusLineCommand: String) throws -> URL {
      let settings = ClaudeSettingsGenerator.settings(defaultMode: bypass ? "bypassPermissions" : "auto", dispatcher: "", statusLineCommand: statusLineCommand)
    }
  SWIFT
end

def good_phlox_app_src
  <<~SWIFT
    WindowGroup { ContentView().environment(\\.locale, appLanguage.locale) }
    Settings { SettingsView().environment(\\.locale, appLanguage.locale) }
    Window("Agent Console", id: "console") { ConsoleView().environment(\\.locale, appLanguage.locale) }
  SWIFT
end

def good_files
  {
    permissions: good_permissions_src,
    settings: good_settings_src,
    settings_view: good_settings_view_src,
    claude_perm: good_claude_perm_src,
    cursor_perm: good_cursor_perm_src,
    codex_settings: good_codex_settings_src,
    cursor_settings: good_cursor_settings_src,
    planner: good_planner_src,
    spawn: good_spawn_src,
    app_env: good_app_env_src,
    descriptor: good_descriptor_src,
    cursor_chat: good_cursor_chat_src,
    composition_root: good_composition_root_src,
    phlox_app: good_phlox_app_src,
    uiwording: good_uiwording_src,
  }
end

def run_selftest
  url = %(let url = "https://phlox.cc/privacy" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://phlox.cc/privacy"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert normalize_code(%(Text("hello world"))).include?("hello world"), "正例: 文字列内空白を正規化で消さない"
  selftest_assert normalize_code(%(Text("hello world"))) != normalize_code(%(Text("helloworld"))), "負例: 文字列内空白の改変を検出する"

  good = good_files
  selftest_errors_eq check_product(good), [], "正例: 契約どおりの配線は空 NG"
  selftest_errors_eq check_invariants(good, good), [], "正例: 説明の折り返しと raw value・未知値の保持"

  commented = with_file(good, :settings) { |src| src.sub("var body", "// keep https://phlox.cc/privacy \\(x)\n      var body") }
  selftest_errors_eq check_product(commented), [], "正例: コメント・URL・補間だけを加える"

  overflow_old = with_file(good, :settings) { |src|
    src.sub(
      "struct ComposerSettingsOverflowMenu: View {",
      "struct ComposerSettingsOverflowMenu: View {"
    ).sub(
      /struct ComposerSettingsOverflowMenu: View \{.*\z/m,
      <<~SWIFT
        struct ComposerSettingsOverflowMenu: View {
          var body: some View {
            Menu("Permission") {
              Button("Don't Ask") {}
            }
          }
        }
      SWIFT
    )
  }
  selftest_errors_eq check_product(overflow_old), [
    "省略メニューが UIWording.permission に接続していない",
    "ComposerSettingsOverflowMenu が環境 locale から languageCode を渡していない",
    "#{PATHS[:settings]} に権限文言の直値 \"Don't Ask\" が残っている",
  ], "負例: 省略メニューだけ未修正"

  selected_old = with_file(good, :settings) { |src|
    src.sub(
      "ComposerControlChip(title: viewModel.isPlanMode ? UIWording.text(.planOption, languageCode: languageCode) : UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: selectedClaudePermission, languageCode: languageCode).title)",
      'ComposerControlChip(title: "Bypass")'
    )
  }
  selftest_errors_eq check_product(selected_old), [
    "選択中ラベルが UIWording.permission に接続していない",
  ], "負例: 選択中ラベルが旧文言"

  mgmt_old = with_file(good, :claude_perm) { |src|
    src.gsub("UIWording.permission(agent: .claude, kind: .claudeRuleBucket, value: bucket.rawValue, languageCode: languageCode)", "bucket")
       .gsub("kind: .permissionsPaneIntro", "kind: .claudePermissionMode")
  }
  mgmt_ng = check_product(mgmt_old)
  selftest_assert mgmt_ng.include?("ClaudePermissionsPane の権限説明が UIWording.permission に接続していない"), "負例: 管理画面の説明が旧文言 (#{mgmt_ng.inspect})"

  swapped = with_file(good, :settings) { |src|
    src.sub(
      'ComposerModeOption(value: "dontAsk", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "dontAsk", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "dontAsk", languageCode: languageCode).explanation, isPlan: false)',
      'ComposerModeOption(value: "dontAsk", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "bypassPermissions", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "bypassPermissions", languageCode: languageCode).explanation, isPlan: false)'
    )
  }
  selftest_errors_eq check_product(swapped), [
    "Claude の dontAsk 説明が bypassPermissions に接続している",
  ], "負例: dontAsk と bypass の説明交換"

  codex_mix = with_file(good, :codex_settings) { |src|
    src.gsub("kind: .codexApprovalPolicy", "kind: .codexSandboxMode")
  }
  selftest_errors_eq check_product(codex_mix), [
    "Codex の承認方針が実行制限の正本へ接続している",
  ], "負例: Codex の承認方針と実行制限の混同"

  cursor_mix = with_file(good, :settings) { |src|
    src.gsub("kind: .cursorOperationMode", "kind: .cursorApprovalMode")
  }
  selftest_errors_eq check_product(cursor_mix), [
    "Cursor の選択中ラベルが UIWording.permission に接続していない",
    "Cursor の動作モードが承認方式の正本へ接続している",
  ], "負例: Cursor の動作モードへ承認説明を流用"

  custom_full = with_file(good, :settings_view) { |src|
    src.sub("Label(wording.rowLabel, systemImage: descriptor.symbolName)", 'Label("\\(descriptor.displayName): フルアクセス（bypass）", systemImage: descriptor.symbolName)')
  }
  custom_ng = check_product(custom_full)
  selftest_assert custom_ng.include?("カスタムエージェントをフルアクセス扱いしている"), "負例: カスタムのフルアクセス (#{custom_ng.inspect})"

  unset_guess = with_file(good, :settings) { |src|
    src.sub(
      "UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: nil, languageCode: languageCode)",
      'UIWording.permission(agent: .cursor, kind: .cursorApprovalMode, value: "unrestricted", languageCode: languageCode)'
    )
  }
  selftest_errors_eq check_product(unset_guess), [
    "Cursor の動作モードが承認方式の正本へ接続している",
  ], "負例: 未設定から権限を推測"

  binding_changed = with_file(good, :settings_view) { |src|
    src.sub("AppStorage(wrappedValue: true, descriptor.bypassKey)", "AppStorage(wrappedValue: false, descriptor.bypassKey)")
  }
  selftest_errors_eq check_invariants(binding_changed, good), [
    "BypassToggleRow の Binding が TASK50_BASELINE から変化している",
  ], "負例: Binding の改変"

  tag_changed = with_file(good, :settings) { |src|
    src.sub('.accessibilityIdentifier("ChatComposer.claudePermissionMenu")', "")
  }
  selftest_errors_eq check_invariants(tag_changed, good), [
    "#{PATHS[:settings]} の tag \"claudePermissionMenu\" が TASK50_BASELINE から変化している",
  ], "負例: tag の改変"

  default_changed = with_file(good, :settings_view) { |src|
    src.sub("buttonStyle(.bordered)", "buttonStyle(.plain)")
  }
  selftest_errors_eq check_invariants(default_changed, good), [
    "tag が TASK50_BASELINE から変化している",
  ], "負例: 既定値・ボタン様式の改変"

  action_changed = with_file(good, :settings) { |src|
    src.gsub("setSpawnPermission(option.value)", "saveNow()")
  }
  selftest_errors_eq check_invariants(action_changed, good), [
    "action が TASK50_BASELINE から変化している",
  ], "負例: action の改変"

  launch_changed = with_file(good, :planner) { |src|
    src.sub("--force", "--yes")
  }
  selftest_errors_eq check_invariants(launch_changed, good), [
    "起動引数が TASK50_BASELINE から変化している",
  ], "負例: 起動引数の改変"

  appear_save = with_file(good, :codex_settings) { |src|
    src.sub("ForEach(CodexGeneralSettings.editableKeys) { key in", "onAppear { model.applyConfig({ $0 }, successMessage: \"x\") }\n        ForEach(CodexGeneralSettings.editableKeys) { key in")
  }
  selftest_errors_eq check_invariants(appear_save, good), [
    "表示時に保存処理が追加されている",
  ], "負例: 表示時の保存処理追加"

  plan48 = with_file(good, :settings) { |src|
    src.gsub("UIWording.text(.planOption, languageCode: languageCode)", '"Plan"')
       .gsub("UIWording.text(.permissionLabel, languageCode: languageCode)", '"Permission"')
  }
  selftest_errors_eq check_product(plan48), [
    "Plan の正本参照が巻き戻っている",
  ], "負例: task-48 の一般文言の巻き戻し"

  deleted = with_file(good, :settings) { |src|
    src.gsub("ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode)", "ForEach([] as [ComposerModeOption]")
  }
  deleted_prod = check_product(deleted)
  deleted_inv = check_invariants(deleted, good)
  selftest_assert deleted_prod.include?("通常メニューが UIWording.permission に接続していない") || deleted_inv.include?("コントロールが削除されている"), "負例: コントロール削除 (prod=#{deleted_prod.inspect} inv=#{deleted_inv.inspect})"

  unused = with_file(good, :settings_view) { |src|
    src.sub(
      "let wording = UIWording.launchPermission(agent: agentKind, displayName: descriptor.displayName, languageCode: languageCode)",
      "let wording = LaunchPermissionWording(rowLabel: descriptor.displayName, offExplanation: \"x\", onExplanation: \"y\")"
    ) + "\n    func decoy() { _ = UIWording.launchPermission(agent: .custom, displayName: \"x\", languageCode: languageCode) }\n    if false { Text(UIWording.launchPermission(agent: .claude, displayName: \"x\", languageCode: languageCode).rowLabel) }\n"
  }
  unused_ng = check_product(unused)
  selftest_assert unused_ng.include?("設定の権限行が UIWording.launchPermission に接続していない"), "負例: 未使用の正本参照 (#{unused_ng.inspect})"

  h1 = with_file(good, :settings) { |src|
    src.sub(
      'ComposerModeOption(value: "acceptEdits", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "acceptEdits"',
      'ComposerModeOption(value: "auto", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "acceptEdits"'
    ).sub(
      'ComposerModeOption(value: "auto", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "auto"',
      'ComposerModeOption(value: "acceptEdits", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "auto"'
    )
  }
  selftest_errors_eq check_invariants(h1, good), [
    "メニューの項目集合・順序が TASK50_BASELINE から変化している",
  ], "負例: H1 メニュー項目順序の変化"

  h2_swap = with_file(good, :spawn) { |src|
    src.sub('fullAccess ? "never" : "on-request"', 'fullAccess ? "on-request" : "never"')
  }
  selftest_errors_eq check_invariants(h2_swap, good), [
    "起動引数が TASK50_BASELINE から変化している",
  ], "負例: H2 起動引数の入れ替え"

  h2_missing = check_invariants(good, good.merge(spawn: nil))
  selftest_errors_eq h2_missing, [
    "基準時点の #{PATHS[:spawn]} を git show できない",
  ], "負例: H2 基準 spawn 欠落"

  h3_unused = with_file(good, :settings_view) { |src|
    src.sub('Label(wording.rowLabel, systemImage: descriptor.symbolName)', 'Label("row", systemImage: descriptor.symbolName)')
  }
  selftest_errors_eq check_product(h3_unused), [
    "設定の権限行が UIWording.launchPermission に接続していない",
  ], "負例: H3 未使用の launchPermission"

  h3_string = with_file(good, :settings) { |src|
    src.sub(
      "ComposerControlChip(title: viewModel.isPlanMode ? UIWording.text(.planOption, languageCode: languageCode) : UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: selectedClaudePermission, languageCode: languageCode).title)",
      'ComposerControlChip(title: "UIWording.permission")'
    )
  }
  selftest_errors_eq check_product(h3_string), [
    "選択中ラベルが UIWording.permission に接続していない",
  ], "負例: H3 文字列に UIWording.permission"

  h3_comment = with_file(good, :settings) { |src|
    src.sub(
      "ComposerControlChip(title: viewModel.isPlanMode ? UIWording.text(.planOption, languageCode: languageCode) : UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: selectedClaudePermission, languageCode: languageCode).title)",
      'ComposerControlChip(title: viewModel.isPlanMode ? UIWording.text(.planOption, languageCode: languageCode) : /* UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: selectedClaudePermission, languageCode: languageCode).title */ "Bypass")'
    )
  }
  selftest_errors_eq check_product(h3_comment), [
    "選択中ラベルが UIWording.permission に接続していない",
  ], "負例: H3 コメントアウトした permission"

  h3_iffalse = with_file(good, :settings) { |src|
    src.sub(
      "ComposerControlChip(title: viewModel.isPlanMode ? UIWording.text(.planOption, languageCode: languageCode) : UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: selectedClaudePermission, languageCode: languageCode).title)",
      'ComposerControlChip(title: "Bypass")\n        if false { UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: selectedClaudePermission, languageCode: languageCode) }'
    )
  }
  selftest_errors_eq check_product(h3_iffalse), [
    "選択中ラベルが UIWording.permission に接続していない",
  ], "負例: H3 if false の permission"

  h4_one = with_file(good, :settings_view) { |src|
    src.sub("Text(wording.offExplanation).fixedSize(horizontal: false, vertical: true)", "Text(isEnabled ? wording.onExplanation : wording.offExplanation).fixedSize(horizontal: false, vertical: true)")
  }
  selftest_errors_eq check_product(h4_one), [
    "設定の権限行が ON/OFF 説明を同時に描画していない",
  ], "負例: H4 三項演算子の片側描画"

  h4_agent = with_file(good, :settings_view) { |src|
    src.sub("agent: agentKind", "agent: .claude")
  }
  selftest_errors_eq check_product(h4_agent), [
    "設定の権限行が agent を固定している",
  ], "負例: H4 agent 固定"

  h4_footer = with_file(good, :settings_view) { |src|
    src.sub("Text(UIWording.settingsPermissionFooter(languageCode: languageCode))", 'Text("old")') +
      "\n    func decoy() { _ = UIWording.settingsPermissionFooter(languageCode: languageCode) }\n"
  }
  selftest_errors_eq check_product(h4_footer), [
    "設定の footer が UIWording.settingsPermissionFooter に接続していない",
  ], "負例: H4 footer 未使用参照"

  h4_list = with_file(good, :settings_view) { |src|
    src.sub("agentCatalog.allDescriptors", "[d1, d2, d3]")
  }
  selftest_errors_eq check_product(h4_list), [
    "動的エージェント一覧が固定3行になっている",
  ], "負例: H4 固定3行"

  h5_intro = with_file(good, :cursor_perm) { |src|
    src.gsub("kind: .permissionsPaneIntro", "kind: .cursorRuleBucket")
  }
  selftest_errors_eq check_product(h5_intro), [
    "CursorPermissionsPane の導入文が UIWording.permission に接続していない",
  ], "負例: H5 Cursor 導入文の欠落"

  h5_choice = with_file(good, :codex_settings) { |src|
    src.sub(
      "Text(UIWording.permission(agent: .codex, kind: .codexSandboxMode, value: option, languageCode: languageCode).title).tag(option)",
      "Text(option).tag(option)"
    )
  }
  selftest_errors_eq check_product(h5_choice), [
    "CodexSettingsPane の choiceControl が UIWording.permission に接続していない",
  ], "負例: H5 Codex choiceControl の生 Text(option)"

  h6 = with_file(good, :settings) { |src|
    blob = named_body(src, "ComposerSettingsControlsView", "cursorModeMenu")
    src.sub(blob, blob.sub(", explanation: option.explanation", ""))
  }
  selftest_errors_eq check_product(h6), [
    "Cursor の通常メニューが UIWording.permission に接続していない",
  ], "負例: H6 Cursor 通常メニューの explanation 欠落"

  h7_locale = with_file(good, :settings) { |src|
    src.sub("@Environment(\\.locale) private var locale\n", "")
  }
  selftest_errors_eq check_product(h7_locale), [
    "ComposerSettingsControls が locale を受け取っていない",
  ], "負例: H7 locale 未受信"

  h7_current = with_file(good, :settings) { |src|
    src.sub("private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }", "private var languageCode: String { Locale.current.identifier }")
  }
  selftest_errors_eq check_product(h7_current), [
    "ComposerSettingsControls が環境 locale から languageCode を渡していない",
  ], "負例: H7 Locale.current"

  h7_ignore = with_file(good, :settings) { |src|
    struct = extract_struct_body(src, "ComposerSettingsControlsView")
    src.sub(struct, struct.gsub("languageCode: languageCode", "languageCode: Locale.current.identifier"))
  }
  selftest_errors_eq check_product(h7_ignore), [
    "ComposerSettingsControls が環境 locale から languageCode を渡していない",
  ], "負例: H7 languageCode 引数無視"

  d2_line = with_file(good, :settings) { |src|
    src.sub("Text(explanation).fixedSize(horizontal: false, vertical: true)", "Text(explanation).lineLimit(1)")
  }
  selftest_errors_eq check_product(d2_line), [
    "SettingsMenuRow の説明が行数制限されている",
  ], "負例: D2 lineLimit"

  d2_frame = with_file(good, :settings) { |src|
    src.sub("Text(explanation).fixedSize(horizontal: false, vertical: true)", "Text(explanation).frame(height: 8)")
  }
  selftest_errors_eq check_product(d2_frame), [
    "SettingsMenuRow の説明が固定高で切断されている",
  ], "負例: D2 固定高"

  d2_scale = with_file(good, :settings) { |src|
    src.sub("Text(explanation).fixedSize(horizontal: false, vertical: true)", "Text(explanation).minimumScaleFactor(0.1)")
  }
  selftest_errors_eq check_product(d2_scale), [
    "SettingsMenuRow の説明が縮小されている",
  ], "負例: D2 縮小"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_errors_eq unset_errs, ["TASK50_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: 基準の未設定"
  selftest_assert unset.nil?, "負例: 未設定は nil"
  _, invalid_errs = baseline_env_errors("not-a-sha")
  selftest_errors_eq invalid_errs, ["TASK50_BASELINE がコミット SHA ではない（ブランチ名は使えない）: not-a-sha"], "負例: SHA 不正"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK50_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD 指定"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK50_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD~1 指定"
  _, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK50_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: @ 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK50_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_errors_eq parse_contract_baseline_text("---\nfoo: 1\n"), :missing, "負例: 契約 baseline_commit 欠落"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n"), :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"not-a-sha\"\n"), :invalid, "負例: 契約 baseline_commit 不正"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"abc1234\"\n"), "abc1234", "正例: 契約 baseline_commit がクォート付き SHA"
  ph_errs = contract_baseline_errors("---\nbaseline_commit: \"PM が凍結時に設定\"\n", "abc1234")
  selftest_errors_eq ph_errs, ["契約 baseline_commit がプレースホルダ（凍結時に実 SHA へ置換する）"], "負例: プレースホルダは NG"

  head_full = git_full_sha("HEAD")
  other_full = git_full_sha("HEAD~1")
  selftest_assert !head_full.nil? && !other_full.nil? && head_full != other_full, "selftest 用に有効で異なる 2 コミットが必要"
  real_mismatch = contract_baseline_errors("---\nbaseline_commit: \"#{head_full}\"\n", other_full)
  selftest_errors_eq real_mismatch, ["TASK50_BASELINE が契約 baseline_commit と一致しない"], "負例: 契約不一致"

  pre_ok = check_frozen_baseline(
    head_full,
    permissions_blob: nil,
    uiwording_blob: good_uiwording_src,
    settings_blob: good_settings_src,
    test_blob: "test",
    test_now: "test",
    rb_blob: "rb",
    rb_now: "rb"
  )
  selftest_errors_eq pre_ok, [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  m2 = check_frozen_baseline(
    head_full,
    permissions_blob: nil,
    uiwording_blob: nil,
    settings_blob: good_settings_src,
    test_blob: "test",
    test_now: "test",
    rb_blob: "rb",
    rb_now: "rb"
  )
  selftest_errors_eq m2, ["基準時点に UIWording.swift が無い（task-48 完成実装を含まない）"], "負例: M2 基準に UIWording が無い"

  post_ng = check_frozen_baseline(
    head_full,
    permissions_blob: good_permissions_src,
    uiwording_blob: good_uiwording_src,
    settings_blob: good_settings_src,
    test_blob: "test",
    test_now: "test",
    rb_blob: "rb",
    rb_now: "rb"
  )
  selftest_errors_eq post_ng, ["基準時点に UIWording+Permissions.swift がある（実装前の凍結ではない）"], "負例: 実装後の自己比較"

  selftest_errors_eq frozen_artifact_errors("rb 自身", "now", "frozen"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 凍結検査の改変"
  selftest_errors_eq frozen_artifact_errors("受け入れテスト", "now", "frozen"), ["基準時点の受け入れテストが現在と同一ではない"], "負例: 凍結テストの改変"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "same", "same"), [], "正例: 凍結 rb と作業ツリーが同一"

  missing = check_product({})
  selftest_assert missing.include?("#{PATHS[:permissions]} が存在しない"), "負例: 対象欠落"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task50-wiring --selftest: OK"
  exit 0
end

ng = []
raw = ENV["TASK50_BASELINE"]
baseline, env_errs = baseline_env_errors(raw)
ng.concat(env_errs)

contract_text = File.exist?(CONTRACT_PATH) ? File.read(CONTRACT_PATH) : nil
if contract_text.nil?
  ng << "契約ファイル #{CONTRACT_PATH} が無い"
else
  ng.concat(contract_baseline_errors(contract_text, baseline))
end

files = worktree_files
ng.concat(check_product(files))

if baseline
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK50_BASELINE が無効なコミット: #{baseline}"
  else
    ng.concat(check_frozen_baseline(full))
    previous = baseline_files(full)
    ng.concat(check_invariants(files, previous))
  end
end

ng = ng.uniq
if ng.empty?
  puts "task50-wiring: OK"
else
  ng.each { |m| puts "task50-wiring: NG #{m}" }
  exit 1
end
