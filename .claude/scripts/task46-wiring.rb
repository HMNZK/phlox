#!/usr/bin/env ruby
# task-46 配線検査: TranscriptItemPresentation が見出し・補足・意味色・開閉へ届き、
# TranscriptTypography 参照が実描画経路に残り、TASK46_BASELINE の凍結テストと
# 変更禁止対象が契約どおりであること。
# コメントと文字列は同時識別する（task43-wiring.rb と同じ字句走査）。
# 比較対象は git show <TASK46_BASELINE>:<path> と作業ファイル。HEAD blob は使わない。

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
  compact(src).gsub(/_=(?:TranscriptItemPresentation|TranscriptTypography|ChatScaledFont|ChatTypography)(?:\.[A-Za-z0-9_]+)*/, "")
end

def strip_dead_model_lets(c)
  s = c.dup
  s.gsub(/let([A-Za-z_][A-Za-z0-9_]*)=TranscriptItemPresentation\.[A-Za-z0-9_]+\([^)]*\)/) do
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

CONTRACT_PATH = "tasks/task-46.md"
WIRING_RB_PATH = ".claude/scripts/task46-wiring.rb"
PRESENTATION_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptItemPresentation.swift"
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
RECAP_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatRecap.swift"
SCALED_FONT_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatScaledFont.swift"
SESSION_FEATURE_SRC = "macos/Packages/SessionFeature/Sources/SessionFeature"

TEST_PRESENTATION = "macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptItemPresentationTests.swift"
TEST_VISUAL = "macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask46Tests.swift"

