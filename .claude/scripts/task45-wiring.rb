#!/usr/bin/env ruby
# task-45 配線検査: SessionTitlePresentation がサイドバー・グリッド・トップバー・
# チームの既存名前領域へ届き、TASK45_BASELINE の凍結テストと変更禁止対象が
# 契約どおりであること。
# コメントと文字列は同時識別する（task43-wiring.rb と同じ字句走査、task46 強化版）。
# 比較対象は git show <TASK45_BASELINE>:<path> と作業ファイル。HEAD blob は使わない。

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

def extract_struct_body(src, name)
  indexed = code_only_indexed(src.to_s)
  m = indexed.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?struct\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = indexed.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
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

def git_tree_has_path?(rev, path)
  system("git", "cat-file", "-e", "#{rev}:#{path}", out: File::NULL, err: File::NULL)
end

def git_show_result(rev, path)
  text = IO.popen(["git", "show", "#{rev}:#{path}"], err: [:child, :out], &:read)
  if $?.success?
    { fetch: :ok, text: text, stderr: nil }
  elsif git_tree_has_path?(rev, path)
    { fetch: :git_error, text: nil, stderr: text.to_s.strip }
  else
    { fetch: :missing, text: nil, stderr: text.to_s.strip }
  end
end

def git_show(rev, path)
  result = git_show_result(rev, path)
  result[:fetch] == :ok ? result[:text] : nil
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
  compact(src).gsub(/_=(?:SessionTitlePresentation|SessionTitleDeriver|TranscriptTypography|ChatTypography)(?:\.[A-Za-z0-9_]+)*/, "")
end

def strip_dead_model_lets(c)
  s = c.dup
  s.gsub(/let([A-Za-z_][A-Za-z0-9_]*)=SessionTitlePresentation\([^)]*\)/) do
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
  DSFont DSColor DSSpacing DSRadius Font
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

