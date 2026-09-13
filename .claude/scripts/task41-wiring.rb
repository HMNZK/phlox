#!/usr/bin/env ruby
# task-41 凍結検査:
# 1) 導出契約の回帰検査（SessionTitleDeriver.swift の公開面・純粋性）は常に実行する。
# 2) 変更範囲検査（AgentDomain の他ファイル・Package.swift 不変）は
#    TASK41_SCOPE_CHECK=1 のときだけ実行する（task-41 verify 分岐。task-44/45 の回帰では付与しない）。
# 文字列導出の正しさは Swift Testing に任せ、Ruby へ再実装しない。

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

def scan_string_for_purity(src, i, out)
  triple = src[i, 3] == '"""'
  j = triple ? i + 3 : i + 1
  while j < src.length
    if triple && src[j, 3] == '"""'
      return j + 3
    end
    if !triple && src[j] == '"'
      return j + 1
    end
    if src[j] == "\\"
      if j + 1 < src.length && src[j + 1] == "("
        j = scan_interpolation_for_purity(src, j + 1, out)
        next
      end
      j += 2
      next
    end
    j += 1
  end
  src.length
end

def scan_interpolation_for_purity(src, open_paren_idx, out)
  depth = 0
  i = open_paren_idx
  while i < src.length
    if src[i, 2] == "//"
      i += 1 while i < src.length && src[i] != "\n"
      if i < src.length && src[i] == "\n"
        out << "\n"
        i += 1
      end
    elsif src[i, 2] == "/*"
      i = skip_block_comment(src, i)
    elsif src[i, 3] == '"""' || src[i] == '"'
      i = scan_string_for_purity(src, i, out)
    else
      if src[i] == "("
        depth += 1
        out << "(" if depth > 1
      elsif src[i] == ")"
        depth -= 1
        return i + 1 if depth == 0
        out << ")"
      else
        out << src[i]
      end
      i += 1
    end
  end
  src.length
end

def code_for_purity(src)
  out = +""
  i = 0
  while i < src.length
    if src[i, 2] == "//"
      i += 1 while i < src.length && src[i] != "\n"
      if i < src.length && src[i] == "\n"
        out << "\n"
        i += 1
      end
    elsif src[i, 2] == "/*"
      i = skip_block_comment(src, i)
    elsif src[i, 3] == '"""' || src[i] == '"'
      i = scan_string_for_purity(src, i, out)
    else
      out << src[i]
      i += 1
    end
  end
  out
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
PRODUCTION_MARKER = "# === task41 production checks ==="

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
  print ProcessInfo random
].freeze

def scope_check_requested?(env = ENV)
  env["TASK41_SCOPE_CHECK"] == "1"
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

def has_public_let_nonoptional_string?(compacted, name)
  needle = "publiclet#{name}:String"
  start = 0
  while (idx = compacted.index(needle, start))
    after_idx = idx + needle.length
    after = after_idx < compacted.length ? compacted[after_idx] : nil
    return true if after != "?" && after != "!"
    start = idx + 1
  end
  false
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
      ng << "public let title: String が無い" unless has_public_let_nonoptional_string?(c, "title")
      ng << "public let fullTitle: String が無い" unless has_public_let_nonoptional_string?(c, "fullTitle")
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

def imported_modules(code)
  mods = []
  code.scan(/(?:^|\n)[ \t]*(?:@[^\s]+[ \t]+)*import[ \t]+(?:(?:struct|class|enum|func|var|let)[ \t]+)?(\w+)/) do |m|
    mods << m[0]
  end
  mods
end

def check_imports_and_purity(src)
  return [] if src.nil?
  ng = []
  code = code_for_purity(src)
  imported_modules(code).each do |mod|
    next if mod == "Foundation"
    ng << "許可していない import #{mod}"
  end
  FORBIDDEN_IMPORTS.each do |mod|
    ng << "許可していない import #{mod}" if imported_modules(code).include?(mod)
  end
  FORBIDDEN_TOKENS.each do |tok|
    ng << "SessionTitleDeriver.swift に #{tok} がある" if code =~ /\b#{Regexp.escape(tok)}\b/
  end
  ng << "SessionTitleDeriver.swift に Date がある" if code =~ /\bDate\b/
  ng << "SessionTitleDeriver.swift に .now がある" if code =~ /\.now\b/
  ng.uniq
end

