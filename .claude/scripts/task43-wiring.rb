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
  TeamComposerTextInput DSFont DSColor DSSpacing DSRadius
].freeze

def collect_reachable(src, start_blob)
  result = start_blob.to_s.dup
  seen = {}
  queue = [start_blob.to_s]
  while (blob = queue.shift)
    blob.scan(/\b([A-Za-z_][A-Za-z0-9_]*)\b/).flatten.uniq.each do |name|
      next if SWIFTUI_SKIP.include?(name)
      next if seen[name]
      seen[name] = true
      helper = extract_var_body(src, name) || extract_func_body(src, name) || extract_struct_body(src, name)
      next if helper.nil?
      result << "\n" << helper
      queue << helper
    end
  end
  result
end

def reachable_from(src, name = "body")
  return :unparseable if src.nil?
  stripped = strip_comments(src)
  start = extract_var_body(stripped, name) || extract_func_body(stripped, name)
  return :unparseable if start.nil?
  erase_if_false(collect_reachable(stripped, start))
end

def code_has_ident?(src, name)
  mask_strings_and_comments(src.to_s).match?(/\b#{Regexp.escape(name)}\b/)
end

def visible_model_text?(reachable, _ax_id)
  return false if reachable == :unparseable || reachable.nil?
  masked = mask_strings_and_comments(reachable)
  return false unless masked.include?("ComposerDestinationLabel.text")
  reachable.match?(/\bText\s*\(\s*destinationText\s*\)/) ||
    reachable.match?(/\bText\s*\(\s*ComposerDestinationLabel\.text/)
end

def help_only?(reachable, ax_id)
  return false if reachable == :unparseable || reachable.nil?
  masked = mask_strings_and_comments(reachable)
  return false unless masked.include?("ComposerDestinationLabel.text")
  has_text_call = reachable.match?(/\bText\s*\(\s*destinationText\s*\)/) ||
                  reachable.match?(/\bText\s*\(\s*ComposerDestinationLabel\.text/)
  has_help = masked.include?(".help(") || reachable.include?(".help(destinationText)")
  has_help && !has_text_call && reachable.include?(ax_id)
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

  composer = reachable_from(files[:chat_composer], "body")
  session = reachable_from(files[:chat_session], "body")
  detail = reachable_from(files[:detail], "singleDetail")
  if composer == :unparseable
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

  unless visible_model_text?(composer, "ChatComposer.destination")
    if help_only?(composer, "ChatComposer.destination")
      ng << "ChatComposer の送信先表示を help のみに移している"
    else
      ng << "単一経路から ComposerDestinationLabel.text の Text に到達しない"
    end
  end
  unless composer.include?(%(.accessibilityIdentifier("ChatComposer.destination")))
    ng << "ChatComposer.destination の AX identifier が無い" unless ng.any? { |m| m.include?("単一経路") || m.include?("help のみ") }
  end
  unless composer.include?(".help(destinationText)") || compact(composer).include?(".help(destinationText)")
    ng << "ChatComposer の全文 help が無い"
  end
  unless composer.include?(".accessibilityLabel(destinationText)") || compact(composer).include?(".accessibilityLabel(destinationText)")
    ng << "ChatComposer のアクセシビリティラベルが無い"
  end
  unless compact(composer).include?("DSFont.caption")
    ng << "ChatComposer が DSFont.caption を使っていない"
  end
  unless compact(composer).include?("DSColor.chatTextSecondary")
    ng << "ChatComposer が DSColor.chatTextSecondary を使っていない"
  end
  text_idx = composer.index("ComposerDestinationLabel.text")
  editor_idx = composer.index("IMESafeTextView")
  if text_idx && editor_idx && text_idx > editor_idx
    ng << "ChatComposer の送信先表示が編集領域の直前に無い"
  elsif text_idx.nil? || editor_idx.nil?
    ng << "ChatComposer の送信先表示が編集領域の直前に無い" unless ng.any? { |m| m.include?("単一経路") || m.include?("help のみ") }
  end
  unless compact(session).include?("ChatComposer(") && compact(session).include?("onGeometryChange")
    ng << "ChatComposer の送信先表示が composer の計測範囲に無い"
  end
  unless call_has_label?(session, "ChatComposer", "projectName")
    ng << "ChatSessionView が projectName を ChatComposer へ渡していない"
  end
  unless init_has_default_project_name?(files[:chat_session]) && init_has_default_project_name?(files[:chat_composer])
    ng << "projectName: String? = nil の既定が無い"
  end
  unless call_has_label?(detail, "ChatSessionView", "projectName")
    ng << "DashboardDetailView の ChatSessionView が projectName を明示していない（既定 nil）"
  end
  chat_args = extract_call_args(detail, "ChatSessionView")
  if chat_args
    c = compact(chat_args)
    ng << "単一のプロジェクト名が session.projectID から取得されていない" unless c.include?("session.projectID") || c.include?("session.projectID")
    ng << "単一のプロジェクト名に router.selectedProjectID を使っている" if c.include?("selectedProjectID")
  end
  text_args = extract_call_args(composer, "ComposerDestinationLabel.text")
  if text_args
    tc = compact(text_args)
    unless tc.include?("attachments.isEmpty")
      ng << "画像のみを送信不可表示している（hasContent が添付を見ていない）"
    end
    if tc.include?("selectedSubAgentId") || tc.include?("focusedID")
      ng << "単一の送信先に選択カード名を使っている"
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

  bar = reachable_from(files[:grid_column], "composerContent")
  bar = reachable_from(files[:grid_column], "body") if bar == :unparseable
  grid = reachable_from(files[:grid_view], "body")
  pane = reachable_from(files[:pane], "body")
  tile = extract_var_body(strip_comments(files[:pane]), "tileContent")
  detail = reachable_from(files[:detail], "detailMainContent")
  if bar == :unparseable
    ng << "GridComposerBar の本文を括弧対応で切り出せない"
    return ng
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

  unless visible_model_text?(bar, "GridComposer.destination")
    if help_only?(bar, "GridComposer.destination")
      ng << "GridComposer の送信先表示を help のみに移している"
    else
      ng << "グリッド経路から ComposerDestinationLabel.text の Text に到達しない"
    end
  end
  unless bar.include?(%(.accessibilityIdentifier("GridComposer.destination")))
    ng << "GridComposer.destination の AX identifier が無い" unless ng.any? { |m| m.include?("グリッド経路") || m.include?("help のみ") }
  end
  unless bar.include?(".help(destinationText)") || compact(bar).include?(".help(destinationText)")
    ng << "GridComposer の全文 help が無い"
  end
  unless bar.include?(".accessibilityLabel(destinationText)") || compact(bar).include?(".accessibilityLabel(destinationText)")
    ng << "GridComposer のアクセシビリティラベルが無い"
  end
  unless compact(bar).include?("DSFont.caption")
    ng << "GridComposer が DSFont.caption を使っていない"
  end
  unless compact(bar).include?("DSColor.chatTextSecondary")
    ng << "GridComposer が DSColor.chatTextSecondary を使っていない"
  end
  text_idx = bar.index("ComposerDestinationLabel.text")
  editor_idx = bar.index("IMESafeTextView")
  if text_idx && editor_idx && text_idx > editor_idx
    ng << "GridComposer の送信先表示が編集領域の直前に無い"
  elsif text_idx.nil? || editor_idx.nil?
    ng << "GridComposer の送信先表示が編集領域の直前に無い" unless ng.any? { |m| m.include?("グリッド経路") || m.include?("help のみ") }
  end
  unless compact(files[:grid_column]).include?("onGeometryChange")
    ng << "GridComposer の送信先表示が composer の計測範囲に無い"
  end
  unless call_has_label?(grid, "PaneLayoutView", "projectNames")
    ng << "SessionGridView が projectNames を PaneLayoutView へ渡していない"
  end
  tile_c = compact(tile)
  unless tile_c.include?("GridChatColumn(") && (tile_c.include?("projectName:") || compact(pane).include?("projectName:"))
    ng << "PaneLayoutView が projectName を GridChatColumn へ渡していない"
  end
  unless pane.include?("session.projectID") || tile.include?("session.projectID")
    ng << "グリッドのプロジェクト名がタイルの session.projectID から取得されていない"
  end
  text_args = extract_call_args(bar, "ComposerDestinationLabel.text")
  if text_args
    tc = compact(text_args)
    ng << "グリッドが選択中カード名を送信先に使っている" if tc.include?("focusedID") || tc.include?("selectedSubAgent")
    unless tc.include?("attachments.isEmpty")
      ng << "画像のみを送信不可表示している（hasContent が添付を見ていない）"
    end
    unless tc.include?("viewModel.displayName") || tc.include?("taskName:viewModel.displayName")
      ng << "グリッドが選択中カード名を送信先に使っている" unless ng.any? { |m| m.include?("選択中カード") }
    end
  end
  unless init_has_default_project_names?(files[:grid_view]) && init_has_default_project_names?(files[:pane])
    ng << "projectNames: [ProjectID: String] = [:] の既定が無い"
  end
  unless call_has_label?(detail, "SessionGridView", "projectNames")
    ng << "DashboardDetailView の SessionGridView が projectNames を明示していない（既定の空辞書）"
  end
  grid_args = extract_call_args(detail, "SessionGridView")
  if grid_args
    c = compact(grid_args)
    ng << "グリッドのプロジェクト名に router.selectedProjectID を使っている" if c.include?("selectedProjectID")
    ng << "グリッド全体の選択名を代入している" if c.include?("selectedSession") && c.include?("projectNames") && !c.include?("projects")
  end
  ng
end

def without_func(src, name)
  body = extract_func_body(src, name)
  return src if body.nil?
  src.sub(body, "")
end

def check_team(files)
  ng = []
  %i[timeline team_composer agora].each do |key|
    ng.concat(missing_file(files, key, PATHS[key]))
  end
  return ng unless files[:timeline] && files[:team_composer] && files[:agora]

  composer = reachable_from(files[:team_composer], "body")
  timeline = reachable_from(files[:timeline], "body")
  if composer == :unparseable
    ng << "TeamComposer の body を括弧対応で切り出せない"
    return ng
  end
  if timeline == :unparseable
    ng << "TeamTimelineView の body を括弧対応で切り出せない"
    return ng
  end

  unless visible_model_text?(composer, "TeamComposer.destination")
    if help_only?(composer, "TeamComposer.destination")
      ng << "TeamComposer の送信先表示を help のみに移している"
    else
      ng << "チーム経路から ComposerDestinationLabel.text の Text に到達しない"
    end
  end
  unless composer.include?(%(.accessibilityIdentifier("TeamComposer.destination")))
    ng << "TeamComposer.destination の AX identifier が無い" unless ng.any? { |m| m.include?("チーム経路") || m.include?("help のみ") }
  end
  unless composer.include?(".help(destinationText)") || compact(composer).include?(".help(destinationText)")
    ng << "TeamComposer の全文 help が無い"
  end
  unless composer.include?(".accessibilityLabel(destinationText)") || compact(composer).include?(".accessibilityLabel(destinationText)")
    ng << "TeamComposer のアクセシビリティラベルが無い"
  end
  text_idx = composer.index("ComposerDestinationLabel.text")
  editor_idx = composer.index("TeamComposerTextInput")
  if text_idx && editor_idx && text_idx > editor_idx
    ng << "TeamComposer の送信先表示が編集領域の直前に無い"
  elsif text_idx.nil? || editor_idx.nil?
    ng << "TeamComposer の送信先表示が編集領域の直前に無い" unless ng.any? { |m| m.include?("チーム経路") || m.include?("help のみ") }
  end
  if composer.match?(/if\s+let\s+targetDisplayName/)
    after = composer[/if\s+let\s+targetDisplayName.*/m].to_s
    if after.include?("ComposerDestinationLabel.text") || after.include?("destinationText")
      ng << "宛先なしでラベルを非表示にしている"
    end
  end
  unless compact(composer).include?(".disabled(!canSend)")
    ng << "TeamComposer の disabled 条件が変わっている"
  end
  unless compact(composer).include?("isEnabled:targetDisplayName!=nil")
    ng << "TeamComposer の編集可否条件が変わっている"
  end

  send_body = extract_func_body(strip_comments(files[:timeline]), "sendTeamMessage")
  display_src = without_func(strip_comments(files[:timeline]), "sendTeamMessage")
  display_reach = erase_if_false(collect_reachable(strip_comments(files[:timeline]), extract_var_body(strip_comments(files[:timeline]), "body").to_s))
  display_reach = without_func(display_reach, "sendTeamMessage")
  send_args = all_call_args(send_body.to_s, "AgoraComposerRouting.action")
  display_args = all_call_args(display_reach, "AgoraComposerRouting.action")
  if display_args.empty?
    ng << "チーム表示用 action が sendTeamMessage と同じ入力元でない（未接続）"
  end
  if send_args.empty?
    ng << "sendTeamMessage の AgoraComposerRouting.action を切り出せない"
  end
  if send_args[0] && display_args[0]
    sc = compact(send_args[0])
    dc = compact(display_args[0])
    unless dc.include?("viewModel.agoraDiscussionCoordinator?.phase") || dc.include?("viewModel.agoraDiscussionCoordinator?.phase")
      ng << "チーム表示用 action の phase が sendTeamMessage と異なる"
    end
    unless sc.include?("viewModel.agoraDiscussionCoordinator?.phase")
      ng << "sendTeamMessage の phase 入力が契約と異なる"
    end
    unless dc.include?("TeamTimelineAgoraPolicy.canStartDiscussion") && dc.include?("canResolveProjectForNewSession")
      ng << "チーム表示用 action の開始可否が sendTeamMessage と異なる"
    end
    unless sc.include?("TeamTimelineAgoraPolicy.canStartDiscussion") && sc.include?("canResolveProjectForNewSession")
      ng << "sendTeamMessage の開始可否入力が契約と異なる"
    end
  end
  unless code_has_ident?(display_reach, "teamDestination")
    ng << "TeamTimelineView が表示用 teamDestination を呼んでいない"
  end
  dest_args = extract_call_args(display_reach, "ComposerDestinationLabel.teamDestination")
  dest_args ||= extract_call_args(files[:timeline], "ComposerDestinationLabel.teamDestination")
  if dest_args
    d = compact(dest_args)
    unless d.include?("rootTaskName:composerTargetNode")
      ng << "親名を子名に差し替えている"
    end
  end

  agora = files[:agora]
  agora_masked = mask_strings_and_comments(agora)
  if agora_masked.match?(/\.ended\b/) || agora_masked.match?(/case\s+\.ended/)
    ng << "終了後を親送信に固定している"
  end
  if agora_masked.match?(/\.concluding\b/) && !agora_masked.include?("discussionUtterance")
    ng << ".concluding を討論外扱いしている"
  end
  if agora_masked.match?(/case\s+\.concluding/)
    ng << ".concluding を討論外扱いしている"
  end
  unless code_has_ident?(agora, "startDiscussion") && code_has_ident?(agora, "discussionUtterance") && code_has_ident?(agora, "legacyRootSend")
    ng << "teamDestination が既存 action 3 件に接続していない"
  end

  can_send = extract_var_body(strip_comments(files[:team_composer]), "canSend")
  if can_send && compact(can_send).include?("canStartDiscussion")
    ng << "討論開始可能を理由にボタンを有効化している"
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

def check_invariants(files, previous)
  ng = []
  INVARIANT_FUNCS.each { |key, name| ng.concat(check_func_unchanged(files, previous, key, name)) }
  INVARIANT_VARS.each { |key, name| ng.concat(check_var_unchanged(files, previous, key, name)) }
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
            IMESafeTextView(text: $text, onSubmit: onSend)
          }
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
  selftest_assert extract_balanced(" { a ", 0, "{", "}").nil?, "負例: 構文切り出し失敗は nil"
  spaced = %(Text("hello world"))
  selftest_assert normalize_code(spaced).include?("hello world"), "正例: 文字列内空白を正規化で消さない"
  selftest_assert normalize_code(%(Text("hello world"))) != normalize_code(%(Text("helloworld"))), "負例: 文字列内空白の改変を検出する"

  good = good_files
  selftest_errors_eq check_product(good), [], "正例: 契約どおりの配線は空 NG"

  commented = with_file(good, :chat_composer) { |src| src.sub("var body", "// keep https://phlox.cc/privacy \\(x)\n      var body") }
  selftest_errors_eq check_product(commented), [], "正例: コメント・URL・補間だけを加える"

  single_unwired = with_file(good, :chat_composer) { |src| src.gsub(destination_view("ChatComposer.destination"), "EmptyView()\n") }
  selftest_errors_eq check_single(single_unwired), ["単一経路から ComposerDestinationLabel.text の Text に到達しない", "ChatComposer の全文 help が無い", "ChatComposer のアクセシビリティラベルが無い", "ChatComposer が DSFont.caption を使っていない", "ChatComposer が DSColor.chatTextSecondary を使っていない"], "負例: 単一だけ未接続"

  grid_card = with_file(good, :grid_column) { |src| src.sub("taskName: viewModel.displayName", "taskName: focusedSession.displayName") }
  selftest_errors_eq check_grid(grid_card).select { |m| m.include?("選択中カード") }, ["グリッドが選択中カード名を送信先に使っている"], "負例: グリッドだけ選択中カード名を表示"

  parent_swap = with_file(good, :timeline) { |src| src.sub("rootTaskName: composerTargetNode?.displayName", "rootTaskName: selectedSession.displayName") }
  selftest_errors_eq check_team(parent_swap).select { |m| m.include?("親名") }, ["親名を子名に差し替えている"], "負例: 親名を子名に差替え"

  ended_fixed = with_file(good, :agora) { |src| src.sub("switch action {", "switch action {\n        case .ended: return .parentSession(projectName: rootProjectName, taskName: rootTaskName)") }
  selftest_errors_eq check_team(ended_fixed).select { |m| m.include?("終了後") }, ["終了後を親送信に固定している"], "負例: 終了後を親送信に固定"

  concluding_out = with_file(good, :agora) { |src| src.sub("case .discussionUtterance: return .discussionUtterance", "case .concluding: return .startDiscussion") }
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