def struct_reachable(src, name, start = "body")
  return :missing if src.nil?
  body = extract_struct_body(src, name)
  indexed = code_only_indexed(src.to_s)
  if indexed.match?(/\bstruct\s+#{Regexp.escape(name)}\b/) && body.nil?
    return :unparseable
  end
  return :missing if body.nil?
  start_blob = extract_var_body(body, start) || extract_func_body(body, start) || body
  collect_reachable(body, start_blob)
end

def struct_live(src, name, start = "body")
  reach = struct_reachable(src, name, start)
  return reach if reach.is_a?(Symbol)
  live_code(reach)
end

CONTRACT_PATH = "tasks/task-45.md"
WIRING_RB_PATH = ".claude/scripts/task45-wiring.rb"
PRESENTATION_PATH = "macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitlePresentation.swift"
TITLE_STATE_PATH = "macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleState.swift"
DERIVER_PATH = "macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleDeriver.swift"
SIDEBAR_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift"
PANE_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift"
TOPBAR_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardTopBarControls.swift"
TIMELINE_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamTimelineView.swift"
POLICY_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/AgentChatRowPolicy.swift"
SESSION_VIEW_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/SessionView.swift"
CHAT_SESSION_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift"
GRID_COLUMN_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift"
INSET_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TopBarInsetPolicy.swift"
TEST_PATH = "macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitlePresentationTests.swift"
PRODUCTION_MARKER = "# === task45 production checks ==="

ALLOWED_PRODUCT_PATHS = [
  PRESENTATION_PATH,
  PANE_PATH,
  SIDEBAR_PATH,
  TOPBAR_PATH,
  TIMELINE_PATH,
  POLICY_PATH,
].freeze

TASK44_PRODUCT_PATHS = [
  TITLE_STATE_PATH,
  "macos/Packages/AgentDomain/Sources/AgentDomain/PersistedSessionDescriptor.swift",
  "macos/Packages/SessionFeature/Sources/SessionFeature/ControllableSession.swift",
  "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift",
  "macos/Packages/SessionFeature/Sources/SessionFeature/SessionViewModel.swift",
  "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift",
  "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift",
  "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionRestoreCoordinator.swift",
  "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionPersistenceCoordinator.swift",
].freeze

SCOPE_UNCHANGED_PATHS = [
  SESSION_VIEW_PATH,
  CHAT_SESSION_PATH,
  INSET_PATH,
  DERIVER_PATH,
].freeze

TYPOGRAPHY_PATHS = [SIDEBAR_PATH, PANE_PATH, TOPBAR_PATH, TIMELINE_PATH, POLICY_PATH].freeze

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
        errs << "TASK45_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  if raw.nil? || raw.strip.empty?
    return [nil, ["TASK45_BASELINE が未設定（HEAD にフォールバックしない）"]]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    return [nil, ["TASK45_BASELINE に HEAD は使えない（完全 SHA を渡す）"]]
  end
  unless value.match?(/\A[0-9a-fA-F]+\z/)
    return [nil, ["TASK45_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"]]
  end
  unless value.match?(/\A[0-9a-fA-F]{40}\z/)
    return [nil, ["TASK45_BASELINE が完全コミット SHA ではない（短い SHA・HEAD・ブランチ名は使えない）: #{value}"]]
  end
  [value, []]
end

def blob_fetch_errors(label, result, now)
  case result[:fetch]
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

def implementation_in_baseline_errors(presentation_blob, title_state_blob, view_blobs, presentation_error: nil, title_state_error: nil)
  ng = []
  if presentation_error
    ng << "基準時点の SessionTitlePresentation.swift を git show できない: #{presentation_error}"
  elsif presentation_blob
    ng << "基準時点に SessionTitlePresentation.swift がある（実装前の凍結ではない）"
  end
  if title_state_error
    ng << "基準時点の SessionTitleState.swift を git show できない: #{title_state_error}"
  elsif title_state_blob.nil?
    ng << "基準時点に SessionTitleState.swift が無い（task-44 完了状態ではない）"
  end
  view_blobs.each do |path, src|
    next if src.nil?
    if mask_strings_and_comments(src).match?(/\bSessionTitlePresentation\b/)
      ng << "基準時点の #{path} に SessionTitlePresentation がある（実装前の凍結ではない）"
    end
  end
  ng
end

def check_frozen_baseline(baseline, artifacts = nil)
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK45_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  ancestor_ok = if artifacts && artifacts.key?(:is_ancestor)
    artifacts[:is_ancestor]
  else
    git_is_ancestor?(full, "HEAD")
  end
  unless ancestor_ok
    ng << "TASK45_BASELINE が HEAD の祖先ではない"
  end
  view_keys = %i[sidebar pane topbar timeline policy]
  if artifacts
    view_blobs = {}
    view_keys.each do |key|
      path = PATHS[key]
      view_blobs[path] = artifacts[:view_blobs] ? artifacts[:view_blobs][path] : artifacts[key]
    end
    ng.concat(implementation_in_baseline_errors(
      artifacts[:presentation_blob],
      artifacts[:title_state_blob],
      view_blobs,
      presentation_error: artifacts[:presentation_error],
      title_state_error: artifacts[:title_state_error]
    ))
    if artifacts[:test_result]
      ng.concat(blob_fetch_errors("受け入れテスト", artifacts[:test_result], artifacts[:test_now]))
    else
      ng.concat(frozen_artifact_errors("受け入れテスト", artifacts[:test_blob], artifacts[:test_now]))
    end
    if artifacts[:rb_result]
      ng.concat(blob_fetch_errors("rb 自身", artifacts[:rb_result], artifacts[:rb_now]))
    else
      ng.concat(frozen_artifact_errors("rb 自身", artifacts[:rb_blob], artifacts[:rb_now]))
    end
  else
    pres = git_show_result(full, PRESENTATION_PATH)
    state = git_show_result(full, TITLE_STATE_PATH)
    view_blobs = {}
    PATHS.each do |key, path|
      next unless view_keys.include?(key)
      shown = git_show_result(full, path)
      view_blobs[path] = shown[:fetch] == :ok ? shown[:text] : nil
    end
    ng.concat(implementation_in_baseline_errors(
      pres[:fetch] == :ok ? pres[:text] : nil,
      state[:fetch] == :ok ? state[:text] : nil,
      view_blobs,
      presentation_error: (pres[:fetch] == :git_error ? pres[:stderr] : nil),
      title_state_error: (state[:fetch] == :git_error ? state[:stderr] : nil)
    ))
    ng.concat(blob_fetch_errors("受け入れテスト", git_show_result(full, TEST_PATH), read_if_exist(TEST_PATH)))
    ng.concat(blob_fetch_errors("rb 自身", git_show_result(full, WIRING_RB_PATH), read_if_exist(WIRING_RB_PATH)))
  end
  ng
end

def scope_check_requested?(env = ENV)
  env["TASK45_SCOPE_CHECK"] == "1"
end

PATHS = {
  presentation: PRESENTATION_PATH,
  sidebar: SIDEBAR_PATH,
  pane: PANE_PATH,
  topbar: TOPBAR_PATH,
  timeline: TIMELINE_PATH,
  policy: POLICY_PATH,
  session_view: SESSION_VIEW_PATH,
  chat_session: CHAT_SESSION_PATH,
  grid_column: GRID_COLUMN_PATH,
  inset: INSET_PATH,
  deriver: DERIVER_PATH,
  title_state: TITLE_STATE_PATH,
}.freeze

def missing_file(files, key, label)
  files[key].nil? ? ["#{label} が存在しない"] : []
end

def drawn_primary?(c)
  c.include?(".primary") && c.include?("Text(")
end

def uses_secondary_model?(c)
  c.include?(".secondary")
end

def flower_reimplemented?(c)
  return false unless c.include?("flowerName")
  c.match?(/flowerName\s*[!=]=/) || c.match?(/titleState\.flowerName/)
end

def has_line_limit?(c)
  c.include?("lineLimit(1)")
end

def has_tail_truncation?(c)
  c.include?("truncationMode(.tail)") || c.include?("truncationMode:.tail")
end

def help_uses_primary?(c)
  c.match?(/\.help\([^)]*\.primary/)
end

def ax_uses_primary?(c)
  c.match?(/accessibilityValue\([^)]*\.primary/)
end

def help_connected?(c)
  c.include?("helpText") && c.include?(".help(")
end

def ax_connected?(c)
  c.include?("accessibilityValue") && c.match?(/\.accessibilityValue\(/)
end

def model_from_title_state?(c)
  c.include?("SessionTitlePresentation(") && c.include?("titleState")
end

def legacy_only_model?(c)
  c.include?("SessionTitlePresentation(") && c.include?(".legacy(") && !c.include?("titleState")
end

def node_lookup?(c)
  c.include?("sessionNode(id:") || c.include?("sessionNodes") || c.match?(/first\s*(?:where:)?\s*\{\s*\$0\.id/)
end

def name_surface_errors(c, label)
  return ["#{label}を解析できない"] if c.is_a?(Symbol)
  ng = []
  unless drawn_primary?(c) && model_from_title_state?(c)
    ng << "#{label}が titleState の表示モデルに未接続"
    return ng
  end
  ng << "#{label}の1行制限が無い" unless has_line_limit?(c)
  ng << "#{label}の末尾省略が無い" unless has_tail_truncation?(c)
  ng << "#{label}の secondary が未接続" unless uses_secondary_model?(c)
  ng << "花名表示条件を View で再実装している" if flower_reimplemented?(c)
  if help_uses_primary?(c)
    ng << "名前 help に fullTitle ではなく primary を渡している"
  elsif !help_connected?(c)
    ng << "#{label}の全文 help が未接続"
  end
  if ax_uses_primary?(c)
    ng << "名前 AX value に fullTitle ではなく primary を渡している"
  elsif !ax_connected?(c)
    ng << "#{label}の名前 AX value が未接続"
  end
  ng
end

def check_presentation_type(src)
  return ["#{PRESENTATION_PATH} が存在しない"] if src.nil?
  indexed = code_only_indexed(src)
  return ["SessionTitlePresentation が存在しない"] unless indexed.match?(/\bstruct\s+SessionTitlePresentation\b/)
  body = extract_struct_body(src, "SessionTitlePresentation")
  return ["SessionTitlePresentation を解析できない"] if body.nil?
  c = compact(mask_strings_and_comments(body))
  ng = []
  %w[primary secondary fullTitle helpText accessibilityValue].each do |field|
    ng << "SessionTitlePresentation.#{field} が無い" unless c.include?(field)
  end
  ng << "View から導出を呼んでいる" if live_code(src).include?("SessionTitleDeriver")
  ng << "View から保存を呼んでいる" if live_code(src) =~ /persistSessionName|waitForPendingWrites|renameSession/
  ng
end

def check_sidebar(src)
  ng = missing_file({ sidebar: src }, :sidebar, SIDEBAR_PATH)
  return ng unless ng.empty?
  c = struct_live(src, "SessionSidebarRowView")
  return ["サイドバーの名前領域を解析できない"] if c.is_a?(Symbol)
  ng.concat(name_surface_errors(c, "サイドバーの名前領域"))
  body = extract_var_body(extract_struct_body(src, "SessionSidebarRowView").to_s, "body")
  body_c = compact(mask_strings_and_comments(body.to_s))
  overwritten = !body_c.include?("emphasis.accessibilityValue") ||
    body_c.match?(/sessionRow\.accessibilityValue\([^)]*(?:presentation|primary|fullTitle|helpText)/)
  ng << "サイドバー行の選択 AX value を名前で上書きしている" if overwritten
  ng << "状態表示が維持されていない" unless c.include?("StatusDot") && c.include?("StatusLabel")
  ng << "開始日時が維持されていない" unless c.include?("startedAt")
  ng.uniq
end

def check_grid(src)
  ng = missing_file({ pane: src }, :pane, PANE_PATH)
  return ng unless ng.empty?
  header = struct_live(src, "PaneTileView", "header")
  header = struct_live(src, "PaneTileView") if header.is_a?(Symbol)
  return ["グリッドの名前領域を解析できない"] if header.is_a?(Symbol)
  ng.concat(name_surface_errors(header, "グリッドの名前領域"))
  raw_header = extract_var_body(extract_struct_body(src, "PaneTileView").to_s, "header")
  raw_header ||= extract_var_body(src, "header")
  if raw_header
    drag = raw_header.index(".draggable")
    gesture = raw_header.index(".simultaneousGesture")
    if drag.nil? || gesture.nil? || drag > gesture
      ng << "ドラッグと選択の順序が変わっている"
    end
    ng << "閉じる操作が維持されていない" unless raw_header.include?("onRemove") && raw_header.include?("セッションを閉じる")
    ng << "状態表示が維持されていない" unless live_code(raw_header).include?("StatusDot")
  else
    ng << "ドラッグと選択の順序が変わっている"
  end
  tile = extract_var_body(extract_struct_body(src, "PaneTileView").to_s, "tileContent")
  tile ||= extract_var_body(src, "tileContent")
  tile_c = live_code(tile.to_s)
  ng << "端末接続が維持されていない" unless tile_c.include?("TerminalView") && tile_c.include?("terminalCoordinator")
  ng
end

def check_topbar(src)
  ng = missing_file({ topbar: src }, :topbar, TOPBAR_PATH)
  return ng unless ng.empty?
  c = struct_live(src, "DashboardLeadingTopBarControls")
  return ["トップバーの名前領域を解析できない"] if c.is_a?(Symbol)
  ng.concat(name_surface_errors(c, "トップバーの名前領域"))
  unless (c.include?("router.selectedSession") || c.include?("selectedSession")) && node_lookup?(c)
    ng << "トップバーが選択ノードに追随していない" unless ng.any? { |m| m.include?("未接続") }
  end
  if c.include?("case.appServer") && !c.include?("case.pty")
    ng << "トップバーが PTY／チャットの選択ノードに対応していない"
  end
  body = extract_var_body(extract_struct_body(src, "DashboardLeadingTopBarControls").to_s, "body")
  body_c = compact(mask_strings_and_comments(erase_if_false(body.to_s)))
  ng << "トップバーの既存操作が維持されていない" unless body_c.include?("settingsButton") && body_c.include?("sidebarToggleButton")
  stacked_title = body_c.match?(/VStack/) && (c.include?("SessionTitlePresentation") || body_c.include?("selectedSessionTitle"))
  ng << "トップバータイトルを2段化している" if stacked_title
  ng
end

def title_helper(src)
  extract_func_body(src, "titlePresentation") || extract_var_body(src, "titlePresentation")
end

def team_model_source(timeline)
  helper = title_helper(timeline)
  parts = [helper, extract_func_body(timeline, "header"), extract_func_body(timeline, "timeline"), extract_struct_body(timeline, "TeamTimelineView")]
  live_code(parts.compact.join("\n"))
end

def check_team_chip(timeline)
  ng = missing_file({ timeline: timeline }, :timeline, TIMELINE_PATH)
  return ng unless ng.empty?
  chip = struct_live(timeline, "TeamTimelineSourceChip")
  return ["チームの source chip を解析できない"] if chip.is_a?(Symbol)
  unless drawn_primary?(chip)
    return ["チームの source chip が現在ノードの表示モデルに未接続"]
  end
  src = team_model_source(timeline)
  unless model_from_title_state?(src) && node_lookup?(src)
    return ["チームの source chip が現在ノードの表示モデルに未接続"]
  end
  ng.concat(name_surface_errors(chip + src, "チームの source chip").reject { |m| m.include?("未接続") && m.include?("source chip") })
  ng
end

def check_team_card(timeline)
  ng = missing_file({ timeline: timeline }, :timeline, TIMELINE_PATH)
  return ng unless ng.empty?
  row = struct_live(timeline, "AgoraTimelineRow")
  return ["チームの発言カードを解析できない"] if row.is_a?(Symbol)
  unless drawn_primary?(row)
    return ["チームの発言カードが現在ノードの表示モデルに未接続"]
  end
  src = team_model_source(timeline)
  unless model_from_title_state?(src) && node_lookup?(src)
    return ["チームの発言カードが現在ノードの表示モデルに未接続"]
  end
  raw = extract_struct_body(timeline, "AgoraTimelineRow").to_s
  ng << "チームカードの移動操作が維持されていない" unless live_code(raw).include?("onOpenSession") && raw.include?("シングルビューで開く")
  ng.concat(name_surface_errors(row + src, "チームの発言カード").reject { |m| m.include?("未接続") && m.include?("発言カード") })
  ng
end

def check_team_thinking(policy, timeline)
  ng = []
  ng.concat(missing_file({ policy: policy }, :policy, POLICY_PATH))
  ng.concat(missing_file({ timeline: timeline }, :timeline, TIMELINE_PATH))
  return ng unless ng.empty?
  row = struct_live(policy, "AgoraThinkingIndicatorRow")
  return ["チームの Thinking 行を解析できない"] if row.is_a?(Symbol)
  unless drawn_primary?(row)
    return ["チームの Thinking 行が現在ノードの表示モデルに未接続"]
  end
  src = team_model_source(timeline)
  unless model_from_title_state?(src) && node_lookup?(src)
    return ["チームの Thinking 行が現在ノードの表示モデルに未接続"]
  end
  ng.concat(name_surface_errors(row + src, "チームの Thinking 行").reject { |m| m.include?("未接続") && m.include?("Thinking") })
  ng
end

def check_team(timeline, policy)
  ng = []
  ng.concat(missing_file({ timeline: timeline }, :timeline, TIMELINE_PATH))
  ng.concat(missing_file({ policy: policy }, :policy, POLICY_PATH))
  return ng unless ng.empty?
  src = team_model_source(timeline)
  chip = struct_live(timeline, "TeamTimelineSourceChip")
  card = struct_live(timeline, "AgoraTimelineRow")
  think = struct_live(policy, "AgoraThinkingIndicatorRow")
  if [chip, card, think].any? { |c| c.is_a?(Symbol) }
    ng << "チームの名前領域を解析できない"
    return ng
  end
  unless drawn_primary?(chip) || drawn_primary?(card) || drawn_primary?(think)
    ng << "チームの名前領域が titleState の表示モデルに未接続"
    return ng
  end
  if legacy_only_model?(src) || (src.include?("SessionTitlePresentation(") && !src.include?("titleState"))
    ng << "チームが現在ノードを無視し古い名前だけを表示している"
  end
  ng.concat(check_team_chip(timeline))
  ng.concat(check_team_card(timeline))
  ng.concat(check_team_thinking(policy, timeline))
  ng.uniq
end

def check_no_new_headers(files)
  ng = []
  session_c = live_code(files[:session_view].to_s)
  chat_main = extract_func_body(files[:chat_session].to_s, "mainColumn")
  chat_c = live_code(chat_main.to_s)
  grid_c = live_code(files[:grid_column].to_s)
  if session_c.include?("SessionTitlePresentation") || session_c.match?(/Text\(\s*viewModel\.displayName/)
    ng << "単体本文に新規ヘッダーを追加している"
  end
  if chat_c.include?("SessionTitlePresentation") || chat_c.match?(/Text\(\s*viewModel\.displayName/)
    ng << "単体本文に新規ヘッダーを追加している"
  end
  if grid_c.include?("SessionTitlePresentation") || grid_c.match?(/Text\(\s*viewModel\.displayName/)
    ng << "グリッド本文に新規ヘッダーを追加している"
  end
  ng.uniq
end

def check_no_derive_save(files)
  ng = []
  %i[presentation sidebar pane topbar timeline policy].each do |key|
    src = files[key]
    next if src.nil?
    visible = compact(mask_strings_and_comments(erase_if_false(src)))
    ng << "View から導出を呼んでいる" if visible.include?("SessionTitleDeriver")
    if visible =~ /persistSessionName|waitForPendingWrites|renameSession\(/
      ng << "View から保存を呼んでいる"
    end
  end
  ng.uniq
end

def typography_tokens(src)
  mask_strings_and_comments(src.to_s).scan(/(?:TranscriptTypography|ChatTypography)\.[A-Za-z0-9_]+/)
end

def unused_typography?(src)
  return false if src.nil?
  masked = mask_strings_and_comments(src)
  compact(masked) =~ /iffalse\{[^}]*(?:TranscriptTypography|ChatTypography)/
end

def check_typography(current, baseline)
  ng = []
  TYPOGRAPHY_PATHS.each do |path|
    key = PATHS.key(path)
    cur = current[key]
    base = baseline && baseline[key]
    next if cur.nil? && base.nil?
    base_refs = typography_tokens(base)
    cur_refs = typography_tokens(cur)
    if base_refs != cur_refs
      (base_refs - cur_refs).each do |ref|
        ng << "#{path} の typography 参照 #{ref} が削除されている"
      end
      (cur_refs - base_refs).each do |ref|
        if base_refs.empty?
          ng << "#{path} に TranscriptTypography のダミー参照を追加している"
        else
          ng << "#{path} の typography 参照 #{ref} が変更されている"
        end
      end
    end
    if unused_typography?(cur)
      ng << "#{path} の typography 参照が未使用化されている"
    end
    live = live_code(cur.to_s)
    constantized = live.include?("Font.system") || live.match?(/\.system\(size:\d/)
    if base_refs.any? && (base_refs - cur_refs).any? && constantized
      ng << "#{path} の typography 参照を定数化している"
    end
    if base_refs.any? && compact(mask_strings_and_comments(cur.to_s)).include?("_=ChatTypography")
      ng << "#{path} の typography 参照が未使用化されている"
    end
  end
  ng.uniq
end

def mask_title_draw(src)
  src.to_s.lines.reject { |line|
    compact(mask_strings_and_comments(line)) =~ /SessionTitlePresentation|presentation\.(primary|secondary|helpText|accessibilityValue)|Text\(session\.displayName\)|Text\(source\.displayName\)|Text\(item\.sessionDisplayName\)|titlePresentation\(|selectedSessionTitle|ifletsecondary/
  }.join
end

def extra_changed_product_paths(rev)
  tracked = IO.popen(["git", "diff", "--name-only", rev, "--", "macos"], err: [:child, :out], &:read)
  untracked = IO.popen(["git", "ls-files", "--others", "--exclude-standard", "--", "macos"], err: [:child, :out], &:read)
  names = (tracked.to_s + untracked.to_s).split("\n").reject(&:empty?).uniq
  names - ALLOWED_PRODUCT_PATHS
end

def scope_errors(current_files, baseline_files)
  ng = []
  extra = current_files[:extra_changed]
  extra.to_a.each do |path|
    ng << "許可パス外の製品変更: #{path}"
  end
  ALLOWED_PRODUCT_PATHS.each do |path|
    key = PATHS.key(path)
    next if key == :presentation
    cur = current_files[key]
    base = baseline_files[key]
    next if cur.nil? || base.nil?
    unless normalize_code(mask_title_draw(cur)) == normalize_code(mask_title_draw(base))
      ng << "許可ファイル内の名前領域以外が基準と一致しない: #{path}"
    end
  end
  (SCOPE_UNCHANGED_PATHS + TASK44_PRODUCT_PATHS).each do |path|
    key = PATHS.key(path)
    cur = key ? current_files[key] : current_files[:scoped] && current_files[:scoped][path]
    base = key ? baseline_files[key] : baseline_files[:scoped] && baseline_files[:scoped][path]
    cur ||= current_files[:scoped] && current_files[:scoped][path]
    base ||= baseline_files[:scoped] && baseline_files[:scoped][path]
    if path == DERIVER_PATH || TASK44_PRODUCT_PATHS.include?(path)
      if !cur.nil? && !base.nil? && !workdir_matches_git_blob?(cur, base)
        ng << "task-41/44 の製品ソースが基準から変化している: #{path}"
      end
    elsif path == INSET_PATH
      if !cur.nil? && !base.nil? && !workdir_matches_git_blob?(cur, base)
        ng << "余白・共有ヘッダー高さのポリシーが基準から変化している"
      end
    elsif !cur.nil? && !base.nil? && !workdir_matches_git_blob?(cur, base)
      ng << "#{path} が基準から変化している"
    end
  end
  ng.uniq
end

def check_product(files)
  ng = []
  ng.concat(check_presentation_type(files[:presentation]))
  ng.concat(check_sidebar(files[:sidebar]))
  ng.concat(check_grid(files[:pane]))
  ng.concat(check_topbar(files[:topbar]))
  ng.concat(check_team(files[:timeline], files[:policy]))
  ng.concat(check_no_new_headers(files))
  ng.concat(check_no_derive_save(files))
  ng.uniq
end

def evaluate_checks(files, baseline_blobs, scope:)
  ng = []
  ng.concat(check_product(files))
  ng.concat(check_typography(files, baseline_blobs)) if baseline_blobs
  ng.concat(scope_errors(files, baseline_blobs)) if scope && baseline_blobs
  ng.uniq
end

def worktree_files(baseline_rev = nil)
  files = {}
  PATHS.each { |key, path| files[key] = read_if_exist(path) }
  files[:extra_changed] = extra_changed_product_paths(baseline_rev) if baseline_rev
  files[:scoped] = {}
  (SCOPE_UNCHANGED_PATHS + TASK44_PRODUCT_PATHS).each do |path|
    files[:scoped][path] = read_if_exist(path)
  end
  files
end

def baseline_files(rev)
  files = {}
  PATHS.each { |key, path| files[key] = git_show(rev, path) }
  files[:scoped] = {}
  (SCOPE_UNCHANGED_PATHS + TASK44_PRODUCT_PATHS).each do |path|
    files[:scoped][path] = git_show(rev, path)
  end
  files
end

def name_view_block(state_expr = "session.titleState", id_expr = "session.id", workspace_expr = "session.workspacePath")
  <<~SWIFT
            let presentation = SessionTitlePresentation(state: #{state_expr}, fallback: SessionViewModel.shortID(for: #{id_expr}), workspacePath: #{workspace_expr})
            Text(presentation.primary)
              .lineLimit(1)
              .truncationMode(.tail)
              .help(presentation.helpText)
              .accessibilityValue(presentation.accessibilityValue)
            if let secondary = presentation.secondary {
              Text(secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
  SWIFT
end

def good_presentation
  <<~SWIFT
    public struct SessionTitlePresentation: Equatable, Sendable {
      public let primary: String
      public let secondary: String?
      public let fullTitle: String
      public let helpText: String
      public let accessibilityValue: String
      public init(state: SessionTitleState, fallback: String, workspacePath: String) {
        self.primary = state.effectiveName(fallback: fallback)
        self.secondary = nil
        self.fullTitle = primary
        self.helpText = fullTitle
        self.accessibilityValue = fullTitle
      }
    }
  SWIFT
end

def good_sidebar
  <<~SWIFT
    private struct SessionSidebarRowView: View {
      let session: SessionNode
      var body: some View {
        if let accessibilityValue = emphasis.accessibilityValue {
          sessionRow.accessibilityValue(Text(accessibilityValue))
        } else {
          sessionRow
        }
      }
      private var sessionRow: some View {
        HStack {
          StatusDot(status: session.displayStatus)
          StatusLabel(status: session.displayStatus)
    #{name_view_block}
          TimelineView(.periodic(from: session.startedAt, by: 60)) { timeline in
            Text(SidebarRelativeTime.label(from: session.startedAt, to: timeline.date))
          }
        }
        .help(session.workspacePath)
      }
      private var emphasis: SidebarRowEmphasis {
        SidebarRowEmphasis.resolve(.session(isCurrent: isSelected, isHovering: isHovering, requiresAttention: requiresAttention))
      }
    }
  SWIFT
end

def good_pane
  <<~SWIFT
    private struct PaneTileView: View {
      var body: some View {
        tileShell
      }
      private var tileShell: some View {
        VStack(spacing: 0) {
          header
          tileContent
        }
      }
      @ViewBuilder
      private var tileContent: some View {
        switch session {
        case .pty(let session):
          TerminalView(coordinator: session.terminalCoordinator)
        case .appServer(let session):
          GridChatColumn(viewModel: session, projectName: projectName, onFocusGained: onSelect)
        }
      }
      private var header: some View {
        HStack {
          StatusDot(status: session.displayStatus)
          StatusLabel(status: session.displayStatus)
    #{name_view_block}
          if !session.workspaceName.isEmpty {
            Text(session.workspaceName)
          }
          Button(action: onRemove) {
            Image(systemName: "xmark")
          }
          .help("セッションを閉じる")
        }
        .draggable(DraggedSession(id: session.id)) {
          Text(session.displayName)
        }
        .simultaneousGesture(
          DragGesture(minimumDistance: 0).onChanged { _ in selectImmediately() }
        )
      }
    }
  SWIFT
end

def good_topbar
  <<~SWIFT
    struct DashboardLeadingTopBarControls: View {
      var body: some View {
        HStack(spacing: DSSpacing.s) {
          sidebarToggleButton
          settingsButton
          selectedSessionTitle
        }
      }
      @ViewBuilder
      private var selectedSessionTitle: some View {
        if let session = selectedNode {
    #{name_view_block}
        }
      }
      private var selectedNode: SessionNode? {
        router.selectedSession.flatMap { viewModel.sessionNode(id: $0) }
      }
      private var settingsButton: some View {
        Button { onOpenSettings() } label: { Image(systemName: "gearshape") }.help("設定")
      }
      private var sidebarToggleButton: some View {
        Button { router.toggleSidebar() } label: { Image(systemName: "sidebar.leading") }
      }
    }
  SWIFT
end

def good_timeline
  <<~SWIFT
    public struct TeamTimelineView: View {
      var body: some View {
        timeline(sources: store.sources, items: store.items)
      }
      private func timeline(sources: [TeamTimelineSource], items: [TeamTimelineItem]) -> some View {
        VStack {
          header(sources: sources)
          AgoraTimelineRows(items: items, presentationFor: titlePresentation, onOpenSession: openSession)
          AgoraThinkingIndicatorRows(sources: thinkingSources(from: sources), presentationFor: titlePresentation)
        }
      }
      private func header(sources: [TeamTimelineSource]) -> some View {
        HStack {
          ForEach(sources) { source in
            TeamTimelineSourceChip(source: source, presentation: titlePresentation(sessionID: source.id, fallbackName: source.displayName))
          }
        }
      }
      private func titlePresentation(sessionID: SessionID, fallbackName: String) -> SessionTitlePresentation {
        if let node = viewModel.sessionNodes.first(where: { $0.id == sessionID }) {
          return SessionTitlePresentation(state: node.titleState, fallback: SessionViewModel.shortID(for: node.id), workspacePath: node.workspacePath)
        }
        return SessionTitlePresentation(state: .legacy(name: fallbackName), fallback: fallbackName, workspacePath: "")
      }
      private func openSession(_ id: SessionID) {
        router.selectedSession = id
      }
    }
    private struct TeamTimelineSourceChip: View {
      let source: TeamTimelineSource
      let presentation: SessionTitlePresentation
      var body: some View {
        HStack {
          Text(source.agentDescriptor.displayName)
          Text(presentation.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(presentation.helpText)
            .accessibilityValue(presentation.accessibilityValue)
          if let secondary = presentation.secondary {
            Text(secondary).lineLimit(1).truncationMode(.tail)
          }
        }
      }
    }
    private struct AgoraTimelineRow: View {
      let item: TeamTimelineItem
      let presentation: SessionTitlePresentation
      let onOpenSession: (SessionID) -> Void
      var body: some View {
        speakerHeader
      }
      private var speakerHeader: some View {
        Button {
          onOpenSession(item.sessionID)
        } label: {
          HStack {
            Text(presentation.primary)
              .lineLimit(1)
              .truncationMode(.tail)
              .help(presentation.helpText)
              .accessibilityValue(presentation.accessibilityValue)
            if let secondary = presentation.secondary {
              Text(secondary).lineLimit(1).truncationMode(.tail)
            }
          }
        }
        .help("シングルビューで開く")
      }
    }
    private struct AgoraTimelineRows: View {
      let items: [TeamTimelineItem]
      let presentationFor: (SessionID, String) -> SessionTitlePresentation
      let onOpenSession: (SessionID) -> Void
      var body: some View {
        ForEach(items) { item in
          AgoraTimelineRow(item: item, presentation: presentationFor(item.sessionID, item.sessionDisplayName), onOpenSession: onOpenSession)
        }
      }
    }
    private struct AgoraThinkingIndicatorRows: View {
      let sources: [TeamTimelineSource]
      let presentationFor: (SessionID, String) -> SessionTitlePresentation
      var body: some View {
        ForEach(sources) { source in
          AgoraThinkingIndicatorRow(source: source, presentation: presentationFor(source.id, source.displayName))
        }
      }
    }
  SWIFT
end

def good_policy
  <<~SWIFT
    public enum AgentChatRowPolicy {
      public static func showsSpeakerHeader(for content: TeamTimelineContent) -> Bool { true }
      public static func usesAgentMessageBubble(for content: TeamTimelineContent) -> Bool { false }
    }
    struct AgoraThinkingIndicatorRow: View {
      let source: TeamTimelineSource
      let presentation: SessionTitlePresentation
      var body: some View {
        VStack {
          HStack {
            Text(presentation.primary)
              .lineLimit(1)
              .truncationMode(.tail)
              .help(presentation.helpText)
              .accessibilityValue(presentation.accessibilityValue)
            if let secondary = presentation.secondary {
              Text(secondary).lineLimit(1).truncationMode(.tail)
            }
          }
          ShimmerTextView(
            text: state.orbLabel,
            font: .system(size: ChatTypography.bodyFontSize(scale: scale), pointSize: ChatTypography.bodyFontSize(scale: scale), color: DSColor.chatTextPrimary, isVisible: isVisible)
          )
        }
      }
    }
  SWIFT
end

def good_session_view
  <<~SWIFT
    public struct SessionView: View {
      public var body: some View {
        VStack {
          HStack {
            Text("開始 \\(Self.startedAtFormatter.string(from: viewModel.startedAt))")
          }
          TerminalView(coordinator: viewModel.terminalCoordinator)
        }
      }
    }
  SWIFT
end

def good_chat_session
  <<~SWIFT
    public struct ChatSessionView: View {
      public var body: some View {
        mainColumn(width: 400)
      }
      private func mainColumn(width: CGFloat) -> some View {
        VStack {
          ApprovalBanner(viewModel: viewModel)
          ChatTranscriptView(viewModel: viewModel)
        }
      }
    }
  SWIFT
end

def good_grid_column
  <<~SWIFT
    struct GridChatColumn: View {
      var body: some View {
        VStack {
          ApprovalBanner(viewModel: viewModel)
          ChatTranscriptView(viewModel: viewModel)
        }
      }
    }
  SWIFT
end

def good_files
  {
    presentation: good_presentation,
    sidebar: good_sidebar,
    pane: good_pane,
    topbar: good_topbar,
    timeline: good_timeline,
    policy: good_policy,
    session_view: good_session_view,
    chat_session: good_chat_session,
    grid_column: good_grid_column,
    inset: "public enum TopBarInsetPolicy { public static func contentTopInset(measuredOverlayHeight: CGFloat) -> CGFloat { max(32, ceil(measuredOverlayHeight) + 8) } }\n",
    deriver: "public enum SessionTitleDeriver { public static func derive(from text: String) -> DerivedSessionTitle? { nil } }\n",
    title_state: "public struct SessionTitleState {}\n",
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
    puts "task45-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task45-wiring --selftest: FAIL #{msg}"
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
  interp = %(let s = "\\(SessionTitlePresentation(state: state, fallback: "abc123", workspacePath: path))" // note)
  selftest_assert strip_comments(interp).include?("SessionTitlePresentation"), "正例: 補間文字列を保持する"
  spaced = %(Text("hello world"))
  selftest_assert normalize_code(spaced).include?("hello world"), "正例: 文字列内空白を正規化で消さない"

  good = good_files
  selftest_errors_eq check_product(good), [], "正例: 契約どおりの配線は空 NG"
  selftest_errors_eq check_typography(good, good), [], "正例: typography 同一 blob は空"

  commented = with_file(good, :sidebar) { |src|
    src + %(\n// SessionTitlePresentation(state: session.titleState)\nlet decoy = "SessionTitleDeriver"\n)
  }
  selftest_errors_eq check_product(commented), [], "正例: コメント・文字列だけを加える"

  sidebar_off = with_file(good, :sidebar) { |src|
    src.gsub(name_view_block, "            Text(session.displayName)\n")
  }
  selftest_errors_eq check_sidebar(sidebar_off[:sidebar]), ["サイドバーの名前領域が titleState の表示モデルに未接続"], "負例: サイドバーだけ未接続"

  grid_off = with_file(good, :pane) { |src|
    src.gsub(name_view_block, "            Text(session.displayName)\n")
  }
  selftest_errors_eq check_grid(grid_off[:pane]).select { |m| m.include?("未接続") }, ["グリッドの名前領域が titleState の表示モデルに未接続"], "負例: グリッドだけ未接続"

  top_off = with_file(good, :topbar) { |src|
    src.gsub(name_view_block, "")
  }
  selftest_errors_eq check_topbar(top_off[:topbar]).select { |m| m.include?("未接続") }, ["トップバーの名前領域が titleState の表示モデルに未接続"], "負例: トップバーだけ未接続"

  team_off = with_file(good, :timeline) { |src|
    src.gsub("presentation: titlePresentation(sessionID: source.id, fallbackName: source.displayName)", "")
      .gsub("Text(presentation.primary)", "Text(source.displayName)")
      .gsub("titlePresentation(sessionID:", "unusedPresentation(sessionID:")
  }
  team_off = with_file(team_off, :policy) { |src|
    src.gsub("Text(presentation.primary)", "Text(source.displayName)")
  }
  selftest_errors_eq check_product(team_off).select { |m| m.include?("チームの名前領域が") }, ["チームの名前領域が titleState の表示モデルに未接続"], "負例: チームだけ未接続"

  chip_off = with_file(good, :timeline) { |src|
    src.sub("Text(presentation.primary)", "Text(source.displayName)")
  }
  selftest_errors_eq check_team_chip(chip_off[:timeline]), ["チームの source chip が現在ノードの表示モデルに未接続"], "負例: source chip だけ未接続"

  card_off = with_file(good, :timeline) { |src|
    src.sub("  var body: some View {\n    speakerHeader\n  }", "  var body: some View {\n    Text(item.sessionDisplayName)\n  }")
  }
  selftest_errors_eq check_team_card(card_off[:timeline]).select { |m| m.include?("発言カード") && m.include?("未接続") }, ["チームの発言カードが現在ノードの表示モデルに未接続"], "負例: 発言カードだけ未接続"

  think_off = with_file(good, :policy) { |src|
    src.gsub("Text(presentation.primary)", "Text(source.displayName)")
  }
  selftest_errors_eq check_team_thinking(think_off[:policy], think_off[:timeline]), ["チームの Thinking 行が現在ノードの表示モデルに未接続"], "負例: Thinking 行だけ未接続"

  old_names = with_file(good, :timeline) { |src|
    src.gsub("state: node.titleState", "state: .legacy(name: fallbackName)")
  }
  selftest_errors_eq check_team(old_names[:timeline], old_names[:policy]).select { |m| m.include?("古い名前") }, ["チームが現在ノードを無視し古い名前だけを表示している"], "負例: 現在ノードを無視して古い名前だけ表示"

  help_primary = with_file(good, :sidebar) { |src|
    src.sub(".help(presentation.helpText)", ".help(presentation.primary)")
  }
  selftest_errors_eq check_sidebar(help_primary[:sidebar]).select { |m| m.include?("help") }, ["名前 help に fullTitle ではなく primary を渡している"], "負例: help に primary"

  ax_primary = with_file(good, :sidebar) { |src|
    src.sub(".accessibilityValue(presentation.accessibilityValue)", ".accessibilityValue(presentation.primary)")
  }
  selftest_errors_eq check_sidebar(ax_primary[:sidebar]).select { |m| m.include?("AX") }, ["名前 AX value に fullTitle ではなく primary を渡している"], "負例: AX に primary"

  no_limit = with_file(good, :sidebar) { |src| src.gsub(".lineLimit(1)", "") }
  selftest_errors_eq check_sidebar(no_limit[:sidebar]).select { |m| m.include?("1行") }, ["サイドバーの名前領域の1行制限が無い"], "負例: 1行制限欠落"

  no_tail = with_file(good, :sidebar) { |src| src.gsub(".truncationMode(.tail)", "") }
  selftest_errors_eq check_sidebar(no_tail[:sidebar]).select { |m| m.include?("末尾") }, ["サイドバーの名前領域の末尾省略が無い"], "負例: 末尾省略欠落"

  no_secondary = with_file(good, :sidebar) { |src|
    src.gsub(/if let secondary = presentation.secondary \{.*?\}/m, "")
  }
  selftest_errors_eq check_sidebar(no_secondary[:sidebar]).select { |m| m.include?("secondary") }, ["サイドバーの名前領域の secondary が未接続"], "負例: secondary 欠落"

  flower_view = with_file(good, :sidebar) { |src|
    src.sub("if let secondary = presentation.secondary {", "if let secondary = presentation.secondary, session.titleState.flowerName != presentation.primary {")
  }
  selftest_errors_eq check_sidebar(flower_view[:sidebar]).select { |m| m.include?("花名") }, ["花名表示条件を View で再実装している"], "負例: 花名条件を View で再実装"

  ax_overwrite = with_file(good, :sidebar) { |src|
    src.sub("sessionRow.accessibilityValue(Text(accessibilityValue))", "sessionRow.accessibilityValue(Text(presentation.primary))")
      .sub("if let accessibilityValue = emphasis.accessibilityValue {", "if true {")
  }
  selftest_errors_eq check_sidebar(ax_overwrite[:sidebar]).select { |m| m.include?("選択 AX") }, ["サイドバー行の選択 AX value を名前で上書きしている"], "負例: 選択 AX を名前で上書き"

  single_header = with_file(good, :session_view) { |src|
    src.sub("Text(\"開始", "Text(viewModel.displayName)\n            Text(\"開始")
  }
  selftest_errors_eq check_no_new_headers(single_header), ["単体本文に新規ヘッダーを追加している"], "負例: 単体本文へ新規ヘッダー"

  grid_header = with_file(good, :grid_column) { |src|
    src.sub("ApprovalBanner(viewModel: viewModel)", "Text(viewModel.displayName)\n          ApprovalBanner(viewModel: viewModel)")
  }
  selftest_errors_eq check_no_new_headers(grid_header), ["グリッド本文に新規ヘッダーを追加している"], "負例: グリッド本文へ新規ヘッダー"

  two_line = with_file(good, :topbar) { |src|
    src.sub("HStack(spacing: DSSpacing.s) {", "VStack(spacing: DSSpacing.s) {")
  }
  selftest_errors_eq check_topbar(two_line[:topbar]).select { |m| m.include?("2段") }, ["トップバータイトルを2段化している"], "負例: トップバータイトルの2段化"

  drag_swap = with_file(good, :pane) { |src|
    src.sub(".draggable(DraggedSession(id: session.id))", ".zzDrag(")
      .sub(".simultaneousGesture(", ".draggable(DraggedSession(id: session.id)) { Text(session.displayName) }\n    .simultaneousGesture(")
      .sub(".zzDrag(", ".simultaneousGesture(")
  }
  selftest_errors_eq check_grid(drag_swap[:pane]).select { |m| m.include?("ドラッグ") }, ["ドラッグと選択の順序が変わっている"], "負例: ドラッグと選択の順序"

  no_status = with_file(good, :sidebar) { |src| src.gsub("StatusDot(status: session.displayStatus)", "").gsub("StatusLabel(status: session.displayStatus)", "") }
  selftest_errors_eq check_sidebar(no_status[:sidebar]).select { |m| m.include?("状態") }, ["状態表示が維持されていない"], "負例: 状態表示の欠落"

  no_close = with_file(good, :pane) { |src| src.gsub('.help("セッションを閉じる")', "").gsub("onRemove", "onIgnore") }
  selftest_errors_eq check_grid(no_close[:pane]).select { |m| m.include?("閉じる") }, ["閉じる操作が維持されていない"], "負例: 閉じる操作の欠落"

  no_term = with_file(good, :pane) { |src| src.gsub("TerminalView(coordinator: session.terminalCoordinator)", "EmptyView()") }
  selftest_errors_eq check_grid(no_term[:pane]).select { |m| m.include?("端末") }, ["端末接続が維持されていない"], "負例: 端末接続の改変"

  no_nav = with_file(good, :timeline) { |src|
    src.gsub("onOpenSession(item.sessionID)", "").gsub("シングルビューで開く", "詳細")
  }
  selftest_errors_eq check_team_card(no_nav[:timeline]).select { |m| m.include?("移動") }, ["チームカードの移動操作が維持されていない"], "負例: チーム移動操作の改変"

  derive_call = with_file(good, :sidebar) { |src|
    src.sub("let presentation = SessionTitlePresentation", "let _ = SessionTitleDeriver.derive(from: session.name)\n            let presentation = SessionTitlePresentation")
  }
  selftest_errors_eq check_no_derive_save(derive_call), ["View から導出を呼んでいる"], "負例: View から導出"

  save_call = with_file(good, :topbar) { |src|
    src.sub("router.toggleSidebar()", "viewModel.renameSession(session, to: presentation.primary); viewModel.persistSessionName()")
  }
  selftest_errors_eq check_no_derive_save(save_call), ["View から保存を呼んでいる"], "負例: View から保存"

  typo_base = good
  typo_del = with_file(good, :policy) { |src| src.gsub("ChatTypography.bodyFontSize", "13") }
  selftest_errors_eq check_typography(typo_del, typo_base).select { |m| m.include?("削除") || m.include?("定数") }, [
    "#{POLICY_PATH} の typography 参照 ChatTypography.bodyFontSize が削除されている",
    "#{POLICY_PATH} の typography 参照を定数化している",
  ], "負例: typography 参照の削除・定数化"

  typo_unused = with_file(good, :policy) { |src|
    src.gsub("font: .system(size: ChatTypography.bodyFontSize(scale: scale), pointSize: ChatTypography.bodyFontSize(scale: scale), color: DSColor.chatTextPrimary, isVisible: isVisible)", "font: .system(size: 13)") + "\n    func decoy() { if false { _ = ChatTypography.bodyFontSize(scale: 1) } }\n"
  }
  selftest_assert check_typography(typo_unused, typo_base).any? { |m| m.include?("未使用") || m.include?("削除") }, "負例: typography 参照の未使用化 (#{check_typography(typo_unused, typo_base).inspect})"

  dummy = with_file(good, :sidebar) { |src| src + "\n    let unused = TranscriptTypography.body\n" }
  dummy_base = good
  selftest_errors_eq check_typography(dummy, dummy_base).select { |m| m.include?("ダミー") }, ["#{SIDEBAR_PATH} に TranscriptTypography のダミー参照を追加している"], "負例: 無参照ファイルへのダミー追加"

  decoy = with_file(good, :sidebar) { |src|
    src.gsub(name_view_block, "            Text(session.displayName)\n") +
      %(\n    // SessionTitlePresentation(state: session.titleState, fallback: "abc123", workspacePath: session.workspacePath)\n    var decoy: some View { Text("SessionTitlePresentation") }\n    if false { Text(SessionTitlePresentation(state: session.titleState, fallback: "a", workspacePath: "").primary) }\n)
  }
  selftest_errors_eq check_sidebar(decoy[:sidebar]), ["サイドバーの名前領域が titleState の表示モデルに未接続"], "負例: コメント・文字列・未使用コードによる偽装"

  unparsed = with_file(good, :sidebar) { |src| src.sub(/var body: some View \{.*\z/m, "var body: some View {") }
  selftest_errors_eq check_sidebar(unparsed[:sidebar]), ["サイドバーの名前領域を解析できない"], "負例: 構文切り出し失敗"

  selftest_errors_eq check_product({}), [
    "#{PRESENTATION_PATH} が存在しない",
    "#{SIDEBAR_PATH} が存在しない",
    "#{PANE_PATH} が存在しない",
    "#{TOPBAR_PATH} が存在しない",
    "#{TIMELINE_PATH} が存在しない",
    "#{POLICY_PATH} が存在しない",
  ], "負例: 対象欠落"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_errors_eq unset_errs, ["TASK45_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: 基準の未設定"
  selftest_assert unset.nil?, "負例: 未設定は nil"
  _invalid, invalid_errs = baseline_env_errors("not-a-sha")
  selftest_errors_eq invalid_errs, ["TASK45_BASELINE がコミット SHA ではない（ブランチ名は使えない）: not-a-sha"], "負例: SHA 不正"
  _head, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK45_BASELINE に HEAD は使えない（完全 SHA を渡す）"], "負例: HEAD 指定"
  _head1, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK45_BASELINE に HEAD は使えない（完全 SHA を渡す）"], "負例: HEAD~1 指定"
  _at, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK45_BASELINE に HEAD は使えない（完全 SHA を渡す）"], "負例: @ 指定"
  _branch, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK45_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
  _short, short_errs = baseline_env_errors("abc1234")
  selftest_errors_eq short_errs, ["TASK45_BASELINE が完全コミット SHA ではない（短い SHA・HEAD・ブランチ名は使えない）: abc1234"], "負例: 短い SHA"
  sha, sha_errs = baseline_env_errors("a" * 40)
  selftest_assert sha == ("a" * 40) && sha_errs.empty?, "正例: 40 桁 SHA 形式は拒否しない"

  selftest_errors_eq parse_contract_baseline_text("---\nfoo: 1\n"), :missing, "負例: 契約 baseline_commit 欠落"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n"), :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"not-a-sha\"\n"), :invalid, "負例: 契約 baseline_commit 不正"
  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"abc1234\"\n"), "abc1234", "正例: 契約 baseline_commit がクォート付き SHA"
  ph_errs = contract_baseline_errors("---\nbaseline_commit: \"PM が凍結時に設定\"\n", "a" * 40)
  selftest_errors_eq ph_errs, ["契約 baseline_commit がプレースホルダ（凍結時に実 SHA へ置換する）"], "負例: プレースホルダは NG"

  head_full = git_full_sha("HEAD")
  other_full = git_full_sha("HEAD^")
  selftest_assert !head_full.nil? && !other_full.nil? && head_full != other_full, "selftest 用に有効で異なる 2 コミットが必要"
  real_mismatch = contract_baseline_errors("---\nbaseline_commit: \"#{other_full}\"\n", head_full)
  selftest_errors_eq real_mismatch, ["TASK45_BASELINE が契約 baseline_commit と一致しない"], "負例: 契約不一致"

  same_blob = "frozen\n"
  artifacts_ok = {
    presentation_blob: nil,
    title_state_blob: "public struct SessionTitleState {}",
    view_blobs: {
      SIDEBAR_PATH => "struct X {}",
      PANE_PATH => "struct X {}",
      TOPBAR_PATH => "struct X {}",
      TIMELINE_PATH => "struct X {}",
      POLICY_PATH => "struct X {}",
    },
    test_blob: same_blob,
    test_now: same_blob,
    rb_blob: same_blob,
    rb_now: same_blob,
  }
  selftest_errors_eq check_frozen_baseline(head_full, artifacts_ok), [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  post_ng = check_frozen_baseline(head_full, artifacts_ok.merge(presentation_blob: "struct SessionTitlePresentation {}"))
  selftest_errors_eq post_ng, ["基準時点に SessionTitlePresentation.swift がある（実装前の凍結ではない）"], "負例: 実装済み基準"

  wired_view = check_frozen_baseline(head_full, artifacts_ok.merge(view_blobs: artifacts_ok[:view_blobs].merge(SIDEBAR_PATH => "let x = SessionTitlePresentation(state: s, fallback: \"a\", workspacePath: \"\")")))
  selftest_errors_eq wired_view, ["基準時点の #{SIDEBAR_PATH} に SessionTitlePresentation がある（実装前の凍結ではない）"], "負例: 表示配線入り基準"

  no_task44 = check_frozen_baseline(head_full, artifacts_ok.merge(title_state_blob: nil))
  selftest_errors_eq no_task44, ["基準時点に SessionTitleState.swift が無い（task-44 完了状態ではない）"], "負例: task-44 完了状態が基準に無い"

  git_fail = check_frozen_baseline(head_full, artifacts_ok.merge(presentation_error: "fatal: bad object"))
  selftest_errors_eq git_fail, ["基準時点の SessionTitlePresentation.swift を git show できない: fatal: bad object"], "負例: 基準 git 障害"

  selftest_errors_eq blob_fetch_errors("rb 自身", { fetch: :ok, text: "now" }, "frozen"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 凍結検査の改変"
  selftest_errors_eq blob_fetch_errors("受け入れテスト", { fetch: :git_error, text: nil, stderr: "fatal: foo" }, "now"), ["基準時点の受け入れテストを git show できない: fatal: foo"], "負例: blob 取得失敗"
  selftest_errors_eq blob_fetch_errors("受け入れテスト", { fetch: :missing, text: nil, stderr: "" }, "now"), ["基準時点の受け入れテストが無い"], "負例: 基準ファイル不存在"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "same", "same"), [], "正例: 凍結 rb と作業ツリーが同一"
  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"

  forced_non_ancestor = check_frozen_baseline(head_full, artifacts_ok.merge(is_ancestor: false))
  selftest_errors_eq forced_non_ancestor, ["TASK45_BASELINE が HEAD の祖先ではない"], "負例: 非祖先"

  out_of_scope = good.merge(extra_changed: ["macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptFormatting.swift"])
  selftest_errors_eq scope_errors(out_of_scope, good), ["許可パス外の製品変更: macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptFormatting.swift"], "負例: scope のみで拒否すべき範囲外変更"
  selftest_errors_eq check_product(good.merge(inset: "changed")), [], "正例: scope なしでは範囲外変更を範囲違反にしない"

  unset_ng = evaluate_checks(out_of_scope, good, scope: false)
  one_ng = evaluate_checks(out_of_scope, good, scope: true)
  selftest_errors_eq unset_ng, [], "正例: 未設定/0 相当は範囲外変更を恒久 NG にしない"
  selftest_errors_eq one_ng, ["許可パス外の製品変更: macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptFormatting.swift"], "負例: SCOPE_CHECK=1 の本番判定"

  with_env("TASK45_SCOPE_CHECK", "1") { selftest_assert scope_check_requested?, "正例: SCOPE_CHECK=1" }
  with_env("TASK45_SCOPE_CHECK", "0") { selftest_assert !scope_check_requested?, "正例: SCOPE_CHECK=0 では恒久のみ" }
  with_env("TASK45_SCOPE_CHECK", nil) { selftest_assert !scope_check_requested?, "正例: 未設定では恒久のみ" }

  header_perm = with_file(good, :session_view) { |src| src.sub("Text(\"開始", "Text(viewModel.displayName)\n            Text(\"開始") }
  selftest_errors_eq evaluate_checks(header_perm, good, scope: false), ["単体本文に新規ヘッダーを追加している"], "負例: scope なしでも失敗すべき恒久違反"

  prod = production_checks_source
  selftest_assert !prod.empty?, "正例: 本番検査セクションが存在する"
  selftest_assert baseline_check_connected?(prod), "正例: 基準検査が本番に接続されている"
  selftest_assert scope_check_gated?(prod), "正例: 変更範囲検査が TASK45_SCOPE_CHECK でゲートされている"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task45-wiring --selftest: OK"
  exit 0
end

# === task45 production checks ===
ng = []

raw = ENV["TASK45_BASELINE"]
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
    ng << "TASK45_BASELINE が無効なコミット: #{baseline}"
    baseline = nil
  else
    ng.concat(check_frozen_baseline(full))
    base_blobs = baseline_files(full)
    files = worktree_files(full)
    ng.concat(check_typography(files, base_blobs))
    if baseline && scope_check_requested?
      ng.concat(scope_errors(files, base_blobs))
    end
    baseline = full
  end
end

ng = ng.uniq
if ng.empty?
  puts "task45-wiring: OK"
else
  ng.each { |m| puts "task45-wiring: NG #{m}" }
  exit 1
end
