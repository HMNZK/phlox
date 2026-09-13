#!/usr/bin/env ruby
# task-51 配線検査: 履歴タイトル材料が entry 生成へ渡り、加工前本文を使うこと。
# Claude の isMeta 除外と Codex の role 判定が材料収集に接続されていること。
# loader・preview 正規化・走査制限・DB 優先・読み取り専用・SQL は TASK51_BASELINE blob と比較する。
# コメントと文字列は同時識別する。比較元は git show <TASK51_BASELINE>:<path>。HEAD blob は使わない。

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

def reachable_from(src, name)
  return :unparseable if src.nil?
  stripped = strip_comments(src)
  cleaned = erase_if_false(stripped)
  start = extract_var_body(cleaned, name) || extract_func_body(cleaned, name)
  return :unparseable if start.nil?
  collect_reachable(cleaned, start)
end

def reachable_in_struct(src, struct_name, start)
  return :unparseable if src.nil?
  struct = extract_struct_body(strip_comments(src), struct_name)
  return :unparseable if struct.nil?
  reachable_from(struct, start)
end

def code_has_ident?(src, name)
  mask_strings_and_comments(src.to_s).match?(/\b#{Regexp.escape(name)}\b/)
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

def git_ls_files(rev, prefix)
  text = IO.popen(["git", "ls-tree", "-r", "--name-only", rev, prefix], err: [:child, :out], &:read)
  return [] unless $?.success?
  text.split("\n").reject(&:empty?)
end

def workdir_matches_git_blob?(workdir_text, git_blob)
  return false if git_blob.nil? || workdir_text.nil?
  workdir_text == git_blob
end

def read_if_exist(path)
  File.exist?(path) ? File.read(path) : nil
end

CONTRACT_PATH = "tasks/task-51.md"
ACCEPTANCE_TEST_PATH = "macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceHistoryTitleSourcesTests.swift"
WIRING_RB_PATH = ".claude/scripts/task51-wiring.rb"
ENTRY_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ClaudeSessionHistoryEntry.swift"
CLAUDE_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift"
CODEX_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift"
SPAWN_DIR = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn"
ALLOWED_SPAWN = [CLAUDE_PATH, CODEX_PATH].freeze
PRODUCTION_MARKER = "# === task51 production checks ==="

CONTRACT_BASELINE_PLACEHOLDER_RE = /PM|凍結|設定|TBD|TODO|FIXME|placeholder|未設定/i
CONTRACT_BASELINE_LINE_RE = /^baseline_commit:\s*(?:"([^"]*)"|'([^']*)'|(\S+))/

def scope_check_requested?(env = ENV)
  env["TASK51_SCOPE_CHECK"] == "1"
end

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
        errs << "TASK51_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK51_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK51_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK51_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
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

def implementation_in_baseline_errors(entry_blob, claude_blob, codex_blob)
  ng = []
  if entry_blob && code_has_ident?(entry_blob, "titleUserMessages")
    ng << "基準時点の ClaudeSessionHistoryEntry に titleUserMessages がある（実装前の凍結ではない）"
  end
  if claude_blob && code_has_ident?(claude_blob, "titleUserMessages")
    ng << "基準時点の Claude 取得器にタイトル材料配線がある（実装前の凍結ではない）"
  end
  if codex_blob && code_has_ident?(codex_blob, "titleUserMessages")
    ng << "基準時点の Codex 取得器にタイトル材料配線がある（実装前の凍結ではない）"
  end
  ng
end

def check_frozen_baseline(baseline, opts = {})
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK51_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  unless git_is_ancestor?(full, "HEAD")
    ng << "TASK51_BASELINE が HEAD の祖先ではない"
  end
  entry_blob = opts.key?(:entry_blob) ? opts[:entry_blob] : git_show(full, ENTRY_PATH)
  claude_blob = opts.key?(:claude_blob) ? opts[:claude_blob] : git_show(full, CLAUDE_PATH)
  codex_blob = opts.key?(:codex_blob) ? opts[:codex_blob] : git_show(full, CODEX_PATH)
  ng.concat(implementation_in_baseline_errors(entry_blob, claude_blob, codex_blob))
  test_blob = opts.key?(:test_blob) ? opts[:test_blob] : git_show(full, ACCEPTANCE_TEST_PATH)
  rb_blob = opts.key?(:rb_blob) ? opts[:rb_blob] : git_show(full, WIRING_RB_PATH)
  test_now = opts.key?(:test_now) ? opts[:test_now] : read_if_exist(ACCEPTANCE_TEST_PATH)
  rb_now = opts.key?(:rb_now) ? opts[:rb_now] : read_if_exist(WIRING_RB_PATH)
  ng.concat(frozen_artifact_errors("受け入れテスト", test_blob, test_now))
  ng.concat(frozen_artifact_errors("rb 自身", rb_blob, rb_now))
  ng
end

def has_public_optional_array?(compacted, name)
  compacted.include?("publiclet#{name}:[String]?")
end

def has_public_optional_string?(compacted, name)
  compacted.include?("publiclet#{name}:String?")
end

def check_entry_api(src)
  if src.nil?
    return ["ClaudeSessionHistoryEntry.swift が存在しない"]
  end
  ng = []
  stripped = strip_comments(src)
  masked = mask_strings_and_comments(src)
  unless masked =~ /\bstruct\s+ClaudeSessionHistoryEntry\b/
    ng << "ClaudeSessionHistoryEntry が無い"
    return ng
  end
  body = extract_struct_body(stripped, "ClaudeSessionHistoryEntry")
  if body.nil?
    ng << "ClaudeSessionHistoryEntry を解析できない"
    return ng
  end
  c = compact(body)
  ng << "public let titleUserMessages: [String]? が無い" unless has_public_optional_array?(c, "titleUserMessages")
  ng << "public let titleSummary: String? が無い" unless has_public_optional_string?(c, "titleSummary")
  ng << "既存 initializer に titleUserMessages: [String]? = nil が無い" unless c.include?("titleUserMessages:[String]?=nil")
  ng << "既存 initializer に titleSummary: String? = nil が無い" unless c.include?("titleSummary:String?=nil")
  ng
end

def entry_title_args(src)
  cleaned = erase_if_false(strip_comments(src.to_s))
  all_call_args(cleaned, "ClaudeSessionHistoryEntry").map do |args|
    {
      messages: labeled_arg(args, "titleUserMessages"),
      summary: labeled_arg(args, "titleSummary"),
      preview: labeled_arg(args, "preview")
    }
  end
end

def materials_transcribe_preview?(arg)
  return false if arg.nil?
  compact(arg).include?("normalizedPreview")
