#!/usr/bin/env ruby
# task-40 配線検査: TranscriptTypography 正本が実 View へ接続され、
# 旧直値が残らず、ChatTypography / ChatScaledFont が委譲し、
# TASK40_BASELINE の凍結テストと変更禁止対象が契約どおりであること。

def compact(s)
  s.gsub(/\s+/, "")
end

def index_after_string(src, i)
  return i + 1 if i >= src.length
  if src[i, 3] == '"""'
    j = i + 3
    while j < src.length
      return j + 3 if src[j, 3] == '"""'
      j += 1
    end
    return src.length
  end
  return i unless src[i] == '"'
  j = i + 1
  while j < src.length
    if src[j] == "\\"
      j += 2
      next
    end
    return j + 1 if src[j] == '"'
    j += 1
  end
  src.length
end

def protect_strings(src)
  out = +""
  strings = []
  i = 0
  while i < src.length
    if src[i, 3] == '"""' || src[i] == '"'
      j = index_after_string(src, i)
      strings << src[i...j]
      out << "__STR#{strings.length - 1}__"
      i = j
    else
      out << src[i]
      i += 1
    end
  end
  [out, strings]
end

def restore_strings(src, strings)
  src.gsub(/__STR(\d+)__/) { strings[Regexp.last_match(1).to_i] }
end

