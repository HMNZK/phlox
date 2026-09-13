#!/usr/bin/env ruby
# task-47 配線検査: TranscriptMarkdownPresentation の prepare / summary が
# 回答・思考の Markdown 入口へ届き、本文色の役割と TranscriptTypography 参照が
# 実描画経路に残り、TASK47_BASELINE の凍結テストと変更禁止対象が契約どおりであること。
# コメントと文字列は同時識別する（task43-wiring.rb / task46-wiring.rb と同じ字句走査）。
# 比較対象は git show <TASK47_BASELINE>:<path> と作業ファイル。HEAD blob は使わない。

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

def extract_init_params_and_body(src, kind, struct_name: "RichMarkdownView")
  search = extract_struct_body(src, struct_name) || src.to_s
  indexed = code_only_indexed(search)
  re = case kind
  when :normal
    /(?:^|\n)[ \t]*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?init\s*\(\s*_/
  when :streaming
    /(?:^|\n)[ \t]*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?init\s*\(\s*streaming\b/
  end
  m = indexed.match(re)
  return nil unless m
  paren = indexed.index("(", m.begin(0))
  return nil unless paren
  params = extract_balanced(search, paren, "(", ")")
  return nil if params.nil?
  after = paren + 1 + params.length + 1
  brace = indexed.index("{", after)
  return nil unless brace
  body = extract_balanced(search, brace, "{", "}")
  return nil if body.nil?
  { params: params, body: body }
end

def extract_init_body(src, kind, struct_name: "RichMarkdownView")
  found = extract_init_params_and_body(src, kind, struct_name: struct_name)
  found && found[:body]
end

def git_tree_has_path?(rev, path)
  system("git", "cat-file", "-e", "#{rev}:#{path}", out: File::NULL, err: File::NULL)
end

def git_show_result(rev, path)
  text = IO.popen(["git", "show", "#{rev}:#{path}"], err: [:child, :out], &:read)
  if $?.success?
    { status: :ok, text: text, stderr: nil }
  elsif git_tree_has_path?(rev, path)
    { status: :git_error, text: nil, stderr: text.to_s.strip }
  else
    { status: :missing, text: nil, stderr: text.to_s.strip }
  end
end

def git_show(rev, path)
  result = git_show_result(rev, path)
  result[:status] == :ok ? result[:text] : nil
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
  compact(src).gsub(/_=(?:TranscriptMarkdownPresentation|TranscriptItemPresentation|TranscriptTypography|ChatScaledFont|ChatTypography)(?:\.[A-Za-z0-9_]+)*/, "")
end

def strip_dead_model_lets(c)
  s = c.dup
  s.gsub(/let([A-Za-z_][A-Za-z0-9_]*)=(?:TranscriptMarkdownPresentation|TranscriptItemPresentation)\.[A-Za-z0-9_]+\([^)]*\)/) do
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

def struct_reachable(src, name)
  return :missing if src.nil?
  body = extract_struct_body(src, name)
  indexed = code_only_indexed(src.to_s)
  if indexed.match?(/\bstruct\s+#{Regexp.escape(name)}\b/) && body.nil?
    return :unparseable
  end
  return :missing if body.nil?
  start = extract_var_body(body, "body") || body
  collect_reachable(src, start)
end

def compact_reach(src, name)
  reach = struct_reachable(src, name)
  return reach if reach.is_a?(Symbol)
  live_code(reach)
end

CONTRACT_PATH = "tasks/task-47.md"
WIRING_RB_PATH = ".claude/scripts/task47-wiring.rb"
PRESENTATION_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptMarkdownPresentation.swift"
ITEM_PRESENTATION_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptItemPresentation.swift"
TYPOGRAPHY_PATH = "macos/Packages/DesignSystem/Sources/DesignSystem/TranscriptTypography.swift"
BASIC_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift"
STRUCTURED_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift"
COMMAND_GROUP_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+CommandGroup.swift"
TASK_LIST_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+TaskList.swift"
CELLS_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells.swift"
COMMON_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCellsCommon.swift"
RENDER_CACHE_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageRenderCache.swift"
FORMATTING_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptFormatting.swift"
MARKDOWN_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift"
CODE_BLOCK_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeBlock.swift"
RECAP_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatRecap.swift"
SCALED_FONT_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatScaledFont.swift"
SESSION_FEATURE_SRC = "macos/Packages/SessionFeature/Sources/SessionFeature"

TEST_PRESENTATION = "macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptMarkdownPresentationTests.swift"
TEST_VISUAL = "macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift"

ACCEPTANCE_PATHS = [TEST_PRESENTATION, TEST_VISUAL].freeze
PRODUCTION_MARKER = "# === task47 production checks ==="
ALLOWED_PRODUCT_PATHS = [
  PRESENTATION_PATH,
  FORMATTING_PATH,
  MARKDOWN_PATH,
  BASIC_PATH,
  STRUCTURED_PATH,
].freeze
SCOPE_PROTECTED_PATHS = [
  CELLS_PATH,
  COMMON_PATH,
  RENDER_CACHE_PATH,
  COMMAND_GROUP_PATH,
  TASK_LIST_PATH,
  CODE_BLOCK_PATH,
  RECAP_PATH,
].freeze
SCALED_FONT_FORWARD = {
  "body" => "body",
  "bodyPointSize" => "body",
  "caption" => "metadata",
  "captionStrong" => "metadataStrong",
  "mono" => "code",
  "monoCaption" => "codeMetadata",
}.freeze
BASIC_PROTECTED_STRUCTS = %w[ErrorMessageCell UserMessageCell TurnCostCell AgentMessageCell].freeze
STRUCTURED_PROTECTED_STRUCTS = %w[CommandExecutionCell FileChangeCell ThinkingIndicatorCell SubAgentMarkerCell].freeze

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
        errs << "TASK47_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK47_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK47_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK47_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
    return [nil, errs]
  end
  [value, errs]
end

def blob_fetch_errors(label, result, now)
  case result[:status]
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
  markdown_blob, item_blob, typography_blob,
  markdown_error: nil, item_error: nil, typography_error: nil
)
  ng = []
  if markdown_error
    ng << "基準時点の TranscriptMarkdownPresentation.swift を git show できない: #{markdown_error}"
  elsif markdown_blob
    ng << "基準時点に TranscriptMarkdownPresentation.swift がある（実装前の凍結ではない）"
  end
  if item_error
    ng << "基準時点の TranscriptItemPresentation.swift を git show できない: #{item_error}"
  elsif item_blob.nil?
    ng << "基準時点に TranscriptItemPresentation.swift が無い（task-46 完了状態ではない）"
  end
  if typography_error
    ng << "基準時点の TranscriptTypography.swift を git show できない: #{typography_error}"
  elsif typography_blob.nil?
    ng << "基準時点に TranscriptTypography.swift が無い（task-40 完了状態ではない）"
  end
  ng
end

def check_frozen_baseline(baseline, artifacts = nil)
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK47_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  ancestor_ok = if artifacts && artifacts.key?(:is_ancestor)
    artifacts[:is_ancestor]
  else
    git_is_ancestor?(full, "HEAD")
  end
  unless ancestor_ok
    ng << "TASK47_BASELINE が HEAD の祖先ではない"
  end
  if artifacts
    ng.concat(implementation_in_baseline_errors(
      artifacts[:markdown_blob],
      artifacts[:item_blob],
      artifacts[:typography_blob],
      markdown_error: artifacts[:markdown_error],
      item_error: artifacts[:item_error],
      typography_error: artifacts[:typography_error]
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
    md = git_show_result(full, PRESENTATION_PATH)
    item = git_show_result(full, ITEM_PRESENTATION_PATH)
    typo = git_show_result(full, TYPOGRAPHY_PATH)
    ng.concat(implementation_in_baseline_errors(
      md[:status] == :ok ? md[:text] : nil,
      item[:status] == :ok ? item[:text] : nil,
      typo[:status] == :ok ? typo[:text] : nil,
      markdown_error: (md[:status] == :git_error ? md[:stderr] : nil),
      item_error: (item[:status] == :git_error ? item[:stderr] : nil),
      typography_error: (typo[:status] == :git_error ? typo[:stderr] : nil)
    ))
    ACCEPTANCE_PATHS.each_with_index do |path, idx|
      ng.concat(blob_fetch_errors("受け入れテスト#{idx + 1}", git_show_result(full, path), read_if_exist(path)))
    end
    ng.concat(blob_fetch_errors("rb 自身", git_show_result(full, WIRING_RB_PATH), read_if_exist(WIRING_RB_PATH)))
  end
  ng
end

def scope_check_requested?(env = ENV)
  env["TASK47_SCOPE_CHECK"] == "1"
end

def missing_struct(src, name, label)
  return ["#{label} が存在しない"] if src.nil?
  reach = struct_reachable(src, name)
  return ["#{name} が存在しない"] if reach == :missing
  return ["#{name} を解析できない"] if reach == :unparseable
  []
end

def font_role_ok?(c, scaled_src)
  return true if c.include?("TranscriptTypography.font(for:")
  SCALED_FONT_FORWARD.each do |fn, role|
    next unless c.include?("ChatScaledFont.#{fn}(")
    return scaled_font_forwards?(scaled_src, fn, role)
  end
  false
end

def scaled_font_forwards?(scaled_src, fn, role)
  return false if scaled_src.nil?
  body = extract_func_body(scaled_src, fn)
  return false if body.nil?
  c = compact(mask_strings_and_comments(body))
  token = fn == "bodyPointSize" ? "TranscriptTypography.pointSize(for:.#{role}" : "TranscriptTypography.font(for:.#{role}"
  c.include?(token) && c.include?("scale:scale")
end

def scale_follows?(c)
  c.include?("ChatFontSettings.adjusted") &&
    !c.match?(/ChatScaledFont\.[A-Za-z]+\(scale:1\)/) &&
    !c.match?(/font\(for:[^)]*scale:1\)/)
end

def spacing_ok?(c)
  %w[withinAnswer metadataGap cardHorizontalInset cardVerticalInset codeContentInset].any? { |tok| c.include?("TranscriptTypography.#{tok}") }
end

def leading_ok?(c)
  c.include?("TranscriptTypography.textLineSpacing")
end

def typography_ok?(c, scaled_src, require_leading: true)
  font_role_ok?(c, scaled_src) && scale_follows?(c) && spacing_ok?(c) && (!require_leading || leading_ok?(c))
end

def check_scaled_font_adapter(src)
  return ["ChatScaledFont.swift が存在しない"] if src.nil?
  ng = []
  SCALED_FONT_FORWARD.each do |fn, role|
    body = extract_func_body(src, fn)
    if body.nil? || !scaled_font_forwards?(src, fn, role)
      ng << "typography 退行"
    end
  end
  ng.uniq
end

def expansion_reset?(src)
  c = compact(mask_strings_and_comments(erase_if_false(src.to_s)))
  return false unless c.include?("onChange")
  c.match?(/onChange\([^)]*\)[^{]*\{[^}]*(?:isExpanded=false|userOverride=nil|userExpandedOverride=nil)/) ||
    (c.include?("isExpanded=false") && c.include?("onChange"))
end

def short_text_direct?(c)
  c.include?("usesDisclosure") && c.include?("trimmedText")
end

def summary_only_body?(c)
  compact(c).match?(/AgentMessageBody\(text:summary/) ||
    compact(c).include?("text:presentation.subtitle") ||
    compact(c).include?("text:headline")
end

def summary_wired?(c)
  c.include?("TranscriptMarkdownPresentation.summary") &&
    (c.include?("summary:TranscriptMarkdownPresentation.summary(text)") ||
      (c.include?("TranscriptMarkdownPresentation.summary(text)") && c.include?("summary:")))
end

def reasoning_body_ok?(c, basic)
  return false unless c.include?("AgentMessageBody(")
  return false unless c.include?("text:text")
  return false if summary_only_body?(c)
  return false unless c.include?("bodyColor:")
  amb = compact_reach(basic, "AgentMessageBody")
  return false if amb.is_a?(Symbol)
  amb.include?("RichMarkdownView") && amb.include?("bodyColor")
end

def secondary_on_reasoning?(c)
  compact(c).include?("bodyColor:DSColor.chatTextSecondary") ||
    compact(c).include?("bodyColor:.secondary")
end

def has_init?(src, kind)
  !extract_init_params_and_body(src, kind).nil?
end

def init_calls_prepare?(src, kind)
  found = extract_init_params_and_body(src, kind)
  return false if found.nil?
  live_code(found[:body] + found[:params]).include?("TranscriptMarkdownPresentation.prepare") ||
    live_code(found[:body]).include?("TranscriptMarkdownPresentation.prepare")
end

def init_stores_markdown_and_color?(src, kind)
  found = extract_init_params_and_body(src, kind)
  return false if found.nil?
  c = live_code(found[:body] + found[:params])
  compact(mask_strings_and_comments(found[:params])).include?("bodyColor") &&
    (c.include?("markdown=") || c.include?("self.markdown="))
end

def view_body_calls_prepare?(src)
  struct = extract_struct_body(src, "RichMarkdownView")
  return false if struct.nil?
  body = extract_var_body(struct, "body")
  return false if body.nil?
  live_code(collect_reachable(src, body)).include?("TranscriptMarkdownPresentation.prepare")
end

def markdown_view_reach(src)
  struct = extract_struct_body(src, "RichMarkdownView")
  return "" if struct.nil?
  init_n = extract_init_body(src, :normal).to_s
  init_s = extract_init_body(src, :streaming).to_s
  body = extract_var_body(struct, "body").to_s
  collect_reachable(src, [init_n, init_s, body].join("\n"))
end

def markdown_consumes_prepare?(src)
  reach = markdown_view_reach(src)
  live = live_code(reach)
  return false unless live.include?("TranscriptMarkdownPresentation.prepare")
  return false unless live.include?("Markdown(")
  c = compact(mask_strings_and_comments(erase_if_false(reach)))
  return true if c.include?("Markdown(TranscriptMarkdownPresentation.prepare")
  return true if c.include?("markdown=TranscriptMarkdownPresentation.prepare") && c.include?("Markdown(markdown)")
  return true if c.match?(/letprepared=TranscriptMarkdownPresentation\.prepare/) && c.include?("Markdown(prepared)")
  false
end

def prepare_token_present?(src)
  compact(mask_strings_and_comments(erase_if_false(src.to_s))).include?("TranscriptMarkdownPresentation.prepare")
end

def check_markdown_entries(src)
  ng = missing_struct(src, "RichMarkdownView", "RichMarkdownView")
  return ng unless ng.empty?
  body_prep = view_body_calls_prepare?(src)
  unless has_init?(src, :normal) && init_stores_markdown_and_color?(src, :normal) && (body_prep || init_calls_prepare?(src, :normal))
    ng << "通常入口未接続"
  end
  unless has_init?(src, :streaming) && init_stores_markdown_and_color?(src, :streaming) && (body_prep || init_calls_prepare?(src, :streaming))
    ng << "streaming 入口未接続"
  end
  if prepare_token_present?(markdown_view_reach(src)) && !markdown_consumes_prepare?(src)
    ng << "補正結果未使用"
  end
  ng.uniq
end

def theme_func_reach(src)
  parts = [extract_func_body(src, "theme"), extract_func_body(src, "chatMarkdownTheme")].compact
  collect_reachable(src, parts.join("\n"))
end

def theme_cache_has_color_role?(src)
  indexed = code_only_indexed(src.to_s)
  m = indexed.match(/func\s+themeCacheKey\s*\(/)
  return false unless m
  paren = indexed.index("(", m.begin(0))
  return false unless paren
  params = extract_balanced(src, paren, "(", ")")
  return false if params.nil?
  body = extract_func_body(src, "themeCacheKey")
  return false if body.nil?
  compact(mask_strings_and_comments(params)).include?("bodyColor") &&
    compact(strip_comments(body)).include?("bodyColor")
end

def theme_body_primary_locked?(src)
  reach = theme_func_reach(src)
  return true if reach.to_s.strip.empty?
  c = live_code(reach)
  !c.include?("ForegroundColor(bodyColor)")
end

def answer_default_primary?(src)
  amb = extract_struct_body(src, "AgentMessageBody")
  return false if amb.nil?
  indexed = code_only_indexed(amb)
  params = []
  amb.scan(/\binit\s*\(/) do
    paren = indexed.index("(", $~.begin(0))
    next unless paren
    extracted = extract_balanced(amb, paren, "(", ")")
    params << extracted if extracted
  end
  blob = compact(mask_strings_and_comments(amb + params.join))
  blob.match?(/bodyColor:Color=DSColor\.chatTextPrimary/) || blob.match?(/bodyColor=DSColor\.chatTextPrimary/)
end

def check_reasoning(src, basic, scaled_src)
  ng = missing_struct(src, "ReasoningSummaryView", "ReasoningSummaryView")
  return ng unless ng.empty?
  c = compact_reach(src, "ReasoningSummaryView")
  return ["ReasoningSummaryView を解析できない"] if c.is_a?(Symbol)
  ng << "思考詳細から分類モデルが未接続" unless c.include?("TranscriptItemPresentation.reasoning") && c.match?(/presentation\.(heading|subtitle|isVisible)/)
  ng << "思考の見出しが分類モデルから届いていない" unless c.include?("presentation.heading")
  ng << "思考の補足が summary(text) から届いていない" unless summary_wired?(c) && c.include?("presentation.subtitle")
  if short_text_direct?(c)
    ng << "短文直接表示"
  elsif summary_only_body?(c)
    ng << "要約だけの本文"
  elsif !reasoning_body_ok?(c, basic)
    ng << "思考の展開本文へ原文が届いていない"
  elsif !secondary_on_reasoning?(c)
    ng << "secondary 転送欠落"
  end
  ng << "typography 退行" unless typography_ok?(c, scaled_src)
  ng << "開閉リセット" if expansion_reset?(src)
  ng.uniq
end

def check_answer(src, scaled_src)
  ng = missing_struct(src, "AgentMessageBody", "AgentMessageBody")
  return ng unless ng.empty?
  c = compact_reach(src, "AgentMessageBody")
  return ["AgentMessageBody を解析できない"] if c.is_a?(Symbol)
  ng << "回答が詳細カードへ収納されている" if c.include?("DisclosureCard")
  ng << "回答既定色の変更" unless answer_default_primary?(src)
  ng << "typography 退行" unless spacing_ok?(c) && scale_follows?(c)
  ng
end

def check_empty_thinking(src)
  return ["ChatMessageCells.swift が存在しない"] if src.nil?
  c = compact(mask_strings_and_comments(src))
  unless c.include?("trimmingCharacters") && c.include?("EmptyView") && c.include?("reasoning")
    return ["空判定変更"]
  end
  if c.match?(/reasoning[^{]*summary[^{]*nil[^{]*EmptyView/) || c.include?("summary==nil") && c.include?("EmptyView") && c.include?("reasoning")
    return ["空判定変更"]
  end
  []
end

def code_prepare_leak?(basic, structured, formatting)
  amb = compact_reach(basic, "AgentMessageBody")
  unless amb.is_a?(Symbol)
    return true if compact(amb).match?(/CodeBlockView\([^)]*TranscriptMarkdownPresentation\.prepare/)
  end
  cmd = compact_reach(structured, "CommandExecutionCell")
  unless cmd.is_a?(Symbol)
    return true if cmd.include?("TranscriptMarkdownPresentation.prepare")
  end
  err = compact_reach(basic, "ErrorMessageCell")
  unless err.is_a?(Symbol)
    return true if err.include?("TranscriptMarkdownPresentation.prepare")
  end
  user = compact_reach(basic, "UserMessageCell")
  unless user.is_a?(Symbol)
    return true if user.include?("TranscriptMarkdownPresentation.prepare")
  end
  file = compact_reach(structured, "FileChangeCell")
  unless file.is_a?(Symbol)
    return true if file.include?("TranscriptMarkdownPresentation.prepare")
  end
  fmt = live_code(formatting.to_s)
  return true if fmt.include?("TranscriptMarkdownPresentation.prepare")
  false
end

def copy_ok?(markdown, code_block)
  paste = extract_func_body(markdown.to_s, "copyToPasteboard")
  if paste
    c = live_code(paste)
    return false if c.include?("TranscriptMarkdownPresentation.prepare")
    return false unless c.include?("content")
  end
  code_struct = extract_struct_body(code_block.to_s, "CodeBlockView")
  if code_struct
    copy = extract_func_body(code_struct, "copyCode")
    if copy
      c = live_code(copy)
      return false if c.include?("TranscriptMarkdownPresentation.prepare")
    end
  end
  true
end

def wrap_ok?(src)
  c = compact(mask_strings_and_comments(src.to_s))
  return false unless c.include?("fixedSize(horizontal:false,vertical:true)")
  table = c[/\.table\{.*?\}/m]
  if table && table.include?("fixedSize(horizontal:false,vertical:true)")
    return false
  end
  true
end

def check_product(files)
  ng = []
  scaled = files[:scaled_font]
  ng.concat(check_reasoning(files[:structured], files[:basic], scaled))
  ng.concat(check_answer(files[:basic], scaled))
  ng.concat(check_markdown_entries(files[:markdown]))
  ng << "テーマ本文 primary 固定" if theme_body_primary_locked?(files[:markdown])
  ng << "色役割のキャッシュキー欠落" unless theme_cache_has_color_role?(files[:markdown])
  ng.concat(check_empty_thinking(files[:cells]))
  ng << "コードへの補正" if code_prepare_leak?(files[:basic], files[:structured], files[:formatting])
  ng << "コピー変更" unless copy_ok?(files[:markdown], files[:code_block])
  ng.concat(check_scaled_font_adapter(scaled))
  ng.uniq
end

def protected_symbol_errors(current, previous, name, kind)
  return [] if current.nil? || previous.nil?
  cur = kind == :enum ? extract_enum_body(current, name) : extract_struct_body(current, name)
  prev = kind == :enum ? extract_enum_body(previous, name) : extract_struct_body(previous, name)
  return ["#{name} を解析できない"] if cur.nil? || prev.nil?
  return [] if normalize_code(cur) == normalize_code(prev)
  ["保護宣言変更"]
end

def extra_changed_product_paths(rev)
  tracked = IO.popen(["git", "diff", "--name-only", rev, "--", SESSION_FEATURE_SRC], err: [:child, :out], &:read)
  untracked = IO.popen(["git", "ls-files", "--others", "--exclude-standard", "--", SESSION_FEATURE_SRC], err: [:child, :out], &:read)
  names = (tracked.to_s + untracked.to_s).split("\n").reject(&:empty?).uniq
  names - ALLOWED_PRODUCT_PATHS
end

def other_struct_errors(current, previous, names)
  ng = []
  names.each do |name|
    next if current.nil? || previous.nil?
    cur = extract_struct_body(current, name)
    prev = extract_struct_body(previous, name)
    next if cur.nil? && prev.nil?
    if cur.nil? || prev.nil?
      ng << "保護宣言変更"
      next
    end
    ng << "保護宣言変更" unless normalize_code(cur) == normalize_code(prev)
  end
  ng.uniq
end

def scope_errors(current_files, baseline_files)
  ng = []
  SCOPE_PROTECTED_PATHS.each do |path|
    key = scope_key(path)
    base = baseline_files[key]
    cur = current_files[key]
    if base.nil?
      ng << "基準時点の #{path} を git show できない"
    elsif cur.nil?
      ng << "#{path} が存在しない"
    elsif !workdir_matches_git_blob?(cur, base)
      ng << "許可パス外の製品変更: #{path}"
    end
  end
  ng.concat(other_struct_errors(current_files[:basic], baseline_files[:basic], BASIC_PROTECTED_STRUCTS))
  ng.concat(other_struct_errors(current_files[:structured], baseline_files[:structured], STRUCTURED_PROTECTED_STRUCTS))
  extra = current_files[:extra_changed]
  extra.to_a.each do |path|
    ng << "許可パス外の製品変更: #{path}"
  end
  ng.uniq
end

def permanent_structure_errors(current_files, baseline_files)
  return [] if baseline_files.nil?
  ng = []
  [
    [:command_group, "CommandGroupHeader", :struct],
    [:command_group, "CommandGroupOutputDisplay", :struct],
    [:common, "DisclosureCard", :struct],
    [:structured, "SubAgentMarkerCell", :struct],
  ].each do |key, name, kind|
    next if current_files[key].nil? || baseline_files[key].nil?
    ng.concat(protected_symbol_errors(current_files[key], baseline_files[key], name, kind))
  end
  unless copy_ok?(current_files[:markdown], current_files[:code_block])
    ng << "コピー変更"
  end
  ng.uniq
end

def scope_key(path)
  {
    CELLS_PATH => :cells,
    COMMON_PATH => :common,
    RENDER_CACHE_PATH => :render_cache,
    FORMATTING_PATH => :formatting,
    MARKDOWN_PATH => :markdown,
    BASIC_PATH => :basic,
    STRUCTURED_PATH => :structured,
    COMMAND_GROUP_PATH => :command_group,
    TASK_LIST_PATH => :task_list,
    RECAP_PATH => :recap,
    SCALED_FONT_PATH => :scaled_font,
    CODE_BLOCK_PATH => :code_block,
    PRESENTATION_PATH => :presentation,
  }[path]
end

def worktree_files(baseline_rev = nil)
  files = {
    structured: read_if_exist(STRUCTURED_PATH),
    basic: read_if_exist(BASIC_PATH),
    command_group: read_if_exist(COMMAND_GROUP_PATH),
    task_list: read_if_exist(TASK_LIST_PATH),
    cells: read_if_exist(CELLS_PATH),
    common: read_if_exist(COMMON_PATH),
    render_cache: read_if_exist(RENDER_CACHE_PATH),
    formatting: read_if_exist(FORMATTING_PATH),
    markdown: read_if_exist(MARKDOWN_PATH),
    recap: read_if_exist(RECAP_PATH),
    scaled_font: read_if_exist(SCALED_FONT_PATH),
    code_block: read_if_exist(CODE_BLOCK_PATH),
    presentation: read_if_exist(PRESENTATION_PATH),
  }
  files[:extra_changed] = extra_changed_product_paths(baseline_rev) if baseline_rev
  files
end

def baseline_files(rev)
  {
    structured: git_show(rev, STRUCTURED_PATH),
    basic: git_show(rev, BASIC_PATH),
    command_group: git_show(rev, COMMAND_GROUP_PATH),
    task_list: git_show(rev, TASK_LIST_PATH),
    cells: git_show(rev, CELLS_PATH),
    common: git_show(rev, COMMON_PATH),
    render_cache: git_show(rev, RENDER_CACHE_PATH),
    formatting: git_show(rev, FORMATTING_PATH),
    markdown: git_show(rev, MARKDOWN_PATH),
    recap: git_show(rev, RECAP_PATH),
    scaled_font: git_show(rev, SCALED_FONT_PATH),
    code_block: git_show(rev, CODE_BLOCK_PATH),
    presentation: git_show(rev, PRESENTATION_PATH),
  }
end

def evaluate_checks(files, baseline_blobs, scope:)
  ng = []
  ng.concat(check_product(files))
  ng.concat(permanent_structure_errors(files, baseline_blobs))
  ng.concat(scope_errors(files, baseline_blobs)) if scope
  ng.uniq
end

def good_markdown
  <<~SWIFT
    public struct RichMarkdownView: View {
      @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      private let markdown: String
      var bodyColor: Color = DSColor.chatTextPrimary
      public init(_ markdown: String, bodyColor: Color = DSColor.chatTextPrimary) {
        self.markdown = TranscriptMarkdownPresentation.prepare(markdown)
        self.bodyColor = bodyColor
      }
      public init(streaming markdown: String, bodyColor: Color = DSColor.chatTextPrimary) {
        self.markdown = TranscriptMarkdownPresentation.prepare(markdown)
        self.bodyColor = bodyColor
      }
      public var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        Markdown(markdown)
          .markdownTheme(Self.theme(for: themeID, scale: scale, bodyColor: bodyColor))
          .environment(\\.openURL, OpenURLAction(handler: openChatMarkdownLink))
      }
      static func theme(for themeID: String, scale: CGFloat, bodyColor: Color) -> Theme {
        let cacheKey = themeCacheKey(themeID: themeID, scale: scale, bodyColor: bodyColor)
        return chatMarkdownTheme(scale: scale, bodyColor: bodyColor)
      }
      static func themeCacheKey(themeID: String, scale: CGFloat, bodyColor: Color) -> String {
        "\\(themeID):\\(scale):\\(bodyColor)"
      }
    }
    private func chatMarkdownTheme(scale: CGFloat, bodyColor: Color) -> Theme {
      Theme()
        .text { ForegroundColor(bodyColor); FontSize(ChatTypography.bodyFontSize(scale: scale)) }
        .heading1 { configuration in
          configuration.label.fixedSize(horizontal: false, vertical: true)
            .markdownTextStyle { ForegroundColor(bodyColor); FontWeight(.bold) }
        }
        .paragraph { configuration in
          configuration.label.fixedSize(horizontal: false, vertical: true)
            .lineSpacing(TranscriptTypography.textLineSpacing)
        }
        .listItem { configuration in
          configuration.label.fixedSize(horizontal: false, vertical: true)
        }
        .code { ForegroundColor(DSColor.chatAccent) }
        .link { ForegroundColor(DSColor.chatAccent) }
        .codeBlock { configuration in
          Button { copyToPasteboard(configuration.content) } label: { Text("Copy") }
        }
        .table { configuration in configuration.label }
    }
    private func copyToPasteboard(_ content: String) {
      NSPasteboard.general.setString(content, forType: .string)
    }
    private func openChatMarkdownLink(_ url: URL) -> OpenURLAction.Result { .handled }
    @ViewBuilder
    private func highlightedCode(_ content: String, language _: String?) -> some View {
      Text(content)
    }
  SWIFT
end

def good_basic
  <<~SWIFT
    struct AgentMessageBody: View {
      let text: String
      var bodyColor: Color = DSColor.chatTextPrimary
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {
          ForEach(Array(ChatMessageRenderCache.markdownBlocks(text).enumerated()), id: \\.offset) { _, block in
            switch block {
            case .markdown(let markdown):
              RichMarkdownView(markdown, bodyColor: bodyColor)
            case .code(let language, let code):
              CodeBlockView(language: language, code: code)
            }
          }
        }
      }
    }
    struct AgentMessageCell: View {
      var body: some View { AgentMessageBody(text: text) }
    }
    struct UserMessageCell: View {
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        Text(text).font(ChatScaledFont.body(scale: scale))
      }
    }
    struct ErrorMessageCell: View {
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        Text(message).font(ChatScaledFont.body(scale: scale))
          .lineSpacing(TranscriptTypography.textLineSpacing)
      }
    }
    struct TurnCostCell: View {
      var body: some View { Text("cost") }
    }
  SWIFT
end

def good_structured
  <<~SWIFT
    struct ReasoningSummaryView: View {
      let text: String
      @State private var userOverride: Bool?
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = TranscriptItemPresentation.reasoning(
          text: text,
          summary: TranscriptMarkdownPresentation.summary(text)
        )
        if presentation.isVisible {
          DisclosureCard(
            isExpanded: Binding(
              get: { TranscriptItemPresentation.isExpanded(userOverride: userOverride, defaultExpanded: presentation.defaultExpanded) },
              set: { userOverride = $0 }
            ),
            title: presentation.heading ?? "",
            subtitle: presentation.subtitle,
            isToolCall: presentation.semanticInk == .process
          ) {
            AgentMessageBody(text: text, bodyColor: DSColor.chatTextSecondary)
              .font(TranscriptTypography.font(for: .body, scale: scale))
              .lineSpacing(TranscriptTypography.textLineSpacing)
              .padding(.top, TranscriptTypography.withinAnswer)
          }
        }
      }
    }
    struct CommandExecutionCell: View {
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        Text(output).font(ChatScaledFont.monoCaption(scale: scale))
      }
    }
    struct ThinkingIndicatorCell: View {
      var body: some View {
        Text(state.orbLabel).accessibilityLabel(state.orbLabel)
      }
    }
    struct FileChangeCell: View {
      var body: some View { Text("diff") }
    }
    struct SubAgentMarkerCell: View {
      var body: some View { Button { onSelect?(id) } label: { Text("sub") } }
    }
  SWIFT
end

def good_cells
  <<~SWIFT
    public struct ChatItemView: View {
      public var body: some View {
        switch item {
        case .reasoning(_, let text, let timestamp):
          if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
          } else {
            ReasoningSummaryView(text: text, timestamp: timestamp)
          }
        default:
          EmptyView()
        }
      }
    }
  SWIFT
end

def good_scaled_font
  <<~SWIFT
    enum ChatScaledFont {
      static func body(scale: CGFloat) -> Font { TranscriptTypography.font(for: .body, scale: scale) }
      static func bodyPointSize(scale: CGFloat) -> CGFloat { TranscriptTypography.pointSize(for: .body, scale: scale) }
      static func caption(scale: CGFloat) -> Font { TranscriptTypography.font(for: .metadata, scale: scale) }
      static func captionStrong(scale: CGFloat) -> Font { TranscriptTypography.font(for: .metadataStrong, scale: scale) }
      static func mono(scale: CGFloat) -> Font { TranscriptTypography.font(for: .code, scale: scale) }
      static func monoCaption(scale: CGFloat) -> Font { TranscriptTypography.font(for: .codeMetadata, scale: scale) }
    }
  SWIFT
end

def good_code_block
  <<~SWIFT
    struct CodeBlockView: View {
      let language: String?
      let code: String
      var body: some View { Text(code) }
      private func copyCode() {
        NSPasteboard.general.setString(code, forType: .string)
      }
    }
  SWIFT
end

def good_files
  {
    structured: good_structured,
    basic: good_basic,
    command_group: "struct CommandGroupHeader { let isRunning: Bool }\nstruct CommandGroupOutputDisplay { let copyText: String }",
    task_list: "struct TaskListCell: View { var body: some View { Text(\"t\") } }",
    cells: good_cells,
    common: "struct DisclosureCard<Content: View>: View { var body: some View { content } }",
    render_cache: "enum ChatMessageRenderCache { static func markdownBlocks(_ text: String) -> [ChatMarkdownBlock] { [] } }",
    formatting: "enum ChatMarkdownFormatter { static func splitFencedCodeBlocks(_ text: String) -> [ChatMarkdownBlock] { [] } }",
    markdown: good_markdown,
    recap: "enum CommandGroupTitle {}",
    scaled_font: good_scaled_font,
    code_block: good_code_block,
    presentation: "enum TranscriptMarkdownPresentation { static func prepare(_ source: String) -> String { source }\n static func summary(_ source: String) -> String? { nil } }",
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
    puts "task47-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task47-wiring --selftest: FAIL #{msg}"
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
  interp = %(let s = "\\(TranscriptMarkdownPresentation.prepare(src))" // note)
  selftest_assert strip_comments(interp).include?("TranscriptMarkdownPresentation.prepare"), "正例: 補間文字列を保持する"
  spaced = %(Text("hello world"))
  selftest_assert normalize_code(spaced).include?("hello world"), "正例: 文字列内空白を正規化で消さない"

  good = good_files
  selftest_errors_eq check_product(good), [], "正例: 契約どおりの配線は空 NG"
  selftest_errors_eq permanent_structure_errors(good, good), [], "正例: 恒久構造比較は同一 blob で空"

  commented = with_file(good, :structured) { |src|
    src + %(\n// TranscriptMarkdownPresentation.prepare\nlet decoy = "TranscriptTypography"\n)
  }
  selftest_errors_eq check_product(commented), [], "正例: コメント・文字列だけを加える"

  no_normal = with_file(good, :markdown) { |src|
    src.sub(
      /init\(_ markdown: String, bodyColor: Color = DSColor\.chatTextPrimary\) \{[^}]*\}/m,
      "init(_ markdown: String, bodyColor: Color = DSColor.chatTextPrimary) {\n    self.markdown = markdown\n    self.bodyColor = bodyColor\n  }"
    )
  }
  selftest_errors_eq check_markdown_entries(no_normal[:markdown]), ["通常入口未接続"], "負例: 通常入口未接続"

  no_stream = with_file(good, :markdown) { |src|
    src.sub(
      /init\(streaming markdown: String, bodyColor: Color = DSColor\.chatTextPrimary\) \{[^}]*\}/m,
      "init(streaming markdown: String, bodyColor: Color = DSColor.chatTextPrimary) {\n    self.markdown = markdown\n    self.bodyColor = bodyColor\n  }"
    )
  }
  selftest_errors_eq check_markdown_entries(no_stream[:markdown]), ["streaming 入口未接続"], "負例: streaming 入口未接続"

  unused = with_file(good, :markdown) { |src|
    src.sub("Markdown(markdown)", "Markdown(raw)")
  }
  selftest_errors_eq check_markdown_entries(unused[:markdown]), ["補正結果未使用"], "負例: 補正結果未使用"

  short = with_file(good, :structured) { |src|
    src.sub(
      "if presentation.isVisible {",
      "if presentation.usesDisclosure { let trimmedText = text"
    )
  }
  selftest_errors_eq check_reasoning(short[:structured], short[:basic], short[:scaled_font]), ["短文直接表示"], "負例: 短文直接表示"

  summary_only = with_file(good, :structured) { |src|
    src.sub("AgentMessageBody(text: text, bodyColor: DSColor.chatTextSecondary)", "AgentMessageBody(text: summary, bodyColor: DSColor.chatTextSecondary)")
  }
  selftest_errors_eq check_reasoning(summary_only[:structured], summary_only[:basic], summary_only[:scaled_font]), ["要約だけの本文"], "負例: 要約だけの本文"

  no_secondary = with_file(good, :structured) { |src|
    src.sub("bodyColor: DSColor.chatTextSecondary", "bodyColor: DSColor.chatTextPrimary")
  }
  selftest_errors_eq check_reasoning(no_secondary[:structured], no_secondary[:basic], no_secondary[:scaled_font]), ["secondary 転送欠落"], "負例: secondary 転送欠落"

  locked = with_file(good, :markdown) { |src|
    src.gsub("ForegroundColor(bodyColor)", "ForegroundColor(DSColor.chatTextPrimary)")
  }
  selftest_errors_eq check_product(locked), ["テーマ本文 primary 固定"], "負例: テーマ本文 primary 固定"

  no_key = with_file(good, :markdown) { |src|
    src.sub(
      "func themeCacheKey(themeID: String, scale: CGFloat, bodyColor: Color)",
      "func themeCacheKey(themeID: String, scale: CGFloat)"
    ).sub(
      "themeCacheKey(themeID: themeID, scale: scale, bodyColor: bodyColor)",
      "themeCacheKey(themeID: themeID, scale: scale)"
    )
  }
  selftest_errors_eq check_product(no_key), ["色役割のキャッシュキー欠落"], "負例: 色役割のキャッシュキー欠落"

  bad_default = with_file(good, :basic) { |src|
    src.gsub("bodyColor: Color = DSColor.chatTextPrimary", "bodyColor: Color = DSColor.chatTextSecondary")
  }
  selftest_errors_eq check_answer(bad_default[:basic], bad_default[:scaled_font]), ["回答既定色の変更"], "負例: 回答既定色の変更"

  code_prep = with_file(good, :basic) { |src|
    src.sub("CodeBlockView(language: language, code: code)", "CodeBlockView(language: language, code: TranscriptMarkdownPresentation.prepare(code))")
  }
  selftest_errors_eq check_product(code_prep), ["コードへの補正"], "負例: コードへの補正"

  copy_ng = with_file(good, :markdown) { |src|
    src.sub("setString(content, forType: .string)", "setString(TranscriptMarkdownPresentation.prepare(content), forType: .string)")
  }
  selftest_errors_eq check_product(copy_ng), ["コピー変更"], "負例: コピー変更"

  reset = with_file(good, :structured) { |src|
    src.sub(
      ".padding(.top, TranscriptTypography.withinAnswer)",
      ".padding(.top, TranscriptTypography.withinAnswer)\n        .onChange(of: text) { userOverride = nil; isExpanded = false }"
    )
  }
  selftest_errors_eq check_product(reset), ["開閉リセット"], "負例: 開閉リセット"

  empty_ng = with_file(good, :cells) { |src|
    src.sub(
      "if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {",
      "if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || summary == nil {"
    )
  }
  selftest_errors_eq check_empty_thinking(empty_ng[:cells]), ["空判定変更"], "負例: 空判定変更"

  protected_ng = with_file(good, :command_group) { |src|
    src.sub("struct CommandGroupHeader { let isRunning: Bool }", "struct CommandGroupHeader { let isRunning: Bool; let extra: Bool }")
  }
  selftest_errors_eq permanent_structure_errors(protected_ng, good), ["保護宣言変更"], "負例: 保護宣言変更"

  no_font = with_file(good, :structured) { |src|
    src.sub("TranscriptTypography.font(for: .body, scale: scale)", "Font.system(size: 13)")
      .sub(".padding(.top, TranscriptTypography.withinAnswer)", ".padding(.top, 8)")
      .sub(".lineSpacing(TranscriptTypography.textLineSpacing)", "")
      .gsub("ChatFontSettings.adjusted(from: chatScale, by: 0)", "1")
  }
  selftest_errors_eq check_reasoning(no_font[:structured], no_font[:basic], no_font[:scaled_font]), ["typography 退行"], "負例: typography 退行"

  unused_let = with_file(good, :structured) { |src|
    src.sub(
      "let presentation = TranscriptItemPresentation.reasoning(",
      "_ = TranscriptMarkdownPresentation.summary(text)\n        let presentation = Dummy.reasoning("
    )
  }
  unused_ng = check_reasoning(unused_let[:structured], unused_let[:basic], unused_let[:scaled_font])
  selftest_assert unused_ng.include?("思考詳細から分類モデルが未接続"), "負例: 戻り値破棄 (#{unused_ng.inspect})"

  fake_decl = with_file(good, :structured) { |src|
    "/* struct ReasoningSummaryView { var body: some View { let presentation = TranscriptItemPresentation.reasoning(text: text, summary: TranscriptMarkdownPresentation.summary(text))\n AgentMessageBody(text: text, bodyColor: DSColor.chatTextSecondary) } } */\n" +
      src.gsub("TranscriptItemPresentation.reasoning(", "Dummy.reasoning(")
        .gsub("TranscriptMarkdownPresentation.summary(text)", "nil")
  }
  fake_ng = check_reasoning(fake_decl[:structured], fake_decl[:basic], fake_decl[:scaled_font])
  selftest_assert fake_ng.include?("思考詳細から分類モデルが未接続"), "負例: コメント内偽宣言 (#{fake_ng.inspect})"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_errors_eq unset_errs, ["TASK47_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: 基準の未設定"
  selftest_assert unset.nil?, "負例: 未設定は nil"
  _invalid, invalid_errs = baseline_env_errors("not-a-sha")
  selftest_errors_eq invalid_errs, ["TASK47_BASELINE がコミット SHA ではない（ブランチ名は使えない）: not-a-sha"], "負例: SHA 不正"
  _head, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK47_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD 指定"
  _head1, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK47_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD~1 指定"
  _at, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK47_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: @ 指定"
  _branch, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK47_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
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
  selftest_errors_eq real_mismatch, ["TASK47_BASELINE が契約 baseline_commit と一致しない"], "負例: 契約不一致"

  same_blob = "frozen\n"
  artifacts_ok = {
    markdown_blob: nil,
    item_blob: "struct TranscriptItemPresentation {}",
    typography_blob: "public enum TranscriptTypography {}",
    test_blobs: [same_blob, same_blob],
    test_nows: [same_blob, same_blob],
    rb_blob: same_blob,
    rb_now: same_blob,
  }
  selftest_errors_eq check_frozen_baseline(head_full, artifacts_ok), [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  post_ng = check_frozen_baseline(head_full, artifacts_ok.merge(markdown_blob: "enum TranscriptMarkdownPresentation {}"))
  selftest_errors_eq post_ng, ["基準時点に TranscriptMarkdownPresentation.swift がある（実装前の凍結ではない）"], "負例: 実装済み基準"

  no_task46 = check_frozen_baseline(head_full, artifacts_ok.merge(item_blob: nil))
  selftest_errors_eq no_task46, ["基準時点に TranscriptItemPresentation.swift が無い（task-46 完了状態ではない）"], "負例: task-46 完了状態が基準に無い"

  no_task40 = check_frozen_baseline(head_full, artifacts_ok.merge(typography_blob: nil))
  selftest_errors_eq no_task40, ["基準時点に TranscriptTypography.swift が無い（task-40 完了状態ではない）"], "負例: task-40 完了状態が基準に無い"

  git_fail = check_frozen_baseline(head_full, artifacts_ok.merge(markdown_error: "fatal: bad object"))
  selftest_errors_eq git_fail, ["基準時点の TranscriptMarkdownPresentation.swift を git show できない: fatal: bad object"], "負例: 基準 git 障害"

  missing_md = check_frozen_baseline(head_full, artifacts_ok.merge(markdown_blob: nil))
  selftest_errors_eq missing_md, [], "正例: 新規製品ファイルの基準不存在は git 障害ではない"

  selftest_errors_eq blob_fetch_errors("rb 自身", { status: :ok, text: "now" }, "frozen"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 凍結検査の改変"
  selftest_errors_eq blob_fetch_errors("受け入れテスト1", { status: :git_error, text: nil, stderr: "fatal: foo" }, "now"), ["基準時点の受け入れテスト1を git show できない: fatal: foo"], "負例: blob 取得失敗"
  selftest_errors_eq blob_fetch_errors("受け入れテスト1", { status: :missing, text: nil, stderr: "" }, "now"), ["基準時点の受け入れテスト1が無い"], "負例: 基準ファイル不存在"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "same", "same"), [], "正例: 凍結 rb と作業ツリーが同一"

  forced_non_ancestor = check_frozen_baseline(head_full, artifacts_ok.merge(is_ancestor: false))
  selftest_errors_eq forced_non_ancestor, ["TASK47_BASELINE が HEAD の祖先ではない"], "負例: 非祖先"

  out_of_scope = good.merge(extra_changed: [CELLS_PATH])
  selftest_errors_eq scope_errors(out_of_scope, good), ["許可パス外の製品変更: #{CELLS_PATH}"], "負例: scope のみで拒否すべき範囲外変更"
  selftest_errors_eq check_product(good.merge(cells: good[:cells])), [], "正例: scope なしでは範囲外パスを範囲違反にしない"

  unset_ng = evaluate_checks(out_of_scope, good, scope: false)
  one_ng = evaluate_checks(out_of_scope, good, scope: true)
  selftest_errors_eq unset_ng, [], "正例: 未設定/0 相当は範囲外変更を恒久 NG にしない"
  selftest_errors_eq one_ng, ["許可パス外の製品変更: #{CELLS_PATH}"], "負例: SCOPE_CHECK=1 の本番判定"

  with_env("TASK47_SCOPE_CHECK", "1") { selftest_assert scope_check_requested?, "正例: SCOPE_CHECK=1" }
  with_env("TASK47_SCOPE_CHECK", "0") { selftest_assert !scope_check_requested?, "正例: SCOPE_CHECK=0 では恒久のみ" }
  with_env("TASK47_SCOPE_CHECK", nil) { selftest_assert !scope_check_requested?, "正例: 未設定では恒久のみ" }
  unset_pred = nil
  zero_pred = nil
  one_pred = nil
  with_env("TASK47_SCOPE_CHECK", nil) { unset_pred = scope_check_requested? }
  with_env("TASK47_SCOPE_CHECK", "0") { zero_pred = scope_check_requested? }
  with_env("TASK47_SCOPE_CHECK", "1") { one_pred = scope_check_requested? }
  selftest_errors_eq evaluate_checks(out_of_scope, good, scope: unset_pred), [], "正例: 未設定の本番分岐"
  selftest_errors_eq evaluate_checks(out_of_scope, good, scope: zero_pred), [], "正例: SCOPE_CHECK=0 の本番分岐"
  selftest_errors_eq evaluate_checks(out_of_scope, good, scope: one_pred), ["許可パス外の製品変更: #{CELLS_PATH}"], "正例: SCOPE_CHECK=1 の本番分岐"

  permanent_fail = with_file(good, :markdown) { |src|
    src.gsub("ForegroundColor(bodyColor)", "ForegroundColor(DSColor.chatTextPrimary)")
  }
  selftest_errors_eq evaluate_checks(permanent_fail, good, scope: false), ["テーマ本文 primary 固定"], "負例: 恒久契約違反は scope なしでも失敗"
  selftest_errors_eq evaluate_checks(permanent_fail, good, scope: true), ["テーマ本文 primary 固定"], "負例: 恒久契約違反は scope ありでも失敗"

  prod = production_checks_source
  selftest_assert !prod.empty?, "正例: 本番検査セクションが存在する"
  selftest_assert baseline_check_connected?(prod), "正例: 基準検査が本番に接続されている"
  selftest_assert scope_check_gated?(prod), "正例: 変更範囲検査が TASK47_SCOPE_CHECK でゲートされている"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task47-wiring --selftest: OK"
  exit 0
end

# === task47 production checks ===
ng = []

raw = ENV["TASK47_BASELINE"]
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
    ng << "TASK47_BASELINE が無効なコミット: #{baseline}"
    baseline = nil
  else
    ng.concat(check_frozen_baseline(full))
    base_blobs = baseline_files(full)
    files = worktree_files(full)
    ng.concat(permanent_structure_errors(files, base_blobs))
    if baseline && scope_check_requested?
      ng.concat(scope_errors(files, base_blobs))
    end
    baseline = full
  end
end

ng = ng.uniq
if ng.empty?
  puts "task47-wiring: OK"
else
  ng.each { |m| puts "task47-wiring: NG #{m}" }
  exit 1
end
