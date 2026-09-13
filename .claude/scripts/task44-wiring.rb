#!/usr/bin/env ruby
# task-44 凍結検査:
# 1) 恒久回帰（名前状態 API・採用経路・四フィールド保存・PID・早期ガード・typography）は常に実行する。
# 2) 変更範囲検査は TASK44_SCOPE_CHECK=1 のときだけ。
# 比較対象は git show <TASK44_BASELINE>:<path>。HEAD フォールバックはしない。

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
  protected, strings = protect_strings(src.to_s)
  protected = protected.gsub(%r{/\*.*?\*/}m, "")
  protected = protected.gsub(%r{//[^\n]*}, "")
  restore_strings(protected, strings)
end

def mask_strings_and_comments(src)
  protected, _strings = protect_strings(src.to_s)
  protected = protected.gsub(%r{/\*.*?\*/}m, "")
  protected.gsub(%r{//[^\n]*}, "")
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

CONTRACT_PATH = "tasks/task-44.md"
WIRING_RB_PATH = ".claude/scripts/task44-wiring.rb"
TITLE_STATE_PATH = "macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleState.swift"
DERIVER_PATH = "macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleDeriver.swift"
DESCRIPTOR_PATH = "macos/Packages/AgentDomain/Sources/AgentDomain/PersistedSessionDescriptor.swift"
CONTROLLABLE_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ControllableSession.swift"
CHAT_VM_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift"
PTY_VM_PATH = "macos/Packages/SessionFeature/Sources/SessionFeature/SessionViewModel.swift"
DASHBOARD_VM_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift"
SPAWN_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift"
RESTORE_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionRestoreCoordinator.swift"
PERSIST_PATH = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionPersistenceCoordinator.swift"
FLOWER_PATH = "macos/Packages/AgentDomain/Sources/AgentDomain/FlowerNameGenerator.swift"

ACCEPTANCE_PATHS = [
  "macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleStateTests.swift",
  "macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDescriptorTests.swift",
  "macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionTitleLifecycleTests.swift",
  "macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceSessionTitlePersistenceTests.swift",
].freeze

ALLOWED_PRODUCT_PATHS = [
  TITLE_STATE_PATH,
  DESCRIPTOR_PATH,
  CONTROLLABLE_PATH,
  CHAT_VM_PATH,
  PTY_VM_PATH,
  DASHBOARD_VM_PATH,
  SPAWN_PATH,
  RESTORE_PATH,
  PERSIST_PATH,
  "docs/agent-output/task-44.md",
].freeze

PRODUCTION_MARKER = "# === task44 production checks ==="
CONTRACT_BASELINE_PLACEHOLDER_RE = /PM|凍結|設定|TBD|TODO|FIXME|placeholder|未設定/i
CONTRACT_BASELINE_LINE_RE = /^baseline_commit:\s*(?:"([^"]*)"|'([^']*)'|(\S+))/

def scope_check_requested?(env = ENV)
  env["TASK44_SCOPE_CHECK"] == "1"
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
        errs << "TASK44_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK44_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK44_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK44_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
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

def implementation_in_baseline_errors(title_state_blob)
  return [] if title_state_blob.nil?
  ["基準時点に SessionTitleState.swift がある（実装前の凍結ではない）"]
end

def task41_in_baseline_errors(deriver_blob)
  return ["基準時点に SessionTitleDeriver.swift が無い（task-41 未成立）"] if deriver_blob.nil?
  []
end

def check_frozen_baseline(baseline, artifacts = nil)
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK44_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  unless git_is_ancestor?(full, "HEAD")
    ng << "TASK44_BASELINE が HEAD の祖先ではない"
  end
  if artifacts
    ng.concat(task41_in_baseline_errors(artifacts[:deriver_blob]))
    ng.concat(implementation_in_baseline_errors(artifacts[:title_state_blob]))
    ACCEPTANCE_PATHS.each_with_index do |path, idx|
      ng.concat(frozen_artifact_errors("受け入れテスト#{idx + 1}", artifacts[:test_blobs][idx], artifacts[:test_nows][idx]))
    end
    ng.concat(frozen_artifact_errors("rb 自身", artifacts[:rb_blob], artifacts[:rb_now]))
  else
    ng.concat(task41_in_baseline_errors(git_show(full, DERIVER_PATH)))
    ng.concat(implementation_in_baseline_errors(git_show(full, TITLE_STATE_PATH)))
    ACCEPTANCE_PATHS.each_with_index do |path, idx|
      ng.concat(frozen_artifact_errors("受け入れテスト#{idx + 1}", git_show(full, path), read_if_exist(path)))
    end
    ng.concat(frozen_artifact_errors("rb 自身", git_show(full, WIRING_RB_PATH), read_if_exist(WIRING_RB_PATH)))
  end
  ng
end

def has_early_guard_before?(compacted, index)
  before = compacted[[index - 1200, 0].max...index]
  has_derived = before.include?(".derived") || before.include?("SessionTitleSource.derived")
  has_manual = before.include?(".manual") || before.include?("SessionTitleSource.manual")
  has_return = before.include?("return")
  has_derived && has_manual && has_return
end

def extraction_guard_errors(src, label)
  return [] if src.nil?
  masked = mask_strings_and_comments(src)
  ng = []
  names = masked.scan(/(?:^|\n)[ \t]*(?:(?:private|public|fileprivate|internal|open|override|final|static|nonisolated)\s+)*func\s+(\w+)\s*\(/).flatten
  names.uniq.each do |name|
    body = extract_func_body(masked, name)
    next if body.nil?
    c = compact(body)
    %w[InputHistoryPolicy.entries SessionTitleDeriver.derive].each do |needle|
      idx = c.index(needle)
      next if idx.nil?
      unless has_early_guard_before?(c, idx)
        ng << "#{label} が derived/manual の早期ガードより前に履歴抽出している"
      end
    end
    if c.include?("iffalse") && (c.include?("InputHistoryPolicy.entries") || c.include?("SessionTitleDeriver.derive"))
      ng << "#{label} が derived/manual の早期ガードより前に履歴抽出している"
    end
  end
  ng.uniq
end

def check_title_state_api(src)
  if src.nil?
    return ["SessionTitleState.swift が存在しない"]
  end
  ng = []
  masked = mask_strings_and_comments(src)
  unless masked =~ /\bpublic\s+enum\s+SessionTitleSource\b/
    ng << "public enum SessionTitleSource が無い"
  end
  unless masked =~ /\bpublic\s+struct\s+SessionTitleState\b/
    ng << "public struct SessionTitleState が無い"
  end
  body = extract_struct_body(masked, "SessionTitleState")
  if masked =~ /\bstruct\s+SessionTitleState\b/ && body.nil?
    ng << "SessionTitleState を解析できない"
  elsif body
    c = compact(body)
    ng << "public let name: String が無い" unless c.include?("publicletname:String")
    ng << "public let source: SessionTitleSource が無い" unless c.include?("publicletsource:SessionTitleSource")
    ng << "generated(flowerName:) が無い" unless c.include?("staticfuncgenerated(flowerName:")
    ng << "legacy(name:) が無い" unless c.include?("staticfunclegacy(name:")
    ng << "receivingUserMessage が無い" unless c.include?("funcreceivingUserMessage(")
    ng << "renamed(to:) が無い" unless c.include?("funcrenamed(toname:")
    ng << "effectiveName(fallback:) が無い" unless c.include?("funceffectiveName(fallback:")
  end
  recv = extract_func_body(masked, "receivingUserMessage")
  if recv
    rc = compact(recv)
    derive_at = rc.index("SessionTitleDeriver.derive")
    if derive_at && !has_early_guard_before?(rc, derive_at)
      ng << "receivingUserMessage が derived/manual の早期ガードより前に SessionTitleDeriver.derive を呼んでいる"
    elsif derive_at.nil?
      ng << "receivingUserMessage が derived/manual の早期ガードより前に SessionTitleDeriver.derive を呼んでいる" unless rc.include?("returnself") && rc.include?(".derived") && rc.include?(".manual")
    end
  elsif masked =~ /\bstruct\s+SessionTitleState\b/
    ng << "receivingUserMessage が無い" unless ng.include?("receivingUserMessage が無い")
  end
  ng
end

def check_descriptor(src)
  if src.nil?
    return ["PersistedSessionDescriptor.swift が存在しない"]
  end
  ng = []
  masked = mask_strings_and_comments(src)
  c = compact(masked)
  ng << "titleSource 引数が無い" unless c.include?("titleSource:SessionTitleSource?")
  ng << "flowerName 引数が無い" unless c.include?("flowerName:String?")
  ng << "fullDerivedTitle 引数が無い" unless c.include?("fullDerivedTitle:String?")
  ng << "titleState 窓口が無い" unless c.include?("vartitleState:SessionTitleState") || c.include?("lettitleState")
  ng << "updating(titleState:) が無い" unless c.include?("funcupdating(titleState:")
  %w[titleSource flowerName fullDerivedTitle].each do |key|
    ng << "CodingKeys に #{key} が無い" unless c.include?(key)
  end
  ng << "token を encode している" if c.include?("encode(token") || c.include?("encodeIfPresent(token")
  ng
end

def check_controllable(src)
  if src.nil?
    return ["ControllableSession.swift が存在しない"]
  end
  ng = []
  masked = mask_strings_and_comments(src)
  c = compact(masked)
  ng << "ControllableSession に titleState が無い" unless c.include?("vartitleState:SessionTitleState")
  ng << "既定実装 .legacy(name: name) が無い" unless c.include?(".legacy(name:name)") || c.include?("legacy(name:name)")
  ng << "SessionNode.titleState が中継していない" unless c.include?("vartitleState:SessionTitleState{controllable.titleState}") || c.include?("controllable.titleState")
  ng
end

def check_vm_title(src, label)
  if src.nil?
    return ["#{label} が存在しない"]
  end
  ng = []
  masked = mask_strings_and_comments(src)
  c = compact(masked)
  ng << "#{label} に titleState が無い" unless c.include?("titleState")
  ng << "#{label} の displayName が effectiveName を使っていない" unless c.include?("effectiveName(fallback:")
  ng.concat(extraction_guard_errors(src, label))
  ng
end

def check_generated_not_name_assign(src, label)
  return [] if src.nil?
  masked = mask_strings_and_comments(src)
  c = compact(masked)
  if c =~ /\.name=generatedName/ || c =~ /name=generatedName/ || c =~ /sessionVM\.name=generated/
    return ["#{label} が花名を通常の name 代入で設定している"]
  end
  []
end

def check_restore_error_fields(src)
  if src.nil?
    return ["SessionSpawnService.swift が存在しない"]
  end
  ng = []
  masked = mask_strings_and_comments(src)
  %w[makeRestoreErrorSession makeRestoreErrorChatSession].each do |fn|
    body = extract_func_body(masked, fn)
    if body.nil?
      ng << "#{fn} が無い"
      next
    end
    c = compact(body)
    unless c.include?("titleState")
      ng << "#{fn} が titleState を渡していない"
    end
  end
  ng.concat(check_generated_not_name_assign(src, "SessionSpawnService"))
  ng
end

def check_persist(src)
  if src.nil?
    return ["SessionPersistenceCoordinator.swift が存在しない"]
  end
  ng = []
  masked = mask_strings_and_comments(src)
  name_body = extract_func_body(masked, "persistSessionName")
  if name_body.nil?
    ng << "persistSessionName が無い"
  else
    c = compact(name_body)
    unless c.include?("titleState") || c.include?("updating(titleState:")
      ng << "persistSessionName が四フィールド一体更新になっていない"
    end
  end
  persist_body = extract_func_body(masked, "persistSession")
  if persist_body
    c = compact(persist_body)
    unless c.include?("titleState")
      ng << "初回保存が最新 titleState を使っていない"
    end
  end
  ws = extract_func_body(masked, "persistSessionWorkspace")
  if ws
    c = compact(ws)
    %w[titleSource flowerName fullDerivedTitle titleState].each do |field|
      next if c.include?(field)
      ng << "workspace 転記が #{field} を落としている"
      break
    end
  end
  ng
end

def check_pid(src)
  if src.nil?
    return ["SessionRestoreCoordinator.swift が存在しない"]
  end
  ng = []
  masked = mask_strings_and_comments(src)
  body = extract_func_body(masked, "restorePersistedSessions")
  if body.nil?
    ng << "restorePersistedSessions を解析できない"
    return ng
  end
  c = compact(masked)
  if c.include?("persistSession(descriptor)")
    ng << "PID 更新が古い descriptor 全体を保存している"
  end
  unless c.include?("firstIndex") || (c.include?("contains") && c.include?("return"))
    ng << "削除済み ID を PID 更新で再作成している"
  end
  ng
end

def typography_refs(src)
  return [] if src.nil?
  mask_strings_and_comments(src).scan(/TranscriptTypography\.\w+/)
end

def unused_typography?(src)
  return false if src.nil?
  masked = mask_strings_and_comments(src)
  compact(masked) =~ /iffalse\{[^}]*TranscriptTypography/
end

def check_typography(current, baseline)
  ng = []
  ALLOWED_PRODUCT_PATHS.each do |path|
    next if path.end_with?(".md")
    base_refs = typography_refs(baseline[path])
    cur_refs = typography_refs(current[path])
    missing = base_refs - cur_refs
    missing.each do |ref|
      ng << "#{path} の TranscriptTypography 参照 #{ref} が削除されている"
    end
    if unused_typography?(current[path])
      ng << "#{path} の TranscriptTypography 参照が未使用化されている"
    end
    if base_refs.empty? && !cur_refs.empty?
      ng << "#{path} に TranscriptTypography のダミー参照を追加している"
    end
    if current[path] && compact(mask_strings_and_comments(current[path])).include?("Font.system") &&
       (base_refs - cur_refs).any?
      ng << "#{path} の TranscriptTypography を定数直書きしている"
    end
  end
  ng.uniq
end

def check_no_name_ai(files)
  ng = []
  files.each do |path, src|
    next if src.nil?
    c = compact(mask_strings_and_comments(src))
    if c =~ /Process\(|NSTask|URLSession\.shared/ && path.include?("SessionTitle")
      ng << "#{path} に名前目的のプロセス起動がある"
    end
  end
  ng
end

def check_pty_no_derive(src)
  return [] if src.nil?
  send_text = extract_func_body(mask_strings_and_comments(src), "sendText")
  send_input = extract_func_body(mask_strings_and_comments(src), "sendInput")
  ng = []
  [send_text, send_input].compact.each do |body|
    c = compact(body)
    if c.include?("SessionTitleDeriver.derive") || c.include?("receivingUserMessage")
      ng << "PTY 入力から自動導出している"
    end
  end
  ng
end

def check_rename(src)
  return [] if src.nil?
  body = extract_func_body(mask_strings_and_comments(src), "renameSession")
  return ["renameSession が無い"] if body.nil?
  c = compact(body)
  unless (c.include?("renamed(to:") || c.include?(".name=")) && c.include?("persistSessionName") && c.include?("titleState")
    ["renameSession が手動状態の一体更新へ到達していない"]
  else
    []
  end
end

def check_product(files)
  ng = []
  ng.concat(check_title_state_api(files[TITLE_STATE_PATH]))
  ng.concat(check_descriptor(files[DESCRIPTOR_PATH]))
  ng.concat(check_controllable(files[CONTROLLABLE_PATH]))
  ng.concat(check_vm_title(files[CHAT_VM_PATH], "ChatSessionViewModel"))
  ng.concat(check_vm_title(files[PTY_VM_PATH], "SessionViewModel"))
  ng.concat(check_pty_no_derive(files[PTY_VM_PATH]))
  ng.concat(check_restore_error_fields(files[SPAWN_PATH]))
  ng.concat(check_generated_not_name_assign(files[DASHBOARD_VM_PATH], "DashboardViewModel"))
  ng.concat(check_rename(files[DASHBOARD_VM_PATH]))
  ng.concat(check_persist(files[PERSIST_PATH]))
  ng.concat(check_pid(files[RESTORE_PATH]))
  ng.concat(check_typography(files, files))
  ng.concat(check_no_name_ai(files))
  ng.uniq
end

def scope_errors(current_files, baseline_files)
  ng = []
  (current_files.keys | baseline_files.keys).each do |path|
    next if ALLOWED_PRODUCT_PATHS.include?(path)
    next if ACCEPTANCE_PATHS.include?(path)
    next if path == WIRING_RB_PATH
    next if path == CONTRACT_PATH
    base = baseline_files[path]
    cur = current_files[path]
    if base != cur
      ng << "許可パス外の製品変更: #{path}"
    end
  end
  if current_files[DERIVER_PATH] && baseline_files[DERIVER_PATH] &&
     current_files[DERIVER_PATH] != baseline_files[DERIVER_PATH]
    ng << "SessionTitleDeriver.swift が基準 blob と同一ではない"
  end
  ng
end

def worktree_files
  files = {}
  ALLOWED_PRODUCT_PATHS.each do |path|
    files[path] = read_if_exist(path)
  end
  files[DERIVER_PATH] = read_if_exist(DERIVER_PATH)
  files[FLOWER_PATH] = read_if_exist(FLOWER_PATH)
  files
end

def baseline_files(rev)
  files = {}
  (ALLOWED_PRODUCT_PATHS + [DERIVER_PATH, FLOWER_PATH]).each do |path|
    files[path] = git_show(rev, path)
  end
  files
end

def good_title_state
  <<~SWIFT
    public enum SessionTitleSource: String, Codable, Hashable, Sendable {
      case flower, derived, manual
    }
    public struct SessionTitleState: Equatable, Sendable {
      public let name: String
      public let source: SessionTitleSource
      public let flowerName: String?
      public let fullDerivedTitle: String?
      public init(name: String, source: SessionTitleSource, flowerName: String?, fullDerivedTitle: String?) {
        self.name = name
        self.source = source
        self.flowerName = flowerName
        self.fullDerivedTitle = fullDerivedTitle
      }
      public static func generated(flowerName: String) -> Self { Self(name: flowerName, source: .flower, flowerName: flowerName, fullDerivedTitle: nil) }
      public static func legacy(name: String) -> Self { Self(name: name, source: .manual, flowerName: nil, fullDerivedTitle: nil) }
      public func receivingUserMessage(_ text: String) -> Self {
        if source == .derived || source == .manual { return self }
        guard let derived = SessionTitleDeriver.derive(from: text) else { return self }
        return SessionTitleState(name: derived.title, source: .derived, flowerName: flowerName, fullDerivedTitle: derived.fullTitle)
      }
      public func renamed(to name: String) -> Self { self }
      public func effectiveName(fallback: String) -> String { name.isEmpty ? fallback : name }
    }
  SWIFT
end

def good_descriptor
  <<~SWIFT
    public struct PersistedSessionDescriptor {
      public let name: String
      public func init(id: SessionID, kind: AgentKind, workingDirectory: String, name: String, projectID: ProjectID?, startedAt: Date, command: String, args: [String], env: [String: String], titleSource: SessionTitleSource? = nil, flowerName: String? = nil, fullDerivedTitle: String? = nil) {}
      public func init(id: SessionID, agentRef: AgentRef, workingDirectory: String, name: String, projectID: ProjectID?, startedAt: Date, command: String, args: [String], env: [String: String], titleSource: SessionTitleSource? = nil, flowerName: String? = nil, fullDerivedTitle: String? = nil) {}
      public var titleState: SessionTitleState { SessionTitleState.legacy(name: name) }
      public func updating(titleState: SessionTitleState) -> PersistedSessionDescriptor { self }
      private enum CodingKeys: String, CodingKey { case titleSource, flowerName, fullDerivedTitle, name }
      public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
      }
    }
  SWIFT
end

def good_controllable
  <<~SWIFT
    public protocol ControllableSession: AnyObject {
      var titleState: SessionTitleState { get }
      var name: String { get set }
    }
    public extension ControllableSession {
      var titleState: SessionTitleState { .legacy(name: name) }
    }
    public enum SessionNode {
      public var titleState: SessionTitleState { controllable.titleState }
      public var controllable: any ControllableSession { fatalError() }
    }
  SWIFT
end

def good_chat_vm
  <<~SWIFT
    public final class ChatSessionViewModel {
      public var titleState: SessionTitleState
      public var displayName: String { titleState.effectiveName(fallback: SessionViewModel.shortID(for: id)) }
      public var name: String {
        get { titleState.name }
        set { titleState = titleState.renamed(to: newValue) }
      }
      func adoptFromTranscript(_ items: [ChatItem]) {
        if titleState.source == .derived || titleState.source == .manual { return }
        let entries = InputHistoryPolicy.entries(from: items)
        _ = entries
      }
    }
  SWIFT
end

def good_pty_vm
  <<~SWIFT
    public final class SessionViewModel {
      public var titleState: SessionTitleState
      public var displayName: String { titleState.effectiveName(fallback: SessionViewModel.shortID(for: id)) }
      public func sendText(_ text: String, submit: Bool) async throws { try await ptyManager.write(Data(text.utf8), to: id) }
      public func sendInput(_ data: Data) async { try? await ptyManager.write(data, to: id) }
    }
  SWIFT
end

def good_dashboard
  <<~SWIFT
    public func spawnNewSession() {
      let generatedName = FlowerNameGenerator.random(avoiding: used)
      let vm = makeSessionViewModel(titleState: .generated(flowerName: generatedName))
    }
    public func renameSession(_ id: SessionID, to name: String) {
      vm.name = name
      persistence.persistSessionName(id: id, titleState: vm.titleState)
    }
  SWIFT
end

def good_spawn
  <<~SWIFT
    func makeSessionViewModel(titleState: SessionTitleState) -> SessionViewModel { SessionViewModel() }
    func makeRestoreErrorSession(_ descriptor: PersistedSessionDescriptor, sessionToken: String, message: String, suppressSpawn: Bool = false) -> SessionViewModel {
      makeSessionViewModel(titleState: descriptor.titleState)
    }
    func makeRestoreErrorChatSession(_ descriptor: PersistedSessionDescriptor, message: String) -> ChatSessionViewModel {
      ChatSessionViewModel(titleState: descriptor.titleState)
    }
  SWIFT
end

def good_restore
  <<~SWIFT
    func restorePersistedSessions() async {
      pendingRestorePIDUpdates.append(descriptor.updating(pid: pid))
      for update in pendingRestorePIDUpdates {
        persistPID(id: update.id, pid: update.pid)
      }
    }
    func persistPID(id: SessionID, pid: pid_t?) {
      guard let index = current.firstIndex(where: { $0.id == id }) else { return }
      current[index] = current[index].updating(pid: pid)
    }
  SWIFT
end

def good_persist
  <<~SWIFT
    func persistSession(_ descriptor: PersistedSessionDescriptor) {
      enqueue {
        var current = await self.sessionStore.load()
        let latest = current.first(where: { $0.id == descriptor.id })?.titleState ?? descriptor.titleState
        current.append(descriptor.updating(titleState: latest))
      }
    }
    func persistSessionName(id: SessionID, name: String) {
      enqueue {
        var current = await self.sessionStore.load()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index] = current[index].updating(titleState: current[index].titleState.renamed(to: name))
      }
    }
    func persistSessionWorkspace(id: SessionID, workingDirectory: String, projectID: ProjectID?) {
      enqueue {
        let existing = current[index]
        _ = existing.titleState
        _ = existing.titleSource
        _ = existing.flowerName
        _ = existing.fullDerivedTitle
      }
    }
  SWIFT
end

def good_files
  {
    TITLE_STATE_PATH => good_title_state,
    DESCRIPTOR_PATH => good_descriptor,
    CONTROLLABLE_PATH => good_controllable,
    CHAT_VM_PATH => good_chat_vm,
    PTY_VM_PATH => good_pty_vm,
    DASHBOARD_VM_PATH => good_dashboard,
    SPAWN_PATH => good_spawn,
    RESTORE_PATH => good_restore,
    PERSIST_PATH => good_persist,
    DERIVER_PATH => "public enum SessionTitleDeriver {}",
    FLOWER_PATH => "public enum FlowerNameGenerator {}",
  }
end

def with_file(files, path)
  copy = files.dup
  copy[path] = yield(files[path].dup)
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
    code.match?(/if scope_check_requested\?/)
end

def selftest_assert(cond, msg = "assertion")
  unless cond
    puts "task44-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task44-wiring --selftest: FAIL #{msg}"
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
  selftest_errors_eq check_product(good), [], "正例: 契約どおりの配線は空 NG"

  comment_only = good_title_state.sub("public enum SessionTitleSource", "// public enum SessionTitleSource")
  selftest_errors_eq check_title_state_api(comment_only).select { |m| m.include?("SessionTitleSource") }, ["public enum SessionTitleSource が無い"], "負例: コメントだけの宣言偽装"

  string_only = good_title_state.sub("public struct SessionTitleState", "let decoy = \"public struct SessionTitleState\"\n    struct Other")
  selftest_assert check_title_state_api(string_only).include?("public struct SessionTitleState が無い"), "負例: 文字列だけの宣言偽装"

  unparsed = "public struct SessionTitleState: Equatable, Sendable {\n  public let name: String"
  selftest_errors_eq check_title_state_api(unparsed), ["public enum SessionTitleSource が無い", "SessionTitleState を解析できない", "receivingUserMessage が無い"], "負例: struct 解析不能"

  selftest_errors_eq check_title_state_api(nil), ["SessionTitleState.swift が存在しない"], "負例: 対象不在"

  flower_mismatch = good_title_state.sub(
    "if source == .derived || source == .manual { return self }",
    "TEMP_GUARD"
  ).sub(
    "guard let derived = SessionTitleDeriver.derive(from: text) else { return self }",
    "if source == .derived || source == .manual { return self }"
  ).sub(
    "TEMP_GUARD",
    "guard let derived = SessionTitleDeriver.derive(from: text) else { return self }"
  )
  selftest_errors_eq check_title_state_api(flower_mismatch), ["receivingUserMessage が derived/manual の早期ガードより前に SessionTitleDeriver.derive を呼んでいる"], "負例: initializer の不整合 derived／flower の正規化欠落（早期 derive）"

  name_assign = with_file(good, DASHBOARD_VM_PATH) { |src| src.sub("titleState: .generated(flowerName: generatedName)", "") + "\n sessionVM.name = generatedName\n" }
  selftest_errors_eq check_product(name_assign), ["DashboardViewModel が花名を通常の name 代入で設定している"], "負例: 生成花名の通常 name 代入"

  restore_drop = with_file(good, SPAWN_PATH) { |src| src.sub("titleState: descriptor.titleState", "name: descriptor.name") }
  selftest_errors_eq check_restore_error_fields(restore_drop[SPAWN_PATH]), ["makeRestoreErrorSession が titleState を渡していない"], "負例: 復元失敗のフィールド欠落"

  ws_drop = with_file(good, PERSIST_PATH) { |src| src.gsub("existing.titleState", "existing.name").gsub("existing.titleSource", "existing.id").gsub("existing.flowerName", "existing.id").gsub("existing.fullDerivedTitle", "existing.id") }
  selftest_errors_eq check_persist(ws_drop[PERSIST_PATH]), ["workspace 転記が titleSource を落としている"], "負例: workspace 転記のフィールド欠落"

  client_input = with_file(good, CHAT_VM_PATH) { |src| src + "\n func adoptClientInput(_ clientInput: String) { let _ = SessionTitleDeriver.derive(from: clientInput) }\n" }
  selftest_errors_eq check_vm_title(client_input[CHAT_VM_PATH], "ChatSessionViewModel"), ["ChatSessionViewModel が derived/manual の早期ガードより前に履歴抽出している"], "負例: サーバーの補足付き本文を無条件採用（早期抽出）"

  rename_drop = with_file(good, DASHBOARD_VM_PATH) { |src| src.sub("vm.name = name", "").sub("titleState: vm.titleState", "name: name") }
  selftest_errors_eq check_product(rename_drop), ["renameSession が手動状態の一体更新へ到達していない"], "負例: rename の手動化欠落、保存接続欠落"

  persist_name_only = with_file(good, PERSIST_PATH) { |src| src.sub("updating(titleState: current[index].titleState.renamed(to: name))", "updating(name: name)") }
  selftest_errors_eq check_persist(persist_name_only[PERSIST_PATH]).select { |m| m.include?("四フィールド") }, ["persistSessionName が四フィールド一体更新になっていない"], "負例: rename の手動化欠落、保存接続欠落"

  first_old = with_file(good, PERSIST_PATH) { |src| src.gsub("titleState", "storedName") }
  selftest_errors_eq check_persist(first_old[PERSIST_PATH]).select { |m| m.include?("初回保存") }, ["初回保存が最新 titleState を使っていない"], "負例: 初回保存で古い状態を使用"

  pid_old = with_file(good, RESTORE_PATH) { |src| src.sub("persistPID(id: update.id, pid: update.pid)", "persistSession(descriptor)") }
  selftest_errors_eq check_pid(pid_old[RESTORE_PATH]).select { |m| m.include?("古い descriptor") }, ["PID 更新が古い descriptor 全体を保存している"], "負例: PID 更新で古い descriptor 全体を保存"

  pid_upsert = with_file(good, RESTORE_PATH) { |src| src.sub("firstIndex", "missingIndex") }
  selftest_errors_eq check_pid(pid_upsert[RESTORE_PATH]), ["削除済み ID を PID 更新で再作成している"], "負例: 削除済み ID を復活"

  guard_only = with_file(good, CHAT_VM_PATH) { |src| src.sub("if titleState.source == .derived || titleState.source == .manual { return }", "") }
  selftest_errors_eq check_vm_title(guard_only[CHAT_VM_PATH], "ChatSessionViewModel"), ["ChatSessionViewModel が derived/manual の早期ガードより前に履歴抽出している"], "負例: 確定状態の早期ガードだけを削除し履歴抽出を実行"

  typo_file = "Text(\"x\").font(TranscriptTypography.font(for: .bodyStrong, scale: 1))\n"
  typo_base = { CHAT_VM_PATH => typo_file }
  typo_del = { CHAT_VM_PATH => "Text(\"x\").font(Font.system(size: 14))\n" }
  selftest_assert check_typography(typo_del, typo_base).any? { |m| m.include?("削除") || m.include?("定数") }, "負例: typography 参照の削除・定数化"
  typo_unused = { CHAT_VM_PATH => "if false { _ = TranscriptTypography.font }\n" }
  selftest_assert check_typography(typo_unused, typo_base).any? { |m| m.include?("未使用") || m.include?("削除") }, "負例: typography 参照の未使用化"
  dummy = { TITLE_STATE_PATH => "let x = TranscriptTypography.withinAnswer\n" }
  dummy_base = { TITLE_STATE_PATH => "public struct SessionTitleState {}\n" }
  selftest_assert check_typography(dummy, dummy_base).any? { |m| m.include?("ダミー") }, "負例: 無参照ファイルへのダミー追加"

  pty_derive = with_file(good, PTY_VM_PATH) { |src| src.sub("try await ptyManager.write(Data(text.utf8), to: id)", "let _ = SessionTitleDeriver.derive(from: text)") }
  selftest_errors_eq check_pty_no_derive(pty_derive[PTY_VM_PATH]), ["PTY 入力から自動導出している"], "負例: PTY の改変"

  token_out = with_file(good, DESCRIPTOR_PATH) { |src| src.sub("try c.encode(name, forKey: .name)", "try c.encode(token, forKey: .token)") }
  selftest_errors_eq check_descriptor(token_out[DESCRIPTOR_PATH]), ["token を encode している"], "負例: 秘密情報除去の改変"

  if_false = with_file(good, CHAT_VM_PATH) { |src| src.sub("let entries = InputHistoryPolicy.entries(from: items)", "if false { let entries = InputHistoryPolicy.entries(from: items) }") }
  selftest_errors_eq check_vm_title(if_false[CHAT_VM_PATH], "ChatSessionViewModel"), ["ChatSessionViewModel が derived/manual の早期ガードより前に履歴抽出している"], "負例: if false による偽装"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_assert unset.nil?, "負例: SHA 未設定は baseline を返さない"
  selftest_errors_eq unset_errs, ["TASK44_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: SHA 未設定"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK44_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD 指定"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK44_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD~1 指定"
  _, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK44_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: @ 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK44_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_errors_eq parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n"), :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  ph_errs = contract_baseline_errors("---\nbaseline_commit: \"PM が凍結時に設定\"\n", "abc1234")
  selftest_errors_eq ph_errs, ["契約 baseline_commit がプレースホルダ（凍結時に実 SHA へ置換する）"], "負例: プレースホルダは NG"

  head_full = git_full_sha("HEAD")
  other_full = git_full_sha("HEAD~1")
  selftest_assert !head_full.nil? && !other_full.nil? && head_full != other_full, "selftest 用に有効で異なる 2 コミットが必要"
  real_mismatch = contract_baseline_errors("---\nbaseline_commit: \"#{head_full}\"\n", other_full)
  selftest_errors_eq real_mismatch, ["TASK44_BASELINE が契約 baseline_commit と一致しない"], "負例: 契約不一致"

  tests = ["t1", "t2", "t3", "t4"]
  pre_ok = check_frozen_baseline(
    head_full,
    {
      deriver_blob: "deriver",
      title_state_blob: nil,
      test_blobs: tests,
      test_nows: tests,
      rb_blob: "rb",
      rb_now: "rb",
    }
  )
  selftest_errors_eq pre_ok, [], "正例: 固定 SHA が HEAD と同じでも実装前 blob なら拒否しない"

  post_ng = check_frozen_baseline(
    head_full,
    {
      deriver_blob: "deriver",
      title_state_blob: good_title_state,
      test_blobs: tests,
      test_nows: tests,
      rb_blob: "rb",
      rb_now: "rb",
    }
  )
  selftest_errors_eq post_ng, ["基準時点に SessionTitleState.swift がある（実装前の凍結ではない）"], "負例: 実装入り基準"

  no_task41 = check_frozen_baseline(
    head_full,
    {
      deriver_blob: nil,
      title_state_blob: nil,
      test_blobs: tests,
      test_nows: tests,
      rb_blob: "rb",
      rb_now: "rb",
    }
  )
  selftest_errors_eq no_task41, ["基準時点に SessionTitleDeriver.swift が無い（task-41 未成立）"], "負例: task-41 未成立基準"

  selftest_errors_eq frozen_artifact_errors("rb 自身", "now", "frozen"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 凍結検査の改変"
  selftest_errors_eq frozen_artifact_errors("受け入れテスト1", nil, "blob"), ["基準時点の受け入れテスト1を git show できない"], "負例: blob 欠落"
  selftest_errors_eq frozen_artifact_errors("受け入れテスト1", "blob", "changed"), ["基準時点の受け入れテスト1が現在と同一ではない"], "負例: テスト改変"

  out_of_scope = { FLOWER_PATH => "changed\n", DERIVER_PATH => "public enum SessionTitleDeriver {}" }
  base_scope = { FLOWER_PATH => "public enum FlowerNameGenerator {}", DERIVER_PATH => "public enum SessionTitleDeriver {}" }
  selftest_errors_eq scope_errors(out_of_scope, base_scope), ["許可パス外の製品変更: #{FLOWER_PATH}"], "負例: scope のみで拒否すべき範囲外変更"
  selftest_errors_eq check_product(good.merge(FLOWER_PATH => "changed\n")), [], "正例: scope なしでは範囲外変更を範囲違反にしない"
  selftest_errors_eq check_product(guard_only), ["ChatSessionViewModel が derived/manual の早期ガードより前に履歴抽出している"], "負例: 恒久契約の破壊は scope なしでも失敗"

  with_env("TASK44_SCOPE_CHECK", "1") { selftest_assert scope_check_requested?, "正例: SCOPE_CHECK=1" }
  with_env("TASK44_SCOPE_CHECK", nil) { selftest_assert !scope_check_requested?, "正例: 未設定では恒久のみ" }

  prod = production_checks_source
  selftest_assert !prod.empty?, "正例: 本番検査セクションが存在する"
  selftest_assert baseline_check_connected?(prod), "正例: 基準検査が本番に接続されている"
  selftest_assert scope_check_gated?(prod), "正例: 変更範囲検査が TASK44_SCOPE_CHECK でゲートされている"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task44-wiring --selftest: OK"
  exit 0
end

# === task44 production checks ===
ng = []

raw = ENV["TASK44_BASELINE"]
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
    ng << "TASK44_BASELINE が無効なコミット: #{baseline}"
    baseline = nil
  else
    ng.concat(check_frozen_baseline(full))
    if scope_check_requested?
      ng.concat(scope_errors(files, baseline_files(full)))
    end
    baseline = full
  end
end

ng = ng.uniq
if ng.empty?
  puts "task44-wiring: OK"
else
  ng.each { |m| puts "task44-wiring: NG #{m}" }
  exit 1
end