def strip_comments(src)
  protected, strings = protect_strings(src)
  protected = protected.gsub(%r{/\*.*?\*/}m, "")
  protected = protected.gsub(%r{//[^\n]*}, "")
  restore_strings(protected, strings)
end

def mask_strings_and_comments(src)
  protected, _strings = protect_strings(src)
  protected = protected.gsub(%r{/\*.*?\*/}m, "")
  protected.gsub(%r{//[^\n]*}, "")
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
    if src[i, 3] == '"""' || src[i] == '"'
      i = index_after_string(src, i)
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

def extract_struct_body(src, name)
  m = src.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?struct\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_enum_body(src, name)
  m = src.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?enum\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_func_body(src, name)
  m = src.match(/(?:^|\n)[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]*)*(?:(?:private|public|fileprivate|internal|open|override|final|static|nonisolated)\s+)*func\s+#{Regexp.escape(name)}\s*\(/)
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

def strip_if_false_blocks(src)
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

def reachable_code(src)
  return "" if src.nil?
  strip_if_false_blocks(mask_strings_and_comments(src))
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

CONTRACT_PATH = "tasks/task-40.md"
ACCEPTANCE_TEST_PATHS = [
  "macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceTranscriptTypographyTests.swift",
  "macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptTypographyIntegrationTests.swift",
].freeze
WIRING_RB_PATH = ".claude/scripts/task40-wiring.rb"

PATHS = {
  typography: "macos/Packages/DesignSystem/Sources/DesignSystem/TranscriptTypography.swift",
  chat_typography: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatTypography.swift",
  scaled: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatScaledFont.swift",
  grouping: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptGrouping.swift",
  transcript: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptView.swift",
  basic: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift",
  common: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCellsCommon.swift",
  structured: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift",
  command_group: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+CommandGroup.swift",
  task_list: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+TaskList.swift",
  markdown: "macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift",
  code_block: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeBlock.swift",
  code_card: "macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeCard.swift",
  compacting: "macos/Packages/SessionFeature/Sources/SessionFeature/CompactingIndicatorCell.swift",
  user_question: "macos/Packages/SessionFeature/Sources/SessionFeature/UserQuestionCell.swift",
}.freeze

ALLOWED_PRODUCT_KEYS = PATHS.keys.freeze

UNCHANGED_PATHS = [
  "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift",
  "macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift",
  "macos/Packages/SessionFeature/Sources/SessionFeature/ComposerLayout.swift",
  "macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift",
  "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionAccessories.swift",
  "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift",
  "macos/Packages/DesignSystem/Sources/DesignSystem/ChatFontSettings.swift",
  "macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift",
  "macos/App/PhloxApp.swift",
].freeze

VIEW_SPECS = [
  { name: "UserMessageCell", key: :basic, any: ["ChatScaledFont.body(", "TranscriptTypography"] },
  { name: "ErrorMessageCell", key: :basic, any: ["ChatScaledFont.body(", "TranscriptTypography"] },
  { name: "AgentMessageBody", key: :basic, any: ["withinAnswer"] },
  { name: "TurnCostCell", key: :basic, any: ["codeMetadata", "ChatScaledFont.monoCaption("] },
  { name: "ChatTimestampText", key: :common, any: ["metadata", "ChatScaledFont.caption("] },
  { name: "DisclosureCard", key: :common, any: ["processSummary"] },
  { name: "ReasoningSummaryView", key: :structured, any: ["processSummary"] },
  { name: "SubAgentMarkerCell", key: :structured, any: ["processSummary"] },
  { name: "ThinkingIndicatorCell", key: :structured, any: ["ShimmerTextView"] },
  { name: "RunningTurnStatusView", key: :structured, any: ["metadata", "ChatScaledFont.caption("] },
  { name: "CommandExecutionCell", key: :structured, any: ["DisclosureCard"] },
  { name: "FileChangeCell", key: :structured, any: ["DisclosureCard"] },
  { name: "CommandGroupCell", key: :command_group, any: ["processSummary", "DisclosureCard"] },
  { name: "CommandGroupExecutionRow", key: :command_group, any: ["processSummary", "ChatScaledFont.mono("] },
  { name: "TaskListCell", key: :task_list, any: ["DisclosureCard", "ChatScaledFont.body("] },
  { name: "UserQuestionCell", key: :user_question, any: ["ChatScaledFont.body(", "TranscriptTypography"] },
  { name: "CompactingIndicatorCell", key: :compacting, any: ["ChatScaledFont.body(", "TranscriptTypography"] },
  { name: "CodeBlockView", key: :code_block, any: ["ChatScaledFont.mono(", "TranscriptTypography"] },
  { name: "ChatCodeCard", key: :code_card, any: ["ChatScaledFont", "TranscriptTypography"] },
  { name: "ChatTranscriptView", key: :transcript, any: ["TranscriptTypography.gap"] },
  { name: "RichMarkdownView", key: :markdown, any: ["ChatTypography.bodyFontSize", "TranscriptTypography"] },
].freeze

ROLE_CASES = %w[
  userMessage agentMessage commandGroup reasoning commandExecution
  fileChange subAgentMarker taskList userQuestion error turnCost
].freeze

SPACING_CONSTANTS = %w[
  withinAnswer betweenAnswers majorSection metadataGap textLineSpacing
  cardHorizontalInset cardVerticalInset codeContentInset
  transcriptHorizontalInset transcriptVerticalInset
].freeze

CONTRACT_BASELINE_PLACEHOLDER_RE = /PM|凍結|設定|TBD|TODO|FIXME|placeholder|未設定/i
CONTRACT_BASELINE_LINE_RE = /^baseline_commit:\s*(?:"([^"]*)"|(\S+))/

def match_contract_baseline_line(text)
  return nil if text.nil?
  m = text.match(CONTRACT_BASELINE_LINE_RE)
  return nil unless m
  m[1] || m[2]
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
        errs << "TASK40_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  if raw.nil? || raw.strip.empty?
    return [nil, ["TASK40_BASELINE が未設定（HEAD にフォールバックしない）"]]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    return [nil, ["TASK40_BASELINE に HEAD は使えない（短い SHA を渡す）"]]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    return [nil, ["TASK40_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"]]
  end
  [value, []]
end

def evaluate_frozen_baseline(full_sha:, is_ancestor:, typography_blob:, test_pairs:, rb_now:, rb_blob:)
  ng = []
  ng << "TASK40_BASELINE が HEAD の祖先ではない" unless is_ancestor
  if typography_blob
    ng << "基準時点に TranscriptTypography.swift がある（実装前の凍結ではない）"
  end
  test_pairs.each do |path, pair|
    if pair[:git].nil?
      ng << "基準時点の受け入れテストを git show できない（git show #{full_sha}:#{path}）"
    elsif !workdir_matches_git_blob?(pair[:now], pair[:git])
      ng << "基準時点の受け入れテストが現在と同一ではない: #{path}"
    end
  end
  if rb_blob.nil?
    ng << "基準時点の rb 自身を git show できない（git show #{full_sha}:#{WIRING_RB_PATH}）"
  elsif !workdir_matches_git_blob?(rb_now, rb_blob)
    ng << "基準時点の rb 自身が現在と同一ではない"
  end
  ng
end

def check_frozen_baseline(baseline)
  full = git_full_sha(baseline)
  if full.nil?
    return ["TASK40_BASELINE が無効なコミット: #{baseline}"]
  end
  evaluate_frozen_baseline(
    full_sha: full,
    is_ancestor: git_is_ancestor?(full, "HEAD"),
    typography_blob: git_show(full, PATHS[:typography]),
    test_pairs: ACCEPTANCE_TEST_PATHS.map { |path|
      [path, { now: read_if_exist(path), git: git_show(full, path) }]
    },
    rb_now: read_if_exist(WIRING_RB_PATH),
    rb_blob: git_show(full, WIRING_RB_PATH)
  )
end

def check_canonical(src)
  ng = []
  if src.nil?
    ng << "TranscriptTypography.swift が存在しない"
    return ng
  end
  reachable = reachable_code(src)
  ng << "TranscriptTypography が無い" unless src =~ /\b(enum|struct)\s+TranscriptTypography\b/
  ng << "Role が無い" unless src =~ /\b(enum|struct)\s+Role\b/
  ng << "Style が無い" unless src =~ /\b(enum|struct)\s+Style\b/
  ng << "BlockRole が無い" unless src =~ /\b(enum|struct)\s+BlockRole\b/
  ng << "style(for:) が無い" unless reachable =~ /\bfunc\s+style\s*\(/
  ng << "pointSize(for:scale:) が無い" unless reachable =~ /\bfunc\s+pointSize\s*\(/
  ng << "font(for:scale:) が無い" unless reachable =~ /\bfunc\s+font\s*\(/
  ng << "color(for:) が無い" unless reachable =~ /\bfunc\s+color\s*\(/
  ng << "gap(after:before:) が無い" unless reachable =~ /\bfunc\s+gap\s*\(/
  SPACING_CONSTANTS.each do |name|
    ng << "間隔定数 #{name} が無い" unless reachable.include?(name)
  end
  %w[UserDefaults FileManager Process URLSession].each do |tok|
    ng << "TranscriptTypography.swift に #{tok} がある" if reachable =~ /\b#{tok}\b/
  end
  ng
end

def function_mentions_role?(body, role)
  c = compact(body.to_s)
  c.include?("TranscriptTypography.pointSize(for:.#{role}") ||
    c.include?("TranscriptTypography.font(for:.#{role}") ||
    c.include?("TranscriptTypography.style(for:.#{role}")
end

def double_scale?(body)
  compact(body.to_s) =~ /TranscriptTypography\.(?:pointSize|font)\([^)]*\)\*scale/ ? true : false
end

def check_delegation(chat_src, scaled_src)
  ng = []
  if chat_src.nil?
    ng << "ChatTypography.swift が存在しない"
  else
    mapping = {
      "bodyFontSize" => "body",
      "codeFontSize" => "inlineCode",
      "heading1FontSize" => "heading1",
      "heading2FontSize" => "heading2",
      "heading3FontSize" => "heading3",
    }
    mapping.each do |func, role|
      body = extract_func_body(chat_src, func)
      if body.nil?
        ng << "ChatTypography.#{func} を切り出せない"
      elsif !function_mentions_role?(body, role)
        ng << "ChatTypography.#{func} が TranscriptTypography.#{role} へ委譲していない"
      elsif double_scale?(body)
        ng << "ChatTypography.#{func} が倍率を二重適用している"
      end
    end
  end
  if scaled_src.nil?
    ng << "ChatScaledFont.swift が存在しない"
  else
    mapping = {
      "body" => "body",
      "bodyPointSize" => "body",
      "caption" => "metadata",
      "captionStrong" => "metadataStrong",
      "mono" => "code",
      "monoCaption" => "codeMetadata",
    }
    mapping.each do |func, role|
      body = extract_func_body(scaled_src, func)
      if body.nil?
        ng << "ChatScaledFont.#{func} を切り出せない"
      elsif !function_mentions_role?(body, role)
        ng << "ChatScaledFont.#{func} が TranscriptTypography.#{role} へ委譲していない"
      elsif double_scale?(body)
        ng << "ChatScaledFont.#{func} が倍率を二重適用している"
      end
    end
  end
  ng
end

def check_view_connections(sources)
  ng = []
  VIEW_SPECS.each do |spec|
    src = sources[spec[:key]]
    if src.nil?
      ng << "#{spec[:name]} のファイルが存在しない"
      next
    end
    body = extract_struct_body(src, spec[:name])
    if body.nil?
      ng << "#{spec[:name]} の struct 本文を切り出せない"
      next
    end
    reachable = reachable_code(body)
    unless spec[:any].any? { |needle| reachable.include?(needle) }
      ng << "#{spec[:name]} が正本または委譲窓口へ到達していない"
    end
  end
  md = sources[:markdown]
  if md
    reachable = reachable_code(md)
    %w[heading1 heading2 heading3 heading4 heading5 heading6].each do |h|
      unless reachable.include?(h)
        ng << "RichMarkdownView が #{h} へ接続していない"
      end
    end
  end
  ng
end

def old_literal_hits(reachable, file_label)
  ng = []
  if reachable =~ /9\s*\*\s*scale/
    ng << "#{file_label} に料金の 9 * scale が残っている"
  end
  if reachable =~ /\.lineSpacing\s*\(\s*3\s*\)/
    ng << "#{file_label} に行間3 が残っている"
  end
  if reachable =~ /spacing:\s*2\b/
    ng << "#{file_label} に説明間2 が残っている"
  end
  ng
end

def check_old_literals(sources)
  ng = []
  PATHS.each do |key, path|
    next if key == :typography
    src = sources[key]
    next if src.nil?
    ng.concat(old_literal_hits(reachable_code(src), path))
  end
  disclosure = sources[:common] && extract_struct_body(sources[:common], "DisclosureCard")
  if disclosure
    disc = reachable_code(disclosure)
    if disc.include?("captionStrong") && !disc.include?("processSummary")
      ng << "共通見出しが captionStrong のまま"
    end
  end
  agent = sources[:basic] && extract_struct_body(sources[:basic], "AgentMessageBody")
  if agent
    c = compact(reachable_code(agent))
    if c =~ /VStack\([^)]*spacing:DSSpacing\.m/ || c =~ /VStack\([^)]*spacing:12/
      ng << "回答内間隔が 12 のまま"
    end
  end
  stack = sources[:transcript] && extract_func_body(sources[:transcript], "transcriptStack")
  if stack
    c = compact(reachable_code(stack))
    if c =~ /VStack\([^)]*spacing:DSSpacing\.m/ || c =~ /VStack\([^)]*spacing:12/
      ng << "一律ブロック間 12 が残っている"
    end
  end
  ng
end

def numeric_system_size?(src)
  reachable_code(src) =~ /\.system\s*\(\s*size:\s*\d/ ? true : false
end

def numeric_font_size?(src)
  reachable_code(src) =~ /\bFontSize\s*\(\s*\d/ ? true : false
end

def check_new_literals(sources)
  ng = []
  PATHS.each do |key, path|
    src = sources[key]
    next if src.nil?
    ng << "#{path} に新たな .system(size: 数値) がある" if numeric_system_size?(src)
    ng << "#{path} に新たな FontSize(数値) がある" if numeric_font_size?(src)
  end
  ng
end

def check_grouping_roles(src)
  ng = []
  if src.nil?
    ng << "ChatTranscriptGrouping.swift が存在しない"
    return ng
  end
  role = extract_var_body(src, "typographyRole")
  if role.nil?
    ng << "typographyRole を切り出せない"
    return ng
  end
  reachable = reachable_code(role)
  ROLE_CASES.each do |name|
    ng << "typographyRole に必須ケース #{name} が欠落している" unless reachable.include?(name)
  end
  ng
end

def check_shimmer(src)
  ng = []
  return ["ChatMessageCells+Structured.swift が存在しない"] if src.nil?
  found = false
  pos = 0
  while (m = src.match(/ShimmerTextView\s*\(/, pos))
    args = extract_balanced(src, m.end(0) - 1, "(", ")")
    found = true
    reachable = reachable_code(args.to_s)
    c = compact(reachable)
    font_body = c.include?("ChatScaledFont.body(") || c.include?("TranscriptTypography.font(for:.body")
    size_body = c.include?("bodyPointSize") || c.include?("pointSize(for:.body")
    ng << "ShimmerTextView の Font が body ではない" unless font_body
    ng << "ShimmerTextView の pointSize が body ではない" unless size_body
    pos = m.end(0)
  end
  ng << "ShimmerTextView 呼び出しが無い" unless found
  ng
end

def check_markdown_cache(src)
  ng = []
  return ["RichMarkdownView.swift が存在しない"] if src.nil?
  unless src =~ /func\s+themeCacheKey\s*\(\s*themeID\s*:\s*String\s*,\s*scale\s*:\s*CGFloat\s*\)/
    ng << "themeCacheKey が themeID と scale で分離していない"
    return ng
  end
  body = extract_func_body(src, "themeCacheKey")
  if body.nil?
    ng << "themeCacheKey を切り出せない"
  else
    stripped = strip_comments(body)
    ng << "themeCacheKey が themeID と scale で分離していない" unless stripped.include?("themeID") && stripped.include?("scale")
  end
  ng
end

def answer_answer_is_major?(gap_body)
  compact(gap_body.to_s) =~ /\.answer,\.answer\)[^c]{0,80}(?:majorSection|24)/ ? true : false
end

def check_gap_application(transcript_src, typography_src)
  ng = []
  if transcript_src.nil?
    ng << "ChatTranscriptView.swift が存在しない"
    return ng
  end
  stack = extract_func_body(transcript_src, "transcriptStack")
  if stack.nil?
    ng << "transcriptStack を切り出せない"
    return ng
  end
  reachable = reachable_code(stack)
  c = compact(reachable)
  ng << "transcriptStack が TranscriptTypography.gap を呼ばない" unless reachable.include?("TranscriptTypography.gap")
  ng << "transcriptStack が typographyRole を使わない" unless reachable.include?("typographyRole")
  unless c =~ /VStack\([^)]*spacing:0/
    if reachable.include?("TranscriptTypography.gap") && (c =~ /VStack\([^)]*spacing:DSSpacing\.m/ || c =~ /VStack\([^)]*spacing:12/)
      ng << "gap と親Stack間隔を二重加算している"
    else
      ng << "transcriptStack の親 VStack が spacing 0 ではない"
    end
  end
  unless reachable.include?("betweenAnswers") || c.include?("padding(.top,16") || c.include?("DSSpacing.l")
    ng << "履歴ボタンと先頭ブロックの間が 16pt ではない"
  end
  unless reachable.include?("withinAnswer") || c.include?("padding(.top,8") || c.include?("DSSpacing.s")
    ng << "処理中・圧縮中表示の前が 8pt ではない"
  end
  if typography_src
    gap_body = extract_func_body(typography_src, "gap")
    if gap_body.nil?
      ng << "gap(after:before:) の本文を切り出せない"
    elsif answer_answer_is_major?(gap_body)
      ng << "同一回答への 24pt がある"
    end
  end
  ng
end

def child_override?(sources)
  ng = []
  disclosure = sources[:common] && extract_struct_body(sources[:common], "DisclosureCard")
  if disclosure
    reachable = reachable_code(disclosure)
    if reachable.include?("processSummary") && reachable.include?("captionStrong")
      ng << "DisclosureCard で正本指定のあと captionStrong に上書きしている"
    end
  end
  ng
end

DRAW_CALL_PREFIXES = [
  ".font(",
  ".foregroundStyle(",
  ".foregroundColor(",
  ".lineSpacing(",
  ".padding(",
  ".markdownMargin(",
  "FontSize(",
  "FontWeight(",
  "ForegroundColor(",
  ".system(size:",
].freeze

def mask_prefix_calls(src, prefix)
  result = src.dup
  loop do
    i = result.index(prefix)
    break unless i
    paren = result.index("(", i)
    break unless paren
    args = extract_balanced(result, paren, "(", ")")
    break if args.nil?
    close = paren + 1 + args.length + 1
    result = result[0...i] + "__DRAW__" + result[close..]
  end
  result
end

def mask_ident_calls(src, ident)
  result = src.dup
  re = /#{Regexp.escape(ident)}\s*(?:\.\s*[A-Za-z_][A-Za-z0-9_]*)*/
  loop do
    m = result.match(re)
    break unless m
    i = m.end(0)
    i += 1 while i < result.length && result[i] =~ /\s/
    if i < result.length && result[i] == "("
      args = extract_balanced(result, i, "(", ")")
      break if args.nil?
      close = i + 1 + args.length + 1
      result = result[0...m.begin(0)] + "__DRAW__" + result[close..]
    else
      result = result[0...m.begin(0)] + "__DRAW__" + result[m.end(0)..]
    end
  end
  result
end

def mask_var_named(src, name)
  result = src.dup
  m = result.match(/(?:^|\n)[ \t]*(?:@[A-Za-z_][\w.]*[ \t]*)*(?:private\s+|public\s+|fileprivate\s+|internal\s+)?(?:static\s+)?var\s+#{Regexp.escape(name)}\b/)
  return result unless m
  brace = result.index("{", m.end(0))
  return result unless brace
  body = extract_balanced(result, brace, "{", "}")
  return result unless body
  close = brace + 1 + body.length + 1
  result[m.begin(0)...close] = "\n__DRAW_VAR__\n"
  result
end

def strip_allowed_surface(src)
  return "" if src.nil?
  result = src.dup
  result = mask_var_named(result, "typographyRole")
  DRAW_CALL_PREFIXES.each { |prefix| result = mask_prefix_calls(result, prefix) }
  %w[TranscriptTypography ChatScaledFont ChatTypography].each do |ident|
    result = mask_ident_calls(result, ident)
  end
  result = result.gsub(/spacing:\s*(?:DSSpacing\.\w+|TranscriptTypography\.\w+|\d+(?:\.\d+)?)/, "spacing:__DRAW__")
  result
end

def check_residual(current, previous, label)
  ng = []
  if current.nil?
    ng << "#{label} が存在しない"
    return ng
  end
  if previous.nil?
    ng << "git show baseline:#{label} に失敗"
    return ng
  end
  if normalize_code(strip_allowed_surface(current)) != normalize_code(strip_allowed_surface(previous))
    ng << "#{label} の残余が TASK40_BASELINE から変化している"
  end
  ng
end

def check_blob_identical(current, previous, label)
  ng = []
  if current.nil?
    ng << "#{label} が存在しない"
    return ng
  end
  if previous.nil?
    ng << "git show baseline:#{label} に失敗"
    return ng
  end
  ng << "#{label} が TASK40_BASELINE から変化している" unless current == previous
  ng
end

def inspect_product(sources, baseline_sources = nil, unchanged_now = nil, unchanged_base = nil)
  ng = []
  ng.concat(check_canonical(sources[:typography]))
  ng.concat(check_delegation(sources[:chat_typography], sources[:scaled]))
  ng.concat(check_view_connections(sources))
  ng.concat(check_old_literals(sources))
  ng.concat(check_new_literals(sources))
  ng.concat(check_grouping_roles(sources[:grouping]))
  ng.concat(check_shimmer(sources[:structured]))
  ng.concat(check_markdown_cache(sources[:markdown]))
  ng.concat(check_gap_application(sources[:transcript], sources[:typography]))
  ng.concat(child_override?(sources))
  if baseline_sources
    ALLOWED_PRODUCT_KEYS.each do |key|
      next if key == :typography
      path = PATHS[key]
      ng.concat(check_residual(sources[key], baseline_sources[key], path))
    end
  end
  if unchanged_now && unchanged_base
    UNCHANGED_PATHS.each do |path|
      ng.concat(check_blob_identical(unchanged_now[path], unchanged_base[path], path))
    end
  end
  ng
end

def selftest_assert(cond, msg)
  unless cond
    puts "task40-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def good_typography_src
  <<~SWIFT
    import SwiftUI
    enum TranscriptTypography {
      enum Role: CaseIterable, Equatable, Sendable {
        case body, bodyStrong, heading1, heading2, heading3, heading4, heading5, heading6
        case processSummary, metadata, metadataStrong, code, codeMetadata, inlineCode
      }
      struct Style: Equatable {
        var baseSize: CGFloat
        var weight: Weight
        var design: Design
        var ink: Ink
        enum Weight { case regular, medium, semibold, bold }
        enum Design { case system, monospaced }
        enum Ink { case primary, secondary, tool, accent }
      }
      enum BlockRole { case user, answer, process, auxiliary }
      static let withinAnswer: CGFloat = DSSpacing.s
      static let betweenAnswers: CGFloat = DSSpacing.l
      static let majorSection: CGFloat = DSSpacing.xl
      static let metadataGap: CGFloat = DSSpacing.xs
      static let textLineSpacing: CGFloat = DSSpacing.xs
      static let cardHorizontalInset: CGFloat = DSSpacing.m
      static let cardVerticalInset: CGFloat = DSSpacing.s
      static let codeContentInset: CGFloat = DSSpacing.m
      static let transcriptHorizontalInset: CGFloat = DSSpacing.l
      static let transcriptVerticalInset: CGFloat = DSSpacing.m
      static func style(for role: Role) -> Style { Style(baseSize: 15, weight: .regular, design: .system, ink: .primary) }
      static func pointSize(for role: Role, scale: CGFloat) -> CGFloat { 15 * scale }
      static func font(for role: Role, scale: CGFloat) -> Font { .system(size: pointSize(for: role, scale: scale)) }
      static func color(for role: Role) -> Color { DSColor.chatTextPrimary }
      static func gap(after: BlockRole?, before: BlockRole) -> CGFloat {
        switch (after, before) {
        case (nil, _): return 0
        case (_, .user): return majorSection
        case (.user, _): return betweenAnswers
        case (.answer, .answer), (.answer, .process), (.answer, .auxiliary): return withinAnswer
        case (.process, .answer), (.auxiliary, .answer): return betweenAnswers
        case (.process, .process), (.process, .auxiliary), (.auxiliary, .process), (.auxiliary, .auxiliary):
          return withinAnswer
        default: return 0
        }
      }
    }
  SWIFT
end

def good_chat_typography_src
  <<~SWIFT
    import CoreGraphics
    public enum ChatTypography {
      public static func bodyFontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .body, scale: scale)
      }
      public static func codeFontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .inlineCode, scale: scale)
      }
      public static func heading1FontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .heading1, scale: scale)
      }
      public static func heading2FontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .heading2, scale: scale)
      }
      public static func heading3FontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .heading3, scale: scale)
      }
    }
  SWIFT
