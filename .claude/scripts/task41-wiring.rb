#!/usr/bin/env ruby
# task-41 凍結検査: SessionTitleDeriver の公開面・許可 import・I/O 非依存を確認し、
# 新規ファイル以外の AgentDomain ソースと Package.swift が TASK41_BASELINE blob と
# 同一であること。文字列導出の正しさは Swift Testing に任せ、Ruby へ再実装しない。

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

CONTRACT_PATH = "tasks/task-41.md"
ACCEPTANCE_TEST_PATH = "macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift"
WIRING_RB_PATH = ".claude/scripts/task41-wiring.rb"
DERIVER_PATH = "macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleDeriver.swift"
AGENT_DOMAIN_SRC = "macos/Packages/AgentDomain/Sources/AgentDomain"
PACKAGE_PATH = "macos/Packages/AgentDomain/Package.swift"

CONTRACT_BASELINE_PLACEHOLDER_RE = /PM|凍結|設定|TBD|TODO|FIXME|placeholder|未設定/i
CONTRACT_BASELINE_LINE_RE = /^baseline_commit:\s*(?:"([^"]*)"|'([^']*)'|(\S+))/

FORBIDDEN_IMPORTS = %w[
  SwiftUI AppKit Combine Observation Network CryptoKit
  Darwin POSIX Dispatch os
].freeze

FORBIDDEN_TOKENS = %w[
  FileManager URLSession UserDefaults NotificationCenter
  Binding View Color NSView NSWindow SwiftUI AppKit Combine
  Timer Clock Process NSTask UUID NSWorkspace URLRequest
].freeze

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
        errs << "TASK41_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK41_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK41_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK41_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
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

def implementation_in_baseline_errors(deriver_blob)
  return [] if deriver_blob.nil?
  ["基準時点に SessionTitleDeriver.swift がある（実装前の凍結ではない）"]
end

def check_frozen_baseline(baseline)
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK41_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  unless git_is_ancestor?(full, "HEAD")
    ng << "TASK41_BASELINE が HEAD の祖先ではない"
  end
  ng.concat(implementation_in_baseline_errors(git_show(full, DERIVER_PATH)))
  test_blob = git_show(full, ACCEPTANCE_TEST_PATH)
  rb_blob = git_show(full, WIRING_RB_PATH)
  ng.concat(frozen_artifact_errors("受け入れテスト", test_blob, read_if_exist(ACCEPTANCE_TEST_PATH)))
  ng.concat(frozen_artifact_errors("rb 自身", rb_blob, read_if_exist(WIRING_RB_PATH)))
  ng
end