end

def check_claude_materials(src)
  if src.nil?
    return ["ClaudeSessionHistory.swift が存在しない"]
  end
  ng = []
  stripped = strip_comments(src)
  masked = mask_strings_and_comments(src)
  parsed = extract_struct_body(stripped, "ParsedLine")
  if parsed.nil?
    ng << (masked =~ /\bstruct\s+ParsedLine\b/ ? "ParsedLine を解析できない" : "ParsedLine に isMeta が無い")
  else
    ng << "ParsedLine に isMeta が無い" unless compact(parsed).include?("letisMeta:Bool?")
  end
  parse_body = extract_func_body(stripped, "parseLine")
  if parse_body.nil?
    ng << "parseLine が isMeta を読んでいない"
  else
    pc = compact(erase_if_false(parse_body))
    unless pc.include?("isMeta") && (pc.include?('json["isMeta"]') || pc.include?("json[\"isMeta\"]"))
      ng << "parseLine が isMeta を読んでいない"
    end
  end
  reach = reachable_in_struct(src, "ClaudeSessionHistoryDiscovery", "entries")
  if reach == :unparseable
    ng << "ClaudeSessionHistoryDiscovery.entries を解析できない"
    return ng
  end
  unless code_has_ident?(reach, "titleUserMessages")
    ng << "取得器が titleUserMessages を entry 生成へ渡していない"
    return ng
  end
  calls = entry_title_args(reach)
  connected = calls.reject { |c| c[:messages].nil? }
  if connected.empty?
    ng << "取得器が titleUserMessages を entry 生成へ渡していない"
    return ng
  end
  if connected.any? { |c| compact(c[:messages]) == "nil" }
    ng << "取得器が titleUserMessages に nil を渡している"
  end
  if connected.any? { |c| materials_transcribe_preview?(c[:messages]) }
    ng << "titleUserMessages が加工済み preview を転記している"
  end
  if connected.any? { |c| materials_transcribe_preview?(c[:summary]) }
    ng << "titleSummary が加工済み preview を転記している"
  end
  meta_ok = mask_strings_and_comments(reach).match?(/\bisMeta\b/) &&
    compact(reach).match?(/isMeta\s*(==\s*true|!=\s*true|==\s*false)/) ||
    compact(reach).include?("isMeta!=true") || compact(reach).include?("isMeta==true")
  ng << "Claude の isMeta 除外が材料収集に接続されていない" unless meta_ok
  ng
end

def check_codex_materials(src)
  if src.nil?
    return ["CodexSessionHistory.swift が存在しない"]
  end
  ng = []
  reach = reachable_in_struct(src, "CodexSessionHistoryDiscovery", "entries")
  if reach == :unparseable
    ng << "CodexSessionHistoryDiscovery.entries を解析できない"
    return ng
  end
  unless code_has_ident?(reach, "titleUserMessages")
    ng << "取得器が titleUserMessages を entry 生成へ渡していない"
    return ng
  end
  calls = entry_title_args(reach)
  connected = calls.reject { |c| c[:messages].nil? }
  if connected.empty?
    ng << "取得器が titleUserMessages を entry 生成へ渡していない"
    return ng
  end
  if connected.any? { |c| compact(c[:messages]) == "nil" }
    ng << "取得器が titleUserMessages に nil を渡している"
  end
  if connected.any? { |c| materials_transcribe_preview?(c[:messages]) }
    ng << "titleUserMessages が加工済み preview を転記している"
  end
  if connected.any? { |c| materials_transcribe_preview?(c[:summary]) }
    ng << "titleSummary が加工済み preview を転記している"
  end
  scan_body = extract_func_body(strip_comments(src), "scan")
  if scan_body.nil?
    ng << "Codex の role 判定が材料収集に接続されていない"
  else
    scan_reach = collect_reachable(strip_comments(src), erase_if_false(scan_body))
    unless code_has_ident?(scan_reach, "messageRole") && code_has_ident?(scan_reach, "titleUserMessages")
      ng << "Codex の role 判定が材料収集に接続されていない"
    end
  end
  query = extract_func_body(strip_comments(src), "queryDatabase")
  if query
    qc = compact(erase_if_false(query))
    unless qc.include?("titleUserMessages") && qc.include?("[]")
      ng << "取得器が titleUserMessages を entry 生成へ渡していない" unless ng.include?("取得器が titleUserMessages を entry 生成へ渡していない")
    end
  end
  ng
end

def loader_uses_isMeta?(src)
  return false if src.nil?
  loader = extract_struct_body(strip_comments(src), "ClaudeSessionTranscriptLoader")
  return false if loader.nil?
  append = extract_func_body(loader, "appendChatItem") || loader
  code_has_ident?(erase_if_false(append), "isMeta")
end

def check_loader_isolation(claude_src, _codex_src = nil)
  ng = []
  if claude_src.nil?
    return ["ClaudeSessionHistory.swift が存在しない"]
  end
  ng << "loader に isMeta 除外を流用している" if loader_uses_isMeta?(claude_src)
  ng
end

