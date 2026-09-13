#!/usr/bin/env ruby
# task-43 配線検査: ComposerDestinationLabel の返り値が単一・グリッド・チームの
# 入力欄近くの Text に到達し、送信先・送信条件は TASK43_BASELINE から変わらないこと。
# コメントと文字列は同時識別する（task17-wiring.rb と同じ字句走査）。
# 比較対象は git show <TASK43_BASELINE>:<path> と作業ファイル。HEAD blob は使わない。

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
  m = src.to_s.match(/(?:^|\n)[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]*)*(?:(?:private|public|fileprivate\s+|internal|open|override|final|static|nonisolated)\s+)*func\s+#{Regexp.escape(name)}\s*\(/)
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

def all_call_args(src, callee)
  args = []
  pos = 0
  re = /#{Regexp.escape(callee)}\s*\(/
  while (m = src.to_s.match(re, pos))
    a = extract_balanced(src, m.end(0) - 1, "(", ")")
    args << a if a
    pos = m.end(0)
  end
  args
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
  ChatComposerFooter ComposerAttachmentStrip ComposerSuggestionPopup IMESafeTextView
  TeamComposerTextInput DSFont DSColor DSSpacing DSRadius ComposerSendButton
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

def all_labeled_args(src, callee, label)
  all_call_args(src.to_s, callee).map { |a| labeled_arg(a, label) }
end

def first_labeled_arg(src, callee, label)
  all_labeled_args(src, callee, label).compact.first
end

def modifier_args(src, name)
  args = []
  pos = 0
  re = /\.#{Regexp.escape(name)}\s*\(/
  while (m = src.to_s.match(re, pos))
    a = extract_balanced(src, m.end(0) - 1, "(", ")")
    args << a if a
    pos = m.end(0)
  end
  args
end

def compact_eq?(a, b)
  compact(a.to_s) == compact(b.to_s)
end

def expr_is_nil?(expr)
  compact(expr.to_s) == "nil"
end

def expr_is_empty_dict?(expr)
  c = compact(expr.to_s)
  c == "[:]" || c == "[:]" || c == "[ProjectID:String]()"
end

def text_argument_idents(src)
  idents = []
  src.to_s.scan(/\bText\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/) { idents << $1 }
  idents
end

def start_member(src, name)
  extract_var_body(src, name) || extract_func_body(src, name)
end

def struct_scope(src, struct_name)
  extract_struct_body(strip_comments(src.to_s), struct_name)
end

def destination_display_start(src, struct_name, start_name)
  scope = struct_scope(src, struct_name)
  return [nil, nil, nil] if scope.nil?
  start = start_member(erase_if_false(scope), start_name)
  return [scope, nil, nil] if start.nil?
  start = erase_if_false(start)
  reach = collect_reachable(scope, start)
  [scope, start, reach]
end

