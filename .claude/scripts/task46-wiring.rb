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

def strip_discarded_calls(src)
  compact(src).gsub(/_=(?:TranscriptItemPresentation|TranscriptTypography|ChatScaledFont|ChatTypography)(?:\.[A-Za-z0-9_]+)*/, "")
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
  if src.match?(/\bstruct\s+#{Regexp.escape(name)}\b/) && body.nil?
    return :unparseable
  end
  return :missing if body.nil?
  start = extract_var_body(body, "body") || body
  collect_reachable(src, start)
end

def compact_reach(src, name)
  reach = struct_reachable(src, name)
  return reach if reach.is_a?(Symbol)
  compact(mask_strings_and_comments(erase_if_false(reach)))
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

def frozen_artifact_errors(label, blob, now)
  if blob.nil?
    ["基準時点の#{label}を git show できない"]
  elsif !workdir_matches_git_blob?(now, blob)
    ["基準時点の#{label}が現在と同一ではない"]
  else
    []
  end
end

def implementation_in_baseline_errors(presentation_blob, typography_blob)
  ng = []
  if presentation_blob
    ng << "基準時点に TranscriptItemPresentation.swift がある（実装前の凍結ではない）"
  end
  if typography_blob.nil?
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
    ng.concat(implementation_in_baseline_errors(artifacts[:presentation_blob], artifacts[:typography_blob]))
    ACCEPTANCE_PATHS.each_with_index do |_path, idx|
      ng.concat(frozen_artifact_errors("受け入れテスト#{idx + 1}", artifacts[:test_blobs][idx], artifacts[:test_nows][idx]))
    end
    ng.concat(frozen_artifact_errors("rb 自身", artifacts[:rb_blob], artifacts[:rb_now]))
  else
    ng.concat(implementation_in_baseline_errors(git_show(full, PRESENTATION_PATH), git_show(full, TYPOGRAPHY_PATH)))
    ACCEPTANCE_PATHS.each_with_index do |path, idx|
      ng.concat(frozen_artifact_errors("受け入れテスト#{idx + 1}", git_show(full, path), read_if_exist(path)))
    end
    ng.concat(frozen_artifact_errors("rb 自身", git_show(full, WIRING_RB_PATH), read_if_exist(WIRING_RB_PATH)))
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

def presentation_connected?(c)
  stripped = strip_discarded_calls(c)
  stripped.include?("TranscriptItemPresentation")
end

def typography_connected?(c)
  stripped = strip_discarded_calls(c)
  stripped.include?("TranscriptTypography") ||
    stripped.include?("ChatScaledFont") ||
    stripped.include?("ChatTypography")
end

def short_text_direct?(c)
  c.include?("usesDisclosure") && c.include?("trimmedText")
end

def constant_true_binding?(c)
  c.include?(".constant(true)") || c.include?("constant(true)")
end

def expansion_reset?(src)
  c = compact(mask_strings_and_comments(erase_if_false(src.to_s)))
  return false unless c.include?("onChange")
  c.match?(/onChange\([^)]*\)[^{]*\{[^}]*(?:isExpanded=false|userOverride=nil|userExpandedOverride=nil)/) ||
    c.include?("isExpanded=false") && c.include?("onChange")
end

def check_reasoning(src)
  ng = missing_struct(src, "ReasoningSummaryView", "ReasoningSummaryView")
  return ng unless ng.empty?
  c = compact_reach(src, "ReasoningSummaryView")
  return ["ReasoningSummaryView を解析できない"] if c.is_a?(Symbol)
  ng << "思考詳細から分類モデルが未接続" unless c.include?("TranscriptItemPresentation.reasoning")
  ng << "短文だけ直接表示している" if short_text_direct?(c)
  ng << "思考詳細が DisclosureCard を使っていない" unless c.include?("DisclosureCard")
  ng << "思考の展開本文へ原文が届いていない" unless c.match?(/\bText\(text\)/) || c.match?(/RichMarkdownView\(/)
  ng << "思考詳細の TranscriptTypography 接続が無い" unless typography_connected?(c)
  ng << "思考詳細の secondary 色が無い" unless c.include?("chatTextSecondary") || c.include?("bodyColor")
  ng.concat(expansion_reset?(src) ? ["表示継続中の更新で開閉をリセットしている"] : [])
  ng
end

def check_command_single(src)
  ng = missing_struct(src, "CommandExecutionCell", "CommandExecutionCell")
  return ng unless ng.empty?
  c = compact_reach(src, "CommandExecutionCell")
  return ["CommandExecutionCell を解析できない"] if c.is_a?(Symbol)
  ng << "コマンド単体から分類モデルが未接続" unless presentation_connected?(c)
  ng << "コマンド単体の件数が描画窓または除外後の行数になっている" if c.include?("rows.count") || c.include?("hiddenRowCount")
  ng << "コマンド単体の実行中補足が閉じたカードへ届いていない" unless c.include?("presentation.subtitle") || c.include?("subtitle:presentation")
  ng << "コマンド単体の TranscriptTypography 接続が無い" unless typography_connected?(c)
  ng << "コマンド単体が DisclosureCard を使っていない" unless c.include?("DisclosureCard")
  ng
end

def check_command_group(src)
  ng = missing_struct(src, "CommandGroupCell", "CommandGroupCell")
  return ng unless ng.empty?
  c = compact_reach(src, "CommandGroupCell")
  return ["CommandGroupCell を解析できない"] if c.is_a?(Symbol)
  ng << "コマンドグループから分類モデルが未接続" unless c.include?("TranscriptItemPresentation.command")
  ng << "グループ実行中の正本が header.isRunning ではない" unless c.include?("header.isRunning") || c.include?("isRunning:header.isRunning")
  ng << "実行中補足が閉じたカードへ届いていない" unless c.include?("presentation.subtitle") || (c.include?("subtitle:") && !c.include?("subtitle:nil"))
  ng << "件数が描画窓または除外後の行数になっている" if c.include?("rowsSlice.rows.count") || c.include?("displayRows.count")
  ng << "描画窓 CommandGroupRowWindow が無い" unless c.include?("CommandGroupRowWindow") || src.to_s.include?("CommandGroupRowWindow")
  ng << "コマンドグループの TranscriptTypography 接続が無い" unless typography_connected?(c)
  copy_src = compact(mask_strings_and_comments(src.to_s))
  ng << "コピー原文の経路が無い" unless copy_src.include?("copyText")
  window_src = compact(mask_strings_and_comments(src.to_s))
  ng << "描画窓 CommandGroupRowWindow が無い" unless window_src.include?("enumCommandGroupRowWindow") || window_src.include?("CommandGroupRowWindow")
  ng.concat(expansion_reset?(src) ? ["表示継続中の更新で開閉をリセットしている"] : [])
  ng
end

def check_task(src)
  ng = missing_struct(src, "TaskListCell", "TaskListCell")
  return ng unless ng.empty?
  c = compact_reach(src, "TaskListCell")
  return ["TaskListCell を解析できない"] if c.is_a?(Symbol)
  ng << "タスクから分類モデルが未接続" unless c.include?("TranscriptItemPresentation.taskList")
  ng << "タスクが定数 Binding で常時展開されている" if constant_true_binding?(c)
  ng << "タスクの TranscriptTypography 接続が無い" unless typography_connected?(c)
  ng.concat(expansion_reset?(src) ? ["表示継続中の更新で開閉をリセットしている"] : [])
  ng
end

def check_error(src)
  ng = missing_struct(src, "ErrorMessageCell", "ErrorMessageCell")
  return ng unless ng.empty?
  c = compact_reach(src, "ErrorMessageCell")
  return ["ErrorMessageCell を解析できない"] if c.is_a?(Symbol)
  heading_ok = c.include?("エラー") || src.to_s.include?('"エラー"')
  ng << "エラー色・見出しの接続が無い" unless heading_ok && c.include?("statusError")
  ng << "エラーの TranscriptTypography 接続が無い" unless typography_connected?(c)
  ng
end

def check_thinking(src)
  ng = missing_struct(src, "ThinkingIndicatorCell", "ThinkingIndicatorCell")
  return ng unless ng.empty?
  c = compact_reach(src, "ThinkingIndicatorCell")
  return ["ThinkingIndicatorCell を解析できない"] if c.is_a?(Symbol)
  ng << "活動ラベルと AX が同じ実状態に由来していない" unless c.include?("orbLabel") && c.include?("accessibilityLabel")
  ng << "処理中の TranscriptTypography 接続が無い" unless typography_connected?(c)
  ng
end

def check_answer(src)
  ng = missing_struct(src, "AgentMessageBody", "AgentMessageBody")
  return ng unless ng.empty?
  c = compact_reach(src, "AgentMessageBody")
  return ["AgentMessageBody を解析できない"] if c.is_a?(Symbol)
  ng << "回答が詳細カードへ収納されている" if c.include?("DisclosureCard")
  ng << "回答の TranscriptTypography 接続が無い" unless typography_connected?(c)
  ng
end

def check_file_change(src)
  ng = missing_struct(src, "FileChangeCell", "FileChangeCell")
  return ng unless ng.empty?
  c = compact_reach(src, "FileChangeCell")
  return ["FileChangeCell を解析できない"] if c.is_a?(Symbol)
  ng << "ファイル変更が FileChangeDisplayPolicy.isExpanded を使っていない" unless c.include?("FileChangeDisplayPolicy.isExpanded")
  ng << "ファイル変更が defaultExpanded(lineCount:) をカード既定に流用している" if c.include?("defaultExpanded(lineCount:")
  ng << "ファイル変更の TranscriptTypography 接続が無い" unless typography_connected?(c)
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
  return ["CommandGroupOutputDisplay を解析できない"] if src.match?(/\bstruct\s+CommandGroupOutputDisplay\b/) && body.nil?
  return ["CommandGroupOutputDisplay が存在しない"] if body.nil?
  c = compact(mask_strings_and_comments(body))
  ng = []
  ng << "描画窓の出力20行上限が無い" unless c.include?("visibleLineLimit=20") || c.include?("staticletvisibleLineLimit=20")
  ng
end

def check_product(files)
  ng = []
  ng.concat(check_reasoning(files[:structured]))
  ng.concat(check_command_single(files[:structured]))
  ng.concat(check_command_group(files[:command_group]))
  ng.concat(check_task(files[:task_list]))
  ng.concat(check_error(files[:basic]))
  ng.concat(check_thinking(files[:structured]))
  ng.concat(check_answer(files[:basic]))
  ng.concat(check_file_change(files[:structured]))
  ng.concat(check_empty_thinking(files[:cells]))
  ng.concat(check_output_window(files[:command_group]))
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
  }[path]
end

def worktree_files
  {
    structured: read_if_exist(STRUCTURED_PATH),
    basic: read_if_exist(BASIC_PATH),
    command_group: read_if_exist(COMMAND_GROUP_PATH),
    task_list: read_if_exist(TASK_LIST_PATH),
    cells: read_if_exist(CELLS_PATH),
    common: read_if_exist(COMMON_PATH),
    render_cache: read_if_exist(RENDER_CACHE_PATH),
    formatting: read_if_exist(FORMATTING_PATH),
    markdown: read_if_exist(MARKDOWN_PATH),
  }
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
  }