ACCEPTANCE_PATHS = [TEST_PRESENTATION, TEST_VISUAL].freeze
PRODUCTION_MARKER = "# === task46 production checks ==="
ALLOWED_PRODUCT_PATHS = [
  PRESENTATION_PATH,
  BASIC_PATH,
  STRUCTURED_PATH,
  COMMAND_GROUP_PATH,
  TASK_LIST_PATH,
].freeze
SCOPE_PROTECTED_PATHS = [
  CELLS_PATH,
  COMMON_PATH,
  RENDER_CACHE_PATH,
  FORMATTING_PATH,
  MARKDOWN_PATH,
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
        errs << "TASK46_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK46_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK46_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK46_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
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

def implementation_in_baseline_errors(presentation_blob, typography_blob, presentation_error: nil, typography_error: nil)
  ng = []
  if presentation_error
    ng << "基準時点の TranscriptItemPresentation.swift を git show できない: #{presentation_error}"
  elsif presentation_blob
    ng << "基準時点に TranscriptItemPresentation.swift がある（実装前の凍結ではない）"
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
    ng << "TASK46_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  ancestor_ok = if artifacts && artifacts.key?(:is_ancestor)
    artifacts[:is_ancestor]
  else
    git_is_ancestor?(full, "HEAD")
  end
  unless ancestor_ok
    ng << "TASK46_BASELINE が HEAD の祖先ではない"
  end
  if artifacts
    ng.concat(implementation_in_baseline_errors(
      artifacts[:presentation_blob],
      artifacts[:typography_blob],
      presentation_error: artifacts[:presentation_error],
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
    pres = git_show_result(full, PRESENTATION_PATH)
    typo = git_show_result(full, TYPOGRAPHY_PATH)
    ng.concat(implementation_in_baseline_errors(
      pres[:status] == :ok ? pres[:text] : nil,
      typo[:status] == :ok ? typo[:text] : nil,
      presentation_error: (pres[:status] == :git_error ? pres[:stderr] : nil),
      typography_error: (typo[:status] == :git_error ? typo[:stderr] : nil)
    ))
    if typo[:status] == :missing
      # implementation_in_baseline_errors already added the task-40 missing message when blob is nil
    end
    ACCEPTANCE_PATHS.each_with_index do |path, idx|
      ng.concat(blob_fetch_errors("受け入れテスト#{idx + 1}", git_show_result(full, path), read_if_exist(path)))
    end
    ng.concat(blob_fetch_errors("rb 自身", git_show_result(full, WIRING_RB_PATH), read_if_exist(WIRING_RB_PATH)))
  end
  ng
end

def scope_check_requested?(env = ENV)
  env["TASK46_SCOPE_CHECK"] == "1"
end

def missing_struct(src, name, label)
  return ["#{label} が存在しない"] if src.nil?
  reach = struct_reachable(src, name)
  return ["#{name} が存在しない"] if reach == :missing
  return ["#{name} を解析できない"] if reach == :unparseable
  []
end

def model_used?(c, factory)
  c.include?(factory) && c.match?(/presentation\.(heading|subtitle|isVisible|defaultExpanded|semanticInk|expandedBody)/)
end

def operable_binding?(c)
  return false if c.include?("constant(true)") || c.include?("constant(false)")
  c.include?("Binding(") && c.include?("get:") && c.include?("set:") &&
    c.include?("TranscriptItemPresentation.isExpanded")
end

def short_text_direct?(c)
  c.include?("usesDisclosure") && c.include?("trimmedText")
end

def expansion_reset?(src)
  c = compact(mask_strings_and_comments(erase_if_false(src.to_s)))
  return false unless c.include?("onChange")
  c.match?(/onChange\([^)]*\)[^{]*\{[^}]*(?:isExpanded=false|userOverride=nil|userExpandedOverride=nil)/) ||
    (c.include?("isExpanded=false") && c.include?("onChange"))
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

def typography_errors(c, scaled_src, label, require_leading: true)
  ng = []
  ng << "#{label}のフォント役割が無い" unless font_role_ok?(c, scaled_src)
  ng << "#{label}の倍率追随が無い" unless scale_follows?(c)
  ng << "#{label}の余白接続が無い" unless spacing_ok?(c)
  ng << "#{label}の行間接続が無い" if require_leading && !leading_ok?(c)
  ng
end

def check_scaled_font_adapter(src)
  return ["ChatScaledFont.swift が存在しない"] if src.nil?
  ng = []
  SCALED_FONT_FORWARD.each do |fn, role|
    body = extract_func_body(src, fn)
    if body.nil?
      ng << "ChatScaledFont が TranscriptTypography へ委譲していない"
      next
    end
    unless scaled_font_forwards?(src, fn, role)
      ng << "ChatScaledFont が TranscriptTypography へ委譲していない"
    end
  end
  ng.uniq
end

def reasoning_body_ok?(c, basic)
  return true if c.match?(/\bText\(text\)/)
  if c.include?("RichMarkdownView(") && (c.include?("bodyColor") || c.include?("chatTextSecondary"))
    return true
  end
  if c.include?("AgentMessageBody(")
    return false unless c.include?("text:text")
    return false if c.include?("text:summary") || c.include?("text:presentation.subtitle")
    return false unless c.include?("bodyColor:")
    amb = compact_reach(basic, "AgentMessageBody")
    return false if amb.is_a?(Symbol)
    return amb.include?("RichMarkdownView") && amb.include?("bodyColor")
  end
  false
end

def check_reasoning(src, basic, scaled_src)
  ng = missing_struct(src, "ReasoningSummaryView", "ReasoningSummaryView")
  return ng unless ng.empty?
  c = compact_reach(src, "ReasoningSummaryView")
  return ["ReasoningSummaryView を解析できない"] if c.is_a?(Symbol)
  ng << "思考詳細から分類モデルが未接続" unless model_used?(c, "TranscriptItemPresentation.reasoning")
  ng << "思考の見出しが分類モデルから届いていない" unless c.include?("presentation.heading")
  ng << "思考の補足が分類モデルから届いていない" unless c.include?("presentation.subtitle")
  ng << "思考の意味色が分類モデルから届いていない" unless c.include?("presentation.semanticInk")
  ng << "短文だけ直接表示している" if short_text_direct?(c)
  ng << "思考詳細が DisclosureCard を使っていない" unless c.include?("DisclosureCard")
  ng << "思考の展開本文へ原文が届いていない" unless reasoning_body_ok?(c, basic)
  ng.concat(typography_errors(c, scaled_src, "思考詳細"))
  ng.concat(expansion_reset?(src) ? ["表示継続中の更新で開閉をリセットしている"] : [])
  ng
end

def check_command_single(src, scaled_src)
  ng = missing_struct(src, "CommandExecutionCell", "CommandExecutionCell")
  return ng unless ng.empty?
  c = compact_reach(src, "CommandExecutionCell")
  return ["CommandExecutionCell を解析できない"] if c.is_a?(Symbol)
  ng << "コマンド単体から分類モデルが未接続" unless model_used?(c, "TranscriptItemPresentation.command")
  ng << "コマンド単体の見出しが分類モデルから届いていない" unless c.include?("presentation.heading")
  ng << "コマンド単体の意味色が分類モデルから届いていない" unless c.include?("presentation.semanticInk")
  ng << "コマンド単体の件数が描画窓または除外後の行数になっている" if c.include?("rows.count") || c.include?("hiddenRowCount")
  ng << "コマンド単体の実行中補足が閉じたカードへ届いていない" unless c.include?("presentation.subtitle")
  ng << "コマンド単体が DisclosureCard を使っていない" unless c.include?("DisclosureCard")
  ng.concat(typography_errors(c, scaled_src, "コマンド単体", require_leading: false))
  ng
end

def check_command_group(src, scaled_src)
  ng = missing_struct(src, "CommandGroupCell", "CommandGroupCell")
  return ng unless ng.empty?
  c = compact_reach(src, "CommandGroupCell")
  return ["CommandGroupCell を解析できない"] if c.is_a?(Symbol)
  ng << "コマンドグループから分類モデルが未接続" unless model_used?(c, "TranscriptItemPresentation.command")
  ng << "コマンドグループの見出しが分類モデルから届いていない" unless c.include?("presentation.heading")
  ng << "グループの表示ガードが header.shouldRender ではない" unless c.include?("header.shouldRender")
  ng << "グループ実行中の正本が header.isRunning ではない" unless c.include?("header.isRunning")
  ng << "実行中補足が閉じたカードへ届いていない" unless c.include?("presentation.subtitle")
  ng << "件数が描画窓または除外後の行数になっている" if c.include?("rowsSlice.rows.count") || c.include?("displayRows.count")
  ng << "描画窓 CommandGroupRowWindow が無い" unless c.include?("CommandGroupRowWindow") || src.to_s.include?("CommandGroupRowWindow")
  ng.concat(typography_errors(c, scaled_src, "コマンドグループ", require_leading: false))
  copy_src = compact(mask_strings_and_comments(src.to_s))
  ng << "コピー原文の経路が無い" unless copy_src.include?("copyText")
  window_src = compact(mask_strings_and_comments(src.to_s))
  ng << "描画窓 CommandGroupRowWindow が無い" unless window_src.include?("enumCommandGroupRowWindow") || window_src.include?("CommandGroupRowWindow")
  ng.concat(expansion_reset?(src) ? ["表示継続中の更新で開閉をリセットしている"] : [])
  ng.uniq
end

def check_task(src, scaled_src)
  ng = missing_struct(src, "TaskListCell", "TaskListCell")
  return ng unless ng.empty?
  c = compact_reach(src, "TaskListCell")
  return ["TaskListCell を解析できない"] if c.is_a?(Symbol)
  ng << "タスクから分類モデルが未接続" unless model_used?(c, "TranscriptItemPresentation.taskList")
  ng << "タスクの見出しが分類モデルから届いていない" unless c.include?("presentation.heading")
  ng << "タスクの意味色が分類モデルから届いていない" unless c.include?("presentation.semanticInk")
  ng << "タスクが定数 Binding で操作できない" unless operable_binding?(c)
  ng.concat(typography_errors(c, scaled_src, "タスク", require_leading: false))
  ng.concat(expansion_reset?(src) ? ["表示継続中の更新で開閉をリセットしている"] : [])
  ng
end

def check_error(src, scaled_src)
  ng = missing_struct(src, "ErrorMessageCell", "ErrorMessageCell")
  return ng unless ng.empty?
  c = compact_reach(src, "ErrorMessageCell")
  return ["ErrorMessageCell を解析できない"] if c.is_a?(Symbol)
  ng << "エラー見出しが分類モデルから届いていない" unless c.include?("presentation.heading")
  ng << "エラー色の接続が無い" unless c.include?("statusError")
  ng.concat(typography_errors(c, scaled_src, "エラー"))
  ng
end

def check_thinking(src, scaled_src)
  ng = missing_struct(src, "ThinkingIndicatorCell", "ThinkingIndicatorCell")
  return ng unless ng.empty?
  c = compact_reach(src, "ThinkingIndicatorCell")
  return ["ThinkingIndicatorCell を解析できない"] if c.is_a?(Symbol)
  ng << "活動ラベルと AX が同じ実状態に由来していない" unless c.include?("orbLabel") && c.include?("accessibilityLabel") && c.scan("state.orbLabel").length >= 2
  ng.concat(typography_errors(c, scaled_src, "処理中", require_leading: false))
  ng
end

def check_answer(src, scaled_src)
  ng = missing_struct(src, "AgentMessageBody", "AgentMessageBody")
  return ng unless ng.empty?
  c = compact_reach(src, "AgentMessageBody")
  return ["AgentMessageBody を解析できない"] if c.is_a?(Symbol)
  ng << "回答が詳細カードへ収納されている" if c.include?("DisclosureCard")
  ng << "回答が詳細用 Binding に依存している" if c.include?("userOverride") || (c.include?("isExpanded") && c.include?("Binding"))
  ng << "回答が RichMarkdownView へ委譲していない" unless c.include?("RichMarkdownView")
  ng
end

def check_file_change(src, scaled_src)
  ng = missing_struct(src, "FileChangeCell", "FileChangeCell")
  return ng unless ng.empty?
  c = compact_reach(src, "FileChangeCell")
  return ["FileChangeCell を解析できない"] if c.is_a?(Symbol)
  ng << "ファイル変更が FileChangeDisplayPolicy.isExpanded を使っていない" unless c.include?("FileChangeDisplayPolicy.isExpanded")
  ng << "ファイル変更が defaultExpanded(lineCount:) をカード既定に流用している" if c.include?("defaultExpanded(lineCount:")
  ng.concat(typography_errors(c, scaled_src, "ファイル変更", require_leading: false))
  ng
end

def check_empty_thinking(src)
  return ["ChatMessageCells.swift が存在しない"] if src.nil?
  c = compact(mask_strings_and_comments(src))
  unless c.include?("trimmingCharacters") && c.include?("EmptyView") && c.include?("reasoning")
    return ["空思考の非表示経路が無い"]
  end
  []
end

def check_output_window(src)
  return ["CommandGroupOutputDisplay が存在しない"] if src.nil?
  body = extract_struct_body(src, "CommandGroupOutputDisplay")
  indexed = code_only_indexed(src.to_s)
  return ["CommandGroupOutputDisplay を解析できない"] if indexed.match?(/\bstruct\s+CommandGroupOutputDisplay\b/) && body.nil?
  return ["CommandGroupOutputDisplay が存在しない"] if body.nil?
  c = compact(mask_strings_and_comments(body))
  ng = []
  ng << "描画窓の出力20行上限が無い" unless c.include?("visibleLineLimit=20") || c.include?("staticletvisibleLineLimit=20")
  ng
end

def check_product(files)
  ng = []
  scaled = files[:scaled_font]
  ng.concat(check_reasoning(files[:structured], files[:basic], scaled))
  ng.concat(check_command_single(files[:structured], scaled))
  ng.concat(check_command_group(files[:command_group], scaled))
  ng.concat(check_task(files[:task_list], scaled))
  ng.concat(check_error(files[:basic], scaled))
  ng.concat(check_thinking(files[:structured], scaled))
  ng.concat(check_answer(files[:basic], scaled))
  ng.concat(check_file_change(files[:structured], scaled))
  ng.concat(check_empty_thinking(files[:cells]))
  ng.concat(check_output_window(files[:command_group]))
  ng.concat(check_scaled_font_adapter(scaled))
  ng.uniq
end

def agent_message_body_errors(current, previous)
  return [] if current.nil? || previous.nil?
  cur = extract_struct_body(current, "AgentMessageBody")
  prev = extract_struct_body(previous, "AgentMessageBody")
  return ["AgentMessageBody を解析できない"] if cur.nil? || prev.nil?
  cur_n = normalize_code(cur)
  prev_n = normalize_code(prev)
  return [] if cur_n == prev_n
  ["AgentMessageBody の宣言が基準から変化している"]
end

def protected_symbol_errors(current, previous, name, kind)
  return [] if current.nil? || previous.nil?
  cur = kind == :enum ? extract_enum_body(current, name) : extract_struct_body(current, name)
  prev = kind == :enum ? extract_enum_body(previous, name) : extract_struct_body(previous, name)
  return ["#{name} を解析できない"] if cur.nil? || prev.nil?
  return [] if normalize_code(cur) == normalize_code(prev)
  ["#{name} が基準 blob と同一ではない"]
end

def protected_member_errors(current, previous, struct_name, member, kind)
  return [] if current.nil? || previous.nil?
  cur_struct = extract_struct_body(current, struct_name)
  prev_struct = extract_struct_body(previous, struct_name)
  return ["#{struct_name}.#{member} を解析できない"] if cur_struct.nil? || prev_struct.nil?
  cur = kind == :var ? extract_var_body(cur_struct, member) : extract_func_body(cur_struct, member)
  prev = kind == :var ? extract_var_body(prev_struct, member) : extract_func_body(prev_struct, member)
  return ["#{struct_name}.#{member} を解析できない"] if cur.nil? || prev.nil?
  return [] if normalize_code(cur) == normalize_code(prev)
  ["#{struct_name}.#{member} が基準 blob と同一ではない"]
end

def extra_changed_product_paths(rev)
  tracked = IO.popen(["git", "diff", "--name-only", rev, "--", SESSION_FEATURE_SRC], err: [:child, :out], &:read)
  untracked = IO.popen(["git", "ls-files", "--others", "--exclude-standard", "--", SESSION_FEATURE_SRC], err: [:child, :out], &:read)
  names = (tracked.to_s + untracked.to_s).split("\n").reject(&:empty?).uniq
  names - ALLOWED_PRODUCT_PATHS
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
  ng.concat(agent_message_body_errors(current_files[:basic], baseline_files[:basic]))
  ng.concat(protected_symbol_errors(current_files[:command_group], baseline_files[:command_group], "CommandGroupRowWindow", :enum))
  ng.concat(protected_symbol_errors(current_files[:command_group], baseline_files[:command_group], "CommandGroupOutputDisplay", :struct))
  ng.concat(protected_symbol_errors(current_files[:render_cache], baseline_files[:render_cache], "FileChangeDisplayPolicy", :enum))
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
    [:command_group, "CommandGroupRowWindow", :enum],
    [:command_group, "CommandGroupExecutionDisplayData", :struct],
    [:render_cache, "FileChangeDisplayPolicy", :enum],
    [:common, "DisclosureCard", :struct],
    [:recap, "CommandGroupTitle", :enum],
    [:structured, "SubAgentMarkerCell", :struct],
  ].each do |key, name, kind|
    next if current_files[key].nil? || baseline_files[key].nil?
    ng.concat(protected_symbol_errors(current_files[key], baseline_files[key], name, kind))
  end
  ng.concat(protected_member_errors(current_files[:structured], baseline_files[:structured], "FileChangeCell", "visibleSections", :var))
  %w[glyph color accessibilityStatus].each do |fn|
    ng.concat(protected_member_errors(current_files[:task_list], baseline_files[:task_list], "TaskListCell", fn, :func))
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
  }[path]
end

def file_hash(
  structured:, basic:, command_group:, task_list:, cells:, common:, render_cache:,
  formatting:, markdown:, recap:, scaled_font:, extra_changed: nil
)
  h = {
    structured: structured,
    basic: basic,
    command_group: command_group,
    task_list: task_list,
    cells: cells,
    common: common,
    render_cache: render_cache,
    formatting: formatting,
    markdown: markdown,
    recap: recap,
    scaled_font: scaled_font,
  }
  h[:extra_changed] = extra_changed if extra_changed
  h
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
  }