end

def good_scaled_src
  <<~SWIFT
    import SwiftUI
    enum ChatScaledFont {
      static func body(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .body, scale: scale)
      }
      static func bodyPointSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .body, scale: scale)
      }
      static func caption(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .metadata, scale: scale)
      }
      static func captionStrong(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .metadataStrong, scale: scale)
      }
      static func mono(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .code, scale: scale)
      }
      static func monoCaption(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .codeMetadata, scale: scale)
      }
    }
  SWIFT
end

def good_grouping_src
  <<~SWIFT
    enum ChatTranscriptBlock: Identifiable, Equatable {
      case single(ChatItem)
      case commandGroup(id: String, items: [ChatItem])
      var id: String { "x" }
      var typographyRole: TranscriptTypography.BlockRole {
        switch self {
        case .single(.userMessage): return .user
        case .single(.agentMessage): return .answer
        case .commandGroup: return .process
        case .single(.reasoning), .single(.commandExecution), .single(.fileChange),
             .single(.subAgentMarker), .single(.taskList), .single(.userQuestion):
          return .process
        case .single(.error), .single(.turnCost): return .auxiliary
        }
      }
    }
    enum ChatTranscriptGrouping {
      static func blocks(from items: [ChatItem]) -> [ChatTranscriptBlock] { [] }
    }
  SWIFT