def static_let_rhs(src, name)
  masked = mask_strings_and_comments(src.to_s)
  m = masked.match(/(?:static\s+)?let\s+#{Regexp.escape(name)}\s*=\s*([^\n]+)/)
  return nil unless m
  compact(m[1])
end

def check_scan_limits(claude_src, codex_src)
  ng = []
  if claude_src.nil?
    ng << "ClaudeSessionHistory.swift が存在しない"
  else
    lines = static_let_rhs(claude_src, "maxLinesPerFile")
    ng << "Claude の maxLinesPerFile が 200 から拡大されている" unless lines == "200"
    bytes = static_let_rhs(claude_src, "maxBytesPerFile")
    ng << "Claude の maxBytesPerFile が 256 * 1024 から拡大されている" unless bytes == "256*1024"
  end
  if codex_src.nil?
    ng << "CodexSessionHistory.swift が存在しない"
  else
    meta = static_let_rhs(codex_src, "maxSessionMetaBytes")
    ng << "Codex の maxSessionMetaBytes が 16 * 1024 から拡大されている" unless meta == "16*1024"
    body = static_let_rhs(codex_src, "maxBytesPerFile")
    ng << "Codex の maxBytesPerFile が 512 * 1024 から拡大されている" unless body == "512*1024"
    scan = extract_func_body(strip_comments(codex_src), "scan")
    if scan.nil? || !compact(erase_if_false(scan)).include?("index>200")
      ng << "Codex の行数打ち切りが 200 から拡大されている"
    end
  end
  ng
end


def loader_uses_isMeta?(src)
  return false if src.nil?
  loader = extract_struct_body(strip_comments(src), "ClaudeSessionTranscriptLoader")
  return false if loader.nil?
  append = extract_func_body(loader, "appendChatItem") || loader
  code_has_ident?(erase_if_false(append), "isMeta")
end

def check_loader_isolation(claude_src, _codex_src = nil)
  ng = []
  if claude_src.nil?
    return ["ClaudeSessionHistory.swift が存在しない"]
  end
  ng << "loader に isMeta 除外を流用している" if loader_uses_isMeta?(claude_src)
  ng
end

def static_let_rhs(src, name)
  masked = mask_strings_and_comments(src.to_s)
  m = masked.match(/(?:static\s+)?let\s+#{Regexp.escape(name)}\s*=\s*([^\n]+)/)
  return nil unless m
  compact(m[1])
end

def check_scan_limits(claude_src, codex_src)
  ng = []
  if claude_src.nil?
    ng << "ClaudeSessionHistory.swift が存在しない"
  else
    lines = static_let_rhs(claude_src, "maxLinesPerFile")
    ng << "Claude の maxLinesPerFile が 200 から拡大されている" unless lines == "200"
    bytes = static_let_rhs(claude_src, "maxBytesPerFile")
    ng << "Claude の maxBytesPerFile が 256 * 1024 から拡大されている" unless bytes == "256*1024"
  end
  if codex_src.nil?
    ng << "CodexSessionHistory.swift が存在しない"
  else
    meta = static_let_rhs(codex_src, "maxSessionMetaBytes")
    ng << "Codex の maxSessionMetaBytes が 16 * 1024 から拡大されている" unless meta == "16*1024"
    body = static_let_rhs(codex_src, "maxBytesPerFile")
    ng << "Codex の maxBytesPerFile が 512 * 1024 から拡大されている" unless body == "512*1024"
    scan = extract_func_body(strip_comments(codex_src), "scan")
    if scan.nil? || !compact(erase_if_false(scan)).include?("index>200")
      ng << "Codex の行数打ち切りが 200 から拡大されている"
    end
  end
  ng
end

def check_db_priority_and_readonly(src)
  if src.nil?
    return ["CodexSessionHistory.swift が存在しない"]
  end
  ng = []
  entries = extract_func_body(strip_comments(src), "entries")
  if entries.nil?
    ng << "CodexSessionHistoryDiscovery.entries を解析できない"
  else
    cleaned = erase_if_false(entries)
    c = compact(cleaned)
    unless c.include?("ifletdatabaseEntries=databaseEntries") && c.include?("returndatabaseEntries")
      ng << "DB 利用時に rollout を追加走査している"
    end
    if c.match?(/ifletdatabaseEntries=databaseEntries[^\{]{0,400}isEmpty/)
      ng << "DB 利用時に rollout を追加走査している"
    end

  end
  query = extract_func_body(strip_comments(src), "queryDatabase")
  if query.nil?
    ng << "SQLite 接続が読み取り専用ではない"
  else
    q = erase_if_false(query)
    qc = compact(q)
    unless qc.include?("SQLITE_OPEN_READONLY")
      ng << "SQLite 接続が読み取り専用ではない"
    end
    if qc.include?("SQLITE_OPEN_READWRITE")
      ng << "SQLite 接続が読み取り専用ではない"
    end
  end
  ng.uniq
end

def frozen_func_errors(label, current_src, baseline_src, struct_name, func_name)
  return ["#{label} の基準を git show できない"] if baseline_src.nil?
  return ["#{label} が存在しない"] if current_src.nil?
  cur_struct = struct_name ? extract_struct_body(strip_comments(current_src), struct_name) : strip_comments(current_src)
  base_struct = struct_name ? extract_struct_body(strip_comments(baseline_src), struct_name) : strip_comments(baseline_src)
  if cur_struct.nil? || base_struct.nil?
    return ["#{label} を解析できない"]
  end
  cur = extract_func_body(cur_struct, func_name)
  base = extract_func_body(base_struct, func_name)
  if base.nil?
    return ["#{label} の基準を解析できない"]
  end
  if cur.nil?
    return ["#{label} を解析できない"]
  end
  compact(erase_if_false(cur)) == compact(erase_if_false(base)) ? [] : ["#{label} が TASK51_BASELINE から変化している"]
end

def sql_compact(src)
  body = extract_func_body(strip_comments(src.to_s), "queryDatabase")
  return nil if body.nil?
  compact(erase_if_false(body))
end

def check_frozen_restore(current, baseline)
  ng = []
  return ng if baseline.nil?
  ng.concat(frozen_func_errors("normalizedPreview", current[:claude], baseline[:claude], "ClaudeSessionHistoryDiscovery", "normalizedPreview"))
  ng.concat(frozen_func_errors("ClaudeSessionTranscriptLoader.load", current[:claude], baseline[:claude], "ClaudeSessionTranscriptLoader", "load"))
  ng.concat(frozen_func_errors("appendChatItem", current[:claude], baseline[:claude], "ClaudeSessionTranscriptLoader", "appendChatItem"))
  ng.concat(frozen_func_errors("Codex loadTranscript", current[:codex], baseline[:codex], "CodexSessionHistoryDiscovery", "loadTranscript"))
  ng.concat(frozen_func_errors("messageRole", current[:codex], baseline[:codex], "CodexSessionHistoryDiscovery", "messageRole"))
  ng.concat(frozen_func_errors("Codex normalizedPreview", current[:codex], baseline[:codex], "CodexSessionHistoryDiscovery", "normalizedPreview"))
  cur_sql = current[:codex] && sql_compact(current[:codex])
  base_sql = baseline[:codex] && sql_compact(baseline[:codex])
  if base_sql.nil?
    ng << "SQL の採否・cwd 条件が基準から変化している" unless current[:codex].nil?
  elsif cur_sql.nil?
    ng << "SQL の採否・cwd 条件が基準から変化している"
  else
    needles = [
      "archived=0",
      "cwd=?",
      "preview<>''ORfirst_user_message<>''",
      "ORDERBYupdated_at_msDESC,idDESC"
    ]
    needles.each do |n|
      unless cur_sql.include?(n)
        ng << "SQL の採否・cwd 条件が基準から変化している"
        break
      end
    end
    needles.each do |n|
      unless base_sql.include?(n)
        next
      end
    end
  end
  ng.uniq
end

def missing_file_errors(files)
  ng = []
  ng << "ClaudeSessionHistoryEntry.swift が存在しない" if files[:entry].nil?
  ng << "ClaudeSessionHistory.swift が存在しない" if files[:claude].nil?
  ng << "CodexSessionHistory.swift が存在しない" if files[:codex].nil?
  ng
end

def check_product(files, baseline_files = nil)
  ng = []
  ng.concat(missing_file_errors(files))
  ng.concat(check_entry_api(files[:entry])) unless files[:entry].nil? && ng.include?("ClaudeSessionHistoryEntry.swift が存在しない")
  ng.concat(check_claude_materials(files[:claude])) unless files[:claude].nil? && ng.include?("ClaudeSessionHistory.swift が存在しない")
  ng.concat(check_codex_materials(files[:codex])) unless files[:codex].nil? && ng.include?("CodexSessionHistory.swift が存在しない")
  ng.concat(check_loader_isolation(files[:claude], files[:codex])) unless files[:claude].nil?
  ng.concat(check_scan_limits(files[:claude], files[:codex]))
  ng.concat(check_db_priority_and_readonly(files[:codex])) unless files[:codex].nil?
  ng.concat(check_frozen_restore(files, baseline_files)) if baseline_files
  ng.uniq
end

def spawn_files_from(map)
  map.select { |path, _| path.start_with?("#{SPAWN_DIR}/") && path.end_with?(".swift") }
end

def scope_source_errors(current_spawn, baseline_spawn, baseline_label)
  if baseline_spawn.empty?
    return ["baseline #{baseline_label} から Spawn ソースを読めない（黙示的成功にしない）"]
  end
  ng = []
  paths = (current_spawn.keys + baseline_spawn.keys).uniq
  paths.each do |path|
    next if ALLOWED_SPAWN.include?(path)
    base = baseline_spawn[path]
    cur = current_spawn[path]
    if base.nil? && !cur.nil?
      ng << "新規製品ファイル #{path} がある（許可は履歴取得器のみ）"
    elsif cur.nil? && !base.nil?
      ng << "#{path} が基準から欠落している"
    elsif !workdir_matches_git_blob?(cur, base)
      ng << "#{path} が基準 blob と同一ではない"
    end
  end
  ng
end

def worktree_spawn_sources
  files = {}
  Dir.glob("#{SPAWN_DIR}/**/*.swift").sort.each do |path|
    files[path] = File.read(path)
  end
  files
end

def baseline_spawn_sources(rev)
  files = {}
  git_ls_files(rev, SPAWN_DIR).each do |path|
    blob = git_show(rev, path)
    files[path] = blob unless blob.nil?
  end
  files
end

def worktree_files
  {
    entry: read_if_exist(ENTRY_PATH),
    claude: read_if_exist(CLAUDE_PATH),
    codex: read_if_exist(CODEX_PATH)
  }
end

def baseline_product_files(rev)
  {
    entry: git_show(rev, ENTRY_PATH),
    claude: git_show(rev, CLAUDE_PATH),
    codex: git_show(rev, CODEX_PATH)
  }
end

def good_entry_src
  <<~SWIFT
    public struct ClaudeSessionHistoryEntry: Equatable, Sendable, Identifiable {
      public var id: String { sessionID }
      public let sessionID: String
      public let preview: String
      public let firstUserAt: Date?
      public let lastModified: Date
      public let gitBranch: String?
      public let fileURL: URL
      public let titleUserMessages: [String]?
      public let titleSummary: String?

      public init(
        sessionID: String,
        preview: String,
        firstUserAt: Date?,
        lastModified: Date,
        gitBranch: String?,
        fileURL: URL,
        titleUserMessages: [String]? = nil,
        titleSummary: String? = nil
      ) {
        self.sessionID = sessionID
        self.preview = preview
        self.firstUserAt = firstUserAt
        self.lastModified = lastModified
        self.gitBranch = gitBranch
        self.fileURL = fileURL
        self.titleUserMessages = titleUserMessages
        self.titleSummary = titleSummary
      }
    }
  SWIFT
end

def baseline_entry_src
  <<~SWIFT
    public struct ClaudeSessionHistoryEntry: Equatable, Sendable, Identifiable {
      public var id: String { sessionID }
      public let sessionID: String
      public let preview: String
      public let firstUserAt: Date?
      public let lastModified: Date
      public let gitBranch: String?
      public let fileURL: URL

      public init(
        sessionID: String,
        preview: String,
        firstUserAt: Date?,
        lastModified: Date,
        gitBranch: String?,
        fileURL: URL
      ) {
        self.sessionID = sessionID
        self.preview = preview
        self.firstUserAt = firstUserAt
        self.lastModified = lastModified
        self.gitBranch = gitBranch
        self.fileURL = fileURL
      }
    }
  SWIFT
end

def good_claude_src
  <<~SWIFT
    struct ClaudeSessionHistoryDiscovery: Sendable {
      static let maxLinesPerFile = 200
      static let maxBytesPerFile = 256 * 1024

      func entries(forWorkingDirectory workingDirectory: String, limit: Int) -> [ClaudeSessionHistoryEntry] {
        let scan = Self.scanFile(at: fileURL)
        guard !scan.isSidechainFile else { continue }
        guard let firstUser = scan.firstUserLine else { continue }
        discovered.append(
          ClaudeSessionHistoryEntry(
            sessionID: sessionID,
            preview: Self.normalizedPreview(from: firstUser.text),
            firstUserAt: firstUser.timestamp,
            lastModified: lastModified,
            gitBranch: firstUser.gitBranch,
            fileURL: fileURL,
            titleUserMessages: scan.titleUserMessages,
            titleSummary: nil
          )
        )
        discovered.sort { $0.lastModified > $1.lastModified }
        return Array(discovered.prefix(limit))
      }

      private static func scanFile(at fileURL: URL) -> FileScanResult {
        while lineCount < maxLinesPerFile, reader.bytesConsumed < maxBytesPerFile {
          processScannedLine(line, titleUserMessages: &titleUserMessages)
        }
        return FileScanResult(titleUserMessages: titleUserMessages)
      }

      private static func processScannedLine(_ line: String, titleUserMessages: inout [String]) {
        if parsed.isSidechain == true { isSidechainFile = true }
        if parsed.type == "user", let userText = extractUserText(from: parsed) {
          if parsed.isMeta == true {
          } else {
            titleUserMessages.append(userText)
          }
          if firstUserLine == nil, !userText.hasPrefix("<") {
            firstUserLine = UserLineInfo(text: userText, timestamp: parsed.timestamp, gitBranch: parsed.gitBranch)
          }
        }
      }

      private static func normalizedPreview(from text: String) -> String {
        let collapsed = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if collapsed.count <= 120 { return collapsed }
        return String(collapsed.prefix(120))
      }
    }

    struct ClaudeSessionTranscriptLoader: Sendable {
      func load(fileURL: URL, maxItems: Int) -> [ChatItem] {
        var items: [ChatItem] = []
        appendChatItem(from: line, lineIndex: 0, into: &items)
        return items
      }

      private func appendChatItem(from line: String, lineIndex: Int, into items: inout [ChatItem]) {
        guard let parsed = ClaudeSessionHistoryDiscovery.parseLine(line) else { return }
        switch parsed.type {
        case "user":
          guard let text = ClaudeSessionHistoryDiscovery.extractUserText(from: parsed), !text.hasPrefix("<") else { return }
          items.append(.userMessage(id: id, text: text, timestamp: timestamp))
        default:
          break
        }
      }
    }

    extension ClaudeSessionHistoryDiscovery {
      struct ParsedLine {
        let type: String?
        let message: ParsedMessage?
        let uuid: String?
        let timestamp: String?
        let gitBranch: String?
        let isSidechain: Bool?
        let isMeta: Bool?
      }

      static func parseLine(_ line: String) -> ParsedLine? {
        return ParsedLine(
          type: json["type"] as? String,
          isMeta: json["isMeta"] as? Bool
        )
      }

      static func extractUserText(from line: ParsedLine) -> String? { nil }
    }
  SWIFT
end

def good_codex_src
  <<~SWIFT
    struct CodexSessionHistoryDiscovery: Sendable {
      static let maxSessionMetaBytes = 16 * 1024
      static let maxBytesPerFile = 512 * 1024

      func entries(
        forWorkingDirectory workingDirectory: String,
        limit: Int,
        onScan: (@Sendable (URL) -> Void)? = nil,
        onRead: (@Sendable (Int) -> Void)? = nil
      ) -> [ClaudeSessionHistoryEntry] {
        if let databaseEntries = databaseEntries(forWorkingDirectory: workingDirectory, normalizedCWD: normalizedCWD, limit: limit) {
          return databaseEntries
        }
        for candidate in rolloutFiles() {
          guard let scan = scan(candidate.url, matchingCWD: normalizedCWD, onScan: onScan, onRead: onRead) else { continue }
          result.append(
            ClaudeSessionHistoryEntry(
              sessionID: sessionID,
              preview: Self.normalizedPreview(preview),
              firstUserAt: scan.firstUserAt,
              lastModified: candidate.modified,
              gitBranch: nil,
              fileURL: candidate.url,
              titleUserMessages: scan.titleUserMessages,
              titleSummary: nil
            )
          )
        }
        return result
      }

      private func databaseEntries(forWorkingDirectory workingDirectory: String, normalizedCWD: String, limit: Int) -> [ClaudeSessionHistoryEntry]? {
        queryDatabase(databaseURL: databaseURL, cwd: normalizedCWD, limit: limit)
      }

      private func queryDatabase(databaseURL: URL, cwd: String, limit: Int) -> [ClaudeSessionHistoryEntry]? {
        let result = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil)
        let sql = """
        SELECT id, rollout_path, preview, first_user_message, updated_at_ms
        FROM threads
        WHERE archived = 0 AND cwd = ?
          AND (preview <> '' OR first_user_message <> '')
        ORDER BY updated_at_ms DESC, id DESC
        LIMIT ?
        """
        let rawFirst = Self.databaseString(statement, column: 3)
        let titleUsers: [String]
        if let rawFirst, !rawFirst.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          titleUsers = [rawFirst]
        } else {
          titleUsers = []
        }
        let titleSummary = Self.databaseString(statement, column: 2)
        entries.append(
          ClaudeSessionHistoryEntry(
            sessionID: sessionID,
            preview: Self.normalizedPreview(preview),
            firstUserAt: nil,
            lastModified: updatedAt,
            gitBranch: nil,
            fileURL: URL(fileURLWithPath: rolloutPath),
            titleUserMessages: titleUsers,
            titleSummary: titleSummary
          )
        )
        return entries
      }

      private func scan(_ fileURL: URL, matchingCWD: String, onScan: (@Sendable (URL) -> Void)?, onRead: (@Sendable (Int) -> Void)?) -> Scan? {
        var titleUserMessages: [String] = []
        for (index, line) in String(decoding: data, as: UTF8.self).split(whereSeparator: \\.isNewline).enumerated() {
          if let role = Self.messageRole(in: object), role == "user", let text = Self.messageText(in: object, role: role) {
            titleUserMessages.append(text)
          }
          if scan.firstUserText == nil, let text = Self.messageText(in: object, role: "user") {
            scan.firstUserText = text
          }
          if index > 200 { break }
        }
        scan.titleUserMessages = titleUserMessages
        return scan
      }

      static func loadTranscript(fileURL: URL, maxItems: Int) -> [ChatItem] { [] }

      private static func messageRole(in object: [String: Any]) -> String? {
        if object["type"] as? String == "response_item" { return payload["role"] as? String }
        return nil
      }

      private static func messageText(in object: [String: Any], role: String) -> String? { nil }

      private static func normalizedPreview(_ text: String) -> String {
        let collapsed = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return collapsed.count <= 120 ? collapsed : String(collapsed.prefix(120))
      }
    }
  SWIFT
end

def good_files
  { entry: good_entry_src, claude: good_claude_src, codex: good_codex_src }
end

def baseline_claude_src
  <<~SWIFT
    struct ClaudeSessionHistoryDiscovery: Sendable {
      static let maxLinesPerFile = 200
      static let maxBytesPerFile = 256 * 1024

      func entries(forWorkingDirectory workingDirectory: String, limit: Int) -> [ClaudeSessionHistoryEntry] {
        let scan = Self.scanFile(at: fileURL)
        guard !scan.isSidechainFile else { continue }
        guard let firstUser = scan.firstUserLine else { continue }
        discovered.append(
          ClaudeSessionHistoryEntry(
            sessionID: sessionID,
            preview: Self.normalizedPreview(from: firstUser.text),
            firstUserAt: firstUser.timestamp,
            lastModified: lastModified,
            gitBranch: firstUser.gitBranch,
            fileURL: fileURL
          )
        )
        discovered.sort { $0.lastModified > $1.lastModified }
        return Array(discovered.prefix(limit))
      }

      private static func scanFile(at fileURL: URL) -> FileScanResult {
        while lineCount < maxLinesPerFile, reader.bytesConsumed < maxBytesPerFile {
          processScannedLine(line)
        }
        return FileScanResult()
      }

      private static func processScannedLine(_ line: String) {
        if parsed.isSidechain == true { isSidechainFile = true }
        if parsed.type == "user", let userText = extractUserText(from: parsed) {
          if firstUserLine == nil, !userText.hasPrefix("<") {
            firstUserLine = UserLineInfo(text: userText, timestamp: parsed.timestamp, gitBranch: parsed.gitBranch)
          }
        }
      }

      private static func normalizedPreview(from text: String) -> String {
        let collapsed = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if collapsed.count <= 120 { return collapsed }
        return String(collapsed.prefix(120))
      }
    }

    struct ClaudeSessionTranscriptLoader: Sendable {
      func load(fileURL: URL, maxItems: Int) -> [ChatItem] {
        var items: [ChatItem] = []
        appendChatItem(from: line, lineIndex: 0, into: &items)
        return items
      }

      private func appendChatItem(from line: String, lineIndex: Int, into items: inout [ChatItem]) {
        guard let parsed = ClaudeSessionHistoryDiscovery.parseLine(line) else { return }
        switch parsed.type {
        case "user":
          guard let text = ClaudeSessionHistoryDiscovery.extractUserText(from: parsed), !text.hasPrefix("<") else { return }
          items.append(.userMessage(id: id, text: text, timestamp: timestamp))
        default:
          break
        }
      }
    }

    extension ClaudeSessionHistoryDiscovery {
      struct ParsedLine {
        let type: String?
        let message: ParsedMessage?
        let uuid: String?
        let timestamp: String?
        let gitBranch: String?
        let isSidechain: Bool?
      }

      static func parseLine(_ line: String) -> ParsedLine? {
        return ParsedLine(
          type: json["type"] as? String
        )
      }

      static func extractUserText(from line: ParsedLine) -> String? { nil }
    }
  SWIFT
end

def baseline_codex_src
  <<~SWIFT
    struct CodexSessionHistoryDiscovery: Sendable {
      static let maxSessionMetaBytes = 16 * 1024
      static let maxBytesPerFile = 512 * 1024

      func entries(
        forWorkingDirectory workingDirectory: String,
        limit: Int,
        onScan: (@Sendable (URL) -> Void)? = nil,
        onRead: (@Sendable (Int) -> Void)? = nil
      ) -> [ClaudeSessionHistoryEntry] {
        if let databaseEntries = databaseEntries(forWorkingDirectory: workingDirectory, normalizedCWD: normalizedCWD, limit: limit) {
          return databaseEntries
        }
        for candidate in rolloutFiles() {
          guard let scan = scan(candidate.url, matchingCWD: normalizedCWD, onScan: onScan, onRead: onRead) else { continue }
          result.append(
            ClaudeSessionHistoryEntry(
              sessionID: sessionID,
              preview: Self.normalizedPreview(preview),
              firstUserAt: scan.firstUserAt,
              lastModified: candidate.modified,
              gitBranch: nil,
              fileURL: candidate.url
            )
          )
        }
        return result
      }

      private func databaseEntries(forWorkingDirectory workingDirectory: String, normalizedCWD: String, limit: Int) -> [ClaudeSessionHistoryEntry]? {
        queryDatabase(databaseURL: databaseURL, cwd: normalizedCWD, limit: limit)
      }

      private func queryDatabase(databaseURL: URL, cwd: String, limit: Int) -> [ClaudeSessionHistoryEntry]? {
        let result = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil)
        let sql = """
        SELECT id, rollout_path, preview, first_user_message, updated_at_ms
        FROM threads
        WHERE archived = 0 AND cwd = ?
          AND (preview <> '' OR first_user_message <> '')
        ORDER BY updated_at_ms DESC, id DESC
        LIMIT ?
        """
        let rawFirst = Self.databaseString(statement, column: 3)
        entries.append(
          ClaudeSessionHistoryEntry(
            sessionID: sessionID,
            preview: Self.normalizedPreview(preview),
            firstUserAt: nil,
            lastModified: updatedAt,
            gitBranch: nil,
            fileURL: URL(fileURLWithPath: rolloutPath)
          )
        )
        return entries
      }

      private func scan(_ fileURL: URL, matchingCWD: String, onScan: (@Sendable (URL) -> Void)?, onRead: (@Sendable (Int) -> Void)?) -> Scan? {
        for (index, line) in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).enumerated() {
          if scan.firstUserText == nil, let text = Self.messageText(in: object, role: "user") {
            scan.firstUserText = text
          }
          if index > 200 { break }
        }
        return scan
      }

      static func loadTranscript(fileURL: URL, maxItems: Int) -> [ChatItem] { [] }

      private static func messageRole(in object: [String: Any]) -> String? {
        if object["type"] as? String == "response_item" { return payload["role"] as? String }
        return nil
      }

      private static func messageText(in object: [String: Any], role: String) -> String? { nil }

      private static func normalizedPreview(_ text: String) -> String {
        let collapsed = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return collapsed.count <= 120 ? collapsed : String(collapsed.prefix(120))
      }
    }
  SWIFT