end

def evaluate_checks(files, baseline_blobs, scope:)
  ng = []
  ng.concat(check_product(files))
  ng.concat(permanent_structure_errors(files, baseline_blobs))
  ng.concat(scope_errors(files, baseline_blobs)) if scope
  ng.uniq
end

def good_structured
  <<~SWIFT
    struct ReasoningSummaryView: View {
      let text: String
      @State private var userOverride: Bool?
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = TranscriptItemPresentation.reasoning(text: text, summary: nil)
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
            Text(text)
              .font(TranscriptTypography.font(for: .body, scale: scale))
              .foregroundStyle(DSColor.chatTextSecondary)
              .lineSpacing(TranscriptTypography.textLineSpacing)
              .padding(.top, TranscriptTypography.withinAnswer)
          }
        }
      }
    }
    struct CommandExecutionCell: View {
      let command: String?
      let output: String
      let isRunning: Bool
      @State private var userOverride: Bool?
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = TranscriptItemPresentation.command(path: .single, itemCount: 1, isRunning: isRunning, hasNonBlankOutput: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        DisclosureCard(
          isExpanded: Binding(
            get: { TranscriptItemPresentation.isExpanded(userOverride: userOverride, defaultExpanded: presentation.defaultExpanded) },
            set: { userOverride = $0 }
          ),
          title: presentation.heading ?? "",
          subtitle: presentation.subtitle,
          isToolCall: presentation.semanticInk == .process
        ) {
          Text(output).font(ChatScaledFont.monoCaption(scale: scale))
            .padding(.top, TranscriptTypography.withinAnswer)
        }
      }
    }
    struct ThinkingIndicatorCell: View {
      var state: AgentActivityState = .thinking
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        HStack {
          Text(state.orbLabel).font(ChatScaledFont.body(scale: scale))
        }
        .accessibilityLabel(state.orbLabel)
        .padding(.vertical, TranscriptTypography.metadataGap)
      }
    }
    struct FileChangeCell: View {
      @State private var userExpandedOverride: Bool?
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      var visibleSections: [DiffSection] {
        changes.enumerated().map { index, change in
          DiffSection(id: index, path: change.path, copyText: change.diff, codeView: ChatMessageRenderCache.diffCodeView(diff: change.diff, path: change.path))
        }
      }
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = TranscriptItemPresentation.fileChange(title: "編集済み")
        DisclosureCard(
          isExpanded: Binding(
            get: { FileChangeDisplayPolicy.isExpanded(userOverride: userExpandedOverride, lineCount: 1) },
            set: { userExpandedOverride = $0 }
          ),
          title: presentation.heading ?? "",
          subtitle: nil
        ) {
          Text("diff").font(ChatScaledFont.monoCaption(scale: scale)).padding(.top, TranscriptTypography.withinAnswer)
        }
      }
    }
    struct SubAgentMarkerCell: View {
      let id: String
      let onSelect: ((String) -> Void)?
      var body: some View {
        Button { onSelect?(id) } label: { Text("sub") }
          .disabled(onSelect == nil)
          .foregroundStyle(DSColor.statusError)
      }
    }
  SWIFT