end

def good_transcript_src
  <<~SWIFT
    struct ChatTranscriptView: View {
      var body: some View { transcriptStack(items: [], transcriptSignal: sig) }
      private func transcriptStack(items: [ChatItem], transcriptSignal: TranscriptFollowSignal) -> some View {
        let visibleSlice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 8)
        return VStack(alignment: .leading, spacing: 0) {
          if visibleSlice.hiddenBlockCount > 0 {
            loadEarlierButton(hiddenCount: visibleSlice.hiddenBlockCount, anchorID: visibleSlice.blocks.first?.id)
              .padding(.bottom, TranscriptTypography.betweenAnswers)
          }
          ForEach(Array(visibleSlice.blocks.enumerated()), id: \\.element.id) { index, block in
            let after: TranscriptTypography.BlockRole? = index == 0 ? nil : visibleSlice.blocks[index - 1].content.typographyRole
            transcriptBlock(block.content, lastTranscriptID: transcriptSignal.lastID)
              .padding(.top, TranscriptTypography.gap(after: after, before: block.content.typographyRole))
          }
          CompactingIndicatorCell(descriptor: agentDescriptor)
            .padding(.top, TranscriptTypography.withinAnswer)
          ThinkingIndicatorCell(descriptor: agentDescriptor)
            .padding(.top, TranscriptTypography.withinAnswer)
        }
      }
    }
  SWIFT
