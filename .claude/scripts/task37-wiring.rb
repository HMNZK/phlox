#!/usr/bin/env ruby
# task-37 配線検査: AgentConsoleStatusSummary が 3 状態ペイン先頭に接続され、
# CLI 詳細が DisclosureGroup に移り、toolbar・設定節・Finder・loadMCPServers が
# TASK37_BASELINE から欠落していないこと。

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

def extract_var_body(src, name)
  m = src.match(/(?:^|\n)[ \t]*(?:@[A-Za-z_][\w.]*[ \t]*)*(?:private\s+|public\s+|fileprivate\s+|internal\s+)?(?:static\s+)?var\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.end(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_call_args(src, callee)
  m = src.match(/#{Regexp.escape(callee)}\s*\(/)
  return nil unless m
  extract_balanced(src, m.end(0) - 1, "(", ")")
end

def git_show(rev, path)
  text = IO.popen(["git", "show", "#{rev}:#{path}"], err: [:child, :out], &:read)
  return text if $?.success?
  nil
end

def git_unchanged?(rev, path)
  system("git", "diff", "--quiet", rev, "--", path)
end

def make_args_exact?(args, available, config)
  return false if args.nil?
  got = compact(args).sub(/,\z/, "")
  got == "isAvailable:#{available},configFileExists:#{config}"
end

def parse_disclosure(src)
  m = src.match(/\bDisclosureGroup\b/)
  return nil unless m
  i = m.end(0)
  i += 1 while i < src.length && src[i] =~ /\s/
  args = nil
  if src[i] == "("
    args = extract_balanced(src, i, "(", ")")
    return nil if args.nil?
    i = i + 1 + args.length + 1
  end
  i += 1 while i < src.length && src[i] =~ /\s/
  return nil unless src[i] == "{"
  body = extract_balanced(src, i, "{", "}")
  return nil if body.nil?
  close = i + 1 + body.length + 1
  j = close
  j += 1 while j < src.length && src[j] =~ /\s/
  label_body = nil
  rest = src[j..]
  if rest && rest.start_with?("label:")
    k = src.index(":", j) + 1
    k += 1 while k < src.length && src[k] =~ /\s/
    if src[k] == "{"
      label_body = extract_balanced(src, k, "{", "}")
      close = k + 1 + label_body.length + 1 if label_body
    end
  end
  { args: args, body: body, label: label_body, before: src[0...m.begin(0)], after: src[close..] }
end

def extract_status_section(src, title)
  m = src.match(/AgentConsoleStatusSection\s*\(\s*title:\s*"#{Regexp.escape(title)}"/)
  return nil unless m
  paren = src.index("(", m.begin(0))
  args = extract_balanced(src, paren, "(", ")")
  return nil if args.nil?
  i = paren + 1 + args.length + 1
  i += 1 while i < src.length && src[i] =~ /\s/
  return nil unless src[i] == "{"
  body = extract_balanced(src, i, "{", "}")
  return nil if body.nil?
  compact(args.to_s + body.to_s)
end

def selftest_assert(cond, msg)
  unless cond
    puts "task37-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def run_selftest
  url = %(let url = "https://example.com" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://example.com"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert !strip_comments("let a = 1 /* x */ let b = 2").include?("x"), "正例: /* */ を除去する"

  good = "isAvailable: model.isAvailable, configFileExists: model.status.configFileExists"
  selftest_assert make_args_exact?(good, "model.isAvailable", "model.status.configFileExists"),
                  "正例: make 実引数が完全一致"
  bad = "isAvailable: model.isAvailable && false, configFileExists: model.status.configFileExists"
  selftest_assert !make_args_exact?(bad, "model.isAvailable", "model.status.configFileExists"),
                  "負例: isAvailable: model.isAvailable && false は完全一致しない"

  claude = "isAvailable: model.isClaudeAvailable, configFileExists: model.status.settingsFileExists"
  selftest_assert make_args_exact?(claude, "model.isClaudeAvailable", "model.status.settingsFileExists"),
                  "正例: Claude の make 実引数"

  dg = parse_disclosure(<<~SWIFT)
    DisclosureGroup(isExpanded: $showsCLIDetails) {
      Text("version")
    } label: {
      Text(summary.cliDetailsTitle)
    }
  SWIFT
  selftest_assert !dg.nil?, "正例: DisclosureGroup(isExpanded:) { } label: { } を切り出せる"
  selftest_assert compact(dg[:args].to_s).include?("isExpanded:$showsCLIDetails") || compact(dg[:args].to_s).include?("$showsCLIDetails"),
                  "正例: isExpanded を読む"
  selftest_assert compact(dg[:label].to_s).include?("summary.cliDetailsTitle"), "正例: label クロージャを読む"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task37-wiring --selftest: OK"
  exit 0
end

ng = []
summary_path = "macos/Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleStatusSummary.swift"
claude_pane = "macos/App/AgentConsole/Claude/ClaudeStatusPane.swift"
codex_pane = "macos/App/AgentConsole/Codex/CodexStatusPane.swift"
cursor_pane = "macos/App/AgentConsole/Cursor/CursorStatusPane.swift"
custom_path = "macos/Packages/AgentDomain/Sources/AgentDomain/CustomAgentDefinition.swift"
composition_path = "macos/App/CompositionRoot.swift"

UNCHANGED_PATHS = [
  custom_path,
  composition_path,
  "macos/App/AgentConsole/Claude/ClaudeConsoleModel.swift",
  "macos/App/AgentConsole/Codex/CodexConsoleModel.swift",
  "macos/App/AgentConsole/Cursor/CursorConsoleModel.swift",
]

status_specs = [
  {
    path: claude_pane,
    name: "ClaudeStatusPane",
    available: "model.isClaudeAvailable",
    config: "model.status.settingsFileExists",
    version_value: "model.status.claudeVersion??\"—\"",
    path_mono: "model.status.claudeExecutablePath",
    extra_needles: [
      "summaryTiles",
      'AgentConsoleStatusSection(title:"設定"',
      'AgentConsoleStatusSection(title:"メモリ"',
      "settings.json",
      "model.status.memoryFiles",
      "model.loadSettings()",
      "model.loadVersion()",
      "model.loadPlugins()",
      "installedPluginCount",
      "marketplaceCount",
      "permissionRuleCount",
      "hookCount",
      "activateFileViewerSelecting",
    ],
  },
  {
    path: codex_pane,
    name: "CodexStatusPane",
    available: "model.isAvailable",
    config: "model.status.configFileExists",
    version_value: "model.status.codexVersion??\"—\"",
    path_mono: "model.status.codexExecutablePath",
    extra_needles: [
      "summaryTiles",
      'AgentConsoleStatusSection(title:"設定"',
      'AgentConsoleStatusSection(title:"メモリ"',
      "config.toml",
      "model.status.memoryFiles",
      "model.loadConfig()",
      "model.loadVersion()",
      "model.loadMCPServers()",
      "installedPluginCount",
      "mcpServerCount",
      "trustedProjectCount",
      "activateFileViewerSelecting",
    ],
  },
  {
    path: cursor_pane,
    name: "CursorStatusPane",
    available: "model.isAvailable",
    config: "model.status.configFileExists",
    version_value: "model.status.cursorVersion??\"—\"",
    path_mono: "model.status.cursorExecutablePath",
    extra_needles: [
      "summaryTiles",
      'AgentConsoleStatusSection(title:"設定"',
      "cli-config.json",
      "mcp.json",
      "model.loadSettings()",
      "model.loadVersionAndModels()",
      "allowRuleCount",
      "denyRuleCount",
      "mcpServerCount",
      "認証情報とキャッシュは画面に出さず、書き込みでも触りません。",
      "activateFileViewerSelecting",
    ],
  },
]

baseline = ENV["TASK37_BASELINE"]
if baseline.nil? || baseline.empty?
  ng << "TASK37_BASELINE が未設定（HEAD にフォールバックしない）"
  baseline = nil
end

unless File.exist?(summary_path)
  ng << "#{summary_path} が存在しない"
else
  summary_src = strip_comments(File.read(summary_path))
  ng << "AgentConsoleStatusSummary.swift が SwiftUI を import している" if summary_src =~ /^\s*import\s+SwiftUI\b/
  ng << "AgentConsoleStatusSummary.swift が AppKit を import している" if summary_src =~ /^\s*import\s+AppKit\b/
  ng << "AgentConsoleStatusSummary.swift に Color がある" if summary_src =~ /\bColor\b/
  ng << "AgentConsoleStatusSummary.swift に View がある" if summary_src =~ /\bView\b/
  ng << "AgentConsoleStatusSummary.swift に Observable がある" if summary_src =~ /\bObservable\b/
  ng << "AgentConsoleStatusSummary.swift に @State がある" if summary_src =~ /@State\b/
  ng << "AgentConsoleStatusSummary.swift に UserDefaults がある" if summary_src =~ /\bUserDefaults\b/
  ng << "AgentConsoleStatusSummary.swift に FileManager がある" if summary_src =~ /\bFileManager\b/
  ng << "AgentConsoleStatusSummary.swift に Process がある" if summary_src =~ /\bProcess\b/
  unless summary_src =~ /\bstruct\s+AgentConsoleStatusSummary\b/
    ng << "AgentConsoleStatusSummary.swift に struct AgentConsoleStatusSummary が無い"
  end
  unless summary_src =~ /\bstatic\s+func\s+make\s*\(\s*isAvailable\s*:/
    ng << "AgentConsoleStatusSummary.swift に static func make(isAvailable: が無い"
  end
end

status_specs.each do |spec|
  unless File.exist?(spec[:path])
    ng << "#{spec[:path]} が存在しない"
    next
  end
  raw = File.read(spec[:path])
  src = strip_comments(raw)
  body = extract_struct_body(src, spec[:name])
  if body.nil?
    ng << "#{spec[:name]} の struct 本文を括弧対応で切り出せない"
    next
  end
  body_c = compact(body)

  unless body_c.include?("@StateprivatevarshowsCLIDetails=false") || body_c.include?("@StateprivatevarshowsCLIDetails:Bool=false")
    ng << "#{spec[:name]} に @State private var showsCLIDetails = false が無い"
  end

  make_args = extract_call_args(body, "AgentConsoleStatusSummary.make")
  if make_args.nil?
    ng << "#{spec[:name]} に AgentConsoleStatusSummary.make( が無い"
  elsif !make_args_exact?(make_args, spec[:available], spec[:config])
    ng << "#{spec[:name]} の make 実引数が #{compact(make_args).inspect}（期待 isAvailable:#{spec[:available]},configFileExists:#{spec[:config]}）"
  end

  %w[
    summary.availabilityText
    summary.availabilityDetail
    summary.configurationText
    summary.configurationDetail
  ].each do |needle|
    ng << "#{spec[:name]} に #{needle} が無い" unless body_c.include?(needle)
  end

  i_avail = body_c.index("summary.availabilityText")
  i_tiles = body_c.index("summaryTiles")
  if i_avail.nil? || i_tiles.nil?
    ng << "#{spec[:name]} の先頭表示順検査に availabilityText / summaryTiles が足りない"
  elsif !(i_avail < i_tiles)
    ng << "#{spec[:name]} で summary.availabilityText が summaryTiles より後にある"
  end

  dg = parse_disclosure(body)
  if dg.nil?
    ng << "#{spec[:name]} の DisclosureGroup を括弧対応で切り出せない"
  else
    args_c = compact(dg[:args].to_s)
    label_c = compact(dg[:label].to_s)
    joined = compact([dg[:args], dg[:body], dg[:label]].compact.join)
    unless args_c.include?("$showsCLIDetails") || joined.include?("isExpanded:$showsCLIDetails")
      ng << "#{spec[:name]} の DisclosureGroup に isExpanded: $showsCLIDetails が無い"
    end
    unless args_c.include?("summary.cliDetailsTitle") || compact(dg[:body]).include?("summary.cliDetailsTitle") || label_c.include?("summary.cliDetailsTitle")
      ng << "#{spec[:name]} の DisclosureGroup に summary.cliDetailsTitle が無い"
    end
    dg_c = compact(dg[:body])
    unless dg_c.include?('label:"バージョン"')
      ng << "#{spec[:name]} の DisclosureGroup 内に label: \"バージョン\" が無い"
    end
    unless dg_c.include?('label:"実行ファイル"')
      ng << "#{spec[:name]} の DisclosureGroup 内に label: \"実行ファイル\" が無い"
    end
    unless dg_c.include?(spec[:version_value])
      ng << "#{spec[:name]} の DisclosureGroup 内に #{spec[:version_value]} が無い"
    end
    unless dg_c.include?(spec[:path_mono])
      ng << "#{spec[:name]} の DisclosureGroup 内に #{spec[:path_mono]} が無い"
    end
    outside = compact(dg[:before].to_s + dg[:after].to_s)
    if outside.include?('label:"バージョン"') || outside.include?('AgentConsoleStatusSection(title:"CLI"')
      ng << "#{spec[:name]} で CLI の 2 行が DisclosureGroup の外にも残っている"
    end
  end

  spec[:extra_needles].each do |needle|
    ng << "#{spec[:name]} に #{needle} が無い" unless body_c.include?(compact(needle)) || body.include?(needle)
  end

  toolbar = extract_var_body(body, "toolbar") || extract_var_body(src, "toolbar")
  if toolbar.nil?
    ng << "#{spec[:name]} の toolbar 本文を切り出せない"
  elsif !compact(toolbar).include?("activateFileViewerSelecting")
    ng << "#{spec[:name]} の toolbar に Finder 操作 activateFileViewerSelecting が無い"
  end

  settings_section = extract_status_section(body, "設定")
  if settings_section.nil?
    ng << "#{spec[:name]} の 設定節を切り出せない"
  end

  next unless baseline

  previous = git_show(baseline, spec[:path])
  if previous.nil?
    ng << "git show #{baseline}:#{spec[:path]} に失敗"
    next
  end
  prev_src = strip_comments(previous)
  prev_body = extract_struct_body(prev_src, spec[:name])
  if prev_body.nil?
    ng << "#{spec[:name]} の baseline struct 本文を切り出せない"
    next
  end

  prev_toolbar = extract_var_body(prev_body, "toolbar") || extract_var_body(prev_src, "toolbar")
  cur_toolbar = toolbar
  if prev_toolbar.nil? || cur_toolbar.nil?
    ng << "#{spec[:name]} の toolbar を #{baseline} と比較できない"
  elsif compact(prev_toolbar) != compact(cur_toolbar)
    ng << "#{spec[:name]} の toolbar が #{baseline} から変化している"
  end

  prev_settings = extract_status_section(prev_body, "設定")
  if prev_settings.nil? || settings_section.nil?
    ng << "#{spec[:name]} の 設定節を #{baseline} と比較できない"
  elsif prev_settings != settings_section
    ng << "#{spec[:name]} の 設定節が #{baseline} から変化している"
  end

  if spec[:name] == "CodexStatusPane"
    prev_c = compact(prev_body)
    unless prev_c.include?("model.loadMCPServers()") && body_c.include?("model.loadMCPServers()")
      ng << "#{spec[:name]} の loadMCPServers() が #{baseline} または HEAD に無い"
    end
  end
end

if baseline
  UNCHANGED_PATHS.each do |path|
    unless git_unchanged?(baseline, path)
      ng << "#{path} が #{baseline} から差分あり"
    end
  end
end

if ng.empty?
  puts "task37-wiring: OK"
else
  ng.each { |m| puts "task37-wiring: NG #{m}" }
  exit 1
end