def visible_model_text_in?(src, struct_name, start_name = "body")
  _scope, start, reach = destination_display_start(src, struct_name, start_name)
  return false if start.nil? || reach.nil?
  return false unless mask_strings_and_comments(reach).include?("ComposerDestinationLabel.text")
  return true if reach.match?(/\bText\s*\(\s*ComposerDestinationLabel\.text/)
  names = model_bound_names(src, struct_name, start_name)
  names.any? { |name| reach.match?(/\bText\s*\(\s*#{Regexp.escape(name)}\s*\)/) }
end

def model_bound_names(src, struct_name, start_name)
  scope, start, reach = destination_display_start(src, struct_name, start_name)
  return [] if start.nil? || reach.nil?
  names = []
  reach.to_s.scan(/(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*ComposerDestinationLabel\.text/) { names << $1 }
  text_argument_idents(reach).each do |name|
    next if names.include?(name)
    helper = extract_var_body(scope, name) || extract_func_body(scope, name)
    if helper && mask_strings_and_comments(helper).include?("ComposerDestinationLabel.text")
      names << name
    end
  end
  names.uniq
end

def destination_text_span(src, struct_name, start_name, editor_ident)
  _scope, start, reach = destination_display_start(src, struct_name, start_name)
  return nil if start.nil? || reach.nil?
  names = model_bound_names(src, struct_name, start_name)
  names.each do |name|
    m = reach.match(/\bText\s*\(\s*#{Regexp.escape(name)}\s*\)/)
    next unless m
    editor = reach.index(editor_ident, m.begin(0)) || [m.begin(0) + 1200, reach.length].min
    return [name, reach[m.begin(0)...editor], reach, m.begin(0)]
  end
  m = reach.match(/\bText\s*\(\s*ComposerDestinationLabel\.text/)
  if m
    editor = reach.index(editor_ident, m.begin(0)) || [m.begin(0) + 1200, reach.length].min
    return [nil, reach[m.begin(0)...editor], reach, m.begin(0)]
  end
  nil
end

def visible_model_text?(src, struct_name, start_name = "body")
  visible_model_text_in?(src, struct_name, start_name)
end

def help_only?(src, struct_name, start_name, ax_id)
  _scope, start, reach = destination_display_start(src, struct_name, start_name)
  return false if start.nil? || reach.nil?
  return false unless mask_strings_and_comments(reach).include?("ComposerDestinationLabel.text")
  has_text = visible_model_text_in?(src, struct_name, start_name)
  has_help = reach.include?(".help(")
  has_help && !has_text && reach.include?(ax_id)
end

def destination_before_editor?(src, struct_name, start_name, editor_ident)
  span = destination_text_span(src, struct_name, start_name, editor_ident)
  return false if span.nil?
  _name, _window, surface, text_idx = span
  editor_idx = surface.index(editor_ident)
  return false if editor_idx.nil?
  text_idx < editor_idx
end

def destination_modifiers_ok?(src, struct_name, start_name, editor_ident, ax_id)
  span = destination_text_span(src, struct_name, start_name, editor_ident)
  return { help: false, ax_label: false, ax_id: false, font: false, color: false } if span.nil?
  name, window, _surface, _idx = span
  help_ok = if name
    window.include?(".help(#{name})")
  else
    window.include?(".help(")
  end
  ax_label_ok = if name
    window.include?(".accessibilityLabel(#{name})")
  else
    window.include?(".accessibilityLabel(")
  end
  {
    help: help_ok,
    ax_label: ax_label_ok,
    ax_id: window.include?(%(.accessibilityIdentifier("#{ax_id}"))),
    font: compact(window).include?("DSFont.caption"),
    color: compact(window).include?("DSColor.chatTextSecondary")
  }
end

def height_geometry_covers?(src, callee)
  idx = src.to_s.index(callee)
  return false if idx.nil?
  window = src[idx, 1800]
  window.include?("onGeometryChange") && window.include?("proxy.size.height") && window.include?("composerHeight")
end

def width_only_geometry?(src)
  has_width = src.to_s.include?("proxy.size.width")
  has_height = src.to_s.include?("proxy.size.height") && src.to_s.include?("composerHeight")
  has_width && !has_height
end

def hides_label_without_destination?(src)
  chunks = []
  src.to_s.scan(/if\s+let\s+targetDisplayName\b[\s\S]{0,800}/) { chunks << $& }
  src.to_s.scan(/if\s+targetDisplayName\s*!=\s*nil[\s\S]{0,800}/) { chunks << $& }
  chunks.any? do |chunk|
    chunk.include?("ComposerDestinationLabel.text") ||
      chunk.match?(/\bText\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*\)/)
  end
end

def has_content_defects(expr, require_attachments:)
  ng = []
  c = compact(expr.to_s)
  if require_attachments
    unless c.match?(/![\w.]*attachments\.isEmpty/)
      ng << "画像のみを送信不可表示している（hasContent が添付を見ていない）"
    end
    if c.include?("attachments.isEmpty") && c.include?("&&") && !c.include?("||")
      ng << "hasContent が trim と添付を AND している"
    end
  end
  unless c.include?("trimmingCharacters") || c.include?("trimmedDraft")
    ng << "hasContent が空白・改行のみを本文ありと扱っている"
  end
  ng
end

def readiness_ok?(expr, allowed)
  c = compact(expr.to_s)
  allowed.any? { |a| c == compact(a) }
end

def team_destination_mapping_errors(agora)
  ng = []
  body = extract_func_body(strip_comments(agora.to_s), "teamDestination")
  body ||= agora.to_s
  c = compact(body)
  unless c.include?("case.startDiscussion:return.startDiscussion")
    ng << "終了後を親送信に固定している"
  end
  unless c.include?("case.discussionUtterance:return.discussionUtterance")
    ng << ".concluding を討論外扱いしている"
  end
  unless c.include?("case.legacyRootSend:return.parentSession")
    ng << "teamDestination が既存 action 3 件に接続していない"
  end
  ng
end

CONTRACT_PATH = "tasks/task-43.md"
WIRING_RB_PATH = ".claude/scripts/task43-wiring.rb"
TEST_SESSION = "macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceComposerDestinationLabelTests.swift"
TEST_DASHBOARD = "macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/AcceptanceTeamComposerDestinationLabelTests.swift"

PATHS = {
  label: "macos/Packages/SessionFeature/Sources/SessionFeature/ComposerDestinationLabel.swift",
  agora: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/ComposerDestinationLabel+Agora.swift",
  chat_composer: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift",
  chat_session: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift",
  grid_column: "macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift",
  grid_view: "macos/Packages/SessionFeature/Sources/SessionFeature/SessionGridView.swift",
  pane: "macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift",
  detail: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardDetailView.swift",
  timeline: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamTimelineView.swift",
  team_composer: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamComposer.swift",
  routing: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/AgoraComposerRouting.swift",
  target: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamComposerTarget.swift",
}.freeze

VIEW_PATHS_FOR_BASELINE = [
  PATHS[:chat_composer],
  PATHS[:chat_session],
  PATHS[:grid_column],
  PATHS[:grid_view],
  PATHS[:pane],
  PATHS[:detail],
  PATHS[:timeline],
  PATHS[:team_composer],
].freeze

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
        errs << "TASK43_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK43_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK43_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK43_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
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

def implementation_in_baseline_errors(label_blob, agora_blob, view_blobs)
  ng = []
  ng << "基準時点に ComposerDestinationLabel.swift がある（実装前の凍結ではない）" if label_blob
  ng << "基準時点に ComposerDestinationLabel+Agora.swift がある（実装前の凍結ではない）" if agora_blob
  view_blobs.each do |path, src|
    next if src.nil?
    if code_has_ident?(src, "ComposerDestinationLabel")
      ng << "基準時点の #{path} に ComposerDestinationLabel がある（実装前の凍結ではない）"
    end
  end
  ng
end

def check_frozen_baseline(baseline, opts = {})
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK43_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  unless git_is_ancestor?(full, "HEAD")
    ng << "TASK43_BASELINE が HEAD の祖先ではない"
  end
  label_blob = opts.key?(:label_blob) ? opts[:label_blob] : git_show(full, PATHS[:label])
  agora_blob = opts.key?(:agora_blob) ? opts[:agora_blob] : git_show(full, PATHS[:agora])
  view_blobs = {}
  VIEW_PATHS_FOR_BASELINE.each do |path|
    view_blobs[path] = if opts[:view_blobs]
      opts[:view_blobs][path]
    else
      git_show(full, path)
    end
  end
  ng.concat(implementation_in_baseline_errors(label_blob, agora_blob, view_blobs))
  test1_blob = opts.key?(:test1_blob) ? opts[:test1_blob] : git_show(full, TEST_SESSION)
  test2_blob = opts.key?(:test2_blob) ? opts[:test2_blob] : git_show(full, TEST_DASHBOARD)
  rb_blob = opts.key?(:rb_blob) ? opts[:rb_blob] : git_show(full, WIRING_RB_PATH)
  test1_now = opts.key?(:test1_now) ? opts[:test1_now] : read_if_exist(TEST_SESSION)
  test2_now = opts.key?(:test2_now) ? opts[:test2_now] : read_if_exist(TEST_DASHBOARD)
  rb_now = opts.key?(:rb_now) ? opts[:rb_now] : read_if_exist(WIRING_RB_PATH)
  ng.concat(frozen_artifact_errors("受け入れテスト SessionFeature", test1_blob, test1_now))
  ng.concat(frozen_artifact_errors("受け入れテスト DashboardFeature", test2_blob, test2_now))
  ng.concat(frozen_artifact_errors("rb 自身", rb_blob, rb_now))
  ng
end

def missing_file(files, key, label)
  files[key].nil? ? ["#{label} が存在しない"] : []
end

def init_has_default_project_name?(src)
  compact(src.to_s).include?("projectName:String?=nil")
end

def init_has_default_project_names?(src)
  compact(src.to_s).include?("projectNames:[ProjectID:String]=[:]") ||
    compact(src.to_s).include?("projectNames:[ProjectID:String]=[:]")
end

def call_has_label?(src, callee, label)
  all_call_args(src.to_s, callee).any? { |a| compact(a).include?("#{label}:") }
end

def check_single(files)
  ng = []
  ng.concat(missing_file(files, :chat_composer, PATHS[:chat_composer]))
  ng.concat(missing_file(files, :chat_session, PATHS[:chat_session]))
  ng.concat(missing_file(files, :detail, PATHS[:detail]))
  return ng unless files[:chat_composer] && files[:chat_session] && files[:detail]

  composer_reach = reachable_in_struct(files[:chat_composer], "ChatComposer", "body")
  session = reachable_from(files[:chat_session], "body")
  detail = reachable_from(files[:detail], "singleDetail")
  if composer_reach == :unparseable
    ng << "ChatComposer の body を括弧対応で切り出せない"
    return ng
  end
  if session == :unparseable
    ng << "ChatSessionView の body を括弧対応で切り出せない"
    return ng
  end
  if detail == :unparseable
    ng << "DashboardDetailView.singleDetail を括弧対応で切り出せない"
    return ng
  end

  unless visible_model_text?(files[:chat_composer], "ChatComposer")
    if help_only?(files[:chat_composer], "ChatComposer", "body", "ChatComposer.destination")
      ng << "ChatComposer の送信先表示を help のみに移している"
    else
      ng << "単一経路から ComposerDestinationLabel.text の Text に到達しない"
    end
  end
  mods = destination_modifiers_ok?(files[:chat_composer], "ChatComposer", "body", "IMESafeTextView", "ChatComposer.destination")
  skip_ax = ng.any? { |m| m.include?("単一経路") || m.include?("help のみ") }
  ng << "ChatComposer.destination の AX identifier が無い" unless mods[:ax_id] || skip_ax
  ng << "ChatComposer の全文 help が無い" unless mods[:help] || skip_ax
  ng << "ChatComposer のアクセシビリティラベルが無い" unless mods[:ax_label] || skip_ax
  ng << "ChatComposer が DSFont.caption を使っていない" unless mods[:font] || skip_ax
  ng << "ChatComposer が DSColor.chatTextSecondary を使っていない" unless mods[:color] || skip_ax
  unless destination_before_editor?(files[:chat_composer], "ChatComposer", "body", "IMESafeTextView")
    ng << "ChatComposer の送信先表示が編集領域の直前に無い" unless skip_ax
  end
  unless code_has_ident?(session, "ChatComposer") && height_geometry_covers?(files[:chat_session], "ChatComposer")
    ng << "ChatComposer の送信先表示が composer の計測範囲に無い"
  end

  session_pn = first_labeled_arg(session, "ChatComposer", "projectName")
  if session_pn.nil? || expr_is_nil?(session_pn)
    ng << "ChatSessionView が projectName を ChatComposer へ渡していない"
  elsif compact(session_pn) != "projectName"
    ng << "ChatSessionView が projectName を ChatComposer へ渡していない" unless ng.include?("ChatSessionView が projectName を ChatComposer へ渡していない")
  end
  composer_init = files[:chat_composer]
  if compact(composer_init).include?("self.projectName=nil")
    ng << "ChatComposer が projectName を nil に差し替えている"
  end
  unless init_has_default_project_name?(files[:chat_session]) && init_has_default_project_name?(files[:chat_composer])
    ng << "projectName: String? = nil の既定が無い"
  end
  detail_pn = first_labeled_arg(detail, "ChatSessionView", "projectName")
  if detail_pn.nil? || expr_is_nil?(detail_pn)
    ng << "DashboardDetailView の ChatSessionView が projectName を明示していない（既定 nil）"
  else
    dpc = compact(detail_pn)
    ng << "単一のプロジェクト名が session.projectID から取得されていない" unless dpc.include?("session.projectID")
    ng << "単一のプロジェクト名に router.selectedProjectID を使っている" if dpc.include?("selectedProjectID")
  end

  text_args = extract_call_args(composer_reach, "ComposerDestinationLabel.text")
  text_args ||= begin
    scope = struct_scope(files[:chat_composer], "ChatComposer")
    extract_call_args(scope.to_s, "ComposerDestinationLabel.text") if scope
  end
  if text_args
    task = labeled_arg(text_args, "taskName")
    unless task && compact(task).include?("viewModel.displayName")
      ng << "単一の作業名が viewModel.displayName ではない"
    end
    tc = compact(text_args)
    ng << "単一の送信先に選択カード名を使っている" if tc.include?("selectedSubAgentId") || tc.include?("focusedID")
    has_c = labeled_arg(text_args, "hasContent")
    ng.concat(has_content_defects(has_c, require_attachments: true)) if has_c
    ready = labeled_arg(text_args, "isReadyForInput")
    unless ready && readiness_ok?(ready, ["canSend", "viewModel.isReadyForInput", "canSubmit"])
      ng << "単一の isReadyForInput が既存の送信準備と結びついていない"
    end
    dest = labeled_arg(text_args, "hasDestination")
    if dest && compact(dest) != "true"
      ng << "単一の hasDestination が既存の送信条件と結びついていない"
    end
    pn = labeled_arg(text_args, "projectName") || labeled_arg(text_args, "for")
    conv = compact(text_args)
    if conv.include?("projectName:nil") && conv.include?(".conversation")
      ng << "ChatComposer が projectName を nil に差し替えている"
    elsif pn && expr_is_nil?(pn)
      ng << "ChatComposer が projectName を nil に差し替えている"
    end
  end
  ng
end

def check_grid(files)
  ng = []
  %i[grid_column grid_view pane detail].each do |key|
    ng.concat(missing_file(files, key, PATHS[key]))
  end
  return ng unless files[:grid_column] && files[:grid_view] && files[:pane] && files[:detail]

  column_struct = struct_scope(files[:grid_column], "GridChatColumn")
  column_body = column_struct && start_member(erase_if_false(column_struct), "body")
  bar = reachable_in_struct(files[:grid_column], "GridComposerBar", "body")
  grid = reachable_from(files[:grid_view], "body")
  pane = reachable_from(files[:pane], "body")
  tile = extract_var_body(strip_comments(files[:pane]), "tileContent")
  detail = reachable_from(files[:detail], "detailMainContent")
  if bar == :unparseable || column_body.nil?
    ng << "GridComposerBar の本文を括弧対応で切り出せない"
    return ng
  end
  unless code_has_ident?(column_body, "GridComposerBar")
    ng << "グリッド経路から ComposerDestinationLabel.text の Text に到達しない"
  end
  if grid == :unparseable
    ng << "SessionGridView の body を括弧対応で切り出せない"
    return ng
  end
  if pane == :unparseable || tile.nil?
    ng << "PaneLayoutView のタイル本文を括弧対応で切り出せない"
    return ng
  end
  if detail == :unparseable
    ng << "DashboardDetailView.detailMainContent を括弧対応で切り出せない"
    return ng
  end

  unless visible_model_text?(files[:grid_column], "GridComposerBar")
    if help_only?(files[:grid_column], "GridComposerBar", "body", "GridComposer.destination")
      ng << "GridComposer の送信先表示を help のみに移している"
    else
      ng << "グリッド経路から ComposerDestinationLabel.text の Text に到達しない" unless ng.include?("グリッド経路から ComposerDestinationLabel.text の Text に到達しない")
    end
  end
  mods = destination_modifiers_ok?(files[:grid_column], "GridComposerBar", "body", "IMESafeTextView", "GridComposer.destination")
  skip_ax = ng.any? { |m| m.include?("グリッド経路") || m.include?("help のみ") }
  ng << "GridComposer.destination の AX identifier が無い" unless mods[:ax_id] || skip_ax
  ng << "GridComposer の全文 help が無い" unless mods[:help] || skip_ax
  ng << "GridComposer のアクセシビリティラベルが無い" unless mods[:ax_label] || skip_ax
  ng << "GridComposer が DSFont.caption を使っていない" unless mods[:font] || skip_ax
  ng << "GridComposer が DSColor.chatTextSecondary を使っていない" unless mods[:color] || skip_ax
  unless destination_before_editor?(files[:grid_column], "GridComposerBar", "body", "IMESafeTextView")
    ng << "GridComposer の送信先表示が編集領域の直前に無い" unless skip_ax
  end
  if width_only_geometry?(files[:grid_column]) || !height_geometry_covers?(files[:grid_column], "GridComposerBar")
    ng << "GridComposer の高さ計測が無い（幅計測だけでは足りない）"
  end

  bar_pn = first_labeled_arg(column_body, "GridComposerBar", "projectName")
  if bar_pn.nil? || expr_is_nil?(bar_pn) || compact(bar_pn) != "projectName"
    ng << "GridChatColumn が projectName を GridComposerBar へ渡していない"
  end
  if compact(files[:grid_column]).include?("self.projectName=nil")
    ng << "GridComposerBar が projectName を nil に差し替えている"
  end
  unless call_has_label?(grid, "PaneLayoutView", "projectNames")
    ng << "SessionGridView が projectNames を PaneLayoutView へ渡していない"
  end
  grid_to_pane = first_labeled_arg(grid, "PaneLayoutView", "projectNames")
  if grid_to_pane && expr_is_empty_dict?(grid_to_pane)
    ng << "SessionGridView が projectNames を PaneLayoutView へ渡していない"
  end
  tile_c = compact(tile)
  pane_pn = first_labeled_arg(tile, "GridChatColumn", "projectName") || first_labeled_arg(pane, "GridChatColumn", "projectName")
  unless tile_c.include?("GridChatColumn(") && pane_pn && !expr_is_nil?(pane_pn)
    ng << "PaneLayoutView が projectName を GridChatColumn へ渡していない"
  end
  unless pane.include?("session.projectID") || tile.include?("session.projectID")
    ng << "グリッドのプロジェクト名がタイルの session.projectID から取得されていない"
  end
  text_args = extract_call_args(bar, "ComposerDestinationLabel.text")
  text_args ||= begin
    scope = struct_scope(files[:grid_column], "GridComposerBar")
    extract_call_args(scope.to_s, "ComposerDestinationLabel.text") if scope
  end
  if text_args
    tc = compact(text_args)
    ng << "グリッドが選択中カード名を送信先に使っている" if tc.include?("focusedID") || tc.include?("selectedSubAgent") || tc.include?("focusedSession")
    task = labeled_arg(text_args, "taskName")
    unless task && compact(task).include?("viewModel.displayName")
      ng << "グリッドが選択中カード名を送信先に使っている" unless ng.any? { |m| m.include?("選択中カード") }
    end
    has_c = labeled_arg(text_args, "hasContent")
    ng.concat(has_content_defects(has_c, require_attachments: true)) if has_c
    ready = labeled_arg(text_args, "isReadyForInput")
    unless ready && readiness_ok?(ready, ["canSend", "viewModel.isReadyForInput", "canSubmit"])
      ng << "グリッドの isReadyForInput が既存の送信準備と結びついていない"
    end
    dest = labeled_arg(text_args, "hasDestination")
    if dest && compact(dest) != "true"
      ng << "グリッドの hasDestination が既存の送信条件と結びついていない"
    end
    pn = labeled_arg(text_args, "projectName")
    if pn && expr_is_nil?(pn)
      ng << "GridComposerBar が projectName を nil に差し替えている"
    end
  end
  unless init_has_default_project_names?(files[:grid_view]) && init_has_default_project_names?(files[:pane])
    ng << "projectNames: [ProjectID: String] = [:] の既定が無い"
  end
  detail_pn = first_labeled_arg(detail, "SessionGridView", "projectNames")
  if detail_pn.nil? || expr_is_empty_dict?(detail_pn)
    ng << "DashboardDetailView の SessionGridView が projectNames を明示していない（既定の空辞書）"
  else
    c = compact(detail_pn)
    ng << "グリッドのプロジェクト名に router.selectedProjectID を使っている" if c.include?("selectedProjectID")
    ng << "グリッド全体の選択名を代入している" if c.include?("selectedSession") && !c.include?("projects")
  end
  ng
end

def without_func(src, name)
  body = extract_func_body(src, name)
  return src if body.nil?
  src.sub(body, "")
end

def team_display_generation(timeline_src)
  stripped = strip_comments(timeline_src.to_s)
  cleaned = erase_if_false(stripped)
  struct = extract_struct_body(cleaned, "TeamTimelineView") || cleaned
  body = extract_var_body(struct, "body")
  return [nil, nil, nil] if body.nil?
  reach = collect_reachable(struct, body, skip: ["sendTeamMessage"])
  composer_args = extract_call_args(reach, "TeamComposer") || extract_call_args(body, "TeamComposer")
  dest = labeled_arg(composer_args, "destination")
  expr = dest.to_s
  if dest && dest.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
    helper = extract_var_body(struct, dest) || extract_func_body(struct, dest)
    expr = helper if helper
  end
  display_action_args = []
  td_call = extract_call_args(expr, "ComposerDestinationLabel.teamDestination")
  action_passed = labeled_arg(td_call, "action")
  if action_passed && action_passed.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/) && expr.match?(/let\s+#{Regexp.escape(action_passed)}\s*=\s*AgoraComposerRouting\.action/)
    display_action_args = all_call_args(expr, "AgoraComposerRouting.action")
  elsif action_passed && compact(action_passed).include?("AgoraComposerRouting.action")
    display_action_args = all_call_args(action_passed, "AgoraComposerRouting.action")
  end
  [reach, expr, display_action_args]
end

def check_team(files)
  ng = []
  %i[timeline team_composer agora].each do |key|
    ng.concat(missing_file(files, key, PATHS[key]))
  end
  return ng unless files[:timeline] && files[:team_composer] && files[:agora]

  composer_reach = reachable_in_struct(files[:team_composer], "TeamComposer", "body")
  timeline = reachable_from(files[:timeline], "body", skip: ["sendTeamMessage"])
  if composer_reach == :unparseable
    ng << "TeamComposer の body を括弧対応で切り出せない"
    return ng
  end
  if timeline == :unparseable
    ng << "TeamTimelineView の body を括弧対応で切り出せない"
    return ng
  end

  unless visible_model_text?(files[:team_composer], "TeamComposer")
    if help_only?(files[:team_composer], "TeamComposer", "body", "TeamComposer.destination")
      ng << "TeamComposer の送信先表示を help のみに移している"
    else
      ng << "チーム経路から ComposerDestinationLabel.text の Text に到達しない"
    end
  end
  mods = destination_modifiers_ok?(files[:team_composer], "TeamComposer", "body", "TeamComposerTextInput", "TeamComposer.destination")
  skip_ax = ng.any? { |m| m.include?("チーム経路") || m.include?("help のみ") }
  ng << "TeamComposer.destination の AX identifier が無い" unless mods[:ax_id] || skip_ax
  ng << "TeamComposer の全文 help が無い" unless mods[:help] || skip_ax
  ng << "TeamComposer のアクセシビリティラベルが無い" unless mods[:ax_label] || skip_ax
  unless destination_before_editor?(files[:team_composer], "TeamComposer", "body", "TeamComposerTextInput")
    ng << "TeamComposer の送信先表示が編集領域の直前に無い" unless skip_ax
  end
  if hides_label_without_destination?(composer_reach) || hides_label_without_destination?(struct_scope(files[:team_composer], "TeamComposer").to_s)
    ng << "宛先なしでラベルを非表示にしている"
  end
  disabled_args = modifier_args(files[:team_composer], "disabled")
  unless disabled_args.any? { |a| compact(a) == "!canSend" }
    ng << "TeamComposer の disabled 条件が変わっている"
  end
  enabled = first_labeled_arg(files[:team_composer], "TeamComposerTextInput", "isEnabled")
  unless enabled && compact(enabled) == "targetDisplayName!=nil"
    ng << "TeamComposer の編集可否条件が変わっている"
  end

  send_body = extract_func_body(strip_comments(files[:timeline]), "sendTeamMessage")
  display_reach, display_expr, display_args = team_display_generation(files[:timeline])
  send_args = all_call_args(send_body.to_s, "AgoraComposerRouting.action")
  if display_args.nil? || display_args.empty?
    ng << "チーム表示用 action が sendTeamMessage と同じ入力元でない（未接続）"
  end
  if send_args.empty?
    ng << "sendTeamMessage の AgoraComposerRouting.action を切り出せない"
  end
  if send_args[0] && display_args && display_args[0]
    send_phase = labeled_arg(send_args[0], "phase")
    disp_phase = labeled_arg(display_args[0], "phase")
    send_can = labeled_arg(send_args[0], "canStartDiscussion")
    disp_can = labeled_arg(display_args[0], "canStartDiscussion")
    unless compact_eq?(send_phase, disp_phase)
      ng << "チーム表示用 action の phase が sendTeamMessage と異なる"
    end
    unless compact_eq?(send_can, disp_can)
      ng << "チーム表示用 action の開始可否が sendTeamMessage と異なる"
    end
    unless compact(send_phase.to_s).include?("viewModel.agoraDiscussionCoordinator?.phase")
      ng << "sendTeamMessage の phase 入力が契約と異なる"
    end
    unless compact(send_can.to_s).include?("TeamTimelineAgoraPolicy.canStartDiscussion") && compact(send_can.to_s).include?("canResolveProjectForNewSession")
      ng << "sendTeamMessage の開始可否入力が契約と異なる"
    end
  end
  unless code_has_ident?(display_expr.to_s, "teamDestination") || code_has_ident?(display_reach.to_s, "teamDestination")
    ng << "TeamTimelineView が表示用 teamDestination を呼んでいない"
  end
  dest_args = extract_call_args(display_expr.to_s, "ComposerDestinationLabel.teamDestination")
  dest_args ||= extract_call_args(display_reach.to_s, "ComposerDestinationLabel.teamDestination")
  if dest_args
    root_task = labeled_arg(dest_args, "rootTaskName")
    root_proj = labeled_arg(dest_args, "rootProjectName")
    unless root_task && compact(root_task).include?("composerTargetNode") && compact(root_task).include?("displayName")
      ng << "親名を子名に差し替えている"
    end
    unless root_proj && compact(root_proj).include?("composerTargetNode") && compact(root_proj).include?("projectID")
      ng << "チームの rootProjectName が composerTargetNode の projectID から取得されていない"
    end
  end

  ng.concat(team_destination_mapping_errors(files[:agora]))
  can_send = extract_var_body(strip_comments(files[:team_composer]), "canSend")
  if can_send && compact(can_send).include?("canStartDiscussion")
    ng << "討論開始可能を理由にボタンを有効化している"
  end
  if (team_text = extract_call_args(composer_reach, "ComposerDestinationLabel.text"))
    dest_bool = labeled_arg(team_text, "hasDestination")
    ng << "チームの hasDestination が targetDisplayName != nil と結びついていない" unless dest_bool && compact(dest_bool).include?("targetDisplayName") && compact(dest_bool).include?("!=nil")
    ready = labeled_arg(team_text, "isReadyForInput")
    ng << "チームの isReadyForInput が既存の送信準備と結びついていない" unless ready && readiness_ok?(ready, ["isReadyForInput", "composerIsReadyForInput"])
    has_c = labeled_arg(team_text, "hasContent")
    ng.concat(has_content_defects(has_c, require_attachments: false)) if has_c
  end
  ng.uniq
end

INVARIANT_FUNCS = [
  [:chat_session, "sendDraft"],
  [:grid_column, "sendDraft"],
  [:team_composer, "send"],
  [:timeline, "sendTeamMessage"],
  [:routing, "action"],
  [:target, "resolveRootSessionID"],
  [:timeline, "canStartDiscussion"],
  [:timeline, "isDiscussionActive"],
].freeze

INVARIANT_VARS = [
  [:chat_composer, "canSubmit"],
  [:grid_column, "canSubmit"],
  [:team_composer, "canSend"],
  [:timeline, "composerTargetNode"],
  [:timeline, "composerTargetDisplayName"],
  [:timeline, "composerIsReadyForInput"],
].freeze

INVARIANT_CALLS = [
  [:chat_composer, "ChatComposerFooter", "canSubmit"],
  [:grid_column, "ChatComposerFooter", "canSubmit"],
  [:chat_composer, "IMESafeTextView", "onSubmit"],
  [:grid_column, "IMESafeTextView", "onSubmit"],
  [:grid_column, "GridComposerBar", "onFocusGained"],
].freeze

INVARIANT_DISABLED = [
  [:chat_composer, "canSubmit"],
  [:team_composer, "canSend"],
].freeze

def check_func_unchanged(files, previous, key, name)
  ng = []
  cur = files[key]
  prev = previous[key]
  if cur.nil? || prev.nil?
    ng << "#{PATHS[key]} の #{name} を baseline または作業ツリーから切り出せない"
    return ng
  end
  a = extract_func_body(strip_comments(prev), name)
  b = extract_func_body(strip_comments(cur), name)
  if a.nil? || b.nil?
    ng << "#{PATHS[key]} の #{name} を括弧対応で切り出せない"
  elsif normalize_code(a) != normalize_code(b)
    ng << "#{name} が TASK43_BASELINE から変化している"
  end
  ng
end

def check_var_unchanged(files, previous, key, name)
  ng = []
  cur = files[key]
  prev = previous[key]
  if cur.nil? || prev.nil?
    ng << "#{PATHS[key]} の #{name} を baseline または作業ツリーから切り出せない"
    return ng
  end
  a = extract_var_body(strip_comments(prev), name)
  b = extract_var_body(strip_comments(cur), name)
  if a.nil? || b.nil?
    ng << "#{PATHS[key]} の #{name} を括弧対応で切り出せない"
  elsif normalize_code(a) != normalize_code(b)
    ng << "#{name} が TASK43_BASELINE から変化している"
  end
  ng
end

def check_call_label_unchanged(files, previous, key, callee, label)
  ng = []
  cur = files[key]
  prev = previous[key]
  if cur.nil? || prev.nil?
    ng << "#{PATHS[key]} の #{callee} を baseline または作業ツリーから切り出せない"
    return ng
  end
  cur_vals = all_labeled_args(strip_comments(cur), callee, label).map { |a| compact(a.to_s) }
  prev_vals = all_labeled_args(strip_comments(prev), callee, label).map { |a| compact(a.to_s) }
  if cur_vals != prev_vals
    ng << "#{callee} の #{label}: が TASK43_BASELINE から変化している"
  end
  ng
end

def check_disabled_unchanged(files, previous, key, predicate)
  ng = []
  cur = files[key]
  prev = previous[key]
  if cur.nil? || prev.nil?
    ng << "#{PATHS[key]} の disabled を baseline または作業ツリーから切り出せない"
    return ng
  end
  cur_vals = modifier_args(strip_comments(cur), "disabled").map { |a| compact(a) }
  prev_vals = modifier_args(strip_comments(prev), "disabled").map { |a| compact(a) }
  if cur_vals != prev_vals
    ng << "#{PATHS[key].split('/').last} の disabled が TASK43_BASELINE から変化している"
  elsif !cur_vals.any? { |v| v == "!#{predicate}" || v.include?(predicate) }
    ng << "#{PATHS[key].split('/').last} の disabled が TASK43_BASELINE から変化している" unless prev_vals.empty?
  end
  ng
end

def check_invariants(files, previous)
  ng = []
  INVARIANT_FUNCS.each { |key, name| ng.concat(check_func_unchanged(files, previous, key, name)) }
  INVARIANT_VARS.each { |key, name| ng.concat(check_var_unchanged(files, previous, key, name)) }
  INVARIANT_CALLS.each { |key, callee, label| ng.concat(check_call_label_unchanged(files, previous, key, callee, label)) }
  INVARIANT_DISABLED.each { |key, predicate| ng.concat(check_disabled_unchanged(files, previous, key, predicate)) }
  ng
end

def check_product(files)
  ng = []
  ng.concat(missing_file(files, :label, PATHS[:label]))
  ng.concat(missing_file(files, :agora, PATHS[:agora]))
  ng.concat(check_single(files))
  ng.concat(check_grid(files))
  ng.concat(check_team(files))
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

def good_label_src
  <<~SWIFT
    public enum ComposerDestinationLabel {
      public enum Destination: Equatable, Sendable {
        case conversation(projectName: String?, taskName: String)
        case startDiscussion
        case discussionUtterance
        case parentSession(projectName: String?, taskName: String?)
      }
      public static func text(for destination: Destination, hasDestination: Bool, isReadyForInput: Bool, hasContent: Bool) -> String {
        "Phlox / 入力欄改善"
      }
    }
  SWIFT
end

def good_agora_src
  <<~SWIFT
    extension ComposerDestinationLabel {
      static func teamDestination(action: AgoraComposerAction, rootProjectName: String?, rootTaskName: String?) -> Destination {
        switch action {
        case .startDiscussion: return .startDiscussion
        case .discussionUtterance: return .discussionUtterance
        case .legacyRootSend: return .parentSession(projectName: rootProjectName, taskName: rootTaskName)
        }
      }
    }
  SWIFT
end

def destination_view(ax)
  <<~SWIFT
            let destinationText = ComposerDestinationLabel.text(for: .conversation(projectName: projectName, taskName: viewModel.displayName), hasDestination: true, isReadyForInput: canSend, hasContent: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachmentStore.attachments.isEmpty)
            Text(destinationText)
              .font(DSFont.caption)
              .foregroundStyle(DSColor.chatTextSecondary)
              .lineLimit(1)
              .help(destinationText)
              .accessibilityLabel(destinationText)
              .accessibilityIdentifier("#{ax}")
  SWIFT
end

def good_chat_composer_src
  <<~SWIFT
    struct ChatComposer: View {
      let projectName: String?
      let canSend: Bool
      init(viewModel: ChatSessionViewModel, text: Binding<String>, isRunning: Bool, canSend: Bool, projectName: String? = nil, onSend: @escaping () -> Void, onInterrupt: @escaping () -> Void) {
        self.projectName = projectName
        self.canSend = canSend
      }
      var body: some View {
        VStack {
    #{destination_view("ChatComposer.destination")}
          ZStack {
            IMESafeTextView(text: $text, onSubmit: onSend)
          }
          ChatComposerFooter(canSubmit: canSubmit, onSend: onSend)
          Button(action: onSend) { Image(systemName: "paperplane.fill") }
            .disabled(!canSubmit)
        }
      }
      private var canSubmit: Bool {
        canSend && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachmentStore.attachments.isEmpty)
      }
    }
  SWIFT
end

def good_chat_session_src
  <<~SWIFT
    public struct ChatSessionView: View {
      let projectName: String?
      public init(viewModel: ChatSessionViewModel, projectName: String? = nil) {
        self.projectName = projectName
      }
      public var body: some View {
        ChatComposer(viewModel: viewModel, text: $viewModel.draft, isRunning: viewModel.showsProcessingIndicator, canSend: viewModel.isReadyForInput, projectName: projectName, onSend: sendDraft, onInterrupt: interruptTurn)
          .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { height in composerHeight = height }
      }
      private func sendDraft() {
        guard let text = viewModel.consumeDraftForSend() else { return }
        Task { try await viewModel.sendText(text, submit: true) }
      }
    }
  SWIFT
end

def good_grid_column_src
  <<~SWIFT
    struct GridChatColumn: View {
      let projectName: String?
      var body: some View {
        GridComposerBar(viewModel: viewModel, text: $viewModel.draft, projectName: projectName, onSend: sendDraft, onInterrupt: interruptTurn, onFocusGained: onFocusGained)
          .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { height in composerHeight = height }
          .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { width in stableWidth = width }
      }
      private func sendDraft() {
        guard let text = viewModel.consumeDraftForSend() else { return }
        Task { try await viewModel.sendText(text, submit: true) }
      }
    }
    struct GridComposerBar: View {
      let projectName: String?
      init(viewModel: ChatSessionViewModel, text: Binding<String>, projectName: String? = nil, onSend: @escaping () -> Void, onInterrupt: @escaping () -> Void, onFocusGained: @escaping () -> Void = {}) {
        self.projectName = projectName
      }
      var body: some View {
        composerContent()
      }
      private func composerContent() -> some View {
        VStack {
    #{destination_view("GridComposer.destination")}
          ZStack {
            IMESafeTextView(text: $text, onSubmit: onSend, onFocusGained: onFocusGained)
          }
          ChatComposerFooter(canSubmit: canSubmit, onSend: onSend)
          Button(action: onSend) { Image(systemName: "paperplane.fill") }
            .disabled(!canSubmit)
        }
      }
      private var canSubmit: Bool {
        viewModel.isReadyForInput && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachmentStore.attachments.isEmpty)
      }
    }
  SWIFT
end

def good_grid_view_src
  <<~SWIFT
    public struct SessionGridView: View {
      let projectNames: [ProjectID: String]
      public init(sessions: [SessionNode], paneLayout: PaneTree, focusedID: Binding<SessionID?>, onRemove: @escaping (SessionNode) -> Void, onRename: @escaping (SessionNode) -> Void, onChangeWorkspace: @escaping (SessionViewModel) -> Void, onLayoutAction: @escaping (PaneLayoutAction) -> Void, projectNames: [ProjectID: String] = [:]) {
        self.projectNames = projectNames
      }
      public var body: some View {
        PaneLayoutView(sessions: sessions, tree: paneLayout, focusedID: $focusedID, onRemove: onRemove, onRename: onRename, onChangeWorkspace: onChangeWorkspace, onLayoutAction: onLayoutAction, projectNames: projectNames)
      }
    }
  SWIFT
end

def good_pane_src
  <<~SWIFT
    public struct PaneLayoutView: View {
      let projectNames: [ProjectID: String]
      public init(sessions: [SessionNode], tree: PaneTree, focusedID: Binding<SessionID?>, onRemove: @escaping (SessionNode) -> Void, onRename: @escaping (SessionNode) -> Void, onChangeWorkspace: @escaping (SessionViewModel) -> Void, onLayoutAction: @escaping (PaneLayoutAction) -> Void, projectNames: [ProjectID: String] = [:]) {
        self.projectNames = projectNames
      }
      public var body: some View {
        PaneTileView(session: session, projectName: session.projectID.flatMap { projectNames[$0] }, onSelect: { focusedID = session.id })
      }
    }
    private struct PaneTileView: View {
      let projectName: String?
      var body: some View {
        tileContent
      }
      private var tileContent: some View {
        switch session {
        case .pty(let session):
          TerminalView(coordinator: session.terminalCoordinator)
        case .appServer(let session):
          GridChatColumn(viewModel: session, projectName: projectName, onFocusGained: onSelect)
        }
      }
    }
  SWIFT
end

def good_detail_src
  <<~SWIFT
    struct DashboardDetailView: View {
      var body: some View {
        detailMainContent
      }
      private var detailMainContent: some View {
        switch router.viewMode {
        case .single:
          singleDetail
        case .grid:
          SessionGridView(sessions: filteredGridSessions, paneLayout: viewModel.paneLayoutForDisplay(), focusedID: $router.selectedSession, onRemove: { _ in }, onRename: { _ in }, onChangeWorkspace: { _ in }, onLayoutAction: { _ in }, projectNames: Dictionary(uniqueKeysWithValues: viewModel.projects.map { ($0.id, $0.name) }))
        case .team:
          TeamTimelineView(viewModel: viewModel, router: router, isCreating: isCreating, onSelectAgentKind: onSelectAgentKind)
        }
      }
      private var singleDetail: some View {
        switch session {
        case .pty(let session):
          SessionView(viewModel: session)
        case .appServer(let session):
          ChatSessionView(viewModel: session, projectName: viewModel.projects.first(where: { $0.id == session.projectID })?.name)
        }
      }
    }
  SWIFT
end

def good_timeline_src
  <<~SWIFT
    struct TeamTimelineView: View {
      var body: some View {
        TeamComposer(targetDisplayName: composerTargetDisplayName, isReadyForInput: composerIsReadyForInput, destination: teamComposerDestination, onSend: sendTeamMessage)
      }
      private var teamComposerDestination: ComposerDestinationLabel.Destination {
        let action = AgoraComposerRouting.action(
          phase: viewModel.agoraDiscussionCoordinator?.phase,
          canStartDiscussion: TeamTimelineAgoraPolicy.canStartDiscussion(canResolveProject: canResolveProjectForNewSession),
          text: ""
        )
        return ComposerDestinationLabel.teamDestination(
          action: action,
          rootProjectName: viewModel.projects.first(where: { $0.id == composerTargetNode?.projectID })?.name,
          rootTaskName: composerTargetNode?.displayName
        )
      }
      private var composerTargetNode: SessionNode? {
        let rootID = TeamComposerTarget.resolveRootSessionID(selectedSessionID: selectedSessionID, parentByID: parentByID)
        return nodes.first { $0.id == rootID }
      }
      private var composerTargetDisplayName: String? {
        if TeamTimelineAgoraPolicy.isDiscussionActive(phase: viewModel.agoraDiscussionCoordinator?.phase) {
          return "討論"
        }
        return composerTargetNode?.displayName
      }
      private var composerIsReadyForInput: Bool {
        if TeamTimelineAgoraPolicy.isDiscussionActive(phase: viewModel.agoraDiscussionCoordinator?.phase) {
          return true
        }
        return store.isComposerReadyForInput
      }
      private var canResolveProjectForNewSession: Bool {
        router.selectedProjectID != nil || viewModel.defaultProjectID(forSelectedSession: router.selectedSession) != nil
      }
      private func sendTeamMessage(_ text: String) async throws {
        let action = AgoraComposerRouting.action(
          phase: viewModel.agoraDiscussionCoordinator?.phase,
          canStartDiscussion: TeamTimelineAgoraPolicy.canStartDiscussion(canResolveProject: canResolveProjectForNewSession),
          text: text
        )
        switch action {
        case .startDiscussion(let agenda):
          _ = await viewModel.startAgoraDiscussion(agenda: agenda, selectedSessionID: selectedSessionID)
        case .discussionUtterance(let utterance):
          await viewModel.submitAgoraUserUtterance(utterance)
        case .legacyRootSend(let message):
          guard let target = composerTargetNode?.controllable else { return }
          try await target.sendText(message, submit: true)
        }
      }
    }
    enum TeamTimelineAgoraPolicy {
      static func isDiscussionActive(phase: AgoraDiscussionPhase?) -> Bool {
        switch phase {
        case .discussing, .concluding: return true
        case .idle, .ended, nil: return false
        }
      }
      static func canStartDiscussion(canResolveProject: Bool) -> Bool { canResolveProject }
    }
  SWIFT
end

def good_team_composer_src
  <<~SWIFT
    struct TeamComposer: View {
      let targetDisplayName: String?
      let isReadyForInput: Bool
      let destination: ComposerDestinationLabel.Destination
      let onSend: (String) async throws -> Void
      private var canSend: Bool {
        targetDisplayName != nil && isReadyForInput && !trimmedDraft.isEmpty
      }
      var body: some View {
        HStack {
          VStack {
            let destinationText = ComposerDestinationLabel.text(for: destination, hasDestination: targetDisplayName != nil, isReadyForInput: isReadyForInput, hasContent: !trimmedDraft.isEmpty)
            Text(destinationText)
              .font(DSFont.caption)
              .help(destinationText)
              .accessibilityLabel(destinationText)
              .accessibilityIdentifier("TeamComposer.destination")
            TeamComposerTextInput(text: $draft, isEnabled: targetDisplayName != nil, onSubmit: send)
          }
          Button(action: send) { Image(systemName: "paperplane.fill") }
            .disabled(!canSend)
        }
      }
      private func send() {
        let text = trimmedDraft
        guard canSend, !text.isEmpty else { return }
        Task { try await onSend(text) }
      }
    }
  SWIFT
end

def good_routing_src
  <<~SWIFT
    public enum AgoraComposerRouting {
      public static func action(phase: AgoraDiscussionPhase?, canStartDiscussion: Bool, text: String) -> AgoraComposerAction {
        switch phase {
        case .discussing, .concluding: return .discussionUtterance(text)
        case .idle, .ended, nil: return canStartDiscussion ? .startDiscussion(agenda: text) : .legacyRootSend(text)
        }
      }
    }
  SWIFT
end

def good_target_src
  <<~SWIFT
    public enum TeamComposerTarget {
      public static func resolveRootSessionID(selectedSessionID: SessionID?, parentByID: [SessionID: SessionID?]) -> SessionID? {
        selectedSessionID
      }
    }
  SWIFT
end

def good_files
  {
    label: good_label_src,
    agora: good_agora_src,
    chat_composer: good_chat_composer_src,
    chat_session: good_chat_session_src,
    grid_column: good_grid_column_src,
    grid_view: good_grid_view_src,
    pane: good_pane_src,
    detail: good_detail_src,
    timeline: good_timeline_src,
    team_composer: good_team_composer_src,
    routing: good_routing_src,
    target: good_target_src,
  }
end

def with_file(files, key)
  copy = files.dup
  copy[key] = yield(files[key].dup)
  copy
end

def selftest_assert(cond, msg)
  unless cond
    puts "task43-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task43-wiring --selftest: FAIL #{msg}"
    puts "  expected: #{expected.inspect}"
    puts "  actual:   #{actual.inspect}"
    exit 1
  end
end

def run_selftest
  url = %(let url = "https://phlox.cc/privacy" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://phlox.cc/privacy"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert !strip_comments("let a = 1 /* x */ let b = 2").include?("x"), "正例: /* */ を除去する"
  nested_c = "let a = 1 /* x /* y */ z */ let b = 2"
  nested_stripped = strip_comments(nested_c)
  selftest_assert !nested_stripped.include?("x") && !nested_stripped.include?("z") && nested_stripped.include?("let b = 2"), "正例: 入れ子ブロックコメントを除去する"
  interp = %(let id = "ChatComposer.\\(group.id)")
  selftest_assert strip_comments(interp).include?("ChatComposer."), "正例: 補間文字列を保持する"
  parens = %(let s = "foo(bar)"; Text(s))
  selftest_assert parens.include?("foo(bar)") && extract_balanced("{#{parens}}", 0, "{", "}").to_s.include?("foo(bar)"), "正例: 文字列内括弧をアサートする"
  selftest_assert extract_balanced(" { a ", 0, "{", "}").nil?, "負例: 構文切り出し失敗は nil"
  spaced = %(Text("hello world"))
  selftest_assert normalize_code(spaced).include?("hello world"), "正例: 文字列内空白を正規化で消さない"
  selftest_assert normalize_code(%(Text("hello world"))) != normalize_code(%(Text("helloworld"))), "負例: 文字列内空白の改変を検出する"

  good = good_files
  selftest_errors_eq check_product(good), [], "正例: 契約どおりの配線は空 NG"

  commented = with_file(good, :chat_composer) { |src| src.sub("var body", "// keep https://phlox.cc/privacy \\(x)\n      var body") }
  selftest_errors_eq check_product(commented), [], "正例: コメント・URL・補間だけを加える"

  alias_ok = with_file(good, :chat_composer) { |src| src.gsub("destinationText", "caption") }
  selftest_errors_eq check_product(alias_ok), [], "正例: 別名 caption で表示"

  computed_ok = with_file(good, :chat_composer) { |src|
    src.sub(/^[ \t]*let destinationText = ComposerDestinationLabel\.text.*\n/, "")
       .gsub("destinationText", "destinationCaption")
       .sub("private var canSubmit:", "private var destinationCaption: String {\n        ComposerDestinationLabel.text(for: .conversation(projectName: projectName, taskName: viewModel.displayName), hasDestination: true, isReadyForInput: canSend, hasContent: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachmentStore.attachments.isEmpty)\n      }\n      private var canSubmit:")
  }
  selftest_errors_eq check_product(computed_ok), [], "正例: 計算プロパティ経由の表示"

  single_unwired = with_file(good, :chat_composer) { |src| src.gsub(destination_view("ChatComposer.destination"), "EmptyView()\n") }
  selftest_errors_eq check_single(single_unwired), ["単一経路から ComposerDestinationLabel.text の Text に到達しない"], "負例: 単一だけ未接続"

  grid_card = with_file(good, :grid_column) { |src| src.sub("taskName: viewModel.displayName", "taskName: focusedSession.displayName") }
  selftest_errors_eq check_grid(grid_card).select { |m| m.include?("選択中カード") }, ["グリッドが選択中カード名を送信先に使っている"], "負例: グリッドだけ選択中カード名を表示"

  parent_swap = with_file(good, :timeline) { |src| src.sub("rootTaskName: composerTargetNode?.displayName", "rootTaskName: selectedSession.displayName") }
  selftest_errors_eq check_team(parent_swap).select { |m| m.include?("親名") }, ["親名を子名に差し替えている"], "負例: 親名を子名に差替え"

  ended_fixed = with_file(good, :agora) { |src| src.sub("case .startDiscussion: return .startDiscussion", "case .startDiscussion: return .parentSession(projectName: rootProjectName, taskName: rootTaskName)") }
  selftest_errors_eq check_team(ended_fixed).select { |m| m.include?("終了後") }, ["終了後を親送信に固定している"], "負例: 終了後を親送信に固定"

  concluding_out = with_file(good, :agora) { |src| src.sub("case .discussionUtterance: return .discussionUtterance", "case .discussionUtterance: return .legacyRootSend") }
  selftest_errors_eq check_team(concluding_out).select { |m| m.include?("concluding") }, [".concluding を討論外扱いしている"], "負例: .concluding を討論外扱い"

  enable_start = with_file(good, :team_composer) { |src| src.sub("targetDisplayName != nil && isReadyForInput && !trimmedDraft.isEmpty", "targetDisplayName != nil && isReadyForInput && !trimmedDraft.isEmpty || canStartDiscussion") }
  selftest_errors_eq check_team(enable_start).select { |m| m.include?("討論開始可能") }, ["討論開始可能を理由にボタンを有効化している"], "負例: 討論開始可能を理由にボタンを有効化"

  image_only = with_file(good, :chat_composer) { |src| src.sub("|| !viewModel.attachmentStore.attachments.isEmpty", "") }
  selftest_errors_eq check_single(image_only).select { |m| m.include?("画像のみ") }, ["画像のみを送信不可表示している（hasContent が添付を見ていない）"], "負例: 画像のみを送信不可表示"

  help_only = with_file(good, :chat_composer) { |src| src.sub("Text(destinationText)", "EmptyView()").sub(".font(DSFont.caption)", ".help(destinationText)\n              .font(DSFont.caption)") }
  selftest_errors_eq check_single(help_only).select { |m| m.include?("help のみ") || m.include?("単一経路") }, ["ChatComposer の送信先表示を help のみに移している"], "負例: 表示を help のみに移す"

  no_ax = with_file(good, :chat_composer) { |src| src.sub('.accessibilityIdentifier("ChatComposer.destination")', "") }
  selftest_errors_eq check_single(no_ax).select { |m| m.include?("AX identifier") || m.include?("単一経路") }, ["ChatComposer.destination の AX identifier が無い"], "負例: AX 欠落"

  hidden = with_file(good, :team_composer) { |src| src.sub("Text(destinationText)", "if let targetDisplayName { Text(destinationText) }") }
  selftest_errors_eq check_team(hidden).select { |m| m.include?("非表示") }, ["宛先なしでラベルを非表示にしている"], "負例: 宛先なしでラベルを非表示"

  submit_changed = with_file(good, :chat_session) { |src| src.sub("submit: true", "submit: false") }
  selftest_errors_eq check_invariants(submit_changed, good).select { |m| m.include?("sendDraft") }, ["sendDraft が TASK43_BASELINE から変化している"], "負例: submit 引数の変更"

  send_dest = with_file(good, :timeline) { |src| src.sub("try await target.sendText(message, submit: true)", "try await target.sendText(message, submit: false)") }
  selftest_errors_eq check_invariants(send_dest, good).select { |m| m.include?("sendTeamMessage") }, ["sendTeamMessage が TASK43_BASELINE から変化している"], "負例: 送信先・submit 引数の変更"

  disabled_changed = with_file(good, :team_composer) { |src| src.sub(".disabled(!canSend)", ".disabled(false)") }
  selftest_errors_eq check_team(disabled_changed).select { |m| m.include?("disabled") }, ["TeamComposer の disabled 条件が変わっている"], "負例: disabled 条件の変更"

  focus_changed = with_file(good, :team_composer) { |src| src.sub("isEnabled: targetDisplayName != nil", "isEnabled: true") }
  selftest_errors_eq check_team(focus_changed).select { |m| m.include?("編集可否") }, ["TeamComposer の編集可否条件が変わっている"], "負例: フォーカス条件の変更"

  decoy = with_file(good, :chat_composer) { |src| src.gsub(destination_view("ChatComposer.destination"), "EmptyView()\n") + %(\n    // ComposerDestinationLabel.text(for: .conversation(projectName: projectName, taskName: viewModel.displayName), hasDestination: true, isReadyForInput: canSend, hasContent: true)\n    var decoy: some View { Text("ComposerDestinationLabel.text") }\n    if false { Text(ComposerDestinationLabel.text(for: .startDiscussion, hasDestination: true, isReadyForInput: true, hasContent: true)) }\n) }
  decoy_ng = check_single(decoy)
  selftest_assert decoy_ng.any? { |m| m.include?("単一経路") || m.include?("help のみ") }, "負例: コメントや未使用コードによる偽装 (#{decoy_ng.inspect})"

  unparsed = with_file(good, :chat_composer) { |src| src.sub(/var body: some View \{.*\z/m, "var body: some View {") }
  unparsed_ng = check_single(unparsed)
  selftest_assert unparsed_ng.any? { |m| m.include?("切り出せない") || m.include?("括弧") }, "負例: 構文切り出し失敗 (#{unparsed_ng.inspect})"

  detail_nil = with_file(good, :detail) { |src| src.sub("projectName: viewModel.projects.first(where: { $0.id == session.projectID })?.name", "projectName: nil") }
  selftest_errors_eq check_single(detail_nil).select { |m| m.include?("既定 nil") || m.include?("session.projectID") }, ["DashboardDetailView の ChatSessionView が projectName を明示していない（既定 nil）"], "負例: 単一の projectName を nil"

  init_nil = with_file(good, :chat_composer) { |src| src.sub("self.projectName = projectName", "self.projectName = nil") }
  selftest_errors_eq check_single(init_nil).select { |m| m.include?("nil に差し替え") }, ["ChatComposer が projectName を nil に差し替えている"], "負例: initializer で projectName を nil"

  grid_empty = with_file(good, :detail) { |src| src.sub("projectNames: Dictionary(uniqueKeysWithValues: viewModel.projects.map { ($0.id, $0.name) })", "projectNames: [:]") }
  selftest_errors_eq check_grid(grid_empty).select { |m| m.include?("空辞書") }, ["DashboardDetailView の SessionGridView が projectNames を明示していない（既定の空辞書）"], "負例: グリッドの projectNames 空辞書"

  bar_drop = with_file(good, :grid_column) { |src| src.sub("projectName: projectName, onSend: sendDraft", "projectName: nil, onSend: sendDraft") }
  selftest_errors_eq check_grid(bar_drop).select { |m| m.include?("GridComposerBar") }, ["GridChatColumn が projectName を GridComposerBar へ渡していない"], "負例: GridChatColumn が projectName を渡さない"

  selected_proj = with_file(good, :detail) { |src| src.sub("session.projectID", "router.selectedProjectID") }
  selftest_errors_eq check_single(selected_proj).select { |m| m.include?("selectedProjectID") }, ["単一のプロジェクト名に router.selectedProjectID を使っている"], "負例: 選択プロジェクトへ差替え"

  if_false_label = with_file(good, :chat_composer) { |src| src.gsub(destination_view("ChatComposer.destination"), "if false {\n#{destination_view("ChatComposer.destination")}\n            }\n") }
  selftest_errors_eq check_single(if_false_label).select { |m| m.include?("単一経路") || m.include?("help のみ") }, ["単一経路から ComposerDestinationLabel.text の Text に到達しない"], "負例: if false 経由の参照"

  string_only = with_file(good, :chat_composer) { |src| src.gsub(destination_view("ChatComposer.destination"), "EmptyView()\n") + %(    let decoy = "ComposerDestinationLabel.text"\n) }
  selftest_errors_eq check_single(string_only).select { |m| m.include?("単一経路") || m.include?("help のみ") }, ["単一経路から ComposerDestinationLabel.text の Text に到達しない"], "負例: 文字列だけの参照"

  grid_dead_helper = with_file(good, :grid_column) { |src| src.sub("composerContent()", "EmptyView()") }
  selftest_errors_eq check_grid(grid_dead_helper).select { |m| m.include?("グリッド経路") || m.include?("help のみ") }, ["グリッド経路から ComposerDestinationLabel.text の Text に到達しない"], "負例: body から呼ばれない helper"

  display_deleted = with_file(good, :timeline) { |src| src.sub("let action = AgoraComposerRouting.action(", "let unusedSendAction = AgoraComposerRouting.action(") }
  selftest_errors_eq check_team(display_deleted).select { |m| m.include?("未接続") || m.include?("開始可否") || m.include?("phase") }, ["チーム表示用 action が sendTeamMessage と同じ入力元でない（未接続）"], "負例: 表示用 action の削除"

  other_action = with_file(good, :timeline) { |src| src.sub("action: action,", "action: .legacyRootSend(\"\"),") }
  selftest_errors_eq check_team(other_action).select { |m| m.include?("未接続") }, ["チーム表示用 action が sendTeamMessage と同じ入力元でない（未接続）"], "負例: 別 action の受け渡し"

  invert_can = with_file(good, :timeline) { |src| src.sub("canStartDiscussion: TeamTimelineAgoraPolicy.canStartDiscussion(canResolveProject: canResolveProjectForNewSession)", "canStartDiscussion: !TeamTimelineAgoraPolicy.canStartDiscussion(canResolveProject: canResolveProjectForNewSession)") }
  selftest_errors_eq check_team(invert_can).select { |m| m.include?("開始可否") }, ["チーム表示用 action の開始可否が sendTeamMessage と異なる"], "負例: 開始可否の反転"

  and_content = with_file(good, :chat_composer) { |src| src.sub("|| !viewModel.attachmentStore.attachments.isEmpty", "&& !viewModel.attachmentStore.attachments.isEmpty") }
  selftest_errors_eq check_single(and_content).select { |m| m.include?("AND") }, ["hasContent が trim と添付を AND している"], "負例: hasContent の || を && に"

  no_trim = with_file(good, :chat_composer) { |src| src.sub("!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty", "!text.isEmpty") }
  selftest_errors_eq check_single(no_trim).select { |m| m.include?("空白") }, ["hasContent が空白・改行のみを本文ありと扱っている"], "負例: hasContent から trim 削除"

  ready_true = with_file(good, :chat_composer) { |src| src.sub("isReadyForInput: canSend", "isReadyForInput: true") }
  selftest_errors_eq check_single(ready_true).select { |m| m.include?("isReadyForInput") }, ["単一の isReadyForInput が既存の送信準備と結びついていない"], "負例: starting/error の readiness を直書き"

  dest_true = with_file(good, :team_composer) { |src| src.sub("hasDestination: targetDisplayName != nil", "hasDestination: true") }
  selftest_errors_eq check_team(dest_true).select { |m| m.include?("hasDestination") }, ["チームの hasDestination が targetDisplayName != nil と結びついていない"], "負例: 宛先なしでも hasDestination true"

  footer_true = with_file(good, :chat_composer) { |src| src.sub("canSubmit: canSubmit", "canSubmit: true") }
  selftest_errors_eq check_invariants(footer_true, good).select { |m| m.include?("canSubmit") }, ["ChatComposerFooter の canSubmit: が TASK43_BASELINE から変化している"], "負例: footer の canSubmit を true に"

  focus_cb = with_file(good, :grid_column) { |src| src.sub("onFocusGained: onFocusGained)", "onFocusGained: {})") }
  selftest_errors_eq check_invariants(focus_cb, good).select { |m| m.include?("onFocusGained") }, ["GridComposerBar の onFocusGained: が TASK43_BASELINE から変化している"], "負例: フォーカス callback の変更"

  submit_cb = with_file(good, :chat_composer) { |src| src.sub("onSubmit: onSend", "onSubmit: {}") }
  selftest_errors_eq check_invariants(submit_cb, good).select { |m| m.include?("onSubmit") }, ["IMESafeTextView の onSubmit: が TASK43_BASELINE から変化している"], "負例: 送信本文 callback の変更"

  width_only = with_file(good, :grid_column) { |src| src.sub(".onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { height in composerHeight = height }\n", "") }
  selftest_errors_eq check_grid(width_only).select { |m| m.include?("高さ計測") }, ["GridComposer の高さ計測が無い（幅計測だけでは足りない）"], "負例: 幅計測だけ残す"

  ax_moved = with_file(good, :chat_composer) { |src| src.sub('.accessibilityIdentifier("ChatComposer.destination")', "").sub("IMESafeTextView(text: $text, onSubmit: onSend)", "IMESafeTextView(text: $text, onSubmit: onSend).accessibilityIdentifier(\"ChatComposer.destination\")") }
  selftest_errors_eq check_single(ax_moved).select { |m| m.include?("AX identifier") }, ["ChatComposer.destination の AX identifier が無い"], "負例: AX を別 View へ移動"

  hidden_ne = with_file(good, :team_composer) { |src| src.sub("Text(destinationText)", "if targetDisplayName != nil { Text(destinationText) }") }
  selftest_errors_eq check_team(hidden_ne).select { |m| m.include?("非表示") }, ["宛先なしでラベルを非表示にしている"], "負例: if != nil でラベル非表示"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_errors_eq unset_errs, ["TASK43_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: 基準の未設定"
  selftest_assert unset.nil?, "負例: 未設定は nil"
  _, invalid_errs = baseline_env_errors("not-a-sha")
  selftest_errors_eq invalid_errs, ["TASK43_BASELINE がコミット SHA ではない（ブランチ名は使えない）: not-a-sha"], "負例: SHA 不正"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK43_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD 指定"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK43_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD~1 指定"
  _, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK43_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: @ 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK43_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_errors_eq parse_contract_baseline_text("---\nfoo: 1\n"), :missing, "負例: 契約 baseline_commit 欠落"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n"), :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"not-a-sha\"\n"), :invalid, "負例: 契約 baseline_commit 不正"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"abc1234\"\n"), "abc1234", "正例: 契約 baseline_commit がクォート付き SHA"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: abc1234\n"), "abc1234", "正例: 契約 baseline_commit がクォート無し SHA"
  ph_errs = contract_baseline_errors("---\nbaseline_commit: \"PM が凍結時に設定\"\n", "abc1234")
  selftest_errors_eq ph_errs, ["契約 baseline_commit がプレースホルダ（凍結時に実 SHA へ置換する）"], "負例: プレースホルダは NG"

  head_full = git_full_sha("HEAD")
  other_full = git_full_sha("HEAD~1")
  selftest_assert !head_full.nil? && !other_full.nil? && head_full != other_full, "selftest 用に有効で異なる 2 コミットが必要"
  real_mismatch = contract_baseline_errors("---\nbaseline_commit: \"#{head_full}\"\n", other_full)
  selftest_errors_eq real_mismatch, ["TASK43_BASELINE が契約 baseline_commit と一致しない"], "負例: 契約不一致"

  empty_views = VIEW_PATHS_FOR_BASELINE.to_h { |p| [p, "struct X { var body: some View { Text(\"ok\") } }\n"] }
  pre_ok = check_frozen_baseline(
    head_full,
    label_blob: nil,
    agora_blob: nil,
    view_blobs: empty_views,
    test1_blob: "test-session",
    test1_now: "test-session",
    test2_blob: "test-dashboard",
    test2_now: "test-dashboard",
    rb_blob: "rb",
    rb_now: "rb"
  )
  selftest_errors_eq pre_ok, [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  post_ng = check_frozen_baseline(
    head_full,
    label_blob: good_label_src,
    agora_blob: nil,
    view_blobs: empty_views,
    test1_blob: "test-session",
    test1_now: "test-session",
    test2_blob: "test-dashboard",
    test2_now: "test-dashboard",
    rb_blob: "rb",
    rb_now: "rb"
  )
  selftest_errors_eq post_ng, ["基準時点に ComposerDestinationLabel.swift がある（実装前の凍結ではない）"], "負例: 実装後の自己比較"

  selftest_errors_eq frozen_artifact_errors("rb 自身", "now", "frozen"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 凍結検査の改変"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "same", "same"), [], "正例: 凍結 rb と作業ツリーが同一"
  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"

  selftest_errors_eq check_product({}), [
    "#{PATHS[:label]} が存在しない",
    "#{PATHS[:agora]} が存在しない",
    "#{PATHS[:chat_composer]} が存在しない",
    "#{PATHS[:chat_session]} が存在しない",
    "#{PATHS[:detail]} が存在しない",
    "#{PATHS[:grid_column]} が存在しない",
    "#{PATHS[:grid_view]} が存在しない",
    "#{PATHS[:pane]} が存在しない",
    "#{PATHS[:timeline]} が存在しない",
    "#{PATHS[:team_composer]} が存在しない",
  ], "負例: 対象欠落"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task43-wiring --selftest: OK"
  exit 0
end

ng = []
raw = ENV["TASK43_BASELINE"]
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
    ng << "TASK43_BASELINE が無効なコミット: #{baseline}"
  else
    ng.concat(check_frozen_baseline(full))
    previous = baseline_files(full)
    ng.concat(check_invariants(files, previous))
  end
end

ng = ng.uniq
if ng.empty?
  puts "task43-wiring: OK"
else
  ng.each { |m| puts "task43-wiring: NG #{m}" }
  exit 1
end