end

def good_basic_src
  <<~SWIFT
    struct UserMessageCell: View {
      var body: some View {
        Text(text)
          .font(ChatScaledFont.body(scale: scale))
          .lineSpacing(TranscriptTypography.textLineSpacing)
      }
    }
    struct TurnCostCell: View {
      var body: some View {
        Text(Self.format(costUSD))
          .font(ChatScaledFont.monoCaption(scale: scale))
      }
    }
    struct AgentMessageBody: View {
      var body: some View {
        VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {
          RichMarkdownView(markdown)
          CodeBlockView(language: language, code: code)
        }
      }
    }
    struct ErrorMessageCell: View {
      var body: some View {
        Text(message)
          .font(ChatScaledFont.body(scale: scale))
          .foregroundStyle(DSColor.statusError)
          .lineSpacing(TranscriptTypography.textLineSpacing)
      }
    }
  SWIFT
end

def good_common_src
  <<~SWIFT
    struct ChatTimestampText: View {
      var body: some View {
        Text(Self.formatter.string(from: timestamp))
          .font(ChatScaledFont.caption(scale: scale))
      }
    }
    struct DisclosureCard<Content: View>: View {
      var body: some View {
        titleContent
          .font(TranscriptTypography.font(for: .processSummary, scale: scale))
          .foregroundStyle(DisclosureCardPalette.title(isToolCall: isToolCall))
        Text(subtitle)
          .font(TranscriptTypography.font(for: .metadata, scale: scale))
          .padding(.top, TranscriptTypography.metadataGap)
        content
      }
    }
  SWIFT