end

def baseline_files
  { entry: baseline_entry_src, claude: baseline_claude_src, codex: baseline_codex_src }
end

def with_replaced(src, old, new)
  return src.sub(old, new) if src.include?(old)
  pattern = old.split(/\s+/).map { |token| Regexp.escape(token) }.join('\s+')
  updated = src.sub(Regexp.new(pattern), new)
  raise "replace failed: #{old}" if updated == src
  updated
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
    code.include?("scope_source_errors") &&
    code.match?(/if baseline && scope_check_requested\?/)
end

def selftest_assert(cond, msg = "assertion")
  unless cond
    puts "task51-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task51-wiring --selftest: FAIL #{msg}"
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

  good = good_files
  base = baseline_files
  selftest_errors_eq check_entry_api(good[:entry]), [], "正例: 公開契約の新規2フィールドと既定 nil"
  selftest_errors_eq check_claude_materials(good[:claude]), [], "正例: Claude 材料配線"
  selftest_errors_eq check_codex_materials(good[:codex]), [], "正例: Codex 材料配線"
  selftest_errors_eq check_loader_isolation(good[:claude]), [], "正例: loader は isMeta 除外なし"
  selftest_errors_eq check_scan_limits(good[:claude], good[:codex]), [], "正例: 走査上限は基準値"
  selftest_errors_eq check_db_priority_and_readonly(good[:codex]), [], "正例: DB 優先と読み取り専用"
  selftest_errors_eq check_frozen_restore(good, base), [], "正例: loader・preview・SQL は基準と同一"
  selftest_errors_eq check_product(good, base), [], "正例: 本番検査関数が配線済み fixture を通す"

  selftest_errors_eq check_entry_api(nil), ["ClaudeSessionHistoryEntry.swift が存在しない"], "負例: 対象不在"
  selftest_errors_eq check_product({}), [
    "ClaudeSessionHistoryEntry.swift が存在しない",
    "ClaudeSessionHistory.swift が存在しない",
    "CodexSessionHistory.swift が存在しない"
  ], "負例: 対象欠落"

  comment_only = <<~SWIFT
    // public let titleUserMessages: [String]?
    // public let titleSummary: String?
    public struct ClaudeSessionHistoryEntry {
      public let sessionID: String
      public init(sessionID: String, preview: String, firstUserAt: Date?, lastModified: Date, gitBranch: String?, fileURL: URL) {}
    }
  SWIFT
  selftest_errors_eq check_entry_api(comment_only), [
    "public let titleUserMessages: [String]? が無い",
    "public let titleSummary: String? が無い",
    "既存 initializer に titleUserMessages: [String]? = nil が無い",
    "既存 initializer に titleSummary: String? = nil が無い"
  ], "負例: コメント等による偽装"

  disconnected = with_replaced(good[:claude], "titleUserMessages: scan.titleUserMessages,", "")
  selftest_errors_eq check_claude_materials(disconnected), ["取得器が titleUserMessages を entry 生成へ渡していない"], "負例: 材料未接続"

  preview_copy = with_replaced(good[:claude], "titleUserMessages: scan.titleUserMessages,", "titleUserMessages: [Self.normalizedPreview(from: firstUser.text)],")
  selftest_errors_eq check_claude_materials(preview_copy), ["titleUserMessages が加工済み preview を転記している"], "負例: 加工済み preview の転記"

  meta_mix = with_replaced(good[:claude], "if parsed.isMeta == true {\n          } else {\n            titleUserMessages.append(userText)\n          }", "titleUserMessages.append(userText)")
  selftest_errors_eq check_claude_materials(meta_mix), ["Claude の isMeta 除外が材料収集に接続されていない"], "負例: メタ本文混入"

  no_role = with_replaced(good[:codex], "if let role = Self.messageRole(in: object), role == \"user\", let text = Self.messageText(in: object, role: role) {\n            titleUserMessages.append(text)\n          }", "if let text = Self.messageText(in: object, role: \"user\") {\n            titleUserMessages.append(text)\n          }")
  selftest_errors_eq check_codex_materials(no_role), ["Codex の role 判定が材料収集に接続されていない"], "負例: role 判定欠落"

  loader_leak = with_replaced(good[:claude], "guard let text = ClaudeSessionHistoryDiscovery.extractUserText(from: parsed), !text.hasPrefix(\"<\") else { return }", "guard let text = ClaudeSessionHistoryDiscovery.extractUserText(from: parsed), parsed.isMeta != true, !text.hasPrefix(\"<\") else { return }")
  selftest_errors_eq check_loader_isolation(loader_leak), ["loader に isMeta 除外を流用している"], "負例: loader への除外流用"

  widened = with_replaced(good[:claude], "static let maxLinesPerFile = 200", "static let maxLinesPerFile = 2000")
  selftest_errors_eq check_scan_limits(widened, good[:codex]), ["Claude の maxLinesPerFile が 200 から拡大されている"], "負例: 走査上限拡大"

  extra_scan = with_replaced(good[:codex], "if let databaseEntries = databaseEntries(forWorkingDirectory: workingDirectory, normalizedCWD: normalizedCWD, limit: limit) {\n          return databaseEntries\n        }", "if let databaseEntries = databaseEntries(forWorkingDirectory: workingDirectory, normalizedCWD: normalizedCWD, limit: limit), !databaseEntries.isEmpty {\n          return databaseEntries\n        }")
  selftest_errors_eq check_db_priority_and_readonly(extra_scan), ["DB 利用時に rollout を追加走査している"], "負例: DB 利用時の追加走査"

  writable = with_replaced(good[:codex], "SQLITE_OPEN_READONLY", "SQLITE_OPEN_READWRITE")
  selftest_errors_eq check_db_priority_and_readonly(writable), ["SQLite 接続が読み取り専用ではない"], "負例: 書込接続"

  if_false = good[:claude].sub(
    "titleUserMessages: scan.titleUserMessages,",
    "titleUserMessages: scan.titleUserMessages,\n            if false { titleUserMessages: [Self.normalizedPreview(from: firstUser.text)] }"
  )
  selftest_errors_eq check_claude_materials(if_false), [], "正例: if false 内の記述は配線に使わない"

  string_decoy = good[:claude] + %(\nlet decoy = "titleUserMessages isMeta == true normalizedPreview"\n)
  selftest_errors_eq check_claude_materials(string_decoy), [], "正例: 文字列内の識別子は配線ではない"

  unused = good[:claude] + <<~SWIFT

    private func unusedTitleHelper() {
      if parsed.isMeta == true { return }
      let _ = ClaudeSessionHistoryEntry(sessionID: "", preview: "", firstUserAt: nil, lastModified: Date(), gitBranch: nil, fileURL: url, titleUserMessages: nil, titleSummary: nil)
    }
  SWIFT
  selftest_errors_eq check_claude_materials(unused).select { |m| m.include?("nil") }, [], "正例: 未使用ヘルパーの nil 渡しは entries 配線を壊さない"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_assert unset.nil?, "負例: SHA 未設定は baseline を返さない"
  selftest_errors_eq unset_errs, ["TASK51_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: SHA 未設定"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK51_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD 指定"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK51_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD~1 指定"
  _, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK51_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: @ 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK51_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
  _, bad_errs = baseline_env_errors("not-a-sha")
  selftest_errors_eq bad_errs, ["TASK51_BASELINE がコミット SHA ではない（ブランチ名は使えない）: not-a-sha"], "負例: 不正 SHA"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"
  selftest_assert !workdir_matches_git_blob?("a", "b"), "負例: git show 内容の不一致"

  selftest_errors_eq frozen_artifact_errors("受け入れテスト", "blob", "blob"), [], "正例: 凍結テストが作業ツリーと同一"
  selftest_errors_eq frozen_artifact_errors("受け入れテスト", nil, "blob"), ["基準時点の受け入れテストを git show できない"], "負例: blob 欠落"
  selftest_errors_eq frozen_artifact_errors("受け入れテスト", "blob", "changed"), ["基準時点の受け入れテストが現在と同一ではない"], "負例: 凍結検査改変"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "rb", "rb"), [], "正例: 凍結 rb が作業ツリーと同一"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "rb", "changed"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 検査改変"

  selftest_errors_eq implementation_in_baseline_errors(baseline_entry_src, baseline_claude_src, baseline_codex_src), [], "正例: 基準に新規材料フィールドも配線もない"
  selftest_errors_eq(
    implementation_in_baseline_errors(good[:entry], good[:claude], good[:codex]),
    [
      "基準時点の ClaudeSessionHistoryEntry に titleUserMessages がある（実装前の凍結ではない）",
      "基準時点の Claude 取得器にタイトル材料配線がある（実装前の凍結ではない）",
      "基準時点の Codex 取得器にタイトル材料配線がある（実装前の凍結ではない）"
    ],
    "負例: 実装入り基準"
  )

  selftest_assert parse_contract_baseline_text("---\nfoo: 1\n") == :missing, "負例: 契約 baseline_commit 欠落"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n") == :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"not-a-sha\"\n") == :invalid, "負例: 契約 baseline_commit 不正"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"abc1234\"\n") == "abc1234", "正例: 契約 baseline_commit がクォート付き SHA"
  ph_errs = contract_baseline_errors("---\nbaseline_commit: \"PM が凍結時に設定\"\n", "abc1234")
  selftest_errors_eq ph_errs, ["契約 baseline_commit がプレースホルダ（凍結時に実 SHA へ置換する）"], "負例: プレースホルダは NG"

  head_full = git_full_sha("HEAD")
  other_full = git_full_sha("HEAD~1")
  selftest_assert !head_full.nil? && !other_full.nil? && head_full != other_full, "selftest 用に有効で異なる 2 コミットが必要"
  real_mismatch = contract_baseline_errors("---\nbaseline_commit: \"#{head_full}\"\n", other_full)
  selftest_errors_eq real_mismatch, ["TASK51_BASELINE が契約 baseline_commit と一致しない"], "負例: 契約不一致"
  match_errs = contract_baseline_errors("---\nbaseline_commit: \"#{head_full}\"\n", head_full)
  selftest_errors_eq match_errs, [], "正例: TASK51_BASELINE が契約 baseline_commit と一致"

  pre_ok = check_frozen_baseline(
    head_full,
    entry_blob: baseline_entry_src,
    claude_blob: baseline_claude_src,
    codex_blob: baseline_codex_src,
    test_blob: "test",
    test_now: "test",
    rb_blob: "rb",
    rb_now: "rb"
  )
  selftest_errors_eq pre_ok, [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  post_ng = check_frozen_baseline(
    head_full,
    entry_blob: good[:entry],
    claude_blob: good[:claude],
    codex_blob: good[:codex],
    test_blob: "test",
    test_now: "test",
    rb_blob: "rb",
    rb_now: "rb"
  )
  selftest_errors_eq post_ng, [
    "基準時点の ClaudeSessionHistoryEntry に titleUserMessages がある（実装前の凍結ではない）",
    "基準時点の Claude 取得器にタイトル材料配線がある（実装前の凍結ではない）",
    "基準時点の Codex 取得器にタイトル材料配線がある（実装前の凍結ではない）"
  ], "負例: 実装後の自己比較"

  flower = "#{SPAWN_DIR}/Other.swift"
  base_spawn = { flower => "import Foundation\n" }
  with_only_allowed = base_spawn.merge(CLAUDE_PATH => good[:claude], CODEX_PATH => good[:codex])
  with_extra = with_only_allowed.merge("#{SPAWN_DIR}/New.swift" => "x\n")
  selftest_errors_eq scope_source_errors(with_only_allowed, base_spawn, "selftest"), [], "正例: 許可取得器の変更は範囲内"
  selftest_errors_eq(
    scope_source_errors(with_extra, base_spawn, "selftest"),
    ["新規製品ファイル #{SPAWN_DIR}/New.swift がある（許可は履歴取得器のみ）"],
    "負例: 許可外の Spawn 追加"
  )
  selftest_errors_eq(
    scope_source_errors({ flower => "changed\n" }, base_spawn, "selftest"),
    ["#{flower} が基準 blob と同一ではない"],
    "負例: Spawn 既存ファイル改変"
  )
  selftest_errors_eq(
    scope_source_errors({}, {}, "deadbeef"),
    ["baseline deadbeef から Spawn ソースを読めない（黙示的成功にしない）"],
    "負例: 変更範囲検査で baseline ソース欠落"
  )

  with_env("TASK51_SCOPE_CHECK", "1") { selftest_assert scope_check_requested?, "正例: SCOPE_CHECK=1 で変更範囲検査 ON" }
  with_env("TASK51_SCOPE_CHECK", "0") { selftest_assert !scope_check_requested?, "負例: SCOPE_CHECK=0 では変更範囲検査 OFF" }
  with_env("TASK51_SCOPE_CHECK", nil) { selftest_assert !scope_check_requested?, "正例: 未設定では材料・復元検査のみ" }

  prod = production_checks_source
  selftest_assert !prod.empty?, "正例: 本番検査セクションが存在する"
  selftest_assert baseline_check_connected?(prod), "正例: 基準検査が本番に接続されている"
  disconnected_prod = prod.gsub("check_frozen_baseline", "removed_fn")
  selftest_assert !baseline_check_connected?(disconnected_prod), "負例: 基準検査の本番接続を外す変異"
  selftest_assert scope_check_gated?(prod), "正例: 変更範囲検査が TASK51_SCOPE_CHECK でゲートされている"
  ungated = prod.gsub("if baseline && scope_check_requested?", "if baseline")
  selftest_assert !scope_check_gated?(ungated), "負例: 変更範囲検査のゲートを外す変異"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task51-wiring --selftest: OK"
  exit 0
end

# === task51 production checks ===
ng = []

raw = ENV["TASK51_BASELINE"]
baseline, env_errs = baseline_env_errors(raw)
ng.concat(env_errs)

contract_text = File.exist?(CONTRACT_PATH) ? File.read(CONTRACT_PATH) : nil
if contract_text.nil?
  ng << "契約ファイル #{CONTRACT_PATH} が無い"
else
  ng.concat(contract_baseline_errors(contract_text, baseline))
end

files = worktree_files
ng.concat(check_product(files, nil))

if baseline
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK51_BASELINE が無効なコミット: #{baseline}"
    baseline = nil
  else
    ng.concat(check_frozen_baseline(full))
    previous = baseline_product_files(full)
    ng.concat(check_frozen_restore(files, previous))
    baseline = full
  end
end

if baseline && scope_check_requested?
  ng.concat(scope_source_errors(worktree_spawn_sources, baseline_spawn_sources(baseline), baseline))
end

ng = ng.uniq
if ng.empty?
  puts "task51-wiring: OK"
else
  ng.each { |m| puts "task51-wiring: NG #{m}" }
  exit 1
end