def derivation_contract_errors(deriver_src)
  check_public_api(deriver_src) + check_imports_and_purity(deriver_src)
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

def scope_source_errors(current_sources, previous_sources, baseline_label)
  if previous_sources.empty?
    ["baseline #{baseline_label} から AgentDomain ソースを読めない（黙示的成功にしない）"]
  else
    other_sources_errors(current_sources, previous_sources)
  end
end

def collect_checks(deriver_src, current_sources, baseline_sources, current_pkg, baseline_pkg, scope_check)
  ng = derivation_contract_errors(deriver_src)
  return ng unless scope_check
  ng.concat(scope_source_errors(current_sources, baseline_sources, "selftest"))
  ng.concat(package_errors(current_pkg, baseline_pkg))
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

def with_body_stmt(src, stmt)
  src.sub(
    "DerivedSessionTitle(title: text, fullTitle: text)",
    "#{stmt}\n        DerivedSessionTitle(title: text, fullTitle: text)"
  )
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
    puts "task41-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def selftest_errors_eq(actual, expected, msg)
  unless actual == expected
    puts "task41-wiring --selftest: FAIL #{msg}"
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

  selftest_assert code_for_purity('let x = "\\(print(1))"').include?("print(1)"), "正例: 補間内コードを走査対象にする"
  selftest_assert !code_for_purity('let x = "print(1)"').include?("print(1)"), "正例: 文字列リテラル内の print は走査しない"

  good = good_deriver_src
  selftest_errors_eq check_public_api(good), [], "正例: 公開面がある"
  selftest_errors_eq check_imports_and_purity(good), [], "正例: Foundation のみ・I/O なし"
  selftest_errors_eq derivation_contract_errors(good), [], "正例: 導出契約回帰（公開面+純粋性）"

  selftest_errors_eq check_public_api(nil), ["SessionTitleDeriver.swift が存在しない"], "負例: 対象不在"

  comment_struct = <<~SWIFT
    import Foundation
    // public struct DerivedSessionTitle: Equatable, Sendable {
    //     public let title: String
    //     public let fullTitle: String
    // }
    public enum SessionTitleDeriver {
      public static func derive(from text: String) -> DerivedSessionTitle? {
        nil
      }
    }
  SWIFT
  selftest_errors_eq check_public_api(comment_struct), ["public struct DerivedSessionTitle が無い"], "負例: コメントだけの struct 宣言偽装"

  comment_enum = <<~SWIFT
    import Foundation
    public struct DerivedSessionTitle: Equatable, Sendable {
      public let title: String
      public let fullTitle: String
    }
    // public enum SessionTitleDeriver {
    //     public static func derive(from text: String) -> DerivedSessionTitle?
    // }
    let decoy = "public enum SessionTitleDeriver"
  SWIFT
  selftest_errors_eq check_public_api(comment_enum), ["public enum SessionTitleDeriver が無い"], "負例: コメントだけの enum 宣言偽装"

  unparsed_struct = <<~SWIFT
    public enum SessionTitleDeriver {
      public static func derive(from text: String) -> DerivedSessionTitle? { nil }
    }
    public struct DerivedSessionTitle: Equatable, Sendable {
      public let title: String
  SWIFT
  selftest_errors_eq check_public_api(unparsed_struct), ["DerivedSessionTitle を解析できない"], "負例: struct 解析不能"

  unparsed_enum = <<~SWIFT
    public struct DerivedSessionTitle: Equatable, Sendable {
      public let title: String
      public let fullTitle: String
    }
    public enum SessionTitleDeriver {
      public static func derive(from text: String) -> DerivedSessionTitle?
  SWIFT
  selftest_errors_eq check_public_api(unparsed_enum), ["SessionTitleDeriver を解析できない"], "負例: enum 解析不能"

  no_public_struct = good.sub("public struct DerivedSessionTitle", "struct DerivedSessionTitle")
  selftest_errors_eq check_public_api(no_public_struct), ["DerivedSessionTitle が public ではない"], "負例: struct の public 欠落"

  no_eq = good.sub(": Equatable, Sendable", ": Sendable")
  selftest_errors_eq check_public_api(no_eq), ["DerivedSessionTitle が Equatable ではない"], "負例: Equatable 欠落"

  no_sendable = good.sub(": Equatable, Sendable", ": Equatable")
  selftest_errors_eq check_public_api(no_sendable), ["DerivedSessionTitle が Sendable ではない"], "負例: Sendable 欠落"

  optional_title = good.sub("public let title: String\n", "public let title: String?\n")
  selftest_errors_eq check_public_api(optional_title), ["public let title: String が無い"], "負例: title の Optional 変異"

  optional_full = good.sub("public let fullTitle: String\n", "public let fullTitle: String?\n")
  selftest_errors_eq check_public_api(optional_full), ["public let fullTitle: String が無い"], "負例: fullTitle の Optional 変異"

  no_title_public = good.sub("public let title: String", "let title: String")
  selftest_errors_eq check_public_api(no_title_public), ["public let title: String が無い"], "負例: title の public 欠落"

  no_public_enum = good.sub("public enum SessionTitleDeriver", "enum SessionTitleDeriver")
  selftest_errors_eq check_public_api(no_public_enum), ["SessionTitleDeriver が public ではない"], "負例: enum の public 欠落"

  banned = good + "\nimport Observation\n"
  selftest_errors_eq check_imports_and_purity(banned), ["許可していない import Observation"], "負例: 禁止依存 Observation"

  io = good.sub("DerivedSessionTitle(title: text, fullTitle: text)", "FileManager.default")
  selftest_errors_eq check_imports_and_purity(io), ["SessionTitleDeriver.swift に FileManager がある"], "負例: I/O 依存 FileManager"

  selftest_errors_eq(
    check_imports_and_purity(with_body_stmt(good, "print(text)")),
    ["SessionTitleDeriver.swift に print がある"],
    "負例: print"
  )
  selftest_errors_eq(
    check_imports_and_purity(with_body_stmt(good, "let _ = ProcessInfo.processInfo")),
    ["SessionTitleDeriver.swift に ProcessInfo がある"],
    "負例: ProcessInfo"
  )
  selftest_errors_eq(
    check_imports_and_purity(with_body_stmt(good, "let _ = Date()")),
    ["SessionTitleDeriver.swift に Date がある"],
    "負例: Date"
  )
  selftest_errors_eq(
    check_imports_and_purity(with_body_stmt(good, "let _ = x.now")),
    ["SessionTitleDeriver.swift に .now がある"],
    "負例: .now"
  )
  selftest_errors_eq(
    check_imports_and_purity(with_body_stmt(good, "let _ = Int.random(in: 0...1)")),
    ["SessionTitleDeriver.swift に random がある"],
    "負例: random"
  )
  selftest_errors_eq(
    check_imports_and_purity(with_body_stmt(good, "let _ = UserDefaults.standard")),
    ["SessionTitleDeriver.swift に UserDefaults がある"],
    "負例: UserDefaults"
  )
  selftest_errors_eq(
    check_imports_and_purity(with_body_stmt(good, 'let _ = "\\(print(text))"')),
    ["SessionTitleDeriver.swift に print がある"],
    "負例: 文字列補間内の print"
  )

  attr_darwin = "@preconcurrency import Darwin\n" + good
  selftest_errors_eq check_imports_and_purity(attr_darwin), ["許可していない import Darwin"], "負例: 属性付き import Darwin"

  attr_foundation = good.sub("import Foundation", "@preconcurrency import Foundation")
  selftest_errors_eq check_imports_and_purity(attr_foundation), [], "正例: 属性付き import Foundation は許可"

  string_decoy = good + %(\nlet x = "import Combine FileManager View print ProcessInfo Date random UserDefaults"\n)
  selftest_errors_eq check_imports_and_purity(string_decoy), [], "正例: 文字列内の禁止語は依存ではない"
  comment_decoy = good + "\n// import Combine\n// FileManager.default\n// print(ProcessInfo.processInfo)\n"
  selftest_errors_eq check_imports_and_purity(comment_decoy), [], "正例: コメント内の禁止語は依存ではない"

  flower = "#{AGENT_DOMAIN_SRC}/FlowerNameGenerator.swift"
  extra = "#{AGENT_DOMAIN_SRC}/SessionTitleState.swift"
  base_files = { flower => "import Foundation\n" }
  pkg = "pkg\n"
  with_follow_on = base_files.merge(DERIVER_PATH => good, extra => "x\n")
  with_only_deriver = base_files.merge(DERIVER_PATH => good)
  changed_existing = { flower => "changed\n", DERIVER_PATH => good }

  selftest_errors_eq other_sources_errors(base_files, base_files), [], "正例: 新規ファイル以外が基準 blob と同一"
  selftest_errors_eq(
    other_sources_errors({ flower => "changed\n" }, base_files),
    ["#{flower} が基準 blob と同一ではない"],
    "負例: 既存ソース改変"
  )
  selftest_errors_eq other_sources_errors(with_only_deriver, base_files), [], "正例: SessionTitleDeriver.swift 追加は既存比較から除外"
  selftest_errors_eq(
    other_sources_errors(base_files.merge(extra => "x\n"), base_files),
    ["新規製品ファイル #{extra} がある（許可は SessionTitleDeriver.swift のみ）"],
    "負例: 許可外の新規ソース"
  )

  selftest_errors_eq package_errors("pkg\n", "pkg\n"), [], "正例: Package.swift が基準と同一"
  selftest_errors_eq(
    package_errors("pkg2\n", "pkg\n"),
    ["AgentDomain の Package.swift が基準 blob と同一ではない（依存追加なし）"],
    "負例: Package.swift 改変（依存追加）"
  )
  selftest_errors_eq package_errors(nil, "pkg\n"), ["Package.swift が存在しない"], "負例: Package.swift 不在"
  selftest_errors_eq package_errors("pkg\n", nil), ["基準時点の Package.swift を git show できない"], "負例: Package.swift blob 欠落"

  selftest_errors_eq(
    collect_checks(good, with_follow_on, base_files, pkg, pkg, false),
    [],
    "正例: 導出契約回帰（SCOPE オフ）は後続ファイル追加を通す"
  )
  selftest_errors_eq(
    collect_checks(optional_title, with_follow_on, base_files, pkg, pkg, false),
    ["public let title: String が無い"],
    "負例: 導出契約回帰（SCOPE オフ）は Optional 変異を落とす"
  )
  selftest_errors_eq(
    collect_checks(good, with_only_deriver, base_files, pkg, pkg, true),
    [],
    "正例: 変更範囲検査（SCOPE オン）は Deriver 追加と他ファイル不変を通す"
  )
  selftest_errors_eq(
    collect_checks(good, with_follow_on, base_files, pkg, pkg, true),
    ["新規製品ファイル #{extra} がある（許可は SessionTitleDeriver.swift のみ）"],
    "負例: 変更範囲検査（SCOPE オン）は他ファイル追加を落とす"
  )
  selftest_errors_eq(
    collect_checks(good, changed_existing, base_files, pkg, pkg, true),
    ["#{flower} が基準 blob と同一ではない"],
    "負例: 変更範囲検査（SCOPE オン）は既存ソース改変を落とす"
  )
  selftest_errors_eq(
    collect_checks(good, with_only_deriver, base_files, "pkg2\n", pkg, true),
    ["AgentDomain の Package.swift が基準 blob と同一ではない（依存追加なし）"],
    "負例: 変更範囲検査（SCOPE オン）は Package.swift 改変を落とす"
  )
  selftest_errors_eq(
    scope_source_errors({}, {}, "deadbeef"),
    ["baseline deadbeef から AgentDomain ソースを読めない（黙示的成功にしない）"],
    "負例: 変更範囲検査で baseline ソース欠落"
  )

  with_env("TASK41_SCOPE_CHECK", "1") { selftest_assert scope_check_requested?, "正例: SCOPE_CHECK=1 で変更範囲検査 ON" }
  with_env("TASK41_SCOPE_CHECK", "0") { selftest_assert !scope_check_requested?, "負例: SCOPE_CHECK=0 では変更範囲検査 OFF" }
  with_env("TASK41_SCOPE_CHECK", nil) { selftest_assert !scope_check_requested?, "正例: 未設定では導出契約回帰のみ" }

  unset, unset_errs = baseline_env_errors(nil)
  selftest_assert unset.nil?, "負例: SHA 未設定は baseline を返さない"
  selftest_errors_eq unset_errs, ["TASK41_BASELINE が未設定（HEAD にフォールバックしない）"], "負例: SHA 未設定"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_errors_eq head_errs, ["TASK41_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD 指定"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_errors_eq head1_errs, ["TASK41_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: HEAD~1 指定"
  _, at_errs = baseline_env_errors("@")
  selftest_errors_eq at_errs, ["TASK41_BASELINE に HEAD は使えない（短い SHA を渡す）"], "負例: @ 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_errors_eq branch_errs, ["TASK41_BASELINE がコミット SHA ではない（ブランチ名は使えない）: main"], "負例: ブランチ名は不正"
  _, bad_errs = baseline_env_errors("not-a-sha")
  selftest_errors_eq bad_errs, ["TASK41_BASELINE がコミット SHA ではない（ブランチ名は使えない）: not-a-sha"], "負例: 不正 SHA"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"
  selftest_assert !workdir_matches_git_blob?("a", "b"), "負例: git show 内容の不一致"

  selftest_errors_eq frozen_artifact_errors("受け入れテスト", "blob", "blob"), [], "正例: 凍結テストが作業ツリーと同一"
  selftest_errors_eq frozen_artifact_errors("受け入れテスト", nil, "blob"), ["基準時点の受け入れテストを git show できない"], "負例: blob 欠落"
  selftest_errors_eq frozen_artifact_errors("受け入れテスト", "blob", "changed"), ["基準時点の受け入れテストが現在と同一ではない"], "負例: テスト改変"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "rb", "rb"), [], "正例: 凍結 rb が作業ツリーと同一"
  selftest_errors_eq frozen_artifact_errors("rb 自身", "rb", "changed"), ["基準時点のrb 自身が現在と同一ではない"], "負例: 検査改変"

  selftest_errors_eq implementation_in_baseline_errors(nil), [], "正例: 基準に SessionTitleDeriver.swift 不在"
  selftest_errors_eq(
    implementation_in_baseline_errors(good),
    ["基準時点に SessionTitleDeriver.swift がある（実装前の凍結ではない）"],
    "負例: 実装入り基準"
  )

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
  selftest_errors_eq ph_errs, ["契約 baseline_commit がプレースホルダ（凍結時に実 SHA へ置換する）"], "負例: プレースホルダは NG"

  parent_full = git_full_sha("HEAD~1")
  if head_full && parent_full && head_full != parent_full
    mismatch_errs = contract_baseline_errors("---\nbaseline_commit: \"#{head_full}\"\n", parent_full)
    selftest_errors_eq mismatch_errs, ["TASK41_BASELINE が契約 baseline_commit と一致しない"], "負例: TASK41_BASELINE と契約の不一致"
    match_errs = contract_baseline_errors("---\nbaseline_commit: \"#{head_full}\"\n", head_full)
    selftest_errors_eq match_errs, [], "正例: TASK41_BASELINE が契約 baseline_commit と一致"
    short = head_full[0, 7]
    short_errs = contract_baseline_errors("---\nbaseline_commit: #{head_full}\n", short)
    selftest_errors_eq short_errs, [], "正例: 短い SHA も完全 SHA に解決して一致"
  else
    mismatch_errs = contract_baseline_errors("---\nbaseline_commit: \"aaaaaaaa\"\n", "bbbbbbbb")
    selftest_assert mismatch_errs.any? { |m| m.include?("一致しない") || m.include?("無効") }, "負例: TASK41_BASELINE と契約の不一致"
  end

  prod = production_checks_source
  selftest_assert !prod.empty?, "正例: 本番検査セクションが存在する"
  selftest_assert baseline_check_connected?(prod), "正例: 基準検査が本番に接続されている"
  disconnected = prod.gsub("check_frozen_baseline", "removed_fn")
  selftest_assert !baseline_check_connected?(disconnected), "負例: 基準検査の本番接続を外す変異"
  selftest_assert scope_check_gated?(prod), "正例: 変更範囲検査が TASK41_SCOPE_CHECK でゲートされている"
  ungated = prod.gsub("if baseline && scope_check_requested?", "if baseline")
  selftest_assert !scope_check_gated?(ungated), "負例: 変更範囲検査のゲートを外す変異"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task41-wiring --selftest: OK"
  exit 0
end

# === task41 production checks ===
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
ng.concat(derivation_contract_errors(deriver))

if baseline && scope_check_requested?
  current_sources = worktree_agent_domain_sources
  previous_sources = baseline_agent_domain_sources(baseline)
  ng.concat(scope_source_errors(current_sources, previous_sources, baseline))
  ng.concat(package_errors(read_if_exist(PACKAGE_PATH), git_show(baseline, PACKAGE_PATH)))
end

ng = ng.uniq
if ng.empty?
  puts "task41-wiring: OK"
else
  ng.each { |m| puts "task41-wiring: NG #{m}" }
  exit 1
end