end

def good_structured_src
  <<~SWIFT
    struct SubAgentMarkerCell: View {
      var body: some View {
        VStack(alignment: .leading, spacing: TranscriptTypography.metadataGap) {
          Text(name).font(TranscriptTypography.font(for: .processSummary, scale: scale))
          Text(description).font(ChatScaledFont.caption(scale: scale))
        }
      }
    }
    struct ThinkingIndicatorCell: View {
      var body: some View {
        ShimmerTextView(
          text: state.orbLabel,
          font: ChatScaledFont.body(scale: scale),
          pointSize: ChatScaledFont.bodyPointSize(scale: scale),
          color: DSColor.chatTextPrimary,
          isVisible: isTimelineVisible
        )
      }
    }
    private struct RunningTurnStatusView: View {
      var body: some View {
        Text(Self.elapsedText(assessment.elapsed))
          .font(ChatScaledFont.caption(scale: scale))
      }
    }
    struct ReasoningSummaryView: View {
      var body: some View {
        Text(text).font(TranscriptTypography.font(for: .processSummary, scale: scale))
      }
    }
    struct CommandExecutionCell: View {
      var body: some View { DisclosureCard(isExpanded: $on, title: title, subtitle: nil) { EmptyView() } }
    }
    struct FileChangeCell: View {
      var body: some View { DisclosureCard(isExpanded: $on, title: title, subtitle: nil) { rows } }
    }
  SWIFT
end

def good_command_group_src
  <<~SWIFT
    struct CommandGroupCell: View {
      var body: some View {
        DisclosureCard(isExpanded: $on, title: title, subtitle: nil) {
          VStack(spacing: TranscriptTypography.withinAnswer) { rows }
        }
      }
    }
    private struct CommandGroupExecutionRow: View {
      var body: some View {
        Text(label).font(TranscriptTypography.font(for: .processSummary, scale: scale))
        Text(command).font(ChatScaledFont.mono(scale: scale))
      }
    }
  SWIFT
end

def good_task_list_src
  <<~SWIFT
    struct TaskListCell: View {
      var body: some View {
        DisclosureCard(isExpanded: $on, title: title, subtitle: nil) {
          Text(item.title).font(ChatScaledFont.body(scale: scale))
        }
      }
    }
  SWIFT
end

def good_markdown_src
  <<~SWIFT
    public struct RichMarkdownView: View {
      var body: some View {
        let _ = ChatTypography.bodyFontSize(scale: scale)
        markdownBody
      }
      static func themeCacheKey(themeID: String, scale: CGFloat) -> String {
        "\\(themeID):\\(scale)"
      }
    }
    private func chatMarkdownTheme(scale: CGFloat) -> Theme {
      Theme()
        .text { FontSize(ChatTypography.bodyFontSize(scale: scale)) }
        .heading1 { FontSize(ChatTypography.heading1FontSize(scale: scale)) }
        .heading2 { FontSize(ChatTypography.heading2FontSize(scale: scale)) }
        .heading3 { FontSize(ChatTypography.heading3FontSize(scale: scale)) }
        .heading4 { FontSize(TranscriptTypography.pointSize(for: .heading4, scale: scale)) }
        .heading5 { FontSize(TranscriptTypography.pointSize(for: .heading5, scale: scale)) }
        .heading6 { FontSize(TranscriptTypography.pointSize(for: .heading6, scale: scale)) }
    }
  SWIFT
end

def good_code_block_src
  <<~SWIFT
    struct CodeBlockView: View {
      var body: some View {
        Text(code).font(ChatScaledFont.mono(scale: scale))
      }
    }
  SWIFT
end

def good_code_card_src
  <<~SWIFT
    struct ChatCodeCard<Header: View, Content: View>: View {
      var body: some View {
        header.font(ChatScaledFont.monoCaption(scale: scale))
        content
      }
    }
  SWIFT
end

def good_compacting_src
  <<~SWIFT
    struct CompactingIndicatorCell: View {
      var body: some View {
        Text("圧縮中").font(ChatScaledFont.body(scale: scale))
      }
    }
  SWIFT
end

def good_user_question_src
  <<~SWIFT
    struct UserQuestionCell: View {
      var body: some View {
        VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {
          Text(question).font(ChatScaledFont.body(scale: scale))
          Text(detail).font(ChatScaledFont.caption(scale: scale))
        }
      }
    }
  SWIFT
end

def good_sources
  {
    typography: good_typography_src,
    chat_typography: good_chat_typography_src,
    scaled: good_scaled_src,
    grouping: good_grouping_src,
    transcript: good_transcript_src,
    basic: good_basic_src,
    common: good_common_src,
    structured: good_structured_src,
    command_group: good_command_group_src,
    task_list: good_task_list_src,
    markdown: good_markdown_src,
    code_block: good_code_block_src,
    code_card: good_code_card_src,
    compacting: good_compacting_src,
    user_question: good_user_question_src,
  }
end

