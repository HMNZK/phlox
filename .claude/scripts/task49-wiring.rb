#!/usr/bin/env ruby
# task-49 配線検査: HistoryEntryPresentation が task-41 の導出器を呼び、
# ChatSessionView から rawWorkspacePath と historyEntries が履歴 View の実行使へ届き、
# 主表示・help・AX・プロジェクト・最終利用・案内・onSelect→startFromHistory が接続され、
# TASK49_BASELINE の保護対象と task-51 の entry／取得器が契約どおりであること。
# コメントと文字列は同時識別する（task46-wiring.rb と同じ字句走査）。
# 比較対象は git show <TASK49_BASELINE>:<path> と作業ファイル。HEAD blob は使わない。

def compact(s)
  s.to_s.gsub(/\s+/, "")
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
    out << src[a...b] if kind == :code
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

def code_only_indexed(src)
  out = src.dup
  each_lexeme(src) do |kind, a, b|
    next if kind == :code
    out[a...b] = " " * (b - a)
  end
  out
end

def extract_type_body(src, name)
  indexed = code_only_indexed(src.to_s)
  m = indexed.match(/(?:(?:private|public|fileprivate|internal|open|final)\s+)*(?:struct|class)\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = indexed.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_struct_body(src, name)
  extract_type_body(src, name)
end

def type_declared?(src, name)
  code_only_indexed(src.to_s).match?(/\b(?:struct|class)\s+#{Regexp.escape(name)}\b/)
end

def extract_enum_body(src, name)
  indexed = code_only_indexed(src.to_s)
  m = indexed.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?enum\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = indexed.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_func_body(src, name)
  indexed = code_only_indexed(src.to_s)
  m = indexed.match(/(?:^|\n)[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]*)*(?:(?:private|public|fileprivate|internal|open|override|final|static|nonisolated)\s+)*func\s+#{Regexp.escape(name)}\s*\(/)
  return nil unless m
  paren = indexed.index("(", m.begin(0))
  return nil unless paren
  params = extract_balanced(src, paren, "(", ")")
  return nil if params.nil?
  after = paren + 1 + params.length + 1
  brace = indexed.index("{", after)
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_var_body(src, name)
  indexed = code_only_indexed(src.to_s)
  m = indexed.match(/(?:^|\n)[ \t]*(?:@[A-Za-z_][\w.]*[ \t]*)*(?:private\s+|public\s+|fileprivate\s+|internal\s+)?(?:static\s+)?var\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  i = skip_ws(indexed, m.end(0))
  if i < indexed.length && indexed[i] == ":"
    depth_a = 0
    depth_p = 0
    while i < indexed.length
      n = comment_or_string_end(src, i)
      if n
        i = n
        next
      end
      break if depth_a == 0 && depth_p == 0 && (indexed[i] == "{" || indexed[i] == "=" || indexed[i] == "\n")
      depth_a += 1 if indexed[i] == "<"
      depth_a -= 1 if indexed[i] == ">"
      depth_p += 1 if indexed[i] == "("
      depth_p -= 1 if indexed[i] == ")"
      i += 1
    end
    i = skip_ws(indexed, i)
  end
  return nil unless i < indexed.length && indexed[i] == "{"
  extract_balanced(src, i, "{", "}")
end

def extract_init_body(src)
  indexed = code_only_indexed(src.to_s)
  pos = 0
  while (m = indexed.match(/(?:public\s+|private\s+|fileprivate\s+|internal\s+)?init\s*\(/, pos))
    paren = m.end(0) - 1
    params = extract_balanced(src, paren, "(", ")")
    return nil if params.nil?
    after = paren + 1 + params.length + 1
    brace = indexed.index("{", after)
    return nil unless brace
    body = extract_balanced(src, brace, "{", "}")
    return body if compact(params).include?("entry:")
    pos = m.end(0)
  end
  nil
end

def all_call_args(src, callee)
  indexed = code_only_indexed(src.to_s)
  args = []
  pos = 0
  re = /#{Regexp.escape(callee)}\s*\(/
  while (m = indexed.match(re, pos))
    a = extract_balanced(src, m.end(0) - 1, "(", ")")
    args << a if a
    pos = m.end(0)
  end
  args
end

def extract_call_args(src, callee)
  all_call_args(src, callee).first
end

def labeled_arg(args, label)
  return nil if args.nil?
  re = /(?:^|,)\s*#{Regexp.escape(label)}\s*:/
  m = args.match(re)
  return nil unless m
  i = skip_ws(args, m.end(0))
  start = i
  depth_p = 0
  depth_b = 0
  depth_a = 0
  while i < args.length
    n = comment_or_string_end(args, i)
    if n
      i = n
      next
    end
    case args[i]
    when "(" then depth_p += 1
    when ")" then depth_p -= 1
    when "{" then depth_b += 1
    when "}" then depth_b -= 1
    when "[" then depth_a += 1
    when "]" then depth_a -= 1
    when ","
      if depth_p == 0 && depth_b == 0 && depth_a == 0
        return args[start...i].strip
      end
    end
    i += 1
  end
  args[start...i].strip
end

def modifier_args(src, name)
  indexed = code_only_indexed(src.to_s)
  args = []
  pos = 0
  re = /\.#{Regexp.escape(name)}\s*\(/
  while (m = indexed.match(re, pos))
    a = extract_balanced(src, m.end(0) - 1, "(", ")")
    args << a if a
    pos = m.end(0)
  end
  args
end

def git_tree_has_path?(rev, path)
  system("git", "cat-file", "-e", "#{rev}:#{path}", out: File::NULL, err: File::NULL)
end

def git_show_result(rev, path)
  text = IO.popen(["git", "show", "#{rev}:#{path}"], err: [:child, :out], &:read)
  if $?.success?
    { kind: :ok, text: text, stderr: nil }
  elsif git_tree_has_path?(rev, path)
    { kind: :git_error, text: nil, stderr: text.to_s.strip }
  else
    { kind: :missing, text: nil, stderr: text.to_s.strip }
  end
end

def git_show(rev, path)
  result = git_show_result(rev, path)
  result[:kind] == :ok ? result[:text] : nil
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

def strip_discarded_calls(src)
  compact(src).gsub(/_=(?:HistoryEntryPresentation|SessionTitleDeriver)(?:\.[A-Za-z0-9_]+)*/, "")
end

def strip_dead_model_lets(c)
  s = c.dup
  s.gsub(/let([A-Za-z_][A-Za-z0-9_]*)=(?:HistoryEntryPresentation|SessionTitleDeriver)(?:\.[A-Za-z0-9_]+)?\([^)]*\)/) do
    ident = Regexp.last_match(1)
    whole = Regexp.last_match(0)
    without = s.sub(whole, "")
    without.include?(ident) ? whole : ""
  end
end

def live_code(src)
  strip_dead_model_lets(strip_discarded_calls(compact(mask_strings_and_comments(erase_if_false(src.to_s)))))
end

SWIFTUI_SKIP = %w[
  Form Section Text Label Toggle Picker Button ForEach TabView Binding Image Link
  LabeledContent Color View EmptyView Spacer Divider Group VStack HStack ZStack
  Tab Item TextField Bool String Int Double Optional true false nil some any body
  Task URL Bundle GeometryReader RoundedRectangle Circle Capsule Overlay alignment
  DSFont DSColor DSSpacing DSRadius Font LazyVStack ScrollView
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

def struct_reachable(src, name)
  return :missing if src.nil?
  body = extract_type_body(src, name)
  if type_declared?(src, name) && body.nil?
    return :unparseable
  end
  return :missing if body.nil?
  start = extract_var_body(body, "body") || extract_init_body(body)
  return :unparseable if start.nil?
  collect_reachable(src, start)
end

def compact_reach(src, name)
  reach = struct_reachable(src, name)
  return reach if reach.is_a?(Symbol)
  live_code(reach)
end

def expr_is_string_literal?(expr)
  s = expr.to_s.strip
  s.start_with?('"') || s.start_with?('"""')
end

def derived_title_returned?(live)
  live.match?(/title=[A-Za-z_][A-Za-z0-9_]*[?!]*\.title/) &&
    live.match?(/fullTitle=[A-Za-z_][A-Za-z0-9_]*[?!]*\.fullTitle/)
end

def has_public_let_nonoptional_string?(compacted, name)
  needle = "publiclet#{name}:String"
  start = 0
  while (idx = compacted.index(needle, start))
    after_idx = idx + needle.length
    after = after_idx < compacted.length ? compacted[after_idx] : nil
    return true if after != "?" && after != "!"
    start = idx + 1
  end
  false
end

def presentation_public_api_errors(src)
  masked = mask_strings_and_comments(src.to_s)
  header = masked[/(?:public\s+)?struct\s+HistoryEntryPresentation\s*:[^{]*\{/]
  return [] if header.nil? && !masked.match?(/\bstruct\s+HistoryEntryPresentation\b/)
  ng = []
  if header.nil? || header !~ /\bpublic\s+struct\s+HistoryEntryPresentation\b/
    ng << "HistoryEntryPresentation が public ではない"
    return ng
  end
  ng << "HistoryEntryPresentation が Sendable ではない" unless header =~ /\bSendable\b/
  body = extract_type_body(src, "HistoryEntryPresentation")
  return ng + ["HistoryEntryPresentation を解析できない"] if body.nil?
  c = compact(mask_strings_and_comments(body))
  %w[title fullTitle projectName].each do |field|
    unless has_public_let_nonoptional_string?(c, field)
      ng << "public let #{field}: String が無い"
    end
  end
  ng
end

def text_string_literals(src)
  all_call_args(src, "Text").map do |args|
    next unless expr_is_string_literal?(args.to_s.strip)
    raw = args.to_s.strip
    if raw.start_with?('"""') && raw.end_with?('"""') && raw.length >= 6
      raw[3...-3]
    elsif raw.start_with?('"') && raw.end_with?('"') && raw.length >= 2
      raw[1...-1]
    end
  end.compact
end

def live_help_args(src)
  modifier_args(src, "help").reject { |a| expr_is_string_literal?(a) }.map { |a| compact(a) }
end

def live_ax_label_args(src)
  modifier_args(src, "accessibilityLabel").reject { |a| expr_is_string_literal?(a) }.map { |a| compact(a) }
end

def foreach_entries_ident(src)
  m = code_only_indexed(src.to_s).match(/ForEach\s*\(\s*entries\s*\)\s*\{\s*([A-Za-z_][A-Za-z0-9_]*)\s+in\b/)
  m && m[1]
end

def row_for_call_arg(src)
  all_call_args(src, "row").map { |a| labeled_arg(a, "for") }.compact.first
end

def row_func_param(src)
  indexed = code_only_indexed(src.to_s)
  m = indexed.match(/func\s+row\s*\(\s*for\s+([A-Za-z_][A-Za-z0-9_]*)\s*:/)
  m && m[1]
end

def on_appear_bodies(src)
  indexed = code_only_indexed(src.to_s)
  bodies = []
  pos = 0
  re = /\.onAppear\s*\{/
  while (m = indexed.match(re, pos))
    brace = m.end(0) - 1
    body = extract_balanced(src, brace, "{", "}")
    bodies << body if body
    pos = m.end(0)
  end
  bodies
end

def button_action_bodies(src)
  indexed = code_only_indexed(src.to_s)
  bodies = []
  pos = 0
  re = /\bButton\s*\{/
  while (m = indexed.match(re, pos))
    brace = m.end(0) - 1
    body = extract_balanced(src, brace, "{", "}")
    bodies << body if body
    pos = m.end(0)
  end
  pos = 0
  re = /\bButton\s*\(\s*action\s*:\s*\{/
  while (m = indexed.match(re, pos))
    brace = m.end(0) - 1
    body = extract_balanced(src, brace, "{", "}")
    bodies << body if body
    pos = m.end(0)
  end
  bodies
end

def mask_allowed_session_view_changes(src)
  src.to_s.gsub(/,?\s*workingDirectory\s*:[^,)\n]+/, "")
end

def has_ponytail_comment?(src)
  found = false
  each_lexeme(src.to_s) do |kind, a, b|
    found = true if kind == :comment && src[a...b].include?("ponytail:")
  end
  found
end

def string_literals(src)
  lits = []
  each_lexeme(src.to_s) do |kind, a, b|
    next unless kind == :string
    raw = src[a...b]
    if raw.start_with?('"""') && raw.end_with?('"""') && raw.length >= 6
      lits << raw[3...-3]
    elsif raw.start_with?('"') && raw.end_with?('"') && raw.length >= 2
      lits << raw[1...-1]
    else
      lits << raw
    end
  end
  lits
end

def forbidden_presentation_deps?(src)
  code = mask_strings_and_comments(src)
  return true if code.match?(/\bimport\s+SwiftUI\b/) || code.match?(/\bimport\s+AppKit\b/)
  live = live_code(src)
  %w[FileManager Process URLSession NSWorkspace UserDefaults].any? { |n| live.include?(n) } ||
    live.include?("Date()") ||
    live.include?("Date.now")
end

def entry_has_title_materials?(src)
  return false if src.nil?
  live = compact(mask_strings_and_comments(src))
  live.include?("titleUserMessages") && live.include?("titleSummary")
end

def display_wiring_in_src?(src)
  return false if src.nil?
  reach = struct_reachable(src, "ChatHistoryStartView")
  return false unless reach.is_a?(String)
  live_code(reach).include?("HistoryEntryPresentation")
end

CONTRACT_PATH = "tasks/task-49.md"
WIRING_RB_PATH = ".claude/scripts/task49-wiring.rb"
PRESENTATION_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/HistoryEntryPresentation.swift"
HISTORY_VIEW_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatHistoryStartView.swift"
SESSION_VIEW_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift"
VM_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift"
LAYOUT_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatHistoryStartLayout.swift"
DERIVER_PATH = "macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleDeriver.swift"
ENTRY_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ClaudeSessionHistoryEntry.swift"
CLAUDE_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift"
CODEX_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift"
SESSION_FEATURE_SRC = "macos/Packages/SessionFeature/Sources/SessionFeature"
TEST_PRESENTATION = "macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceHistoryEntryPresentationTests.swift"
ACCEPTANCE_PATHS = [TEST_PRESENTATION].freeze
PRODUCTION_MARKER = "# === task49 production checks ==="
ALLOWED_PRODUCT_PATHS = [
  PRESENTATION_PATH,
  HISTORY_VIEW_PATH,
  SESSION_VIEW_PATH,
].freeze
ALLOWED_SCOPE_PATHS = (
  ALLOWED_PRODUCT_PATHS + ["docs/agent-output/task-49.md"]
).freeze
TASK51_PATHS = [ENTRY_PATH, CLAUDE_PATH, CODEX_PATH].freeze

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
        errs << "TASK49_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK49_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK49_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK49_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
    return [nil, errs]
  end
  [value, errs]
end

def blob_fetch_errors(label, result, now)
  case result[:kind]
  when :missing
    ["基準時点の#{label}が無い"]
  when :git_error
    msg = result[:stderr].to_s.empty? ? "基準時点の#{label}を git show できない" : "基準時点の#{label}を git show できない: #{result[:stderr]}"
    [msg]
  when :ok
    workdir_matches_git_blob?(now, result[:text]) ? [] : ["基準時点の#{label}が現在と同一ではない"]
  else
    ["基準時点の#{label}を git show できない"]
  end
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

def implementation_in_baseline_errors(
  presentation_blob, deriver_blob, entry_blob, history_blob,
  presentation_error: nil, deriver_error: nil, entry_error: nil
)
  ng = []
  if presentation_error
    ng << "基準時点の HistoryEntryPresentation.swift を git show できない: #{presentation_error}"
  elsif presentation_blob
    ng << "基準時点に HistoryEntryPresentation.swift がある（実装前の凍結ではない）"
  end
  if deriver_error
    ng << "基準時点の SessionTitleDeriver.swift を git show できない: #{deriver_error}"
  elsif deriver_blob.nil?
    ng << "基準時点に SessionTitleDeriver.swift が無い（task-41 完了状態ではない）"
  end
  if entry_error
    ng << "基準時点の ClaudeSessionHistoryEntry.swift を git show できない: #{entry_error}"
  elsif entry_blob.nil?
    ng << "基準時点に ClaudeSessionHistoryEntry.swift が無い（task-51 完了状態ではない）"
  elsif !entry_has_title_materials?(entry_blob)
    ng << "基準時点の entry に titleUserMessages が無い（task-51 完了状態ではない）"
  end
  if history_blob && display_wiring_in_src?(history_blob)
    ng << "基準時点に本タスクの表示配線がある（実装前の凍結ではない）"
  end
  ng
end

def check_frozen_baseline(baseline, artifacts = nil)
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK49_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  ancestor_ok = if artifacts && artifacts.key?(:is_ancestor)
    artifacts[:is_ancestor]
  else
    git_is_ancestor?(full, "HEAD")
  end
  unless ancestor_ok
    ng << "TASK49_BASELINE が HEAD の祖先ではない"
  end
  if artifacts
    ng.concat(implementation_in_baseline_errors(
      artifacts[:presentation_blob],
      artifacts[:deriver_blob],
      artifacts[:entry_blob],
      artifacts[:history_blob],
      presentation_error: artifacts[:presentation_error],
      deriver_error: artifacts[:deriver_error],
      entry_error: artifacts[:entry_error]
    ))
    if artifacts[:test_results]
      ACCEPTANCE_PATHS.each_with_index do |_path, idx|
        ng.concat(blob_fetch_errors("受け入れテスト#{idx + 1}", artifacts[:test_results][idx], artifacts[:test_nows][idx]))
      end
    else
      ACCEPTANCE_PATHS.each_with_index do |_path, idx|
        ng.concat(frozen_artifact_errors("受け入れテスト#{idx + 1}", artifacts[:test_blobs][idx], artifacts[:test_nows][idx]))
      end
    end
    if artifacts[:rb_result]
      ng.concat(blob_fetch_errors("rb 自身", artifacts[:rb_result], artifacts[:rb_now]))
    else
      ng.concat(frozen_artifact_errors("rb 自身", artifacts[:rb_blob], artifacts[:rb_now]))
    end
  else
    pres = git_show_result(full, PRESENTATION_PATH)
    deriver = git_show_result(full, DERIVER_PATH)
    entry = git_show_result(full, ENTRY_PATH)
    history = git_show_result(full, HISTORY_VIEW_PATH)
    ng.concat(implementation_in_baseline_errors(
      pres[:kind] == :ok ? pres[:text] : nil,
      deriver[:kind] == :ok ? deriver[:text] : nil,
      entry[:kind] == :ok ? entry[:text] : nil,
      history[:kind] == :ok ? history[:text] : nil,
      presentation_error: (pres[:kind] == :git_error ? pres[:stderr] : nil),
      deriver_error: (deriver[:kind] == :git_error ? deriver[:stderr] : nil),
      entry_error: (entry[:kind] == :git_error ? entry[:stderr] : nil)
    ))
    ACCEPTANCE_PATHS.each_with_index do |path, idx|
      ng.concat(blob_fetch_errors("受け入れテスト#{idx + 1}", git_show_result(full, path), read_if_exist(path)))
    end
    ng.concat(blob_fetch_errors("rb 自身", git_show_result(full, WIRING_RB_PATH), read_if_exist(WIRING_RB_PATH)))
  end
  ng
end

def scope_check_requested?(env = ENV)
  env["TASK49_SCOPE_CHECK"] == "1"
end

def check_presentation(src)
  return ["HistoryEntryPresentation.swift が存在しない"] if src.nil?
  reach = struct_reachable(src, "HistoryEntryPresentation")
  return ["HistoryEntryPresentation が存在しない"] if reach == :missing
  return ["HistoryEntryPresentation を解析できない"] if reach == :unparseable
  live = live_code(reach)
  ng = []
  unless live.include?("SessionTitleDeriver.derive")
    ng << "表示モデルが SessionTitleDeriver.derive を呼んでいない"
  end
  unless derived_title_returned?(live)
    ng << "導出結果の title／fullTitle が返されていない"
  end
  ng << "最終利用に firstUserAt を使っている" if live.include?("firstUserAt")
  unless live.include?("lastModified")
    ng << "lastUsedAt が lastModified に接続されていない"
  end
  unless live.include?("distantPast")
    ng << "distantPast を nil にする分岐が無い"
  end
  ng << "ponytail: コメントが無い" unless has_ponytail_comment?(src)
  ng << "表示モデルが View または I/O に依存している" if forbidden_presentation_deps?(src)
  ng.concat(presentation_public_api_errors(src))
  ng
end

def preview_as_primary?(reach)
  compact(mask_strings_and_comments(reach)).include?("Text(entry.preview)")
end

def check_history_view(src)
  return ["ChatHistoryStartView.swift が存在しない"] if src.nil?
  reach = struct_reachable(src, "ChatHistoryStartView")
  return ["ChatHistoryStartView が存在しない"] if reach == :missing
  return ["ChatHistoryStartView を解析できない"] if reach == :unparseable
  live = live_code(reach)
  code = compact(mask_strings_and_comments(reach))
  text_lits = text_string_literals(reach)
  ng = []
  unless live.include?("HistoryEntryPresentation")
    ng << "行から表示モデルが未接続"
  end
  if preview_as_primary?(reach)
    ng << "主表示が entry.preview になっている"
  elsif !code.include?("Text(presentation.title)")
    ng << "主表示が HistoryEntryPresentation.title ではない"
  end
  args = extract_call_args(reach, "HistoryEntryPresentation")
  wd = labeled_arg(args, "workingDirectory")
  if expr_is_string_literal?(wd)
    ng << "作業ディレクトリを固定値にしている"
  elsif live.include?("HistoryEntryPresentation") && (wd.nil? || !compact(wd).include?("workingDirectory"))
    ng << "作業ディレクトリを固定値にしている"
  end
  helps = live_help_args(reach).join
  ax = live_ax_label_args(reach).join
  ng << "fullTitle の help が無い" unless helps.include?("presentation.fullTitle")
  ng << "projectPath の help が無い" unless helps.include?("presentation.projectPath")
  ng << "sessionID の help が無い" unless helps.include?("sessionID")
  ng << "fullTitle のアクセシビリティラベルが無い" unless ax.include?("presentation.fullTitle")
  ng << "sessionID のアクセシビリティラベルが無い" unless ax.include?("sessionID")
  ng << "最終利用に firstUserAt を使っている" if live.include?("firstUserAt")
  unless code.include?("Text(presentation.projectName)")
    ng << "projectName が描画されていない"
  end
  unless live.include?("presentation.lastUsedAt")
    ng << "lastUsedAt が補助表示へ渡っていない"
  end
  ng << "最終利用 の案内が無い" unless text_lits.include?("最終利用")
  ng << "最終利用日時不明 の案内が無い" unless text_lits.include?("最終利用日時不明") || string_literals(reach).include?("最終利用日時不明")
  ng << "続きから再開 の案内が無い" unless text_lits.include?("続きから再開")
  ng << "新規作成 の案内が無い" unless text_lits.include?("新規作成")
  ng << "下の入力欄から新しい依頼を始めます の案内が無い" unless text_lits.include?("下の入力欄から新しい依頼を始めます")
  loop_ident = foreach_entries_ident(reach)
  row_arg = row_for_call_arg(reach)
  row_param = row_func_param(src)
  model_entry = labeled_arg(args, "entry")
  if loop_ident.nil? || row_arg.nil? || compact(row_arg) != loop_ident
    ng << "ForEach の要素が行へ渡っていない"
  end
  if row_param && model_entry && compact(model_entry) != row_param
    ng << "モデルの entry が行の対象と異なる"
  end
  select_args = all_call_args(reach, "onSelect")
  unless row_param && select_args.any? { |a| compact(a) == row_param }
    ng << "onSelect が元 entry を渡していない"
  end
  if live.include?("ClaudeSessionHistoryEntry(") || select_args.any? { |a| compact(a).include?("title") }
    ng << "タイトルから再開先を引き直している"
  end
  appear = on_appear_bodies(reach)
  if appear.any? { |body| compact(body).include?("onSelect") }
    ng << "表示時に再開している"
  end
  if select_args.length > 1
    ng << "onSelect が重複呼び出しされている"
  end
  button_actions = button_action_bodies(reach)
  unless button_actions.any? { |body| compact(body).include?("onSelect") }
    ng << "Button が無い"
  end
  ax_ids = modifier_args(reach, "accessibilityIdentifier").map { |a| compact(a) }.join
  ng << "ChatHistoryStartView の AX identifier が無い" unless ax_ids.include?("ChatHistoryStartView")
  ng << "ChatHistoryStartView.row の AX identifier が無い" unless ax_ids.include?("ChatHistoryStartView.row")
  ng << "ForEach(entries) が無い" unless live.include?("ForEach(entries)")
  ng << "ScrollView が無い" unless live.include?("ScrollView")
  ng << "lineLimit(1) が無い" unless live.include?("lineLimit(1)")
  ng << "maxCardHeight の frame 配線が無い" unless code.include?("frame(maxHeight:maxCardHeight)")
  ng << "ブランチ表示が無い" unless live.include?("gitBranch")
  ng.uniq
end

def code_compact(expr)
  compact(mask_strings_and_comments(expr.to_s))
end

def overlay_geometry_reader_scope(src)
  indexed = code_only_indexed(src.to_s)
  pos = 0
  re = /GeometryReader\s*\{/
  while (m = indexed.match(re, pos))
    brace = m.end(0) - 1
    body = extract_balanced(src, brace, "{", "}")
    if body && compact(mask_strings_and_comments(body)).include?("ChatHistoryStartLayout.maxCardHeight")
      return body
    end
    pos = m.end(0)
  end
  src
end

def overlay_height_alias_bound?(name, scope_src)
  return false unless name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
  indexed = code_only_indexed(scope_src.to_s)
  pos = 0
  re = /\blet\s+#{Regexp.escape(name)}(?:\s*:\s*[A-Za-z_][A-Za-z0-9_.]*)?\s*=/
  while (m = indexed.match(re, pos))
    i = m.end(0)
    i += 1 while i < indexed.length && indexed[i] =~ /\s/
    rest = indexed[i..]
    break if rest.nil?
    rm = rest.match(/\AoverlayGeometry\s*\.\s*size\s*\.\s*height\b/)
    if rm
      after = rest[rm.end(0)..].to_s.lstrip
      return true if after.empty? || after.start_with?(";") || after.match?(/\A(?:let|var|return|if|guard|switch|for|while)\b/)
    end
    pos = m.end(0)
  end
  false
end

def measured_overlay_height?(avail, scope_src)
  expr = code_compact(avail)
  return false if expr.empty?
  return true if expr == "overlayGeometry.size.height"
  overlay_height_alias_bound?(expr, overlay_geometry_reader_scope(scope_src))
end

def check_session_view(src)
  return ["ChatSessionView.swift が存在しない"] if src.nil?
  reach = struct_reachable(src, "ChatSessionView")
  return ["ChatSessionView が存在しない"] if reach == :missing
  return ["ChatSessionView を解析できない"] if reach == :unparseable
  live = live_code(reach)
  ng = []
  args = extract_call_args(reach, "ChatHistoryStartView")
  if args.nil?
    ng << "ChatHistoryStartView が描画経路に無い"
    return ng
  end
  entries_arg = labeled_arg(args, "entries")
  unless entries_arg && compact(entries_arg).include?("viewModel.historyEntries")
    ng << "historyEntries が履歴 View へ届いていない"
  end
  wd = labeled_arg(args, "workingDirectory")
  if expr_is_string_literal?(wd)
    ng << "作業ディレクトリを固定値にしている"
  elsif wd.nil? || !compact(wd).include?("rawWorkspacePath")
    ng << "rawWorkspacePath が履歴 View へ届いていない"
  elsif compact(wd).include?("workspacePath") && !compact(wd).include?("rawWorkspacePath")
    ng << "rawWorkspacePath が履歴 View へ届いていない"
  end
  on_select = labeled_arg(args, "onSelect")
  if on_select.nil? || !compact(on_select).include?("startFromHistory")
    ng << "onSelect → startFromHistory が維持されていない"
  else
    start_arg = extract_call_args(on_select, "startFromHistory")
    sc = compact(start_arg)
    if sc.include?("title") || sc.include?("preview") || compact(on_select).include?("ClaudeSessionHistoryEntry(")
      ng << "タイトルから再開先を引き直している"
    elsif sc != "entry"
      ng << "別 entry を選択している"
    end
  end
  unless live.include?("shouldOfferHistoryStart")
    ng << "履歴表示条件 shouldOfferHistoryStart が描画経路に無い"
  end
  if live.include?("shouldOfferHistoryStart||") || live.include?("||shouldOfferHistoryStart")
    ng << "描画側の履歴表示条件を弱めている"
  end
  unless live.include?("cardMaxHeight=ChatHistoryStartLayout.maxCardHeight")
    ng << "maxCardHeight が実測値に接続されていない"
  end
  mh_args = extract_call_args(reach, "ChatHistoryStartLayout.maxCardHeight")
  avail = labeled_arg(mh_args, "availableHeight")
  composer_h = labeled_arg(mh_args, "composerHeight")
  unless avail && measured_overlay_height?(avail, reach)
    ng << "maxCardHeight の availableHeight が実測値ではない"
  end
  unless composer_h && compact(composer_h).include?("composerHeight")
    ng << "maxCardHeight の composerHeight が実測値ではない"
  end
  hv_mh = labeled_arg(args, "maxCardHeight")
  unless hv_mh && compact(hv_mh).include?("cardMaxHeight")
    ng << "maxCardHeight 引数が実測値ではない"
  end
  unless modifier_args(reach, "padding").any? { |a| compact(a).include?(".bottom") && compact(a).include?("bottomInset") }
    ng << "bottomInset の余白が無い"
  end
  unless live.include?("ChatHistoryStartLayout")
    ng << "ChatHistoryStartLayout が描画経路に無い"
  end
  unless live.include?("ChatComposer")
    ng << "composer の操作領域が描画経路に無い"
  end
  unless compact(mask_strings_and_comments(reach)).include?("overlay(alignment:.bottom)")
    ng << "composer の overlay 配線が無い"
  end
  ng.uniq
end

def check_product(files)
  ng = []
  ng.concat(check_presentation(files[:presentation]))
  ng.concat(check_history_view(files[:history]))
  ng.concat(check_session_view(files[:session]))
  ng.uniq
end

def protected_member_errors(current, previous, struct_name, member, kind)
  return ["#{struct_name}.#{member} を解析できない"] if current.nil? || previous.nil?
  cur_struct = extract_type_body(current, struct_name)
  prev_struct = extract_type_body(previous, struct_name)
  return ["#{struct_name}.#{member} を解析できない"] if cur_struct.nil? || prev_struct.nil?
  cur = kind == :var ? extract_var_body(cur_struct, member) : extract_func_body(cur_struct, member)
  prev = kind == :var ? extract_var_body(prev_struct, member) : extract_func_body(prev_struct, member)
  return ["#{struct_name}.#{member} を解析できない"] if cur.nil? || prev.nil?
  return [] if normalize_code(cur) == normalize_code(prev)
  ["#{struct_name}.#{member} が基準 blob と同一ではない"]
end

def blob_identity_errors(label, current, previous)
  return ["#{label} を基準と比較できない"] if current.nil? || previous.nil?
  workdir_matches_git_blob?(current, previous) ? [] : ["#{label} が凍結時点から変更されている"]
end

def layout_errors(current, previous)
  return ["ChatHistoryStartLayout の比較元・比較先が欠落している"] if previous.nil? || current.nil?
  cur = extract_enum_body(current, "ChatHistoryStartLayout") || current
  prev = extract_enum_body(previous, "ChatHistoryStartLayout") || previous
  return [] if normalize_code(cur) == normalize_code(prev)
  ["ChatHistoryStartLayout が基準 blob と同一ではない"]
end

def session_view_freeze_errors(current, previous)
  return ["ChatSessionView の比較元・比較先が欠落している"] if current.nil? || previous.nil?
  cur = extract_type_body(current, "ChatSessionView")
  prev = extract_type_body(previous, "ChatSessionView")
  return ["ChatSessionView を解析できない"] if cur.nil? || prev.nil?
  return [] if normalize_code(mask_allowed_session_view_changes(cur)) == normalize_code(mask_allowed_session_view_changes(prev))
  ["ChatSessionView が基準 blob と同一ではない"]
end

def history_view_freeze_errors(current, previous)
  return ["ChatHistoryStartView の比較元・比較先が欠落している"] if current.nil? || previous.nil?
  cur = extract_type_body(current, "ChatHistoryStartView")
  prev = extract_type_body(previous, "ChatHistoryStartView")
  return ["ChatHistoryStartView を解析できない"] if cur.nil? || prev.nil?
  cur_code = compact(mask_strings_and_comments(cur))
  prev_code = compact(mask_strings_and_comments(prev))
  return [] if cur_code.include?("frame(maxHeight:maxCardHeight)") && prev_code.include?("frame(maxHeight:maxCardHeight)") &&
    cur_code.include?("maxCardHeight") && prev_code.include?("maxCardHeight")
  ["ChatHistoryStartView の高さ配線が基準 blob と同一ではない"]
end

def invariant_errors(current_files, baseline_files)
  return [] if baseline_files.nil?
  ng = []
  ng.concat(protected_member_errors(current_files[:vm], baseline_files[:vm], "ChatSessionViewModel", "shouldOfferHistoryStart", :var))
  ng.concat(protected_member_errors(current_files[:vm], baseline_files[:vm], "ChatSessionViewModel", "scheduleHistoryCacheLoadIfNeeded", :func))
  ng.concat(protected_member_errors(current_files[:vm], baseline_files[:vm], "ChatSessionViewModel", "startFromHistory", :func))
  ng.concat(session_view_freeze_errors(current_files[:session], baseline_files[:session]))
  ng.concat(history_view_freeze_errors(current_files[:history], baseline_files[:history]))
  ng.concat(layout_errors(current_files[:layout], baseline_files[:layout]))
  ng.concat(blob_identity_errors("task-51 の ClaudeSessionHistoryEntry.swift", current_files[:entry], baseline_files[:entry]))
  ng.concat(blob_identity_errors("task-51 の ClaudeSessionHistory.swift", current_files[:claude], baseline_files[:claude]))
  ng.concat(blob_identity_errors("task-51 の CodexSessionHistory.swift", current_files[:codex], baseline_files[:codex]))
  ng.uniq
end

def extra_changed_product_paths(rev)
  tracked = IO.popen(["git", "diff", "--name-only", rev], err: [:child, :out], &:read)
  untracked = IO.popen(["git", "ls-files", "--others", "--exclude-standard"], err: [:child, :out], &:read)
  names = (tracked.to_s + untracked.to_s).split("\n").reject(&:empty?).uniq
  names - ALLOWED_SCOPE_PATHS
end

def scope_errors(current_files, _baseline_files)
  ng = []
  extra = current_files[:extra_changed]
  extra.to_a.each do |path|
    ng << "許可パス外の製品変更: #{path}"
  end
  ng.uniq
end

def file_hash(presentation:, history:, session:, vm:, layout:, entry:, claude:, codex:, extra_changed: nil)
  h = {
    presentation: presentation,
    history: history,
    session: session,
    vm: vm,
    layout: layout,
    entry: entry,
    claude: claude,
    codex: codex,
  }
  h[:extra_changed] = extra_changed if extra_changed
  h
end

def worktree_files(baseline_rev = nil)
  files = {
    presentation: read_if_exist(PRESENTATION_PATH),
    history: read_if_exist(HISTORY_VIEW_PATH),
    session: read_if_exist(SESSION_VIEW_PATH),
    vm: read_if_exist(VM_PATH),
    layout: read_if_exist(LAYOUT_PATH),
    entry: read_if_exist(ENTRY_PATH),
    claude: read_if_exist(CLAUDE_PATH),
    codex: read_if_exist(CODEX_PATH),
  }
  files[:extra_changed] = extra_changed_product_paths(baseline_rev) if baseline_rev
  files
end

def baseline_files(rev)
  {
    presentation: git_show(rev, PRESENTATION_PATH),
    history: git_show(rev, HISTORY_VIEW_PATH),
    session: git_show(rev, SESSION_VIEW_PATH),
    vm: git_show(rev, VM_PATH),
    layout: git_show(rev, LAYOUT_PATH),
    entry: git_show(rev, ENTRY_PATH),
    claude: git_show(rev, CLAUDE_PATH),
    codex: git_show(rev, CODEX_PATH),
  }
end

def evaluate_checks(files, baseline_blobs, scope:)
  ng = []
  ng.concat(check_product(files))
  ng.concat(invariant_errors(files, baseline_blobs))
  ng.concat(scope_errors(files, baseline_blobs)) if scope
  ng.uniq
end

def good_presentation
  <<~SWIFT
    import Foundation
    import AgentDomain
    public struct HistoryEntryPresentation: Equatable, Sendable {
      public let title: String
      public let fullTitle: String
      public let projectName: String
      public let projectPath: String?
      public let lastUsedAt: Date?
      /// ponytail: 定型文除外は接頭辞だけ。拡張には具体例と固定テストが要る。
      public init(entry: ClaudeSessionHistoryEntry, workingDirectory: String?) {
        let derived = SessionTitleDeriver.derive(from: entry.preview)
        title = derived?.title ?? "作業名なし"
        fullTitle = derived?.fullTitle ?? "作業名なし"
        projectName = "プロジェクト不明"
        projectPath = workingDirectory
        lastUsedAt = entry.lastModified == .distantPast ? nil : entry.lastModified
      }
    }
  SWIFT
end

def good_history
  <<~SWIFT
    struct ChatHistoryStartView: View {
      let entries: [ClaudeSessionHistoryEntry]
      var maxCardHeight: CGFloat = ChatHistoryStartLayout.maxCardHeightCap
      let workingDirectory: String?
      let onSelect: (ClaudeSessionHistoryEntry) -> Void
      var body: some View {
        VStack {
          header
          Text("新規作成")
          Text("下の入力欄から新しい依頼を始めます")
          ScrollView {
            LazyVStack {
              ForEach(entries) { entry in
                row(for: entry)
              }
            }
          }
          .frame(maxHeight: maxCardHeight)
        }
        .accessibilityIdentifier("ChatHistoryStartView")
      }
      private var header: some View {
        Text("続きから再開")
      }
      private func row(for entry: ClaudeSessionHistoryEntry) -> some View {
        let presentation = HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory)
        return Button {
          onSelect(entry)
        } label: {
          VStack {
            Text(presentation.title)
              .lineLimit(1)
              .help(presentation.fullTitle)
            Text(presentation.projectName)
              .help(presentation.projectPath ?? "")
            Text("最終利用")
            Text(formattedLastUsed(presentation.lastUsedAt))
            if let branch = entry.gitBranch, !branch.isEmpty {
              Text(branch)
            }
          }
        }
        .help(entry.sessionID)
        .accessibilityLabel(presentation.fullTitle + " " + entry.sessionID)
        .accessibilityIdentifier("ChatHistoryStartView.row")
      }
      private func formattedLastUsed(_ date: Date?) -> String {
        guard let date else { return "最終利用日時不明" }
        return formatter.string(from: date)
      }
    }
  SWIFT
end

def baseline_history
  <<~SWIFT
    struct ChatHistoryStartView: View {
      let entries: [ClaudeSessionHistoryEntry]
      var body: some View {
        Text("履歴から再開")
        ForEach(entries) { entry in
          Button { onSelect(entry) } label: { Text(entry.preview) }
        }
      }
    }
  SWIFT
end

def good_session
  <<~SWIFT
    struct ChatSessionView: View {
      var body: some View {
        overlay {
          if viewModel.shouldOfferHistoryStart {
            GeometryReader { overlayGeometry in
              let cardMaxHeight = ChatHistoryStartLayout.maxCardHeight(
                availableHeight: overlayGeometry.size.height,
                composerHeight: composerHeight
              )
              let bottomInset = ChatHistoryStartLayout.bottomInset(composerHeight: composerHeight)
              ChatHistoryStartView(
                entries: viewModel.historyEntries,
                maxCardHeight: cardMaxHeight,
                workingDirectory: viewModel.rawWorkspacePath,
                onSelect: { entry in
                  Task { await viewModel.startFromHistory(entry) }
                }
              )
              .padding(.bottom, bottomInset)
            }
          }
        }
        .overlay(alignment: .bottom) {
          ChatComposer(viewModel: viewModel)
        }
      }
    }
  SWIFT
end

def good_vm
  <<~SWIFT
    @MainActor
    @Observable
    public final class ChatSessionViewModel: Identifiable {
      public var shouldOfferHistoryStart: Bool {
        guard agentRef == .builtin(.claudeCode) || agentRef == .builtin(.codex) else { return false }
        guard historyProvider != nil else { return false }
        guard transcript.isEmpty, submitBaselineTurnSeq == nil else { return false }
        return !cachedHistoryEntries.isEmpty
      }
      public var historyEntries: [ClaudeSessionHistoryEntry] { cachedHistoryEntries }
      private func scheduleHistoryCacheLoadIfNeeded() {
        guard let historyProvider, !historyCacheLoaded else { return }
        historyCacheLoadTask = Task {
          let entries = await Task.detached { Array(historyProvider().prefix(20)) }.value
        }
      }
      public func startFromHistory(_ entry: ClaudeSessionHistoryEntry) async {
        let loaded = historyTranscriptLoader(entry)
        try await client.resume(sessionRef: entry.sessionID)
      }
    }
  SWIFT
end

def good_layout
  <<~SWIFT
    enum ChatHistoryStartLayout {
      static let minCardHeight: CGFloat = 120
      static let maxCardHeightCap: CGFloat = 360
      static let verticalReserve: CGFloat = 56
      static func maxCardHeight(availableHeight: CGFloat, composerHeight: CGFloat) -> CGFloat {
        let raw = availableHeight - composerHeight - verticalReserve
        return min(max(raw, minCardHeight), maxCardHeightCap)
      }
      static func bottomInset(composerHeight: CGFloat) -> CGFloat { composerHeight }
    }
  SWIFT
end

def good_entry
  <<~SWIFT
    public struct ClaudeSessionHistoryEntry {
      public let sessionID: String
      public let preview: String
      public let titleUserMessages: [String]?
      public let titleSummary: String?
    }
  SWIFT
end

def good_files
  {
    presentation: good_presentation,
    history: good_history,
    session: good_session,
    vm: good_vm,
    layout: good_layout,
    entry: good_entry,
    claude: "enum ClaudeSessionHistoryDiscovery {}\n",
    codex: "enum CodexSessionHistoryDiscovery {}\n",
  }
end

def with_file(files, key)
  copy = files.dup
  copy[key] = yield(copy[key].to_s)
  copy
end

def production_checks_source(src = File.read(__FILE__))
  i = src.index(PRODUCTION_MARKER)
  return "" if i.nil?
  src[i..]
end

def baseline_check_connected?(src)
  strip_comments(src).include?("check_frozen_baseline")
end

def scope_check_gated?(src)
  code = strip_comments(src)
  code.include?("scope_check_requested?") &&
    code.include?("scope_errors") &&
    code.match?(/if baseline && scope_check_requested\?/)
end

def selftest_assert(cond, msg = "assertion")
  unless cond
    puts "task49-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task49-wiring --selftest: FAIL #{msg}"
    puts "  expected: #{expected.inspect}"
    puts "  actual:   #{actual.inspect}"
    exit 1
  end
end

def with_env(key, value)
  previous = ENV[key]
  if value.nil?
    ENV.delete(key)
  else
    ENV[key] = value
  end
  yield
ensure
  if previous.nil?
    ENV.delete(key)
  else
    ENV[key] = previous
  end
end

def run_selftest
  url = %(let url = "https://example.com" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://example.com"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert !strip_comments("let a = 1 /* x */ let b = 2").include?("x"), "正例: /* */ を除去する"
  nested = "let a = 1 /* x /* z */ y */ let b = 2"
  nested_stripped = strip_comments(nested)
  selftest_assert !nested_stripped.include?("x") && !nested_stripped.include?("z") && nested_stripped.include?("let b = 2"), "正例: 入れ子ブロックコメントを除去する"
  interp = %(let s = "\\(SessionTitleDeriver.derive(from: t))" // note)
  selftest_assert strip_comments(interp).include?("SessionTitleDeriver.derive"), "正例: 補間文字列を保持する"
  spaced = %(Text("hello world"))
  selftest_assert normalize_code(spaced).include?("hello world"), "正例: 文字列内空白を正規化で消さない"

  good = good_files
  selftest_errors_eq check_product(good), [], "正例: 契約どおりの配線は空 NG"
  selftest_errors_eq invariant_errors(good, good), [], "正例: 恒久比較は同一 blob で空"

  commented = with_file(good, :presentation) { |src|
    src + %(\n// SessionTitleDeriver.derive\nlet decoy = "HistoryEntryPresentation"\n)
  }
  selftest_errors_eq check_product(commented), [], "正例: コメント・文字列だけを加える"

  commented_call = with_file(good, :presentation) { |src|
    src.sub(
      "let derived = SessionTitleDeriver.derive(from: entry.preview)",
      "// let derived = SessionTitleDeriver.derive(from: entry.preview)\n        let derived: DerivedSessionTitle? = nil"
    )
  }
  selftest_errors_eq check_presentation(commented_call[:presentation]), ["表示モデルが SessionTitleDeriver.derive を呼んでいない"], "負例: コメントだけのモデル呼び出し"

  string_only = with_file(good, :presentation) { |src|
    src.sub(
      "let derived = SessionTitleDeriver.derive(from: entry.preview)",
      %(let derived: DerivedSessionTitle? = nil\n        let decoy = "SessionTitleDeriver.derive(from: entry.preview)")
    )
  }
  selftest_errors_eq check_presentation(string_only[:presentation]), ["表示モデルが SessionTitleDeriver.derive を呼んでいない"], "負例: 文字列だけのモデル呼び出し"

  unused = with_file(good, :history) { |src|
    src.sub(
      "let presentation = HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory)",
      "let unused = HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory)\n        let presentation = Dummy.row()"
    )
  }
  selftest_errors_eq check_history_view(unused[:history]), ["行から表示モデルが未接続"], "負例: 未使用ヘルパー"

  discarded = with_file(good, :history) { |src|
    src.sub(
      "let presentation = HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory)",
      "_ = HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory)\n        let presentation = Dummy.row()"
    )
  }
  selftest_errors_eq check_history_view(discarded[:history]), ["行から表示モデルが未接続"], "負例: 戻り値破棄"

  if_false = with_file(good, :history) { |src|
    src.sub(
      "let presentation = HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory)",
      "if false {\n          let presentation = HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory)\n        }\n        let presentation = Dummy.row()"
    )
  }
  selftest_errors_eq check_history_view(if_false[:history]), ["行から表示モデルが未接続"], "負例: if false だけのモデル呼び出し"

  preview = with_file(good, :history) { |src|
    src.sub("Text(presentation.title)", "Text(entry.preview)")
  }
  selftest_errors_eq check_history_view(preview[:history]), ["主表示が entry.preview になっている"], "負例: 主表示を entry.preview に戻す"

  fixed_wd = with_file(good, :session) { |src|
    src.sub("workingDirectory: viewModel.rawWorkspacePath", 'workingDirectory: "/tmp/fixed"')
  }
  selftest_errors_eq check_session_view(fixed_wd[:session]), ["作業ディレクトリを固定値にしている"], "負例: 作業ディレクトリを固定値にする"

  first_user = with_file(good, :history) { |src|
    src.sub("formattedLastUsed(presentation.lastUsedAt)", "formattedLastUsed(entry.firstUserAt)")
  }
  selftest_errors_eq check_history_view(first_user[:history]), [
    "最終利用に firstUserAt を使っている",
    "lastUsedAt が補助表示へ渡っていない",
  ], "負例: 最終利用に firstUserAt を使う"

  model_first_user = with_file(good, :presentation) { |src|
    src.sub(
      "entry.lastModified == .distantPast ? nil : entry.lastModified",
      "entry.lastModified == .distantPast ? nil : (entry.firstUserAt ?? entry.lastModified)"
    )
  }
  selftest_errors_eq check_presentation(model_first_user[:presentation]), ["最終利用に firstUserAt を使っている"], "負例: モデルが firstUserAt を使う"

  no_help = with_file(good, :history) { |src|
    src.gsub(/\.help\([^)]*\)/, "")
  }
  selftest_errors_eq check_history_view(no_help[:history]), [
    "fullTitle の help が無い",
    "projectPath の help が無い",
    "sessionID の help が無い",
  ], "負例: help を欠落させる"

  no_ax = with_file(good, :history) { |src|
    src.sub('.accessibilityLabel(presentation.fullTitle + " " + entry.sessionID)', "")
  }
  selftest_errors_eq check_history_view(no_ax[:history]), [
    "fullTitle のアクセシビリティラベルが無い",
    "sessionID のアクセシビリティラベルが無い",
  ], "負例: アクセシビリティを欠落させる"

  no_resume = with_file(good, :history) { |src|
    src.sub('Text("続きから再開")', 'Text("履歴から再開")')
  }
  selftest_errors_eq check_history_view(no_resume[:history]), ["続きから再開 の案内が無い"], "負例: 続きから再開の案内を欠落させる"

  no_new = with_file(good, :history) { |src|
    src.sub('Text("新規作成")', 'Text("別案内")')
  }
  selftest_errors_eq check_history_view(no_new[:history]), ["新規作成 の案内が無い"], "負例: 新規作成の案内を欠落させる"

  other_entry = with_file(good, :session) { |src|
    src.sub("startFromHistory(entry)", "startFromHistory(entries[0])")
  }
  selftest_errors_eq check_session_view(other_entry[:session]), ["別 entry を選択している"], "負例: 別 entry を選択する"

  retitle = with_file(good, :session) { |src|
    src.sub("startFromHistory(entry)", "startFromHistory(entries.first { $0.preview == title }!)")
  }
  selftest_errors_eq check_session_view(retitle[:session]), ["タイトルから再開先を引き直している"], "負例: タイトルから再開先を引き直す"

  weaken = with_file(good, :vm) { |src|
    src.sub(
      "guard transcript.isEmpty, submitBaselineTurnSeq == nil else { return false }",
      "guard true else { return false }"
    )
  }
  selftest_errors_eq invariant_errors(weaken, good), ["ChatSessionViewModel.shouldOfferHistoryStart が基準 blob と同一ではない"], "負例: 履歴表示条件を弱める"

  cache = with_file(good, :vm) { |src|
    src.sub("prefix(20)", "prefix(50)")
  }
  selftest_errors_eq invariant_errors(cache, good), ["ChatSessionViewModel.scheduleHistoryCacheLoadIfNeeded が基準 blob と同一ではない"], "負例: キャッシュを変更する"

  restore = with_file(good, :vm) { |src|
    src.sub("try await client.resume(sessionRef: entry.sessionID)", "try await client.start()")
  }
  selftest_errors_eq invariant_errors(restore, good), ["ChatSessionViewModel.startFromHistory が基準 blob と同一ではない"], "負例: 復元処理を変更する"

  entry_changed = with_file(good, :entry) { |src| src + "\n" }
  selftest_errors_eq invariant_errors(entry_changed, good), ["task-51 の ClaudeSessionHistoryEntry.swift が凍結時点から変更されている"], "負例: task-51 の entry を変更する"

  claude_changed = with_file(good, :claude) { |src| src.sub("Discovery", "Loader") }
  selftest_errors_eq invariant_errors(claude_changed, good), ["task-51 の ClaudeSessionHistory.swift が凍結時点から変更されている"], "負例: task-51 の取得器を変更する"

  unparsed = "struct HistoryEntryPresentation: Equatable { public init(entry: ClaudeSessionHistoryEntry, workingDirectory: String?) {"
  selftest_errors_eq check_presentation(unparsed), ["HistoryEntryPresentation を解析できない"], "負例: 構文切り出し失敗"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_errors_eq unset_errs, ["TASK49_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: 基準の未設定"
  selftest_assert unset.nil?, "負例: 未設定は nil"
  _invalid, invalid_errs = baseline_env_errors("not-a-sha")
  selftest_errors_eq invalid_errs, ["TASK49_BASELINE がコミット SHA ではない（ブランチ名は使えない）: not-a-sha"], "負例: SHA 不正"
  _head, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK49_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD 指定"
  _head1, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK49_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD~1 指定"
  _at, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK49_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: @ 指定"
  _branch, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK49_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_errors_eq parse_contract_baseline_text("---\nfoo: 1\n"), :missing, "負例: 契約 baseline_commit 欠落"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n"), :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"not-a-sha\"\n"), :invalid, "負例: 契約 baseline_commit 不正"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"abc1234\"\n"), "abc1234", "正例: 契約 baseline_commit がクォート付き SHA"
  ph_errs = contract_baseline_errors("---\nbaseline_commit: \"PM が凍結時に設定\"\n", "abc1234")
  selftest_errors_eq ph_errs, ["契約 baseline_commit がプレースホルダ（凍結時に実 SHA へ置換する）"], "負例: プレースホルダは NG"

  head_full = git_full_sha("HEAD")
  other_full = git_full_sha("HEAD^")
  selftest_assert !head_full.nil? && !other_full.nil? && head_full != other_full, "selftest 用に有効で異なる 2 コミットが必要"
  real_mismatch = contract_baseline_errors("---\nbaseline_commit: \"#{other_full}\"\n", head_full)
  selftest_errors_eq real_mismatch, ["TASK49_BASELINE が契約 baseline_commit と一致しない"], "負例: 契約不一致"

  same_blob = "frozen\n"
  artifacts_ok = {
    presentation_blob: nil,
    deriver_blob: "public enum SessionTitleDeriver {}",
    entry_blob: good_entry,
    history_blob: baseline_history,
    test_blobs: [same_blob],
    test_nows: [same_blob],
    rb_blob: same_blob,
    rb_now: same_blob,
  }
  selftest_errors_eq check_frozen_baseline(head_full, artifacts_ok), [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  post_ng = check_frozen_baseline(head_full, artifacts_ok.merge(presentation_blob: "struct HistoryEntryPresentation {}"))
  selftest_errors_eq post_ng, ["基準時点に HistoryEntryPresentation.swift がある（実装前の凍結ではない）"], "負例: 実装済み基準"

  wired_ng = check_frozen_baseline(head_full, artifacts_ok.merge(history_blob: good_history))
  selftest_errors_eq wired_ng, ["基準時点に本タスクの表示配線がある（実装前の凍結ではない）"], "負例: 実装入り基準の表示配線"

  no_task41 = check_frozen_baseline(head_full, artifacts_ok.merge(deriver_blob: nil))
  selftest_errors_eq no_task41, ["基準時点に SessionTitleDeriver.swift が無い（task-41 完了状態ではない）"], "負例: task-41 完了状態が基準に無い"

  no_task51 = check_frozen_baseline(head_full, artifacts_ok.merge(entry_blob: "public struct ClaudeSessionHistoryEntry { public let preview: String }\n"))
  selftest_errors_eq no_task51, ["基準時点の entry に titleUserMessages が無い（task-51 完了状態ではない）"], "負例: task-51 完了状態が基準に無い"

  git_fail = check_frozen_baseline(head_full, artifacts_ok.merge(presentation_error: "fatal: bad object"))
  selftest_errors_eq git_fail, ["基準時点の HistoryEntryPresentation.swift を git show できない: fatal: bad object"], "負例: 基準 git 障害"

  missing_pres = check_frozen_baseline(head_full, artifacts_ok.merge(presentation_blob: nil))
  selftest_errors_eq missing_pres, [], "正例: 新規製品ファイルの基準不存在は git 障害ではない"

  selftest_errors_eq blob_fetch_errors("rb 自身", { kind: :ok, text: "now" }, "frozen"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 凍結検査の改変"
  selftest_errors_eq blob_fetch_errors("受け入れテスト1", { kind: :git_error, text: nil, stderr: "fatal: foo" }, "now"), ["基準時点の受け入れテスト1を git show できない: fatal: foo"], "負例: blob 取得失敗"
  selftest_errors_eq blob_fetch_errors("受け入れテスト1", { kind: :missing, text: nil, stderr: "" }, "now"), ["基準時点の受け入れテスト1が無い"], "負例: 基準ファイル不存在"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "same", "same"), [], "正例: 凍結 rb と作業ツリーが同一"
  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"

  non_anc = check_frozen_baseline(other_full, artifacts_ok)
  selftest_assert !non_anc.include?("TASK49_BASELINE が HEAD の祖先ではない"), "正例: HEAD^ は祖先"
  forced_non_ancestor = check_frozen_baseline(head_full, artifacts_ok.merge(is_ancestor: false))
  selftest_errors_eq forced_non_ancestor, ["TASK49_BASELINE が HEAD の祖先ではない"], "負例: 非祖先"

  out_of_scope = good.merge(extra_changed: [VM_PATH])
  selftest_errors_eq scope_errors(out_of_scope, good), ["許可パス外の製品変更: #{VM_PATH}"], "負例: scope のみで拒否すべき範囲外変更"
  selftest_errors_eq check_product(good.merge(vm: "changed")), [], "正例: scope なしでは範囲外変更を範囲違反にしない"

  unset_ng = evaluate_checks(out_of_scope, good, scope: false)
  one_ng = evaluate_checks(out_of_scope, good, scope: true)
  selftest_errors_eq unset_ng, [], "正例: 未設定/0 相当は範囲外変更を恒久 NG にしない"
  selftest_errors_eq one_ng, ["許可パス外の製品変更: #{VM_PATH}"], "負例: SCOPE_CHECK=1 の本番判定"

  with_env("TASK49_SCOPE_CHECK", "1") { selftest_assert scope_check_requested?, "正例: SCOPE_CHECK=1" }
  with_env("TASK49_SCOPE_CHECK", "0") { selftest_assert !scope_check_requested?, "正例: SCOPE_CHECK=0 では恒久のみ" }
  with_env("TASK49_SCOPE_CHECK", nil) { selftest_assert !scope_check_requested?, "正例: 未設定では恒久のみ" }
  unset_pred = nil
  zero_pred = nil
  one_pred = nil
  with_env("TASK49_SCOPE_CHECK", nil) { unset_pred = scope_check_requested? }
  with_env("TASK49_SCOPE_CHECK", "0") { zero_pred = scope_check_requested? }
  with_env("TASK49_SCOPE_CHECK", "1") { one_pred = scope_check_requested? }
  selftest_errors_eq evaluate_checks(out_of_scope, good, scope: unset_pred), [], "正例: 未設定の本番分岐"
  selftest_errors_eq evaluate_checks(out_of_scope, good, scope: zero_pred), [], "正例: SCOPE_CHECK=0 の本番分岐"
  selftest_errors_eq evaluate_checks(out_of_scope, good, scope: one_pred), ["許可パス外の製品変更: #{VM_PATH}"], "正例: SCOPE_CHECK=1 の本番分岐"

  selftest_errors_eq protected_member_errors(nil, good[:vm], "ChatSessionViewModel", "shouldOfferHistoryStart", :var), ["ChatSessionViewModel.shouldOfferHistoryStart を解析できない"], "負例: VM 比較元欠落は非ゼロ"
  selftest_errors_eq protected_member_errors(good[:vm], nil, "ChatSessionViewModel", "shouldOfferHistoryStart", :var), ["ChatSessionViewModel.shouldOfferHistoryStart を解析できない"], "負例: VM 比較先欠落は非ゼロ"
  selftest_assert extract_type_body(good[:vm], "ChatSessionViewModel"), "正例: class ChatSessionViewModel を解析する"

  weaken_view = with_file(good, :session) { |src|
    src.sub("if viewModel.shouldOfferHistoryStart", "if viewModel.shouldOfferHistoryStart || true")
  }
  selftest_errors_eq check_session_view(weaken_view[:session]), ["描画側の履歴表示条件を弱めている"], "負例: 描画条件を || true にする"
  selftest_errors_eq session_view_freeze_errors(weaken_view[:session], good[:session]), ["ChatSessionView が基準 blob と同一ではない"], "負例: 描画条件変更は View 凍結比較で検出"

  measured = with_file(good, :session) { |src|
    src.sub("ChatHistoryStartLayout.maxCardHeight", "FixedHeight.value")
  }
  selftest_errors_eq check_session_view(measured[:session]), [
    "maxCardHeight が実測値に接続されていない",
    "maxCardHeight の availableHeight が実測値ではない",
    "maxCardHeight の composerHeight が実測値ではない",
  ], "負例: maxCardHeight を固定値にする"

  height_arg = with_file(good, :session) { |src|
    src.sub("availableHeight: overlayGeometry.size.height", "availableHeight: 800")
  }
  selftest_errors_eq check_session_view(height_arg[:session]), ["maxCardHeight の availableHeight が実測値ではない"], "負例: maxCardHeight 引数を固定値にする"

  comment_only_height = with_file(good, :session) { |src|
    src.sub("availableHeight: overlayGeometry.size.height", "availableHeight: 800 /* overlayGeometry.size.height */")
  }
  selftest_errors_eq check_session_view(comment_only_height[:session]), ["maxCardHeight の availableHeight が実測値ではない"], "負例: コメントだけで availableHeight を満たす"

  alias_height = with_file(good, :session) { |src|
    src.sub("GeometryReader { overlayGeometry in", "GeometryReader { overlayGeometry in\n              let availableHeight = overlayGeometry.size.height")
      .sub("availableHeight: overlayGeometry.size.height", "availableHeight: availableHeight")
  }
  selftest_errors_eq check_session_view(alias_height[:session]), [], "正例: 別名代入の availableHeight"

  unrelated_height = with_file(good, :session) { |src|
    src.sub("GeometryReader { overlayGeometry in", "GeometryReader { overlayGeometry in\n              let availableHeight = composerHeight")
      .sub("availableHeight: overlayGeometry.size.height", "availableHeight: availableHeight")
  }
  selftest_errors_eq check_session_view(unrelated_height[:session]), ["maxCardHeight の availableHeight が実測値ではない"], "負例: availableHeight が無関係な値"

  view_mh = with_file(good, :session) { |src|
    src.sub("maxCardHeight: cardMaxHeight", "maxCardHeight: 360")
  }
  selftest_errors_eq check_session_view(view_mh[:session]), ["maxCardHeight 引数が実測値ではない"], "負例: ChatHistoryStartView の maxCardHeight を固定値にする"

  no_pad = with_file(good, :session) { |src|
    src.sub(".padding(.bottom, bottomInset)", "")
  }
  selftest_errors_eq check_session_view(no_pad[:session]), ["bottomInset の余白が無い"], "負例: bottomInset 余白を削除する"
  selftest_errors_eq session_view_freeze_errors(no_pad[:session], good[:session]), ["ChatSessionView が基準 blob と同一ではない"], "負例: 余白削除は View 凍結比較で検出"

  composer_overlay = with_file(good, :session) { |src|
    src.sub(".overlay(alignment: .bottom)", ".overlay(alignment: .top)")
  }
  selftest_errors_eq check_session_view(composer_overlay[:session]), ["composer の overlay 配線が無い"], "負例: composer overlay 配線を外す"

  foreach_first = with_file(good, :history) { |src|
    src.sub("row(for: entry)", "row(for: entries[0])")
  }
  selftest_errors_eq check_history_view(foreach_first[:history]), ["ForEach の要素が行へ渡っていない"], "負例: 全行が先頭履歴を選ぶ"

  model_other = with_file(good, :history) { |src|
    src.sub("HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory)", "HistoryEntryPresentation(entry: entries[0], workingDirectory: workingDirectory)")
  }
  selftest_errors_eq check_history_view(model_other[:history]), ["モデルの entry が行の対象と異なる"], "負例: モデルへ別 entry を渡す"

  dup_select = with_file(good, :history) { |src|
    src.sub("onSelect(entry)", "onSelect(entry); onSelect(entry)")
  }
  selftest_errors_eq check_history_view(dup_select[:history]), ["onSelect が重複呼び出しされている"], "負例: onSelect の重複呼び出し"

  appear_select = with_file(good, :history) { |src|
    src.sub(".help(entry.sessionID)", ".onAppear { onSelect(entry) }.help(entry.sessionID)")
  }
  selftest_errors_eq check_history_view(appear_select[:history]), [
    "表示時に再開している",
    "onSelect が重複呼び出しされている",
  ], "負例: 表示時再開"

  no_button = with_file(good, :history) { |src|
    src.sub("Button {", "Group {")
  }
  selftest_errors_eq check_history_view(no_button[:history]), ["Button が無い"], "負例: Button 撤去"

  fixed_project = with_file(good, :history) { |src|
    src.sub("Text(presentation.projectName)", "Text(\"固定名\")")
  }
  selftest_errors_eq check_history_view(fixed_project[:history]), ["projectName が描画されていない"], "負例: 補助表示の固定化"

  nil_last = with_file(good, :history) { |src|
    src.sub("formattedLastUsed(presentation.lastUsedAt)", "formattedLastUsed(nil)")
  }
  selftest_errors_eq check_history_view(nil_last[:history]), ["lastUsedAt が補助表示へ渡っていない"], "負例: lastUsedAt を nil 固定"

  fake_help = with_file(good, :history) { |src|
    src.sub(".help(presentation.fullTitle)", ".help(\"presentation.fullTitle\")")
  }
  selftest_errors_eq check_history_view(fake_help[:history]), ["fullTitle の help が無い"], "負例: help の文字列偽装"

  hidden_new = with_file(good, :history) { |src|
    src.sub("Text(\"新規作成\")", ".accessibilityIdentifier(\"新規作成\")")
  }
  selftest_errors_eq check_history_view(hidden_new[:history]), ["新規作成 の案内が無い"], "負例: 案内を非表示用途へ移動"

  discard_derived = with_file(good, :presentation) { |src|
    src.sub("title = derived?.title ?? \"作業名なし\"", "title = \"独自処理\"")
  }
  selftest_errors_eq check_presentation(discard_derived[:presentation]), ["導出結果の title／fullTitle が返されていない"], "負例: 導出結果を捨てて別値を代入"

  defaults_write = with_file(good, :presentation) { |src|
    src.sub("projectName = \"プロジェクト不明\"", "projectName = \"プロジェクト不明\"; _ = UserDefaults.standard")
  }
  selftest_errors_eq check_presentation(defaults_write[:presentation]), ["表示モデルが View または I/O に依存している"], "負例: UserDefaults.standard 依存"

  date_now = with_file(good, :presentation) { |src|
    src.sub("projectPath = workingDirectory", "projectPath = workingDirectory; _ = Date.now")
  }
  selftest_errors_eq check_presentation(date_now[:presentation]), ["表示モデルが View または I/O に依存している"], "負例: Date.now 依存"

  no_sendable = with_file(good, :presentation) { |src|
    src.sub(": Equatable, Sendable", ": Equatable")
  }
  selftest_errors_eq check_presentation(no_sendable[:presentation]), ["HistoryEntryPresentation が Sendable ではない"], "負例: Sendable 欠落"

  optional_title = with_file(good, :presentation) { |src|
    src.sub("public let title: String", "public let title: String?")
  }
  selftest_errors_eq check_presentation(optional_title[:presentation]), ["public let title: String が無い"], "負例: title の Optional 変異"

  hist_frame = with_file(good, :history) { |src|
    src.sub(".frame(maxHeight: maxCardHeight)", ".frame(maxHeight: 360)")
  }
  selftest_errors_eq check_history_view(hist_frame[:history]), ["maxCardHeight の frame 配線が無い"], "負例: 履歴 View の高さを固定値にする"

  prod = production_checks_source
  selftest_assert !prod.empty?, "正例: 本番検査セクションが存在する"
  selftest_assert baseline_check_connected?(prod), "正例: 基準検査が本番に接続されている"
  selftest_assert scope_check_gated?(prod), "正例: 変更範囲検査が TASK49_SCOPE_CHECK でゲートされている"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task49-wiring --selftest: OK"
  exit 0
end

# === task49 production checks ===
ng = []

raw = ENV["TASK49_BASELINE"]
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
    ng << "TASK49_BASELINE が無効なコミット: #{baseline}"
    baseline = nil
  else
    ng.concat(check_frozen_baseline(full))
    base_blobs = baseline_files(full)
    files = worktree_files(full)
    ng.concat(invariant_errors(files, base_blobs))
    if baseline && scope_check_requested?
      ng.concat(scope_errors(files, base_blobs))
    end
    baseline = full
  end
end

ng = ng.uniq
if ng.empty?
  puts "task49-wiring: OK"
else
  ng.each { |m| puts "task49-wiring: NG #{m}" }
  exit 1
end
