#!/usr/bin/env ruby
# task-48 配線検査: 一般操作文言が UIWording 正本へ接続され、
# 残余の操作文言直値が無く、action / Binding / tag / Plan / 計算は
# TASK48_BASELINE から変わらないこと。
# コメントと文字列は同時識別する（task43-wiring.rb / task17-wiring.rb と同じ字句走査）。
# 比較対象は git show <TASK48_BASELINE>:<path> と作業ファイル。HEAD blob は使わない。

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

CONTRACT_PATH = "tasks/task-48.md"
WIRING_RB_PATH = ".claude/scripts/task48-wiring.rb"
TEST_PATH = "macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceUIWordingTests.swift"

PATHS = {
  uiwording: "macos/Packages/DesignSystem/Sources/DesignSystem/UIWording.swift",
  chat_composer: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift",
  grid_column: "macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift",
  settings: "macos/Packages/SessionFeature/Sources/SessionFeature/ComposerSettingsControls.swift",
  context: "macos/Packages/SessionFeature/Sources/SessionFeature/ComposerContextIndicator.swift",
  cells_basic: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift",
  cells_structured: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift",
  accessories: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionAccessories.swift",
  code_block: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeBlock.swift",
  markdown: "macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift",
  copy_button: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCopyButton.swift",
  team_composer: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamComposer.swift",
  sidebar: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift",
}.freeze

KEY_CASES = %w[
  composerPlaceholder errorHeading missingCommand outputAvailable missingSubAgentDescription
  copyAction copyCodeHelp copyMessageHelp copiedFeedback missingCodeBlockLanguage
  missingMarkdownLanguage acceptAction declineAction cancelAction modelLabel
  reasoningEffortLabel permissionLabel approvalLabel modeLabel planOption
  effortLow effortMedium effortHigh effortXHigh effortMax refreshAction
  missingBranch branchCheckoutFailed noLocalBranches contextWindowHeading projectsHeading
].freeze