def mutate(sources, key)
  copy = sources.dup
  copy[key] = yield(sources[key].dup)
  copy
end

def run_selftest
  url = %(let url = "https://example.com" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://example.com"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert !strip_comments("let a = 1 /* x */ let b = 2").include?("x"), "正例: /* */ を除去する"

  good = good_sources
  product_ng = inspect_product(good, good)
  selftest_assert product_ng.empty?, "正例: 契約どおりの直接参照・委譲は空 NG (#{product_ng.inspect})"

  comment_only = mutate(good, :basic) { |src| src.sub("struct UserMessageCell", "// keep\n    struct UserMessageCell") }
  comment_ng = inspect_product(comment_only, good)
  selftest_assert comment_ng.empty?, "正例: 意味を変えない空白・コメント変更 (#{comment_ng.inspect})"

  spaced = mutate(good, :basic) { |src| src.gsub("  ", "    ") }
  spaced_ng = inspect_product(spaced, good)
  selftest_assert spaced_ng.empty?, "正例: 空白だけの変更は合格 (#{spaced_ng.inspect})"

  drop = mutate(good, :common) { |src| src.sub("TranscriptTypography.font(for: .processSummary, scale: scale)", "ChatScaledFont.caption(scale: scale)") }
  drop_ng = inspect_product(drop)
  selftest_assert drop_ng.any? { |m| m.include?("DisclosureCard") }, "負例: 接続削除 (#{drop_ng.inspect})"

  wrong_role = mutate(good, :basic) { |src| src.sub("ChatScaledFont.monoCaption(scale: scale)", "ChatScaledFont.body(scale: scale)") }
  wrong_ng = inspect_product(wrong_role)
  selftest_assert wrong_ng.any? { |m| m.include?("TurnCostCell") }, "負例: 誤った役割 (#{wrong_ng.inspect})"

  override = mutate(good, :common) { |src|
    src.sub(
      ".font(TranscriptTypography.font(for: .processSummary, scale: scale))",
      ".font(TranscriptTypography.font(for: .processSummary, scale: scale))\n          .font(ChatScaledFont.captionStrong(scale: scale))"
    )
  }
  override_ng = inspect_product(override)
  selftest_assert override_ng.any? { |m| m.include?("上書き") }, "負例: 子Viewの上書き (#{override_ng.inspect})"

  old_cost = mutate(good, :basic) { |src|
    src.sub("struct TurnCostCell: View {", "struct TurnCostCell: View {\n      let revived = 9 * scale")
  }
  old_ng = inspect_product(old_cost)
  selftest_assert old_ng.any? { |m| m.include?("9 * scale") }, "負例: 旧直値の復活 (#{old_ng.inspect})"

  double = mutate(good, :scaled) { |src|
    src.sub(
      "TranscriptTypography.pointSize(for: .body, scale: scale)",
      "TranscriptTypography.pointSize(for: .body, scale: scale) * scale"
    )
  }
  double_ng = inspect_product(double)
  selftest_assert double_ng.any? { |m| m.include?("二重適用") }, "負例: 倍率の二重適用 (#{double_ng.inspect})"

  stacked = mutate(good, :transcript) { |src| src.sub("spacing: 0", "spacing: DSSpacing.m") }
  stacked_ng = inspect_product(stacked)
  selftest_assert stacked_ng.any? { |m| m.include?("二重加算") || m.include?("spacing 0") }, "負例: gapの二重加算 (#{stacked_ng.inspect})"

  major = mutate(good, :typography) { |src|
    src.sub("case (.answer, .answer), (.answer, .process), (.answer, .auxiliary): return withinAnswer",
            "case (.answer, .answer): return majorSection\n        case (.answer, .process), (.answer, .auxiliary): return withinAnswer")
  }
  major_ng = inspect_product(major)
  selftest_assert major_ng.any? { |m| m.include?("24pt") }, "負例: 同一回答への24pt (#{major_ng.inspect})"

  comment_ref = mutate(good, :common) { |src|
    src.sub(
      ".font(TranscriptTypography.font(for: .processSummary, scale: scale))",
      "// TranscriptTypography.font(for: .processSummary, scale: scale)"
    )
  }
  comment_ref_ng = inspect_product(comment_ref)
  selftest_assert comment_ref_ng.any? { |m| m.include?("DisclosureCard") }, "負例: コメントだけの参照 (#{comment_ref_ng.inspect})"

  unused = mutate(good, :common) { |src|
    src.sub(
      ".font(TranscriptTypography.font(for: .processSummary, scale: scale))",
      ".font(ChatScaledFont.caption(scale: scale))"
    ) + "\n    func unusedHelper() { _ = TranscriptTypography.font(for: .processSummary, scale: 1) }\n"
  }
  unused_ng = inspect_product(unused)
  selftest_assert unused_ng.any? { |m| m.include?("DisclosureCard") }, "負例: 未使用ヘルパー (#{unused_ng.inspect})"

  iff = mutate(good, :common) { |src|
    src.sub(
      ".font(TranscriptTypography.font(for: .processSummary, scale: scale))",
      "if false { .font(TranscriptTypography.font(for: .processSummary, scale: scale)) }"
    )
  }
  iff_ng = inspect_product(iff)
  selftest_assert iff_ng.any? { |m| m.include?("DisclosureCard") }, "負例: if false (#{iff_ng.inspect})"

  missing_case = mutate(good, :grouping) { |src| src.sub(".single(.turnCost)", ".single(.unknownCost)") }
  missing_ng = inspect_product(missing_case)
  selftest_assert missing_ng.any? { |m| m.include?("turnCost") }, "負例: 必須ケース欠落 (#{missing_ng.inspect})"

  copy_change = mutate(good, :basic) { |src| src.sub("RichMarkdownView(markdown)", "RichMarkdownView(\"gone\")") }
  copy_ng = inspect_product(copy_change, good)
  selftest_assert copy_ng.any? { |m| m.include?("残余") }, "負例: 許可面以外の残余改変 (#{copy_ng.inspect})"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_assert unset.nil? && unset_errs.any? { |m| m.include?("未設定") }, "負例: SHA欠落"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_assert head_errs.any? { |m| m.include?("HEAD") }, "負例: HEAD指定"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_assert head1_errs.any? { |m| m.include?("HEAD") }, "負例: HEAD~1 指定"
  _, headc_errs = baseline_env_errors("HEAD^")
  selftest_assert headc_errs.any? { |m| m.include?("HEAD") }, "負例: HEAD^ 指定"
  _, at_errs = baseline_env_errors("@")
  selftest_assert at_errs.any? { |m| m.include?("HEAD") }, "負例: @ 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_assert branch_errs.any? { |m| m.include?("ブランチ") || m.include?("SHA") }, "負例: ブランチ名は不正"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  frozen_ok = evaluate_frozen_baseline(
    full_sha: "abc1234",
    is_ancestor: true,
    typography_blob: nil,
    test_pairs: ACCEPTANCE_TEST_PATHS.map { |path| [path, { now: "t", git: "t" }] },
    rb_now: "rb",
    rb_blob: "rb"
  )
  selftest_assert frozen_ok.empty?, "正例: 固定SHAが HEAD と同じでも実装前 blob なら拒否しない (#{frozen_ok.inspect})"

  not_anc = evaluate_frozen_baseline(
    full_sha: "abc1234",
    is_ancestor: false,
    typography_blob: nil,
    test_pairs: ACCEPTANCE_TEST_PATHS.map { |path| [path, { now: "t", git: "t" }] },
    rb_now: "rb",
    rb_blob: "rb"
  )
  selftest_assert not_anc.any? { |m| m.include?("祖先") }, "負例: 非祖先"

  implemented = evaluate_frozen_baseline(
    full_sha: "abc1234",
    is_ancestor: true,
    typography_blob: "enum TranscriptTypography {}",
    test_pairs: ACCEPTANCE_TEST_PATHS.map { |path| [path, { now: "t", git: "t" }] },
    rb_now: "rb",
    rb_blob: "rb"
  )
  selftest_assert implemented.any? { |m| m.include?("実装前") }, "負例: 実装済み基準"

  blob_fail = evaluate_frozen_baseline(
    full_sha: "abc1234",
    is_ancestor: true,
    typography_blob: nil,
    test_pairs: ACCEPTANCE_TEST_PATHS.map { |path| [path, { now: "t", git: nil }] },
    rb_now: "rb",
    rb_blob: "rb"
  )
  selftest_assert blob_fail.any? { |m| m.include?("git show") }, "負例: blob取得失敗"

  test_changed = evaluate_frozen_baseline(
    full_sha: "abc1234",
    is_ancestor: true,
    typography_blob: nil,
    test_pairs: ACCEPTANCE_TEST_PATHS.map { |path| [path, { now: "now", git: "old" }] },
    rb_now: "rb",
    rb_blob: "rb"
  )
  selftest_assert test_changed.any? { |m| m.include?("受け入れテスト") }, "負例: 凍結テスト改変"

  rb_changed = evaluate_frozen_baseline(
    full_sha: "abc1234",
    is_ancestor: true,
    typography_blob: nil,
    test_pairs: ACCEPTANCE_TEST_PATHS.map { |path| [path, { now: "t", git: "t" }] },
    rb_now: "now",
    rb_blob: "old"
  )
  selftest_assert rb_changed.any? { |m| m.include?("rb 自身") }, "負例: 検査自身の改変"

  selftest_assert parse_contract_baseline_text("---\nfoo: 1\n") == :missing, "負例: 契約 baseline_commit 欠落"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n") == :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"not-a-sha\"\n") == :invalid, "負例: 契約 baseline_commit 不正"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"abc1234\"\n") == "abc1234", "正例: 契約 baseline_commit が SHA"
  mismatch_errs = contract_baseline_errors("---\nbaseline_commit: \"aaaaaaaa\"\n", "bbbbbbbb")
  selftest_assert mismatch_errs.any? { |m| m.include?("一致しない") || m.include?("無効") }, "負例: 契約SHAとの不一致"

  selftest_assert check_canonical(nil).any? { |m| m.include?("存在しない") }, "負例: 必要なファイルが無い"
  unchanged_ng = check_blob_identical("a", "b", "ChatSessionView.swift")
  selftest_assert unchanged_ng.any? { |m| m.include?("変化") }, "負例: 変更禁止対象の改変"
  selftest_assert check_blob_identical("a", "a", "ChatSessionView.swift").empty?, "正例: 変更禁止対象の blob 同一"
  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task40-wiring --selftest: OK"
  exit 0