end

def good_basic
  <<~SWIFT
    struct AgentMessageBody: View {
      let text: String
      var body: some View {
        VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {
          RichMarkdownView(text)
          CodeBlockView(language: nil, code: text)
        }
      }
    }
    struct ErrorMessageCell: View {
      let message: String
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = TranscriptItemPresentation.error(message: message)
        VStack {
          Label(presentation.heading ?? "", systemImage: "exclamationmark.triangle")
            .font(ChatScaledFont.captionStrong(scale: scale))
            .foregroundStyle(DSColor.statusError)
          Text(message).font(ChatScaledFont.body(scale: scale))
            .lineSpacing(TranscriptTypography.textLineSpacing)
        }
        .padding(.horizontal, TranscriptTypography.cardHorizontalInset)
        .background(DSColor.statusError.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DSColor.statusError.opacity(0.35), lineWidth: 1))
      }
    }
  SWIFT
end

def good_command_group
  <<~SWIFT
    struct CommandGroupHeader: Equatable {
      let isRunning: Bool
      let shouldRender: Bool
    }
    struct CommandGroupOutputDisplay: Equatable {
      static let visibleLineLimit = 20
      let output: String
      var copyText: String { output }
    }
    enum CommandGroupRowWindow {
      static let defaultLimit = 50
      static func slice(items: [ChatItem], lastTranscriptID: String?, isTurnRunning: Bool, limit: Int) -> CommandGroupRowsSlice { CommandGroupRowsSlice() }
    }
    struct CommandGroupRowsSlice {}
    struct CommandGroupExecutionDisplayData {
      let copyText: String
    }
    struct CommandGroupCell: View {
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let header = CommandGroupHeader(isRunning: true, shouldRender: true)
        let presentation = TranscriptItemPresentation.command(path: .group, itemCount: items.count, isRunning: header.isRunning, hasNonBlankOutput: true)
        if header.shouldRender {
          DisclosureCard(
            isExpanded: $isExpanded,
            title: presentation.heading ?? "",
            subtitle: presentation.subtitle,
            isToolCall: presentation.semanticInk == .process
          ) {
            let rowsSlice = CommandGroupRowWindow.slice(items: items, lastTranscriptID: lastTranscriptID, isTurnRunning: isTurnRunning, limit: rowLimit)
            Text(copy).font(TranscriptTypography.font(for: .processSummary, scale: scale))
              .padding(.top, TranscriptTypography.withinAnswer)
          }
        }
      }
    }
    private struct CommandGroupExecutionRow: View {
      var body: some View {
        let display = CommandGroupExecutionDisplayData(copyText: "cmd")
        ChatCodeCard(copyText: display.copyText) { Text("row") }
      }
    }
  SWIFT