end

def good_structured
  <<~SWIFT
    struct ReasoningSummaryView: View {
      let text: String
      @State private var userOverride: Bool?
      var body: some View {
        let presentation = TranscriptItemPresentation.reasoning(text: text, summary: nil)
        if presentation.isVisible {
          DisclosureCard(
            isExpanded: Binding(
              get: { TranscriptItemPresentation.isExpanded(userOverride: userOverride, defaultExpanded: presentation.defaultExpanded) },
              set: { userOverride = $0 }
            ),
            title: presentation.heading ?? "",
            subtitle: presentation.subtitle,
            isToolCall: true
          ) {
            Text(text)
              .font(TranscriptTypography.font(for: .body, scale: 1))
              .foregroundStyle(DSColor.chatTextSecondary)
              .lineSpacing(TranscriptTypography.textLineSpacing)
          }
        }
      }
    }
    struct CommandExecutionCell: View {
      let command: String?
      let output: String
      let isRunning: Bool
      @State private var userOverride: Bool?
      var body: some View {
        let presentation = TranscriptItemPresentation.command(path: .single, itemCount: 1, isRunning: isRunning, hasNonBlankOutput: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        DisclosureCard(
          isExpanded: Binding(
            get: { TranscriptItemPresentation.isExpanded(userOverride: userOverride, defaultExpanded: presentation.defaultExpanded) },
            set: { userOverride = $0 }
          ),
          title: presentation.heading ?? "",
          subtitle: presentation.subtitle,
          isToolCall: true
        ) {
          Text(output).font(ChatScaledFont.monoCaption(scale: 1))
            .padding(.top, TranscriptTypography.withinAnswer)
        }
      }
    }
    struct ThinkingIndicatorCell: View {
      var state: AgentActivityState = .thinking
      var body: some View {
        HStack {
          Text(state.orbLabel).font(ChatScaledFont.body(scale: 1))
        }
        .accessibilityLabel(state.orbLabel)
        .padding(.vertical, TranscriptTypography.metadataGap)
      }
    }
    struct FileChangeCell: View {
      @State private var userExpandedOverride: Bool?
      var body: some View {
        let presentation = TranscriptItemPresentation.fileChange(title: "編集済み")
        DisclosureCard(
          isExpanded: Binding(
            get: { FileChangeDisplayPolicy.isExpanded(userOverride: userExpandedOverride, lineCount: 1) },
            set: { userExpandedOverride = $0 }
          ),
          title: presentation.heading ?? "",
          subtitle: nil
        ) {
          Text("diff").padding(.top, TranscriptTypography.withinAnswer)
        }
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
      var body: some View {
        let presentation = TranscriptItemPresentation.error(message: message)
        VStack {
          Label("エラー", systemImage: "exclamationmark.triangle")
            .font(ChatScaledFont.captionStrong(scale: 1))
            .foregroundStyle(DSColor.statusError)
          Text(message).font(ChatScaledFont.body(scale: 1))
            .lineSpacing(TranscriptTypography.textLineSpacing)
        }
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
      var body: some View {
        let header = CommandGroupHeader(isRunning: true, shouldRender: true)
        let presentation = TranscriptItemPresentation.command(path: .group, itemCount: items.count, isRunning: header.isRunning, hasNonBlankOutput: true)
        DisclosureCard(
          isExpanded: $isExpanded,
          title: presentation.heading ?? "",
          subtitle: presentation.subtitle,
          isToolCall: true
        ) {
          let rowsSlice = CommandGroupRowWindow.slice(items: items, lastTranscriptID: lastTranscriptID, isTurnRunning: isTurnRunning, limit: rowLimit)
          Text(copy).font(TranscriptTypography.font(for: .processSummary, scale: 1))
            .padding(.top, TranscriptTypography.withinAnswer)
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
      var body: some View {
        let presentation = TranscriptItemPresentation.taskList(count: tasks.count)
        DisclosureCard(
          isExpanded: Binding(
            get: { TranscriptItemPresentation.isExpanded(userOverride: userOverride, defaultExpanded: presentation.defaultExpanded) },
            set: { userOverride = $0 }
          ),
          title: presentation.heading ?? "",
          subtitle: nil
        ) {
          Text(presentation.expandedBody ?? "").font(TranscriptTypography.font(for: .body, scale: 1))
            .padding(.top, TranscriptTypography.withinAnswer)
        }
      }
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

def good_files
  {
    structured: good_structured,
    basic: good_basic,
    command_group: good_command_group,
    task_list: good_task_list,
    cells: good_cells,
    common: "struct DisclosureCard {}",
    render_cache: "enum FileChangeDisplayPolicy { static func isExpanded(userOverride: Bool?, lineCount: Int) -> Bool { userOverride ?? false } }",
    formatting: "enum ChatTranscriptFormatting {}",
    markdown: "struct RichMarkdownView {}",
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

  commented = with_file(good, :task_list) { |src|
    src + %(\n// TranscriptItemPresentation.taskList\nlet decoy = "TranscriptTypography"\n)
  }
  selftest_errors_eq check_product(commented), [], "正例: コメント・文字列だけを加える"

  task47 = with_file(good, :structured) { |src|
    src.sub("Text(text)", "RichMarkdownView(text, bodyColor: DSColor.chatTextSecondary)")
      .sub("summary: nil", "summary: ReasoningPresentation(text: text).headline")
  }
  task47 = with_file(task47, :basic) { |src|
    src.sub("let text: String", "let text: String\n      var bodyColor: Color = DSColor.chatTextPrimary")
  }
  selftest_errors_eq check_product(task47), [], "正例: task-47 許可の本文・要約・色引数変更"

  unwired = with_file(good, :structured) { |src|
    src.gsub("TranscriptItemPresentation.reasoning(text: text, summary: nil)", "ReasoningPresentation(text: text)")
      .gsub("presentation.heading ?? \"\"", "\"思考\"")
      .gsub("presentation.subtitle", "nil")
      .gsub("presentation.isVisible", "true")
  }
  selftest_errors_eq check_reasoning(unwired[:structured]), ["思考詳細から分類モデルが未接続"], "負例: モデル未接続"

  short = with_file(good, :structured) { |src|
    src.sub(
      "if presentation.isVisible {",
      "if presentation.usesDisclosure { let trimmedText = text"
    )
  }
  selftest_errors_eq check_reasoning(short[:structured]), ["短文だけ直接表示している"], "負例: 短文だけ直接表示"

  counted = with_file(good, :command_group) { |src|
    src.sub("title: presentation.heading ?? \"\"", "title: String(rowsSlice.rows.count)")
  }
  selftest_errors_eq check_command_group(counted[:command_group]), ["件数が描画窓または除外後の行数になっている"], "負例: 件数誤り"

  always = with_file(good, :task_list) { |src|
    src.sub(
      "isExpanded: Binding(",
      "isExpanded: .constant(true), unused: Binding("
    )
  }
  selftest_errors_eq check_task(always[:task_list]), ["タスクが定数 Binding で常時展開されている"], "負例: 常時展開"

  reset = with_file(good, :task_list) { |src|
    src.sub(
      ".padding(.top, TranscriptTypography.withinAnswer)",
      ".padding(.top, TranscriptTypography.withinAnswer)\n        .onChange(of: tasks) { userOverride = nil; isExpanded = false }"
    )
  }
  selftest_errors_eq check_task(reset[:task_list]), ["表示継続中の更新で開閉をリセットしている"], "負例: 更新時リセット"

  no_sub = with_file(good, :command_group) { |src|
    src.sub("subtitle: presentation.subtitle", "subtitle: nil")
      .sub("isRunning: header.isRunning", "isRunning: false")
      .sub("let header = CommandGroupHeader(isRunning: true, shouldRender: true)", "let ignored = 1")
  }
  selftest_errors_eq check_command_group(no_sub[:command_group]).sort, [
    "グループ実行中の正本が header.isRunning ではない",
    "実行中補足が閉じたカードへ届いていない",
  ].sort, "負例: 実行中補足欠落"

  no_err = with_file(good, :basic) { |src|
    src.gsub("エラー", "Error").gsub("DSColor.statusError", "DSColor.chatTextPrimary")
  }
  selftest_errors_eq check_error(no_err[:basic]), ["エラー色・見出しの接続が無い"], "負例: エラー色欠落"

  no_ax = with_file(good, :structured) { |src|
    src.gsub(".accessibilityLabel(state.orbLabel)", "").gsub("state.orbLabel", "\"Thinking...\"")
  }
  selftest_errors_eq check_thinking(no_ax[:structured]), ["活動ラベルと AX が同じ実状態に由来していない"], "負例: 活動 AX 欠落"

  no_copy = with_file(good, :command_group) { |src|
    src.gsub("copyText", "label")
  }
  selftest_errors_eq check_command_group(no_copy[:command_group]), ["コピー原文の経路が無い"], "負例: コピー欠落"

  no_window = with_file(good, :command_group) { |src|
    src.gsub("CommandGroupRowWindow", "LegacyWindow").gsub("visibleLineLimit = 20", "visibleLineLimit = 5")
  }
  window_ng = check_command_group(no_window[:command_group]) + check_output_window(no_window[:command_group])
  selftest_errors_eq window_ng.uniq.sort, [
    "描画窓 CommandGroupRowWindow が無い",
    "描画窓の出力20行上限が無い",
  ].sort, "負例: 描画窓欠落"

  no_typo = with_file(good, :task_list) { |src|
    src.gsub("TranscriptTypography.font(for: .body, scale: 1)", "Font.system(size: 13)")
      .gsub("TranscriptTypography.withinAnswer", "8")
  }
  selftest_errors_eq check_task(no_typo[:task_list]), ["タスクの TranscriptTypography 接続が無い"], "負例: TranscriptTypography 接続欠落"

  decoy = with_file(good, :task_list) { |src|
    src.gsub("TranscriptItemPresentation.taskList(count: tasks.count)", "/* TranscriptItemPresentation.taskList */ Dummy.task()")
      .gsub("TranscriptTypography.font(for: .body, scale: 1)", "Font.system(size: 13)")
      .gsub("TranscriptTypography.withinAnswer", "8") + %(\nlet unused = "TranscriptTypography"\nif false { _ = TranscriptTypography.font(for: .body, scale: 1) }\n)
  }
  decoy_ng = check_task(decoy[:task_list])
  selftest_assert decoy_ng.include?("タスクから分類モデルが未接続") && decoy_ng.include?("タスクの TranscriptTypography 接続が無い"), "負例: コメント・if false・未使用コードによる偽装 (#{decoy_ng.inspect})"

  unparsed = "struct TaskListCell: View { var body: some View {"
  selftest_errors_eq check_task(unparsed), ["TaskListCell を解析できない"], "負例: 構文切り出し失敗"

  task47_reset = with_file(task47, :task_list) { |src|
    src.sub(
      ".padding(.top, TranscriptTypography.withinAnswer)",
      ".padding(.top, TranscriptTypography.withinAnswer)\n        .onChange(of: tasks) { isExpanded = false }"
    )
  }
  selftest_errors_eq check_product(task47_reset), ["表示継続中の更新で開閉をリセットしている"], "負例: task-47 許可 fixture に開閉リセットを1件加える"

  task47_typo = with_file(task47, :task_list) { |src|
    src.gsub("TranscriptTypography.font(for: .body, scale: 1)", "Font.system(size: 13)")
      .gsub("TranscriptTypography.withinAnswer", "8")
  }
  selftest_errors_eq check_product(task47_typo), ["タスクの TranscriptTypography 接続が無い"], "負例: task-47 許可 fixture に typography 退行を1件加える"

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
  pre_ok = check_frozen_baseline(
    head_full,
    presentation_blob: nil,
    typography_blob: "public enum TranscriptTypography {}",
    test_blobs: [same_blob, same_blob],
    test_nows: [same_blob, same_blob],
    rb_blob: same_blob,
    rb_now: same_blob
  )
  selftest_errors_eq pre_ok, [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  post_ng = check_frozen_baseline(
    head_full,
    presentation_blob: "struct TranscriptItemPresentation {}",
    typography_blob: "public enum TranscriptTypography {}",
    test_blobs: [same_blob, same_blob],
    test_nows: [same_blob, same_blob],
    rb_blob: same_blob,
    rb_now: same_blob
  )
  selftest_errors_eq post_ng, ["基準時点に TranscriptItemPresentation.swift がある（実装前の凍結ではない）"], "負例: 実装済み基準"

  no_task40 = check_frozen_baseline(
    head_full,
    presentation_blob: nil,
    typography_blob: nil,
    test_blobs: [same_blob, same_blob],
    test_nows: [same_blob, same_blob],
    rb_blob: same_blob,
    rb_now: same_blob
  )
  selftest_errors_eq no_task40, ["基準時点に TranscriptTypography.swift が無い（task-40 完了状態ではない）"], "負例: task-40 完了状態が基準に無い"

  selftest_errors_eq frozen_artifact_errors("rb 自身", "now", "frozen"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 凍結検査の改変"
  selftest_errors_eq frozen_artifact_errors("受け入れテスト1", nil, "now"), ["基準時点の受け入れテスト1を git show できない"], "負例: blob 取得失敗"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "same", "same"), [], "正例: 凍結 rb と作業ツリーが同一"
  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"

  non_anc = check_frozen_baseline(
    other_full,
    presentation_blob: nil,
    typography_blob: "ok",
    test_blobs: [same_blob, same_blob],
    test_nows: [same_blob, same_blob],
    rb_blob: same_blob,
    rb_now: same_blob
  )
  selftest_assert !non_anc.include?("TASK46_BASELINE が HEAD の祖先ではない"), "正例: HEAD^ は祖先"
  forced_non_ancestor = check_frozen_baseline(
    head_full,
    presentation_blob: nil,
    typography_blob: "ok",
    test_blobs: [same_blob, same_blob],
    test_nows: [same_blob, same_blob],
    rb_blob: same_blob,
    rb_now: same_blob,
    is_ancestor: false
  )
  selftest_errors_eq forced_non_ancestor, ["TASK46_BASELINE が HEAD の祖先ではない"], "負例: 非祖先"

  out_of_scope = good.merge(extra_changed: [FORMATTING_PATH])
  selftest_errors_eq scope_errors(out_of_scope, good), ["許可パス外の製品変更: #{FORMATTING_PATH}"], "負例: scope のみで拒否すべき範囲外変更"
  selftest_errors_eq check_product(good.merge(formatting: "changed")), [], "正例: scope なしでは範囲外変更を範囲違反にしない"

  body_changed = with_file(good, :basic) { |src|
    src.sub("RichMarkdownView(text)", "Text(text)")
  }
  selftest_errors_eq agent_message_body_errors(body_changed[:basic], good[:basic]), ["AgentMessageBody の宣言が基準から変化している"], "負例: SCOPE_CHECK で AgentMessageBody 改変"

  with_env("TASK46_SCOPE_CHECK", "1") { selftest_assert scope_check_requested?, "正例: SCOPE_CHECK=1" }
  with_env("TASK46_SCOPE_CHECK", "0") { selftest_assert !scope_check_requested?, "正例: SCOPE_CHECK=0 では恒久のみ" }
  with_env("TASK46_SCOPE_CHECK", nil) { selftest_assert !scope_check_requested?, "正例: 未設定では恒久のみ" }

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
    if baseline && scope_check_requested?
      ng.concat(scope_errors(files, baseline_files(full)))
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