end

ng = []
raw = ENV["TASK40_BASELINE"]
baseline, env_errs = baseline_env_errors(raw)
ng.concat(env_errs)

contract_text = File.exist?(CONTRACT_PATH) ? File.read(CONTRACT_PATH) : nil
if contract_text.nil?
  ng << "契約ファイル #{CONTRACT_PATH} が無い"
else
  ng.concat(contract_baseline_errors(contract_text, baseline))
end

if baseline
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK40_BASELINE が無効なコミット: #{baseline}"
    baseline = nil
  else
    ng.concat(check_frozen_baseline(full))
    baseline = full
  end
end

sources = {}
PATHS.each do |key, path|
  sources[key] = read_if_exist(path)
end

ng.concat(inspect_product(sources))

if baseline
  previous = {}
  PATHS.each do |key, path|
    previous[key] = git_show(baseline, path)
  end
  unchanged_now = {}
  unchanged_base = {}
  UNCHANGED_PATHS.each do |path|
    unchanged_now[path] = read_if_exist(path)
    unchanged_base[path] = git_show(baseline, path)
  end
  residual_ng = []
  ALLOWED_PRODUCT_KEYS.each do |key|
    next if key == :typography
    path = PATHS[key]
    residual_ng.concat(check_residual(sources[key], previous[key], path))
  end
  UNCHANGED_PATHS.each do |path|
    residual_ng.concat(check_blob_identical(unchanged_now[path], unchanged_base[path], path))
  end
  ng.concat(residual_ng)
end

ng = ng.uniq
if ng.empty?
  puts "task40-wiring: OK"
else
  ng.each { |m| puts "task40-wiring: NG #{m}" }
  exit 1
end