end

def good_task_list
  <<~SWIFT
    struct TaskListCell: View {
      let tasks: [AgentTaskItem]
      @State private var userOverride: Bool?
      @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
      var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = TranscriptItemPresentation.taskList(count: tasks.count)
        DisclosureCard(
          isExpanded: Binding(
            get: { TranscriptItemPresentation.isExpanded(userOverride: userOverride, defaultExpanded: presentation.defaultExpanded) },
            set: { userOverride = $0 }
          ),
          title: presentation.heading ?? "",
          subtitle: nil,
          isToolCall: presentation.semanticInk == .process
        ) {
          Text(presentation.expandedBody ?? "").font(TranscriptTypography.font(for: .body, scale: scale))
            .padding(.top, TranscriptTypography.withinAnswer)
        }
      }
      private func glyph(for status: AgentTaskStatus) -> String { "circle" }
      private func color(for status: AgentTaskStatus) -> Color { DSColor.chatTextSecondary }
      private func accessibilityStatus(for status: AgentTaskStatus) -> String { "Pending" }
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
        case .agentMessage(_, let text, let timestamp):
          AgentMessageCell(text: text, timestamp: timestamp, descriptor: agentDescriptor)
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

def good_files
  {
    structured: good_structured,
    basic: good_basic,
    command_group: good_command_group,
    task_list: good_task_list,
    cells: good_cells,
    common: "struct DisclosureCard<Content: View>: View { var body: some View { content } }",
    render_cache: "enum FileChangeDisplayPolicy { static func isExpanded(userOverride: Bool?, lineCount: Int) -> Bool { userOverride ?? false } }",
    formatting: "enum ChatTranscriptFormatting {}",
    markdown: "struct RichMarkdownView {}",
    recap: "enum CommandGroupTitle { static func derive(items: [ChatItem]) -> String { ChatCommandGroupTitle.derive(commands: [], itemCount: items.count) } }",
    scaled_font: good_scaled_font,
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
    puts "task46-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task46-wiring --selftest: FAIL #{msg}"
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
  interp = %(let s = "\\(TranscriptTypography.font(for: .body, scale: 1))" // note)
  selftest_assert strip_comments(interp).include?("TranscriptTypography.font"), "正例: 補間文字列を保持する"
  spaced = %(Text("hello world"))
  selftest_assert normalize_code(spaced).include?("hello world"), "正例: 文字列内空白を正規化で消さない"

  good = good_files
  selftest_errors_eq check_product(good), [], "正例: 契約どおりの配線は空 NG"
  selftest_errors_eq permanent_structure_errors(good, good), [], "正例: 恒久構造比較は同一 blob で空"

  commented = with_file(good, :task_list) { |src|
    src + %(\n// TranscriptItemPresentation.taskList\nlet decoy = "TranscriptTypography"\n)
  }
  selftest_errors_eq check_product(commented), [], "正例: コメント・文字列だけを加える"

  task47 = with_file(good, :structured) { |src|
    src.sub(
      "Text(text)",
      "AgentMessageBody(text: text, bodyColor: DSColor.chatTextSecondary)"
    ).sub("summary: nil", "summary: ReasoningPresentation(text: text).headline")
  }
  task47 = with_file(task47, :basic) { |src|
    src.sub(
      "let text: String",
      "let text: String\n      var bodyColor: Color = DSColor.chatTextPrimary"
    ).sub("RichMarkdownView(text)", "RichMarkdownView(text, bodyColor: bodyColor)")
  }
  selftest_errors_eq check_product(task47), [], "正例: task-47 許可の本文・要約・色引数変更"

  unwired = with_file(good, :structured) { |src|
    src.gsub("TranscriptItemPresentation.reasoning(text: text, summary: nil)", "ReasoningPresentation(text: text)")
  }
  selftest_errors_eq check_reasoning(unwired[:structured], unwired[:basic], unwired[:scaled_font]), ["思考詳細から分類モデルが未接続"], "負例: モデル未接続"

  bad_title = with_file(good, :structured) { |src|
    src.sub("title: presentation.heading ?? \"\"", "title: \"思考の詳細\"")
  }
  selftest_errors_eq check_reasoning(bad_title[:structured], bad_title[:basic], bad_title[:scaled_font]), ["思考の見出しが分類モデルから届いていない"], "負例: 思考見出し固定文字列"

  bad_sub = with_file(good, :structured) { |src|
    src.sub("subtitle: presentation.subtitle,", "subtitle: nil,")
  }
  selftest_errors_eq check_reasoning(bad_sub[:structured], bad_sub[:basic], bad_sub[:scaled_font]), ["思考の補足が分類モデルから届いていない"], "負例: 思考補足未配線"

  bad_ink = with_file(good, :structured) { |src|
    src.sub("isToolCall: presentation.semanticInk == .process", "isToolCall: true")
  }
  selftest_errors_eq check_reasoning(bad_ink[:structured], bad_ink[:basic], bad_ink[:scaled_font]), ["思考の意味色が分類モデルから届いていない"], "負例: 意味色未配線"

  short = with_file(good, :structured) { |src|
    src.sub(
      "if presentation.isVisible {",
      "if presentation.usesDisclosure { let trimmedText = text"
    )
  }
  selftest_errors_eq check_reasoning(short[:structured], short[:basic], short[:scaled_font]), ["短文だけ直接表示している"], "負例: 短文だけ直接表示"

  counted = with_file(good, :command_group) { |src|
    src.sub("itemCount: items.count", "itemCount: rowsSlice.rows.count")
  }
  selftest_errors_eq check_command_group(counted[:command_group], counted[:scaled_font]), ["件数が描画窓または除外後の行数になっている"], "負例: 件数誤り"

  always = with_file(good, :task_list) { |src|
    src.sub(
      "isExpanded: Binding(",
      "isExpanded: .constant(true), unused: Binding("
    )
  }
  selftest_errors_eq check_task(always[:task_list], always[:scaled_font]), ["タスクが定数 Binding で操作できない"], "負例: 常時展開"

  always_false = with_file(good, :task_list) { |src|
    src.sub(
      "isExpanded: Binding(",
      "isExpanded: .constant(false), unused: Binding("
    )
  }
  selftest_errors_eq check_task(always_false[:task_list], always_false[:scaled_font]), ["タスクが定数 Binding で操作できない"], "負例: constant(false)"

  reset = with_file(good, :task_list) { |src|
    src.sub(
      ".padding(.top, TranscriptTypography.withinAnswer)",
      ".padding(.top, TranscriptTypography.withinAnswer)\n        .onChange(of: tasks) { userOverride = nil; isExpanded = false }"
    )
  }
  selftest_errors_eq check_task(reset[:task_list], reset[:scaled_font]), ["表示継続中の更新で開閉をリセットしている"], "負例: 更新時リセット"

  no_sub = with_file(good, :command_group) { |src|
    src.sub("subtitle: presentation.subtitle", "subtitle: nil")
  }
  selftest_errors_eq check_command_group(no_sub[:command_group], no_sub[:scaled_font]), ["実行中補足が閉じたカードへ届いていない"], "負例: 実行中補足欠落"

  no_run = with_file(good, :command_group) { |src|
    src.sub("isRunning: header.isRunning", "isRunning: false")
  }
  selftest_errors_eq check_command_group(no_run[:command_group], no_run[:scaled_font]), [
    "グループ実行中の正本が header.isRunning ではない",
  ], "負例: 実行中正本欠落"

  no_guard = with_file(good, :command_group) { |src|
    src.sub("if header.shouldRender {", "if true {")
  }
  selftest_errors_eq check_command_group(no_guard[:command_group], no_guard[:scaled_font]), ["グループの表示ガードが header.shouldRender ではない"], "負例: shouldRender 欠落"

  no_err_color = with_file(good, :basic) { |src|
    src.gsub("DSColor.statusError", "DSColor.chatTextPrimary")
  }
  selftest_errors_eq check_error(no_err_color[:basic], no_err_color[:scaled_font]), ["エラー色の接続が無い"], "負例: エラー色欠落"

  no_err_heading = with_file(good, :basic) { |src|
    src.sub("Label(presentation.heading ?? \"\"", "Label(\"エラー\"")
  }
  selftest_errors_eq check_error(no_err_heading[:basic], no_err_heading[:scaled_font]), ["エラー見出しが分類モデルから届いていない"], "負例: エラー見出しリテラル"

  no_ax = with_file(good, :structured) { |src|
    src.gsub(".accessibilityLabel(state.orbLabel)", "").gsub("Text(state.orbLabel)", "Text(\"Thinking...\")")
  }
  selftest_errors_eq check_thinking(no_ax[:structured], no_ax[:scaled_font]), ["活動ラベルと AX が同じ実状態に由来していない"], "負例: 活動 AX 欠落"

  no_copy = with_file(good, :command_group) { |src|
    src.gsub("copyText", "label")
  }
  selftest_errors_eq check_command_group(no_copy[:command_group], no_copy[:scaled_font]), ["コピー原文の経路が無い"], "負例: コピー欠落"

  no_window = with_file(good, :command_group) { |src|
    src.gsub("CommandGroupRowWindow", "LegacyWindow")
  }
  selftest_errors_eq check_command_group(no_window[:command_group], no_window[:scaled_font]), ["描画窓 CommandGroupRowWindow が無い"], "負例: 描画窓欠落"

  no_limit = with_file(good, :command_group) { |src|
    src.gsub("visibleLineLimit = 20", "visibleLineLimit = 5")
  }
  selftest_errors_eq check_output_window(no_limit[:command_group]), ["描画窓の出力20行上限が無い"], "負例: 20行上限欠落"

  no_font = with_file(good, :structured) { |src|
    src.sub("TranscriptTypography.font(for: .body, scale: scale)", "Font.system(size: 13)")
  }
  selftest_errors_eq typography_errors(compact_reach(no_font[:structured], "ReasoningSummaryView"), no_font[:scaled_font], "思考詳細"), ["思考詳細のフォント役割が無い"], "負例: フォント役割退行"

  no_scale = with_file(good, :structured) { |src|
    src.gsub("scale: scale", "scale: 1")
  }
  selftest_errors_eq typography_errors(compact_reach(no_scale[:structured], "ReasoningSummaryView"), no_scale[:scaled_font], "思考詳細"), ["思考詳細の倍率追随が無い"], "負例: 倍率固定"

  no_pad = with_file(good, :structured) { |src|
    src.sub(".padding(.top, TranscriptTypography.withinAnswer)", ".padding(.top, 8)")
  }
  selftest_errors_eq typography_errors(compact_reach(no_pad[:structured], "ReasoningSummaryView"), no_pad[:scaled_font], "思考詳細"), ["思考詳細の余白接続が無い"], "負例: 余白退行"

  no_lead = with_file(good, :structured) { |src|
    src.sub(".lineSpacing(TranscriptTypography.textLineSpacing)", "")
  }
  selftest_errors_eq typography_errors(compact_reach(no_lead[:structured], "ReasoningSummaryView"), no_lead[:scaled_font], "思考詳細"), ["思考詳細の行間接続が無い"], "負例: 行間退行"

  no_adapter = with_file(good, :scaled_font) { |src|
    src.sub("TranscriptTypography.font(for: .body, scale: scale)", "Font.system(size: 13)")
  }
  selftest_errors_eq check_scaled_font_adapter(no_adapter[:scaled_font]), ["ChatScaledFont が TranscriptTypography へ委譲していない"], "負例: ChatScaledFont 転送欠落"

  fake_decl = with_file(good, :task_list) { |src|
    "/* struct TaskListCell { var body: some View { let presentation = TranscriptItemPresentation.taskList(count: 1)\n DisclosureCard(isExpanded: Binding(get: { true }, set: { _ in }), title: presentation.heading ?? \"\", subtitle: nil, isToolCall: presentation.semanticInk == .process) { Text(\"ok\").font(TranscriptTypography.font(for: .body, scale: scale)).padding(.top, TranscriptTypography.withinAnswer) } } } */\n" +
      src.gsub("TranscriptItemPresentation.taskList(count: tasks.count)", "Dummy.task()")
        .gsub("presentation.heading ?? \"\"", "\"Tasks\"")
        .gsub("presentation.semanticInk == .process", "true")
  }
  fake_ng = check_task(fake_decl[:task_list], fake_decl[:scaled_font])
  selftest_assert fake_ng.include?("タスクから分類モデルが未接続"), "負例: コメント内偽宣言 (#{fake_ng.inspect})"

  unused = with_file(good, :task_list) { |src|
    src.sub(
      "let presentation = TranscriptItemPresentation.taskList(count: tasks.count)",
      "let unused = TranscriptItemPresentation.taskList(count: tasks.count)\n        let presentation = Dummy.task()"
    )
  }
  selftest_errors_eq check_task(unused[:task_list], unused[:scaled_font]), ["タスクから分類モデルが未接続"], "負例: 未使用変数"

  discarded = with_file(good, :task_list) { |src|
    src.sub(
      "let presentation = TranscriptItemPresentation.taskList(count: tasks.count)",
      "_ = TranscriptItemPresentation.taskList(count: tasks.count)\n        let presentation = Dummy.task()"
    )
  }
  selftest_errors_eq check_task(discarded[:task_list], discarded[:scaled_font]), ["タスクから分類モデルが未接続"], "負例: 戻り値破棄"

  selftest_errors_eq check_answer(good[:basic], good[:scaled_font]), [], "正例: 回答は RichMarkdownView 委譲で足り、局所のフォント役割・倍率追随を要求しない"

  bound_answer = with_file(good, :basic) { |src|
    src.sub(
      "VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {",
      "@State private var userOverride: Bool?\n        VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {"
    )
  }
  selftest_errors_eq check_answer(bound_answer[:basic], bound_answer[:scaled_font]), ["回答が詳細用 Binding に依存している"], "負例: 回答が詳細 Binding に依存"

  no_rich_answer = with_file(good, :basic) { |src|
    src.sub("RichMarkdownView(text)", "Text(text)")
  }
  selftest_errors_eq check_answer(no_rich_answer[:basic], no_rich_answer[:scaled_font]), ["回答が RichMarkdownView へ委譲していない"], "負例: AgentMessageBody から RichMarkdownView を外す"

  unparsed = "struct TaskListCell: View { var body: some View {"
  selftest_errors_eq check_task(unparsed, good[:scaled_font]), ["TaskListCell を解析できない"], "負例: 構文切り出し失敗"

  task47_reset = with_file(task47, :task_list) { |src|
    src.sub(
      ".padding(.top, TranscriptTypography.withinAnswer)",
      ".padding(.top, TranscriptTypography.withinAnswer)\n        .onChange(of: tasks) { isExpanded = false }"
    )
  }
  selftest_errors_eq check_product(task47_reset), ["表示継続中の更新で開閉をリセットしている"], "負例: task-47 許可 fixture に開閉リセットを1件加える"

  task47_typo = with_file(task47, :task_list) { |src|
    src.gsub("TranscriptTypography.font(for: .body, scale: scale)", "Font.system(size: 13)")
  }
  selftest_errors_eq check_product(task47_typo), ["タスクのフォント役割が無い"], "負例: task-47 許可 fixture に typography 退行を1件加える"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_errors_eq unset_errs, ["TASK46_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: 基準の未設定"
  selftest_assert unset.nil?, "負例: 未設定は nil"
  _invalid, invalid_errs = baseline_env_errors("not-a-sha")
  selftest_errors_eq invalid_errs, ["TASK46_BASELINE がコミット SHA ではない（ブランチ名は使えない）: not-a-sha"], "負例: SHA 不正"
  _head, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK46_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD 指定"
  _head1, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK46_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD~1 指定"
  _at, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK46_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: @ 指定"
  _branch, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK46_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
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
  selftest_errors_eq real_mismatch, ["TASK46_BASELINE が契約 baseline_commit と一致しない"], "負例: 契約不一致"

  same_blob = "frozen\n"
  artifacts_ok = {
    presentation_blob: nil,
    typography_blob: "public enum TranscriptTypography {}",
    test_blobs: [same_blob, same_blob],
    test_nows: [same_blob, same_blob],
    rb_blob: same_blob,
    rb_now: same_blob,
  }
  selftest_errors_eq check_frozen_baseline(head_full, artifacts_ok), [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  post_ng = check_frozen_baseline(head_full, artifacts_ok.merge(presentation_blob: "struct TranscriptItemPresentation {}"))
  selftest_errors_eq post_ng, ["基準時点に TranscriptItemPresentation.swift がある（実装前の凍結ではない）"], "負例: 実装済み基準"

  no_task40 = check_frozen_baseline(head_full, artifacts_ok.merge(typography_blob: nil))
  selftest_errors_eq no_task40, ["基準時点に TranscriptTypography.swift が無い（task-40 完了状態ではない）"], "負例: task-40 完了状態が基準に無い"

  git_fail = check_frozen_baseline(head_full, artifacts_ok.merge(presentation_error: "fatal: bad object"))
  selftest_errors_eq git_fail, ["基準時点の TranscriptItemPresentation.swift を git show できない: fatal: bad object"], "負例: 基準 git 障害"

  missing_pres = check_frozen_baseline(head_full, artifacts_ok.merge(presentation_blob: nil))
  selftest_errors_eq missing_pres, [], "正例: 新規製品ファイルの基準不存在は git 障害ではない"

  selftest_errors_eq blob_fetch_errors("rb 自身", { status: :ok, text: "now" }, "frozen"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 凍結検査の改変"
  selftest_errors_eq blob_fetch_errors("受け入れテスト1", { status: :git_error, text: nil, stderr: "fatal: foo" }, "now"), ["基準時点の受け入れテスト1を git show できない: fatal: foo"], "負例: blob 取得失敗"
  selftest_errors_eq blob_fetch_errors("受け入れテスト1", { status: :missing, text: nil, stderr: "" }, "now"), ["基準時点の受け入れテスト1が無い"], "負例: 基準ファイル不存在"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "same", "same"), [], "正例: 凍結 rb と作業ツリーが同一"
  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"

  non_anc = check_frozen_baseline(other_full, artifacts_ok)
  selftest_assert !non_anc.include?("TASK46_BASELINE が HEAD の祖先ではない"), "正例: HEAD^ は祖先"
  forced_non_ancestor = check_frozen_baseline(head_full, artifacts_ok.merge(is_ancestor: false))
  selftest_errors_eq forced_non_ancestor, ["TASK46_BASELINE が HEAD の祖先ではない"], "負例: 非祖先"

  out_of_scope = good.merge(extra_changed: [FORMATTING_PATH])
  selftest_errors_eq scope_errors(out_of_scope, good), ["許可パス外の製品変更: #{FORMATTING_PATH}"], "負例: scope のみで拒否すべき範囲外変更"
  selftest_errors_eq check_product(good.merge(formatting: "changed")), [], "正例: scope なしでは範囲外変更を範囲違反にしない"

  unset_ng = evaluate_checks(out_of_scope, good, scope: false)
  one_ng = evaluate_checks(out_of_scope, good, scope: true)
  selftest_errors_eq unset_ng, [], "正例: 未設定/0 相当は範囲外変更を恒久 NG にしない"
  selftest_errors_eq one_ng, ["許可パス外の製品変更: #{FORMATTING_PATH}"], "負例: SCOPE_CHECK=1 の本番判定"

  with_env("TASK46_SCOPE_CHECK", "1") { selftest_assert scope_check_requested?, "正例: SCOPE_CHECK=1" }
  with_env("TASK46_SCOPE_CHECK", "0") { selftest_assert !scope_check_requested?, "正例: SCOPE_CHECK=0 では恒久のみ" }
  with_env("TASK46_SCOPE_CHECK", nil) { selftest_assert !scope_check_requested?, "正例: 未設定では恒久のみ" }
  unset_pred = nil
  zero_pred = nil
  one_pred = nil
  with_env("TASK46_SCOPE_CHECK", nil) { unset_pred = scope_check_requested? }
  with_env("TASK46_SCOPE_CHECK", "0") { zero_pred = scope_check_requested? }
  with_env("TASK46_SCOPE_CHECK", "1") { one_pred = scope_check_requested? }
  selftest_errors_eq evaluate_checks(out_of_scope, good, scope: unset_pred), [], "正例: 未設定の本番分岐"
  selftest_errors_eq evaluate_checks(out_of_scope, good, scope: zero_pred), [], "正例: SCOPE_CHECK=0 の本番分岐"
  selftest_errors_eq evaluate_checks(out_of_scope, good, scope: one_pred), ["許可パス外の製品変更: #{FORMATTING_PATH}"], "正例: SCOPE_CHECK=1 の本番分岐"

  body_changed = with_file(good, :basic) { |src|
    src.sub("RichMarkdownView(text)", "Text(text)")
  }
  selftest_errors_eq agent_message_body_errors(body_changed[:basic], good[:basic]), ["AgentMessageBody の宣言が基準から変化している"], "負例: SCOPE_CHECK で AgentMessageBody 改変"

  prod = production_checks_source
  selftest_assert !prod.empty?, "正例: 本番検査セクションが存在する"
  selftest_assert baseline_check_connected?(prod), "正例: 基準検査が本番に接続されている"
  selftest_assert scope_check_gated?(prod), "正例: 変更範囲検査が TASK46_SCOPE_CHECK でゲートされている"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task46-wiring --selftest: OK"
  exit 0
end

# === task46 production checks ===
ng = []

raw = ENV["TASK46_BASELINE"]
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
    ng << "TASK46_BASELINE が無効なコミット: #{baseline}"
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
  puts "task46-wiring: OK"
else
  ng.each { |m| puts "task46-wiring: NG #{m}" }
  exit 1
end