FORBIDDEN_UIWORDING = [
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

PLACEHOLDER_LEFTOVER = ["Ask Phlox anything...", "メッセージを入力", "Enter a message"].freeze

SITE_LEFTOVER = {
  chat_composer: PLACEHOLDER_LEFTOVER,
  grid_column: PLACEHOLDER_LEFTOVER,
  team_composer: PLACEHOLDER_LEFTOVER,
  cells_basic: ["Error", "Turn cost"],
  cells_structured: ["Command", "Output available", "Sub-agent"],
  code_block: ["Copy", "Copy code", "text"],
  markdown: ["Copy", "Copy code", "code"],
  copy_button: ["Copy message", "コピーしました", "Copied"],
  accessories: ["Accept", "Decline", "Cancel"],
  sidebar: ["Projects"],
  context: ["Branch checkout failed", "No local branches", "Context window:"],
  settings: [
    "Model", "Effort", "Reasoning Effort", "Permission", "Approval", "Mode", "Plan",
    "Low", "Medium", "High", "XHigh", "X High", "Max", "Refresh", "Branch",
  ],
}.freeze

VIEW_SITES = [
  { file: :chat_composer, struct: "ChatComposer", key: "composerPlaceholder" },
  { file: :grid_column, struct: "GridChatColumn", key: "composerPlaceholder" },
  { file: :team_composer, struct: "TeamComposer", key: "composerPlaceholder" },
  { file: :cells_basic, struct: "ErrorMessageCell", key: "errorHeading" },
  { file: :cells_basic, struct: "TurnCostCell", key: "turnCostAccessibility" },
  { file: :cells_structured, struct: "CommandExecutionCell", key: "missingCommand" },
  { file: :cells_structured, struct: "CommandExecutionCell", key: "outputAvailable" },
  { file: :cells_structured, struct: "SubAgentMarkerCell", key: "missingSubAgentDescription" },
  { file: :code_block, struct: "CodeBlockView", key: "copyAction" },
  { file: :code_block, struct: "CodeBlockView", key: "copyCodeHelp" },
  { file: :code_block, struct: "CodeBlockView", key: "missingCodeBlockLanguage" },
  { file: :markdown, struct: "RichMarkdownView", key: "copyAction" },
  { file: :markdown, struct: "RichMarkdownView", key: "copyCodeHelp" },
  { file: :markdown, struct: "RichMarkdownView", key: "missingMarkdownLanguage" },
  { file: :copy_button, struct: "MessageCopyButton", key: "copyMessageHelp" },
  { file: :copy_button, struct: "MessageCopyButton", key: "copiedFeedback" },
  { file: :accessories, struct: "ApprovalBanner", key: "acceptAction" },
  { file: :accessories, struct: "ApprovalBanner", key: "declineAction" },
  { file: :accessories, struct: "ApprovalBanner", key: "cancelAction" },
  { file: :sidebar, struct: "DashboardSidebarView", key: "projectsHeading" },
  { file: :settings, struct: "ComposerSettingsControlsView", key: "modelLabel" },
  { file: :settings, struct: "ComposerSettingsControlsView", key: "reasoningEffortLabel" },
  { file: :settings, struct: "ComposerSettingsControlsView", key: "permissionLabel" },
  { file: :settings, struct: "ComposerSettingsControlsView", key: "approvalLabel" },
  { file: :settings, struct: "ComposerSettingsControlsView", key: "modeLabel" },
  { file: :settings, struct: "ComposerSettingsControlsView", key: "planOption" },
  { file: :settings, struct: "ComposerSettingsOverflowMenu", key: "modelLabel" },
  { file: :settings, struct: "ComposerSettingsOverflowMenu", key: "reasoningEffortLabel" },
  { file: :settings, struct: "ComposerSettingsOverflowMenu", key: "permissionLabel" },
  { file: :settings, struct: "ComposerSettingsOverflowMenu", key: "modeLabel" },
  { file: :settings, struct: "ComposerOverflowBranchMenu", key: "refreshAction" },
  { file: :settings, struct: "ComposerOverflowBranchMenu", key: "missingBranch" },
  { file: :context, struct: "ComposerBranchControl", key: "branchCheckoutFailed" },
  { file: :context, struct: "ComposerBranchControl", key: "noLocalBranches" },
].freeze

REQUIRED_AX = {
  chat_composer: ["ChatComposer.input"],
  grid_column: ["GridComposer.input"],
  code_block: ["CodeBlock.copyButton"],
  cells_basic: ["ChatMessage.turnCost"],
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
        errs << "TASK48_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK48_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK48_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK48_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
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

def implementation_in_baseline_errors(uiwording_blob)
  if uiwording_blob
    ["基準時点に UIWording.swift がある（実装前の凍結ではない）"]
  else
    []
  end
end

def check_frozen_baseline(baseline, opts = {})
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK48_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  unless git_is_ancestor?(full, "HEAD")
    ng << "TASK48_BASELINE が HEAD の祖先ではない"
  end
  ui_blob = opts.key?(:uiwording_blob) ? opts[:uiwording_blob] : git_show(full, PATHS[:uiwording])
  ng.concat(implementation_in_baseline_errors(ui_blob))
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

def check_uiwording(src)
  ng = []
  if src.nil?
    ng << "#{PATHS[:uiwording]} が存在しない"
    return ng
  end
  enum_body = extract_enum_body(src, "UIWording")
  if enum_body.nil?
    ng << "UIWording を括弧対応で切り出せない"
    return ng
  end
  ng << "UIWording が public enum ではない" unless src.match?(/public\s+enum\s+UIWording\b/)
  ng << "UIWording.Key が無い" unless code_has_ident?(src, "Key")
  params = extract_func_params(src, "text")
  if params.nil?
    ng << "UIWording.text を括弧対応で切り出せない"
  else
    pc = compact(params)
    ng << "UIWording.text が languageCode を受け取らない" unless pc.include?("languageCode")
  end
  %w[contextUsagePercent contextTokenUsage turnCostAccessibility].each do |name|
    p = extract_func_params(src, name)
    if p.nil?
      ng << "UIWording.#{name} が無い"
    elsif !compact(p).include?("languageCode")
      ng << "UIWording.#{name} が languageCode を受け取らない"
    end
  end
  KEY_CASES.each do |name|
    ng << "UIWording.Key.#{name} が無い" unless src.match?(/\bcase\s+#{Regexp.escape(name)}\b/)
  end
  masked = mask_strings_and_comments(src)
  FORBIDDEN_UIWORDING.each do |snip|
    if masked.include?(snip)
      ng << "UIWording が禁止語 #{snip} を使っている"
    end
  end
  ng
end

def require_key(files, file_key, struct, key, message)
  src = files[file_key]
  return [message.sub("を参照していない", "のファイルが存在しない")] if src.nil?
  reach = reachable_in_struct(src, struct, "body")
  if reach == :unparseable
    return ["#{struct} の body を括弧対応で切り出せない"]
  end
  has_ui = code_has_ident?(reach, "UIWording")
  has_key = code_has_ident?(reach, key)
  has_lang = compact(reach).include?("languageCode")
  return [message] unless has_ui && has_key && has_lang
  []
end

def check_copy_ax(files)
  src = files[:copy_button]
  return ["#{PATHS[:copy_button]} が存在しない"] if src.nil?
  reach = reachable_in_struct(src, "MessageCopyButton", "body")
  return ["MessageCopyButton の body を括弧対応で切り出せない"] if reach == :unparseable
  ax = extract_call_args(reach, "accessibilityLabel") || ""
  unless code_has_ident?(ax, "copiedFeedback") && compact(ax).include?("didCopy")
    return ["MessageCopyButton のコピー後 AX ラベルが UIWording.copiedFeedback ではない"]
  end
  []
end

def check_overflow_menus(files)
  src = files[:settings]
  return ["#{PATHS[:settings]} が存在しない"] if src.nil?
  reach = reachable_in_struct(src, "ComposerSettingsOverflowMenu", "body")
  return ["ComposerSettingsOverflowMenu の body を括弧対応で切り出せない"] if reach == :unparseable
  ng = []
  %w[modelLabel reasoningEffortLabel permissionLabel modeLabel].each do |key|
    unless code_has_ident?(reach, "UIWording") && code_has_ident?(reach, key)
      ng << "省略メニューが UIWording.Key.#{key} を参照していない"
    end
  end
  ng
end

def check_language(files)
  ng = []
  locale_structs = {
    chat_composer: "ChatComposer",
    grid_column: "GridChatColumn",
    team_composer: "TeamComposer",
    cells_basic: "ErrorMessageCell",
    copy_button: "MessageCopyButton",
    accessories: "ApprovalBanner",
    sidebar: "DashboardSidebarView",
    settings: "ComposerSettingsControlsView",
    context: "ComposerBranchControl",
    code_block: "CodeBlockView",
    markdown: "RichMarkdownView",
  }
  locale_structs.each do |file_key, struct|
    src = files[file_key]
    next ng << "#{PATHS[file_key]} が存在しない" if src.nil?
    body = extract_struct_body(src, struct)
    next ng << "#{struct} を括弧対応で切り出せない" if body.nil?
    unless has_locale_environment?(body)
      ng << "#{struct} が @Environment(\\.locale) を使っていない"
    end
    if language_code_pinned?(body)
      ng << "#{struct} が表示言語を languageCode リテラルへ固定している"
    end
  end
  ng
end

def check_leftovers(files)
  ng = []
  SITE_LEFTOVER.each do |file_key, leftovers|
    src = files[file_key]
    next ng << "#{PATHS[file_key]} が存在しない" if src.nil?
    leftover_in_literals(src, leftovers).each do |lit|
      ng << "#{PATHS[file_key]} に操作文言の直値 #{lit.inspect} が残っている"
    end
  end
  ng
end

def check_output_available_condition(files)
  src = files[:cells_structured]
  return ["#{PATHS[:cells_structured]} が存在しない"] if src.nil?
  reach = reachable_in_struct(src, "CommandExecutionCell", "body")
  return ["CommandExecutionCell の body を括弧対応で切り出せない"] if reach == :unparseable
  c = compact(mask_strings_and_comments(reach))
  unless c.include?("isRunning") && c.include?("output.isEmpty")
    return ["CommandExecutionCell の出力あり表示条件が変わっている"]
  end
  []
end

def check_popover_text(files)
  src = files[:context]
  return ["#{PATHS[:context]} が存在しない"] if src.nil?
  params = extract_func_params(src, "lines")
  if params.nil?
    return ["ComposerContextPopoverText.lines を括弧対応で切り出せない"]
  end
  pc = compact(params)
  ng = []
  unless pc.include?("usedTokens") && pc.include?("windowTokens") && pc.include?("languageCode")
    ng << "ComposerContextPopoverText.lines の言語受け渡しが無い"
  end
  body = extract_func_body(src, "lines")
  if body.nil?
    ng << "ComposerContextPopoverText.lines の本体を切り出せない"
    return ng
  end
  unless code_has_ident?(body, "contextWindowHeading") && code_has_ident?(body, "contextUsagePercent") && code_has_ident?(body, "contextTokenUsage")
    ng << "ComposerContextPopoverText.lines が UIWording の数値テンプレートに接続していない"
  end
  args = extract_call_args(body, "UIWording.contextUsagePercent")
  ac = compact(args.to_s)
  if ac.include?("usedPercent:100-percent") || ac.include?("usedPercent:(100-percent)")
    ng << "ComposerContextPopoverText の使用率の引数が逆転している"
  elsif !ac.include?("usedPercent:percent") || !ac.include?("remainingPercent:100-percent")
    ng << "ComposerContextPopoverText の使用率の引数が逆転している" unless ng.any? { |m| m.include?("数値テンプレート") }
  end
  unless code_has_ident?(body, "tokenText")
    ng << "ComposerContextPopoverText.lines が tokenText を使っていない"
  end
  ng
end

def approval_respond_tokens(src)
  body = extract_struct_body(src.to_s, "ApprovalBanner")
  compact(mask_strings_and_comments(body.to_s)).scan(/\.accept|\.decline|\.cancel/)
end

def plan_flags_in_case(body, pattern)
  chunk = body[pattern]
  return nil unless chunk
  chunk.scan(/isPlan:\s*(true|false)/).flatten
end

def check_plan_order(src)
  body = extract_func_body(src.to_s, "composerModeOptions")
  return ["composerModeOptions を括弧対応で切り出せない"] if body.nil?
  claude = plan_flags_in_case(body, /builtin\(\.claudeCode\)[\s\S]*?(?=builtin\(\.cursor\)|\z)/)
  cursor = plan_flags_in_case(body, /builtin\(\.cursor\)[\s\S]*?(?=default:|\z)/)
  ng = []
  if claude.nil? || claude.empty? || claude.last != "true" || claude[0..-2].any? { |f| f == "true" }
    ng << "Plan の項目順序が TASK48_BASELINE から変化している"
  elsif cursor.nil? || cursor.empty? || cursor.last != "true" || cursor[0..-2].any? { |f| f == "true" }
    ng << "Plan の項目順序が TASK48_BASELINE から変化している"
  end
  ng
end

def check_sites(files)
  ng = []
  VIEW_SITES.each do |site|
    msg = "#{site[:struct]} が UIWording.Key.#{site[:key]} を参照していない"
    ng.concat(require_key(files, site[:file], site[:struct], site[:key], msg))
  end
  ng.concat(check_copy_ax(files))
  ng.concat(check_language(files))
  ng.concat(check_leftovers(files))
  ng.concat(check_output_available_condition(files))
  ng.concat(check_popover_text(files))
  ng
end

def check_product(files)
  ng = []
  ng.concat(missing_file(files, :uiwording))
  ng.concat(check_uiwording(files[:uiwording])) unless files[:uiwording].nil?
  PATHS.each_key do |key|
    next if key == :uiwording
    ng.concat(missing_file(files, key))
  end
  if PATHS.keys.all? { |k| k == :uiwording || files[k] }
    ng.concat(check_sites(files))
  end
  ng.uniq
end

def masked_compact_func(src, name)
  body = extract_func_body(src.to_s, name)
  return nil if body.nil?
  compact(mask_strings_and_comments(body))
end

def check_invariants(current, previous)
  ng = []
  return ng if previous.nil?

  if current[:team_composer] && previous[:team_composer]
    now = compact(mask_strings_and_comments(extract_struct_body(current[:team_composer], "TeamComposer").to_s))
    unless now.include?("isEnabled:targetDisplayName!=nil")
      ng << "TeamComposer の Binding が TASK48_BASELINE から変化している"
    end
    unless now.include?(".disabled(!canSend)") || now.include?("disabled(!canSend)")
      ng << "TeamComposer の Binding が TASK48_BASELINE から変化している" unless ng.include?("TeamComposer の Binding が TASK48_BASELINE から変化している")
    end
  end

  if current[:accessories] && previous[:accessories]
    if approval_respond_tokens(current[:accessories]) != approval_respond_tokens(previous[:accessories])
      ng << "ApprovalBanner の action が TASK48_BASELINE から変化している"
    end
    reach = reachable_in_struct(current[:accessories], "ApprovalBanner", "body")
    unless reach == :unparseable
      unless code_has_ident?(reach, "acceptAction") && compact(mask_strings_and_comments(reach)).include?(".accept")
        ng << "ApprovalBanner の承認操作が削除されている"
      end
    end
  end

  REQUIRED_AX.each do |file_key, lits|
    src = current[file_key]
    next if src.nil?
    vals = string_literal_values(src)
    lits.each do |lit|
      ng << "#{PATHS[file_key]} の tag #{lit.inspect} が TASK48_BASELINE から変化している" unless vals.include?(lit)
    end
  end

  if current[:settings]
    unless compact(mask_strings_and_comments(current[:settings])).include?("option.isPlan&&!viewModel.isPlanModeAvailable")
      ng << "Plan の排他条件が TASK48_BASELINE から変化している"
    end
    ng.concat(check_plan_order(current[:settings]))
    selected = masked_compact_func(current[:settings], "modeOptionIsSelected")
    if selected && !(selected.include?("ifoption.isPlan") && selected.include?("!viewModel.isPlanMode"))
      ng << "Plan の排他条件が TASK48_BASELINE から変化している"
    end
    defaults = mask_strings_and_comments(current[:settings]).scan(/default:\s*effort/)
    ng << "effort の既定値が TASK48_BASELINE から変化している" if defaults.size < 2
  end

  if current[:context]
    token = extract_func_body(current[:context], "tokenText")
    if token
      tc = compact(mask_strings_and_comments(token))
      nc = compact(strip_comments(token))
      unless tc.include?("1_000") && (nc.include?(".rounded()") || nc.include?("rounded()"))
        ng << "tokenText の計算が TASK48_BASELINE から変化している"
      end
    end
    lines = extract_func_body(current[:context], "lines")
    if lines
      lc = compact(mask_strings_and_comments(lines))
      unless lc.include?("windowTokens>0") && lc.include?("usedTokens") && lc.include?("100")
        ng << "コンテキスト割合計算が TASK48_BASELINE から変化している"
      end
    end
  end

  if current[:copy_button]
    copy = extract_func_body(current[:copy_button], "copyAndShowFeedback")
    if copy
      unless compact(copy).include?("1_400_000_000")
        ng << "コピー成功表示の時間が TASK48_BASELINE から変化している"
      end
    end
  end

  ng.uniq
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
    puts "task48-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task48-wiring --selftest: FAIL #{msg}"
    puts "  expected: #{expected.inspect}"
    puts "  actual:   #{actual.inspect}"
    exit 1
  end
end

def key_cases_src
  KEY_CASES.map { |n| "    case #{n}" }.join("\n")
end

def good_uiwording_src
  <<~SWIFT
    public enum UIWording {
      public enum Key: String, CaseIterable, Equatable, Hashable, Sendable {
    #{key_cases_src}
      }
      public static func text(_ key: Key, languageCode: String) -> String { "x" }
      public static func contextUsagePercent(usedPercent: Int, remainingPercent: Int, languageCode: String) -> String { "x" }
      public static func contextTokenUsage(usedText: String, windowText: String, languageCode: String) -> String { "x" }
      public static func turnCostAccessibility(amountText: String, languageCode: String) -> String { "x" }
    }
  SWIFT
end

def locale_and_code
  <<~SWIFT
        @Environment(\\.locale) private var locale
        private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }
  SWIFT
end

def good_chat_composer_src
  <<~SWIFT
    struct ChatComposer: View {
    #{locale_and_code}
      @State private var text = ""
      @State private var isComposing = false
      var body: some View {
        ZStack {
          IMESafeTextView(text: $text, onSubmit: onSend)
            .accessibilityIdentifier("ChatComposer.input")
          if ComposerPlaceholderVisibility.shouldShowPlaceholder(text: text, isComposing: isComposing) {
            Text(UIWording.text(.composerPlaceholder, languageCode: languageCode))
          }
        }
      }
      func onSend() {}
    }
  SWIFT
end

def good_grid_column_src
  <<~SWIFT
    struct GridChatColumn: View {
    #{locale_and_code}
      @State private var text = ""
      @State private var isComposing = false
      var body: some View {
        ZStack {
          IMESafeTextView(text: $text, onSubmit: onSend)
            .accessibilityIdentifier("GridComposer.input")
          if ComposerPlaceholderVisibility.shouldShowPlaceholder(text: text, isComposing: isComposing) {
            Text(UIWording.text(.composerPlaceholder, languageCode: languageCode))
          }
        }
      }
      func onSend() {}
    }
  SWIFT
end

def good_team_composer_src
  <<~SWIFT
    struct TeamComposer: View {
    #{locale_and_code}
      let targetDisplayName: String?
      let isReadyForInput: Bool
      @State private var draft = ""
      @State private var isComposing = false
      private var canSend: Bool {
        targetDisplayName != nil && isReadyForInput && !trimmedDraft.isEmpty
      }
      private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
      var body: some View {
        HStack {
          ZStack {
            TeamComposerTextInput(text: $draft, isEnabled: targetDisplayName != nil, onSubmit: send)
            if draft.isEmpty && !isComposing {
              Text(UIWording.text(.composerPlaceholder, languageCode: languageCode))
            }
          }
          Button(action: send) { Image(systemName: "paperplane.fill") }
            .disabled(!canSend)
        }
      }
      private func send() {}
    }
  SWIFT
end

def good_cells_basic_src
  <<~SWIFT
    struct TurnCostCell: View {
    #{locale_and_code}
      let costUSD: Double
      var body: some View {
        Text(Self.format(costUSD))
          .accessibilityLabel(UIWording.turnCostAccessibility(amountText: Self.format(costUSD), languageCode: languageCode))
          .accessibilityIdentifier("ChatMessage.turnCost")
      }
      static func format(_ costUSD: Double) -> String { "$0.01" }
    }
    struct ErrorMessageCell: View {
    #{locale_and_code}
      let message: String
      var body: some View {
        VStack {
          Label(UIWording.text(.errorHeading, languageCode: languageCode), systemImage: "exclamationmark.triangle")
          Text(message)
        }
      }
    }
  SWIFT
end

def good_cells_structured_src
  <<~SWIFT
    struct CommandExecutionCell: View {
    #{locale_and_code}
      let command: String?
      let output: String
      let isRunning: Bool
      var body: some View {
        DisclosureCard(
          title: command?.isEmpty == false ? command! : UIWording.text(.missingCommand, languageCode: languageCode),
          subtitle: isRunning ? "実行中" : (output.isEmpty ? nil : UIWording.text(.outputAvailable, languageCode: languageCode))
        )
      }
    }
    struct SubAgentMarkerCell: View {
    #{locale_and_code}
      let description: String
      var body: some View {
        Text(description.isEmpty ? UIWording.text(.missingSubAgentDescription, languageCode: languageCode) : description)
      }
    }
  SWIFT
end

def good_code_block_src
  <<~SWIFT
    struct CodeBlockView: View {
    #{locale_and_code}
      let language: String?
      let code: String
      var body: some View {
        HStack {
          Text(language?.isEmpty == false ? language! : UIWording.text(.missingCodeBlockLanguage, languageCode: languageCode))
          Button(action: copyCode) {
            Label(UIWording.text(.copyAction, languageCode: languageCode), systemImage: "doc.on.doc")
          }
          .help(UIWording.text(.copyCodeHelp, languageCode: languageCode))
          .accessibilityIdentifier("CodeBlock.copyButton")
        }
      }
      private func copyCode() {}
    }
  SWIFT
end

def good_markdown_src
  <<~SWIFT
    struct RichMarkdownView: View {
    #{locale_and_code}
      var body: some View {
        HStack {
          Text(configuration.language?.isEmpty == false ? configuration.language! : UIWording.text(.missingMarkdownLanguage, languageCode: languageCode))
          Button(action: {}) {
            Label(UIWording.text(.copyAction, languageCode: languageCode), systemImage: "doc.on.doc")
          }
          .help(UIWording.text(.copyCodeHelp, languageCode: languageCode))
        }
      }
    }
  SWIFT
end

def good_copy_button_src
  <<~SWIFT
    struct MessageCopyButton: View {
    #{locale_and_code}
      @State private var didCopy = false
      var body: some View {
        Button(action: copyAndShowFeedback) {
          if didCopy {
            Text(UIWording.text(.copiedFeedback, languageCode: languageCode))
          }
        }
        .help(didCopy ? UIWording.text(.copiedFeedback, languageCode: languageCode) : UIWording.text(.copyMessageHelp, languageCode: languageCode))
        .accessibilityLabel(didCopy ? UIWording.text(.copiedFeedback, languageCode: languageCode) : UIWording.text(.copyMessageHelp, languageCode: languageCode))
      }
      private func copyAndShowFeedback() {
        ChatMessageCopy.copyPlainTextToPasteboard(text)
        didCopy = true
        resetTask = Task { @MainActor in
          try? await Task.sleep(nanoseconds: 1_400_000_000)
          didCopy = false
        }
      }
    }
  SWIFT
end

def good_accessories_src
  <<~SWIFT
    struct ApprovalBanner: View {
    #{locale_and_code}
      var body: some View {
        HStack {
          Button(UIWording.text(.acceptAction, languageCode: languageCode)) {
            respond(approval, .accept)
          }
          Button(UIWording.text(.declineAction, languageCode: languageCode)) {
            respond(approval, .decline)
          }
          Button(UIWording.text(.cancelAction, languageCode: languageCode)) {
            respond(approval, .cancel)
          }
        }
      }
      func respond(_ approval: Approval, _ action: ApprovalAction) {}
    }
  SWIFT
end

def good_sidebar_src
  <<~SWIFT
    struct DashboardSidebarView: View {
    #{locale_and_code}
      var body: some View {
        sidebarProjectTitleBar
      }
      private var sidebarProjectTitleBar: some View {
        Text(UIWording.text(.projectsHeading, languageCode: languageCode))
      }
    }
  SWIFT
end

def good_context_src
  <<~SWIFT
    enum ComposerContextPopoverText {
      static func lines(usedTokens: Int, windowTokens: Int, languageCode: String) -> [String] {
        let percent: Int
        if windowTokens > 0 {
          percent = Int((Double(usedTokens) / Double(windowTokens) * 100).rounded())
        } else {
          percent = 0
        }
        return [
          UIWording.text(.contextWindowHeading, languageCode: languageCode),
          UIWording.contextUsagePercent(usedPercent: percent, remainingPercent: 100 - percent, languageCode: languageCode),
          UIWording.contextTokenUsage(usedText: tokenText(usedTokens), windowText: tokenText(windowTokens), languageCode: languageCode),
        ]
      }
      static func tokenText(_ tokens: Int) -> String {
        guard tokens >= 1_000 else { return "\\(tokens)" }
        return "\\(Int((Double(tokens) / 1_000).rounded()))k"
      }
    }
    struct ComposerBranchControl: View {
    #{locale_and_code}
      var body: some View {
        Button("branch") {}
          .alert(UIWording.text(.branchCheckoutFailed, languageCode: languageCode), isPresented: .constant(false)) {
            Button("OK", role: .cancel) {}
          }
        Text(UIWording.text(.noLocalBranches, languageCode: languageCode))
      }
    }
    struct ComposerContextPopover: View {
    #{locale_and_code}
      var body: some View {
        ForEach(ComposerContextPopoverText.lines(usedTokens: used, windowTokens: window, languageCode: languageCode), id: \\.self) { line in
          Text(line)
        }
      }
    }
  SWIFT
end

def good_settings_src
  <<~SWIFT
    func composerModeOptions(for agentRef: AgentRef, codexProfileIDs: [String], languageCode: String) -> [ComposerModeOption] {
      switch agentRef {
      case .builtin(.codex):
        codexProfileIDs.map {
          ComposerModeOption(value: $0, title: composerPermissionTitle(for: $0, languageCode: languageCode), isPlan: false)
        } + [
          ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), isPlan: true),
        ]
      case .builtin(.claudeCode):
        [
          ComposerModeOption(value: "acceptEdits", title: "Accept Edits", isPlan: false),
          ComposerModeOption(value: "auto", title: "Auto", isPlan: false),
          ComposerModeOption(value: "bypassPermissions", title: "Bypass", isPlan: false),
          ComposerModeOption(value: "manual", title: "Manual", isPlan: false),
          ComposerModeOption(value: "dontAsk", title: "Don't Ask", isPlan: false),
          ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), isPlan: true),
        ]
      case .builtin(.cursor):
        [
          ComposerModeOption(value: nil, title: "Agent", isPlan: false),
          ComposerModeOption(value: "ask", title: "Ask", isPlan: false),
          ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), isPlan: true),
        ]
      default:
        []
      }
    }
    func composerPermissionTitle(for id: String?, languageCode: String) -> String {
      switch id {
      case ":read-only": "Read Only"
      case ":workspace": "Auto"
      case ":danger-full-access": "Full Access"
      case .some(let value): value
      case nil: UIWording.text(.approvalLabel, languageCode: languageCode)
      }
    }
    struct ComposerSettingsControlsView: View {
    #{locale_and_code}
      var body: some View {
        Menu(UIWording.text(.modelLabel, languageCode: languageCode)) { EmptyView() }
        Menu(UIWording.text(.reasoningEffortLabel, languageCode: languageCode)) {
          Button(UIWording.text(.effortLow, languageCode: languageCode)) {}
        }
        Menu(UIWording.text(.permissionLabel, languageCode: languageCode)) {
          ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode), id: \\.self) { option in
            Button(option.title) { select(option) }
              .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
          }
        }
        Menu(UIWording.text(.modeLabel, languageCode: languageCode)) { EmptyView() }
        ComposerControlChip(title: viewModel.isPlanMode ? UIWording.text(.planOption, languageCode: languageCode) : UIWording.text(.approvalLabel, languageCode: languageCode))
      }
      private func select(_ option: ComposerModeOption) {}
      private static func spawnEffortTitle(for effort: String, languageCode: String) -> String {
        switch effort {
        case "low": UIWording.text(.effortLow, languageCode: languageCode)
        case "medium": UIWording.text(.effortMedium, languageCode: languageCode)
        case "high": UIWording.text(.effortHigh, languageCode: languageCode)
        case "xhigh": UIWording.text(.effortXHigh, languageCode: languageCode)
        case "max": UIWording.text(.effortMax, languageCode: languageCode)
        default: effort
        }
      }
      private func modeOptionIsSelected(_ option: ComposerModeOption, currentValue: String?) -> Bool {
        if option.isPlan {
          return viewModel.isPlanMode
        }
        return !viewModel.isPlanMode && option.value == currentValue
      }
    }
    struct ComposerSettingsOverflowMenu: View {
    #{locale_and_code}
      var body: some View {
        Menu {
          overflowMenu(for: .model)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
      private func overflowMenu(for kind: ComposerControlKind) -> some View {
        Menu(UIWording.text(.modelLabel, languageCode: languageCode)) { EmptyView() }
        Menu(UIWording.text(.reasoningEffortLabel, languageCode: languageCode)) { EmptyView() }
        Menu(UIWording.text(.permissionLabel, languageCode: languageCode)) { EmptyView() }
        Menu(UIWording.text(.modeLabel, languageCode: languageCode)) { EmptyView() }
      }
      private static func spawnEffortTitle(for effort: String, languageCode: String) -> String {
        switch effort {
        case "low": UIWording.text(.effortLow, languageCode: languageCode)
        default: effort
        }
      }
    }
    struct ComposerOverflowBranchMenu: View {
    #{locale_and_code}
      var body: some View {
        Menu(branchTitle) {
          Button(UIWording.text(.refreshAction, languageCode: languageCode)) { refresh() }
        }
      }
      private var branchTitle: String {
        if let currentBranch { return "Branch: \\(currentBranch)" }
        return UIWording.text(.missingBranch, languageCode: languageCode)
      }
      private func refresh() {}
    }
  SWIFT
end

def good_files
  {
    uiwording: good_uiwording_src,
    chat_composer: good_chat_composer_src,
    grid_column: good_grid_column_src,
    settings: good_settings_src,
    context: good_context_src,
    cells_basic: good_cells_basic_src,
    cells_structured: good_cells_structured_src,
    accessories: good_accessories_src,
    code_block: good_code_block_src,
    markdown: good_markdown_src,
    copy_button: good_copy_button_src,
    team_composer: good_team_composer_src,
    sidebar: good_sidebar_src,
  }
end

def run_selftest
  url = %(let url = "https://phlox.cc/privacy" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://phlox.cc/privacy"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert normalize_code(%(Text("hello world"))).include?("hello world"), "正例: 文字列内空白を正規化で消さない"

  good = good_files
  selftest_errors_eq check_product(good), [], "正例: 契約どおりの配線は空 NG"
  selftest_errors_eq check_invariants(good, good), [], "正例: 動的出力と不変条件を保持"

  commented = with_file(good, :chat_composer) { |src| src.sub("var body", "// keep https://phlox.cc/privacy \\(x)\n      var body") }
  selftest_errors_eq check_product(commented), [], "正例: コメント・URL・補間だけを加える"

  old_placeholder = with_file(good, :chat_composer) { |src|
    src.sub(
      "Text(UIWording.text(.composerPlaceholder, languageCode: languageCode))",
      'Text("Ask Phlox anything...")'
    )
  }
  selftest_errors_eq check_product(old_placeholder), [
    "ChatComposer が UIWording.Key.composerPlaceholder を参照していない",
    "#{PATHS[:chat_composer]} に操作文言の直値 \"Ask Phlox anything...\" が残っている",
  ], "負例: 入力欄1箇所だけ旧文言"

  wrong_key = with_file(good, :chat_composer) { |src| src.gsub("composerPlaceholder", "errorHeading") }
  selftest_errors_eq check_product(wrong_key), [
    "ChatComposer が UIWording.Key.composerPlaceholder を参照していない",
  ], "負例: 誤ったキー"

  overflow_old = with_file(good, :settings) { |src|
    src.sub(
      /private func overflowMenu\(for kind: ComposerControlKind\) -> some View \{\s*Menu\(UIWording\.text\(\.modelLabel, languageCode: languageCode\)\)/,
      'private func overflowMenu(for kind: ComposerControlKind) -> some View { Menu("Model")'
    )
  }
  selftest_errors_eq check_product(overflow_old), [
    "ComposerSettingsOverflowMenu が UIWording.Key.modelLabel を参照していない",
    "#{PATHS[:settings]} に操作文言の直値 \"Model\" が残っている",
  ], "負例: 省略メニューだけ未修正"

  copy_ax = with_file(good, :copy_button) { |src|
    src.sub(
      ".accessibilityLabel(didCopy ? UIWording.text(.copiedFeedback, languageCode: languageCode) : UIWording.text(.copyMessageHelp, languageCode: languageCode))",
      '.accessibilityLabel(didCopy ? "コピーしました" : UIWording.text(.copyMessageHelp, languageCode: languageCode))'
    )
  }
  selftest_errors_eq check_product(copy_ax), [
    "MessageCopyButton のコピー後 AX ラベルが UIWording.copiedFeedback ではない",
    "#{PATHS[:copy_button]} に操作文言の直値 \"コピーしました\" が残っている",
  ], "負例: コピー後 AX ラベルだけ未修正"

  unused = with_file(good, :chat_composer) { |src|
    src.sub(
      "Text(UIWording.text(.composerPlaceholder, languageCode: languageCode))",
      "EmptyView()"
    ) + "\n    func decoy() { Text(UIWording.text(.composerPlaceholder, languageCode: languageCode)) }\n    if false { Text(UIWording.text(.composerPlaceholder, languageCode: languageCode)) }\n    let dummy = \"UIWording.composerPlaceholder\"\n"
  }
  selftest_errors_eq check_product(unused), [
    "ChatComposer が UIWording.Key.composerPlaceholder を参照していない",
  ], "負例: 未使用コードへの参照"

  deleted = with_file(good, :accessories) { |src|
    src.sub(
      /Button\(UIWording\.text\(\.acceptAction, languageCode: languageCode\)\) \{\s*respond\(approval, \.accept\)\s*\}/,
      ""
    )
  }
  selftest_errors_eq check_invariants(deleted, good), [
    "ApprovalBanner の action が TASK48_BASELINE から変化している",
    "ApprovalBanner の承認操作が削除されている",
  ], "負例: コントロール削除"

  pinned = with_file(good, :chat_composer) { |src| src.gsub("languageCode: languageCode", 'languageCode: "en"') }
  selftest_errors_eq check_product(pinned), [
    "ChatComposer が表示言語を languageCode リテラルへ固定している",
  ], "負例: 言語固定"

  swapped = with_file(good, :context) { |src|
    src.sub(
      "usedPercent: percent, remainingPercent: 100 - percent",
      "usedPercent: 100 - percent, remainingPercent: percent"
    )
  }
  selftest_errors_eq check_product(swapped), [
    "ComposerContextPopoverText の使用率の引数が逆転している",
  ], "負例: 数値の逆転"

  action_changed = with_file(good, :accessories) { |src|
    src.sub("respond(approval, .accept)", "respond(approval, .decline)")
  }
  selftest_errors_eq check_invariants(action_changed, good), [
    "ApprovalBanner の action が TASK48_BASELINE から変化している",
  ], "負例: action の改変"

  binding_changed = with_file(good, :team_composer) { |src|
    src.sub("isEnabled: targetDisplayName != nil", "isEnabled: true")
  }
  selftest_errors_eq check_invariants(binding_changed, good), [
    "TeamComposer の Binding が TASK48_BASELINE から変化している",
  ], "負例: Binding の改変"

  tag_changed = with_file(good, :code_block) { |src|
    src.sub('.accessibilityIdentifier("CodeBlock.copyButton")', "")
  }
  selftest_errors_eq check_invariants(tag_changed, good), [
    "#{PATHS[:code_block]} の tag \"CodeBlock.copyButton\" が TASK48_BASELINE から変化している",
  ], "負例: tag の改変"

  default_changed = with_file(good, :settings) { |src|
    src.sub("default: effort", 'default: "Low"')
  }
  selftest_errors_eq check_invariants(default_changed, good), [
    "effort の既定値が TASK48_BASELINE から変化している",
  ], "負例: 既定値の改変"

  plan_order = with_file(good, :settings) { |src|
    src.sub(
      'ComposerModeOption(value: "acceptEdits", title: "Accept Edits", isPlan: false),',
      'ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), isPlan: true), ComposerModeOption(value: "acceptEdits", title: "Accept Edits", isPlan: false),'
    ).sub(
      /ComposerModeOption\(value: "dontAsk", title: "Don't Ask", isPlan: false\),\s*ComposerModeOption\(value: "plan", title: UIWording\.text\(\.planOption, languageCode: languageCode\), isPlan: true\),/,
      'ComposerModeOption(value: "dontAsk", title: "Don\'t Ask", isPlan: false),'
    )
  }
  selftest_errors_eq check_invariants(plan_order, good), [
    "Plan の項目順序が TASK48_BASELINE から変化している",
  ], "負例: Plan の順序の改変"

  exclusive = with_file(good, :settings) { |src|
    src.sub("option.isPlan && !viewModel.isPlanModeAvailable", "false")
  }
  selftest_errors_eq check_invariants(exclusive, good), [
    "Plan の排他条件が TASK48_BASELINE から変化している",
  ], "負例: Plan の排他条件の改変"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_errors_eq unset_errs, ["TASK48_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: 基準の未設定"
  selftest_assert unset.nil?, "負例: 未設定は nil"
  _, invalid_errs = baseline_env_errors("not-a-sha")
  selftest_errors_eq invalid_errs, ["TASK48_BASELINE がコミット SHA ではない（ブランチ名は使えない）: not-a-sha"], "負例: SHA 不正"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK48_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD 指定"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK48_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD~1 指定"
  _, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK48_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: @ 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK48_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
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
  selftest_errors_eq real_mismatch, ["TASK48_BASELINE が契約 baseline_commit と一致しない"], "負例: 契約不一致"

  pre_ok = check_frozen_baseline(
    head_full,
    uiwording_blob: nil,
    test_blob: "test",
    test_now: "test",
    rb_blob: "rb",
    rb_now: "rb"
  )
  selftest_errors_eq pre_ok, [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  post_ng = check_frozen_baseline(
    head_full,
    uiwording_blob: good_uiwording_src,
    test_blob: "test",
    test_now: "test",
    rb_blob: "rb",
    rb_now: "rb"
  )
  selftest_errors_eq post_ng, ["基準時点に UIWording.swift がある（実装前の凍結ではない）"], "負例: 実装後の自己比較"

  selftest_errors_eq frozen_artifact_errors("rb 自身", "now", "frozen"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 凍結検査の改変"
  selftest_errors_eq frozen_artifact_errors("受け入れテスト", "now", "frozen"), ["基準時点の受け入れテストが現在と同一ではない"], "負例: 凍結テストの改変"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "same", "same"), [], "正例: 凍結 rb と作業ツリーが同一"

  missing = check_product({})
  selftest_assert missing.include?("#{PATHS[:uiwording]} が存在しない"), "負例: 対象欠落"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task48-wiring --selftest: OK"
  exit 0
end

ng = []
raw = ENV["TASK48_BASELINE"]
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
    ng << "TASK48_BASELINE が無効なコミット: #{baseline}"
  else
    ng.concat(check_frozen_baseline(full))
    previous = baseline_files(full)
    ng.concat(check_invariants(files, previous))
  end
end

ng = ng.uniq
if ng.empty?
  puts "task48-wiring: OK"
else
  ng.each { |m| puts "task48-wiring: NG #{m}" }
  exit 1
end