def struct_header(src, name)
  m = src.match(/(?:public\s+)?struct\s+#{Regexp.escape(name)}\s*:[^{]*\{/)
  return nil unless m
  m[0]
end

def check_public_api(src)
  ng = []
  if src.nil?
    ng << "SessionTitleDeriver.swift が存在しない"
    return ng
  end
  masked = mask_strings_and_comments(src)
  header = struct_header(masked, "DerivedSessionTitle")
  if header.nil?
    if masked =~ /\bstruct\s+DerivedSessionTitle\b/
      ng << "DerivedSessionTitle を解析できない"
    else
      ng << "public struct DerivedSessionTitle が無い"
    end
  else
    ng << "DerivedSessionTitle が public ではない" unless header =~ /\bpublic\s+struct\s+DerivedSessionTitle\b/
    ng << "DerivedSessionTitle が Equatable ではない" unless header =~ /\bEquatable\b/
    ng << "DerivedSessionTitle が Sendable ではない" unless header =~ /\bSendable\b/
    body = extract_struct_body(masked, "DerivedSessionTitle")
    if body.nil?
      ng << "DerivedSessionTitle を解析できない"
    else
      c = compact(body)
      ng << "public let title: String が無い" unless c.include?("publiclettitle:String")
      ng << "public let fullTitle: String が無い" unless c.include?("publicletfullTitle:String")
    end
  end

  unless masked =~ /\bpublic\s+enum\s+SessionTitleDeriver\b/
    if masked =~ /\benum\s+SessionTitleDeriver\b/
      ng << "SessionTitleDeriver が public ではない"
    else
      ng << "public enum SessionTitleDeriver が無い"
    end
  end
  enum_body = extract_enum_body(masked, "SessionTitleDeriver")
  if masked =~ /\benum\s+SessionTitleDeriver\b/ && enum_body.nil?
    ng << "SessionTitleDeriver を解析できない"
  elsif enum_body
    c = compact(enum_body)
    unless c.include?("publicstaticfuncderive(fromtext:String)->DerivedSessionTitle?")
      ng << "public static func derive(from text: String) -> DerivedSessionTitle? が無い"
    end
  end
  ng
end

def imported_modules(masked)
  mods = []
  masked.scan(/^\s*import\s+(?:(?:struct|class|enum|func|var|let)\s+)?(\w+)/) do |m|
    mods << m[0]
  end
  mods
end

def check_imports_and_purity(src)
  return [] if src.nil?
  ng = []
  masked = mask_strings_and_comments(src)
  imported_modules(masked).each do |mod|
    next if mod == "Foundation"
    ng << "許可していない import #{mod}"
  end
  FORBIDDEN_IMPORTS.each do |mod|
    ng << "許可していない import #{mod}" if imported_modules(masked).include?(mod)
  end
  FORBIDDEN_TOKENS.each do |tok|
    ng << "SessionTitleDeriver.swift に #{tok} がある" if masked =~ /\b#{Regexp.escape(tok)}\b/
  end
  ng << "SessionTitleDeriver.swift に Date( がある" if masked.include?("Date(")
  ng << "SessionTitleDeriver.swift に UUID( がある" if masked.include?("UUID(")
  ng = ng.uniq
  ng
end

def other_sources_errors(current_files, baseline_files)
  ng = []
  paths = (current_files.keys + baseline_files.keys).uniq
  paths.each do |path|
    next if path == DERIVER_PATH
    base = baseline_files[path]
    cur = current_files[path]
    if base.nil? && !cur.nil?
      ng << "新規製品ファイル #{path} がある（許可は SessionTitleDeriver.swift のみ）"
    elsif cur.nil? && !base.nil?
      ng << "#{path} が基準から欠落している"
    elsif !workdir_matches_git_blob?(cur, base)
      ng << "#{path} が基準 blob と同一ではない"
    end
  end
  ng
end

def package_errors(current, baseline)
  ng = []
  if current.nil?
    ng << "Package.swift が存在しない"
    return ng
  end
  if baseline.nil?
    ng << "基準時点の Package.swift を git show できない"
    return ng
  end
  unless workdir_matches_git_blob?(current, baseline)
    ng << "AgentDomain の Package.swift が基準 blob と同一ではない（依存追加なし）"
  end
  ng
end

def worktree_agent_domain_sources
  files = {}
  Dir.glob("#{AGENT_DOMAIN_SRC}/**/*.swift").sort.each do |path|
    files[path] = File.read(path)
  end
  files
end

def baseline_agent_domain_sources(rev)
  files = {}
  git_ls_files(rev, AGENT_DOMAIN_SRC).each do |path|
    blob = git_show(rev, path)
    files[path] = blob unless blob.nil?
  end
  files
end

def good_deriver_src
  <<~SWIFT
    import Foundation

    public struct DerivedSessionTitle: Equatable, Sendable {
      public let title: String
      public let fullTitle: String
    }

    public enum SessionTitleDeriver {
      public static func derive(from text: String) -> DerivedSessionTitle? {
        DerivedSessionTitle(title: text, fullTitle: text)
      }
    }
  SWIFT
end

def selftest_assert(cond, msg)
  unless cond
    puts "task41-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def run_selftest
  url = %(let url = "https://example.com" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://example.com"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert !strip_comments("let a = 1 /* x */ let b = 2").include?("x"), "正例: /* */ を除去する"

  good = good_deriver_src
  selftest_assert check_public_api(good).empty?, "正例: 公開面がある (#{check_public_api(good).inspect})"
  selftest_assert check_imports_and_purity(good).empty?, "正例: Foundation のみ・I/O なし (#{check_imports_and_purity(good).inspect})"

  selftest_assert check_public_api(nil).any? { |m| m.include?("存在しない") }, "負例: 対象不在"

  comment_only = <<~SWIFT
    // public struct DerivedSessionTitle: Equatable, Sendable {
    //     public let title: String
    //     public let fullTitle: String
    // }
    // public enum SessionTitleDeriver {
    //     public static func derive(from text: String) -> DerivedSessionTitle?
    // }
    let decoy = "public enum SessionTitleDeriver"
  SWIFT
  fake = check_public_api(comment_only)
  selftest_assert fake.any? { |m| m.include?("DerivedSessionTitle") || m.include?("SessionTitleDeriver") }, "負例: コメントだけの宣言偽装"

  unparsed = "public struct DerivedSessionTitle: Equatable, Sendable {\npublic let title: String\n"
  selftest_assert check_public_api(unparsed).any? { |m| m.include?("解析できない") }, "負例: 解析不能"

  banned = good + "\nimport Combine\n"
  selftest_assert check_imports_and_purity(banned).any? { |m| m.include?("Combine") }, "負例: 禁止依存"

  io = good.sub("DerivedSessionTitle(title: text, fullTitle: text)", "FileManager.default")
  selftest_assert check_imports_and_purity(io).any? { |m| m.include?("FileManager") }, "負例: I/O 依存"

  string_decoy = good + %(\nlet x = "import Combine FileManager View"\n)
  selftest_assert check_imports_and_purity(string_decoy).empty?, "正例: 文字列内の禁止語は依存ではない"
  comment_decoy = good + "\n// import Combine\n// FileManager.default\n"
  selftest_assert check_imports_and_purity(comment_decoy).empty?, "正例: コメント内の禁止語は依存ではない"

  base_files = {
    "#{AGENT_DOMAIN_SRC}/FlowerNameGenerator.swift" => "import Foundation\n",
  }
  selftest_assert other_sources_errors(base_files, base_files).empty?, "正例: 新規ファイル以外が基準 blob と同一"
  changed = { "#{AGENT_DOMAIN_SRC}/FlowerNameGenerator.swift" => "changed\n" }
  selftest_assert other_sources_errors(changed, base_files).any? { |m| m.include?("同一ではない") }, "負例: 既存ソース改変"
  with_new = base_files.merge(DERIVER_PATH => good)
  selftest_assert other_sources_errors(with_new, base_files).empty?, "正例: SessionTitleDeriver.swift 追加は既存比較から除外"
  extra = base_files.merge("#{AGENT_DOMAIN_SRC}/Extra.swift" => "x\n")
  selftest_assert other_sources_errors(extra, base_files).any? { |m| m.include?("新規製品ファイル") }, "負例: 許可外の新規ソース"

  selftest_assert package_errors("pkg\n", "pkg\n").empty?, "正例: Package.swift が基準と同一"
  selftest_assert package_errors("pkg2\n", "pkg\n").any? { |m| m.include?("Package.swift") }, "負例: Package.swift 改変（依存追加）"
  selftest_assert package_errors(nil, "pkg\n").any? { |m| m.include?("存在しない") }, "負例: Package.swift 不在"
  selftest_assert package_errors("pkg\n", nil).any? { |m| m.include?("git show") }, "負例: Package.swift blob 欠落"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_assert unset.nil? && unset_errs.any? { |m| m.include?("未設定") }, "負例: SHA 未設定"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_assert head_errs.any? { |m| m.include?("HEAD") }, "負例: HEAD 指定"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_assert head1_errs.any? { |m| m.include?("HEAD") }, "負例: HEAD~1 指定"
  _, at_errs = baseline_env_errors("@")
  selftest_assert at_errs.any? { |m| m.include?("HEAD") }, "負例: @ 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_assert branch_errs.any? { |m| m.include?("ブランチ") || m.include?("SHA") }, "負例: ブランチ名は不正"
  _, bad_errs = baseline_env_errors("not-a-sha")
  selftest_assert bad_errs.any? { |m| m.include?("SHA") }, "負例: 不正 SHA"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"
  selftest_assert !workdir_matches_git_blob?("a", "b"), "負例: git show 内容の不一致"

  selftest_assert frozen_artifact_errors("受け入れテスト", "blob", "blob").empty?, "正例: 凍結テストが作業ツリーと同一"
  selftest_assert frozen_artifact_errors("受け入れテスト", nil, "blob").any? { |m| m.include?("git show") }, "負例: blob 欠落"
  selftest_assert frozen_artifact_errors("受け入れテスト", "blob", "changed").any? { |m| m.include?("同一ではない") }, "負例: テスト改変"
  selftest_assert frozen_artifact_errors("rb 自身", "rb", "rb").empty?, "正例: 凍結 rb が作業ツリーと同一"
  selftest_assert frozen_artifact_errors("rb 自身", "rb", "changed").any? { |m| m.include?("同一ではない") }, "負例: 検査改変"

  selftest_assert implementation_in_baseline_errors(nil).empty?, "正例: 基準に SessionTitleDeriver.swift 不在"
  selftest_assert implementation_in_baseline_errors(good).any? { |m| m.include?("SessionTitleDeriver.swift") }, "負例: 実装入り基準"

  head_full = git_full_sha("HEAD")
  selftest_assert !head_full.nil?, "正例: HEAD を完全 SHA に解決できる"
  selftest_assert git_is_ancestor?(head_full, "HEAD"), "正例: HEAD は HEAD の祖先"
  selftest_assert git_full_sha("0" * 40).nil?, "負例: 存在しない SHA は無効"

  selftest_assert parse_contract_baseline_text("---\nfoo: 1\n") == :missing, "負例: 契約 baseline_commit 欠落"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n") == :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"not-a-sha\"\n") == :invalid, "負例: 契約 baseline_commit 不正"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"abc1234\"\n") == "abc1234", "正例: 契約 baseline_commit がクォート付き SHA"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: abc1234\n") == "abc1234", "正例: 契約 baseline_commit がクォート無し SHA"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: 'abc1234'\n") == "abc1234", "正例: 契約 baseline_commit が単一クォート SHA"
  ph_errs = contract_baseline_errors("---\nbaseline_commit: \"PM が凍結時に設定\"\n", "abc1234")
  selftest_assert ph_errs.any? { |m| m.include?("プレースホルダ") }, "負例: プレースホルダは NG"

  parent_full = git_full_sha("HEAD~1")
  if head_full && parent_full && head_full != parent_full
    mismatch_errs = contract_baseline_errors("---\nbaseline_commit: \"#{head_full}\"\n", parent_full)
    selftest_assert mismatch_errs.any? { |m| m.include?("一致しない") }, "負例: TASK41_BASELINE と契約の不一致"
    match_errs = contract_baseline_errors("---\nbaseline_commit: \"#{head_full}\"\n", head_full)
    selftest_assert match_errs.empty?, "正例: TASK41_BASELINE が契約 baseline_commit と一致"
    short = head_full[0, 7]
    short_errs = contract_baseline_errors("---\nbaseline_commit: #{head_full}\n", short)
    selftest_assert short_errs.empty?, "正例: 短い SHA も完全 SHA に解決して一致"
  else
    mismatch_errs = contract_baseline_errors("---\nbaseline_commit: \"aaaaaaaa\"\n", "bbbbbbbb")
    selftest_assert mismatch_errs.any? { |m| m.include?("一致しない") || m.include?("無効") }, "負例: TASK41_BASELINE と契約の不一致"
  end
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task41-wiring --selftest: OK"
  exit 0
end

ng = []

raw = ENV["TASK41_BASELINE"]
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
    ng << "TASK41_BASELINE が無効なコミット: #{baseline}"
    baseline = nil
  else
    ng.concat(check_frozen_baseline(full))
    baseline = full
  end
end

deriver = read_if_exist(DERIVER_PATH)
ng.concat(check_public_api(deriver))
ng.concat(check_imports_and_purity(deriver))

if baseline
  current_sources = worktree_agent_domain_sources
  previous_sources = baseline_agent_domain_sources(baseline)
  if previous_sources.empty?
    ng << "baseline #{baseline} から AgentDomain ソースを読めない（黙示的成功にしない）"
  else
    ng.concat(other_sources_errors(current_sources, previous_sources))
  end
  ng.concat(package_errors(read_if_exist(PACKAGE_PATH), git_show(baseline, PACKAGE_PATH)))
end

ng = ng.uniq
if ng.empty?
  puts "task41-wiring: OK"
else
  ng.each { |m| puts "task41-wiring: NG #{m}" }
  exit 1
end
