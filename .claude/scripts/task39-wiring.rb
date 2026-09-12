#!/usr/bin/env ruby
# task-39 配線検査: TerminalView の載せ替えが TerminalMount の所有権判定を通り、
# dismantle（または同等）から detach に到達し、Dashboard / SessionViewModel の
# 呼び出し経路とサイズ・描画・ADR-0116・Whitebox が TASK39_BASELINE から欠けず、
# [BUG01] / Bug01Trace / 追加 os_log が製品に無いこと。

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

def extract_call_args(src, callee)
  m = src.match(/#{Regexp.escape(callee)}\s*\(/)
  return nil unless m
  extract_balanced(src, m.end(0) - 1, "(", ")")
end

def count_calls(src, callee)
  n = 0
  pos = 0
  re = /#{Regexp.escape(callee)}\s*\(/
  while (m = src.match(re, pos))
    n += 1
    pos = m.begin(0) + 1
  end
  n
end

def code_call_count(src, callee)
  count_calls(mask_strings_and_comments(src), callee)
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
  strip_if_false_blocks(mask_strings_and_comments(src))
end

def function_bodies(src)
  bodies = []
  pos = 0
  re = /(?:^|\n)[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]*)*(?:(?:private|public|fileprivate|internal|open|override|final|static|nonisolated)\s+)*func\s+\w+\s*\(/
  while (m = src.match(re, pos))
    paren = src.index("(", m.begin(0))
    unless paren
      pos = m.end(0)
      next
    end
    params = extract_balanced(src, paren, "(", ")")
    unless params
      pos = m.end(0)
      next
    end
    after = paren + 1 + params.length + 1
    brace = src.index("{", after)
    unless brace
      pos = m.end(0)
      next
    end
    body = extract_balanced(src, brace, "{", "}")
    bodies << body if body
    pos = m.end(0)
  end
  bodies
end

def inside_if_attach_block?(prefix)
  pos = 0
  last_open = nil
  while (i = prefix.index("ifTerminalMount.attach", pos))
    brace = prefix.index("{", i)
    break unless brace
    last_open = brace
    pos = i + 1
  end
  return false unless last_open
  depth = 0
  prefix[last_open..].each_char do |ch|
    depth += 1 if ch == "{"
    depth -= 1 if ch == "}"
  end
  depth > 0
end

def attach_true_dominates?(prefix)
  return true if inside_if_attach_block?(prefix)
  if prefix.match?(/guardTerminalMount\.attach[^{]*else\{return\}/)
    return true
  end
  if prefix.include?("TerminalMount.attach") && prefix.match?(/guard[A-Za-z0-9_]+else\{return\}/)
    return true
  end
  false
end

def all_scrolls_attach_gated?(body)
  c = compact(body)
  return true unless c.include?("scrollToBottom()")
  idx = 0
  while (pos = c.index("scrollToBottom()", idx))
    prefix = c[0...pos]
    return false unless attach_true_dominates?(prefix)
    idx = pos + 1
  end
  true
end

def scroll_reservation_errors(src)
  ng = []
  reachable_file = reachable_code(src)
  unless reachable_file.include?("scrollToBottom")
    ng << "成功時の scrollToBottom 予約が無い"
    return ng
  end
  found = false
  function_bodies(src).each do |body|
    reachable = reachable_code(body)
    next unless reachable.include?("scrollToBottom")
    found = true
    unless all_scrolls_attach_gated?(reachable)
      ng << "scrollToBottom 予約が attach 成功（戻り値 true）に条件付けられていない"
      break
    end
  end
  unless found
    unless all_scrolls_attach_gated?(reachable_file)
      ng << "scrollToBottom 予約が attach 成功（戻り値 true）に条件付けられていない"
    end
  end
  ng
end

def baseline_tv_has_detach?(src)
  return false if src.nil?
  mount = extract_enum_body(src, "TerminalMount")
  return false unless mount
  masked = mask_strings_and_comments(mount)
  masked.match?(/static\s+func\s+detach\s*\(/) && mount.include?("-> Bool")
end

CONTRACT_BASELINE_PLACEHOLDER_RE = /PM|凍結|設定|TBD|TODO|FIXME|placeholder|未設定/i

def parse_contract_baseline_text(text)
  return :missing if text.nil?
  m = text.match(/^baseline_commit:\s*"([^"]*)"/)
  return :missing unless m
  value = m[1].strip
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
    raw = contract_text && contract_text[/^baseline_commit:\s*"([^"]*)"/, 1]
    ["契約 baseline_commit が不正: #{raw}"]
  else
    errs = []
    contract_full = git_full_sha(parsed)
    if contract_full.nil?
      errs << "契約 baseline_commit が無効なコミット: #{parsed}"
    elsif env_sha
      env_full = git_full_sha(env_sha)
      if env_full && env_full != contract_full
        errs << "TASK39_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def check_frozen_baseline(baseline)
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK39_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  unless git_is_ancestor?(full, "HEAD")
    ng << "TASK39_BASELINE が HEAD の祖先ではない"
  end
  tv_blob = git_show(full, PATHS[:terminal_view])
  if tv_blob.nil?
    ng << "基準時点の TerminalView.swift を git show できない（git show #{full}:#{PATHS[:terminal_view]}）"
  elsif baseline_tv_has_detach?(tv_blob)
    ng << "基準時点の TerminalView.swift に TerminalMount.detach がある（実装前の凍結ではない）"
  end
  test_blob = git_show(full, ACCEPTANCE_TEST_PATH)
  rb_blob = git_show(full, WIRING_RB_PATH)
  test_now = read_if_exist(ACCEPTANCE_TEST_PATH)
  rb_now = read_if_exist(WIRING_RB_PATH)
  if test_blob.nil?
    ng << "基準時点の受け入れテストを git show できない（git show #{full}:#{ACCEPTANCE_TEST_PATH}）"
  elsif !workdir_matches_git_blob?(test_now, test_blob)
    ng << "基準時点の受け入れテストが現在と同一ではない"
  end
  if rb_blob.nil?
    ng << "基準時点の rb 自身を git show できない（git show #{full}:#{WIRING_RB_PATH}）"
  elsif !workdir_matches_git_blob?(rb_now, rb_blob)
    ng << "基準時点の rb 自身が現在と同一ではない"
  end
  ng
end

def git_ls_files(rev, prefix)
  text = IO.popen(["git", "ls-tree", "-r", "--name-only", rev, prefix], err: [:child, :out], &:read)
  return [] unless $?.success?
  text.split("\n").reject(&:empty?)
end

def git_unchanged?(rev, path)
  system("git", "diff", "--quiet", rev, "--", path)
end

CONTRACT_PATH = "tasks/task-39.md"
ACCEPTANCE_TEST_PATH = "macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift"
WIRING_RB_PATH = ".claude/scripts/task39-wiring.rb"
WHITEBOX_GUARD = "guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }"

PATHS = {
  dashboard: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift",
  detail: "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardDetailView.swift",
  session: "macos/Packages/SessionFeature/Sources/SessionFeature/SessionView.swift",
  grid: "macos/Packages/SessionFeature/Sources/SessionFeature/SessionGridView.swift",
  pane: "macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift",
  session_vm: "macos/Packages/SessionFeature/Sources/SessionFeature/SessionViewModel.swift",
  grid_chat: "macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift",
  terminal_view: "macos/Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift",
  coordinator: "macos/Packages/TerminalUI/Sources/TerminalUI/TerminalCoordinator.swift",
  hosting: "macos/Packages/TerminalUI/Sources/TerminalUI/TerminalHostingView.swift",
  whitebox: "macos/Packages/TerminalUI/Tests/TerminalUITests/TerminalOpenAtBottomWhiteboxTests.swift",
}.freeze

UNCHANGED_PATHS = [
  PATHS[:dashboard],
  PATHS[:detail],
  PATHS[:session],
  PATHS[:grid],
  PATHS[:pane],
  PATHS[:session_vm],
  PATHS[:grid_chat],
  PATHS[:whitebox],
].freeze

PRODUCT_SOURCE_PREFIXES = [
  "macos/Packages/TerminalUI/Sources",
].freeze

INVESTIGATION_WALK_PREFIXES = [
  "macos/Packages/TerminalUI/Sources",
  "macos/Packages/SessionFeature/Sources",
  "macos/Packages/DashboardFeature/Sources",
].freeze

def read_if_exist(path)
  File.exist?(path) ? File.read(path) : nil
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK39_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK39_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK39_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
    return [nil, errs]
  end
  [value, errs]
end

def log_counts(src)
  masked = mask_strings_and_comments(src)
  {
    os_log: masked.scan(/\bos_log\s*\(/).size,
    logger: masked.scan(/\bLogger\s*\(/).size,
    print: masked.scan(/\bprint\s*\(/).size,
    nslog: masked.scan(/\bNSLog\s*\(/).size,
  }
end

def check_extra_logs(current_files, baseline_files)
  ng = []
  current_files.each do |path, src|
    next if src.nil?
    base = baseline_files[path] || ""
    cur = log_counts(src)
    prev = log_counts(base)
    %i[os_log logger print nslog].each do |kind|
      if cur[kind] > prev[kind]
        ng << "#{path} に baseline から追加された #{kind} がある（#{prev[kind]}→#{cur[kind]}）"
      end
    end
  end
  ng
end

def investigation_hits(src)
  hits = []
  hits << "[BUG01]" if src.include?("[BUG01]")
  hits << "Bug01Trace" if src.include?("Bug01Trace")
  hits
end

def terminal_view_coordinator_args(src)
  args = []
  s = strip_comments(src)
  pos = 0
  while (m = s.match(/TerminalView\s*\(/, pos))
    a = extract_balanced(s, m.end(0) - 1, "(", ")")
    args << compact(a) if a
    pos = m.end(0)
  end
  args
end

def check_missing(path, src, label = path)
  src.nil? ? ["#{label} が存在しない"] : []
end

def view_mode_case_bodies(src)
  body = extract_var_body(src, "detailMainContent")
  return nil if body.nil?
  mappings = {}
  pos = 0
  while (m = body.match(/case\s+\.(\w+)\s*:/, pos))
    after = m.end(0)
    nxt = body.index(/case\s+\./, after) || body.length
    mappings[m[1]] = compact(body[after...nxt])
    pos = after
  end
  mappings
end

def check_detail_branches(src)
  ng = []
  return ["DashboardDetailView.swift が存在しない"] if src.nil?
  main = extract_var_body(src, "detailMainContent")
  if main.nil?
    ng << "detailMainContent の本文を括弧対応で切り出せない"
    return ng
  end
  cases = view_mode_case_bodies(src)
  if cases.nil? || cases.empty?
    ng << "detailMainContent の viewMode switch を切り出せない"
    return ng
  end
  %w[single grid team].each do |name|
    ng << "detailMainContent から case .#{name} が削除されている" unless cases.key?(name)
  end
  if cases["single"] && !cases["single"].include?("singleDetail")
    ng << "single 分岐が singleDetail ではない（入れ替えまたは削除）"
  end
  if cases["grid"] && !cases["grid"].include?("SessionGridView(")
    ng << "grid 分岐の SessionGridView が無い（入れ替えまたは削除）"
  end
  if cases["grid"] && !cases["grid"].include?("focusedID:$router.selectedSession")
    ng << "grid の focusedID が $router.selectedSession ではない"
  end
  if cases["team"] && !cases["team"].include?("TeamTimelineView(")
    ng << "team 分岐の TeamTimelineView が無い"
  end
  single = extract_var_body(src, "singleDetail")
  if single.nil?
    ng << "singleDetail の本文を括弧対応で切り出せない"
    return ng
  end
  single_c = compact(single)
  ng << "singleDetail に router.selectedSession が無い" unless compact(single).include?("router.selectedSession")
  ng << "singleDetail の .pty 分岐が無い" unless single_c.include?("case.pty(")
  ng << "singleDetail の .appServer 分岐が無い" unless single_c.include?("case.appServer(")
  ng << "singleDetail の SessionView が無い" unless single_c.include?("SessionView(viewModel:session)")
  ng << "singleDetail の ChatSessionView が無い" unless single_c.include?("ChatSessionView(viewModel:session)")
  ng
end

def check_session_terminal_calls(session_src, pane_src, grid_src)
  ng = []
  ng.concat(check_missing(PATHS[:session], session_src, "SessionView.swift"))
  ng.concat(check_missing(PATHS[:pane], pane_src, "PaneLayoutView.swift"))
  ng.concat(check_missing(PATHS[:grid], grid_src, "SessionGridView.swift"))
  if session_src
    args = terminal_view_coordinator_args(session_src)
    if args.empty?
      ng << "SessionView の TerminalView 呼び出しが削除されている"
    else
      unless args.include?("coordinator:viewModel.terminalCoordinator")
        ng << "SessionView の TerminalView が viewModel.terminalCoordinator 以外に差し替わっている: #{args.inspect}"
      end
      if args.size != 1
        ng << "SessionView の TerminalView 呼び出しが #{args.size} 箇所（期待 1）"
      end
    end
  end
  if pane_src
    tile = extract_var_body(pane_src, "tileContent")
    if tile.nil?
      ng << "PaneLayoutView.tileContent の本文を括弧対応で切り出せない"
    else
      tile_c = compact(tile)
      ng << "tileContent の .pty 分岐が無い" unless tile_c.include?("case.pty(")
      ng << "tileContent の .appServer 分岐が無い" unless tile_c.include?("case.appServer(")
      unless tile_c.include?("TerminalView(coordinator:session.terminalCoordinator)")
        ng << "PaneLayoutView の TerminalView が session.terminalCoordinator ではない"
      end
      if code_call_count(tile, "TerminalView") != 1
        ng << "tileContent の TerminalView 呼び出しが重複または欠落している"
      end
    end
  end
  if grid_src
    body = extract_var_body(grid_src, "body")
    if body.nil?
      ng << "SessionGridView.body の本文を括弧対応で切り出せない"
    elsif !compact(body).include?("PaneLayoutView(")
      ng << "SessionGridView が PaneLayoutView を呼んでいない"
    end
  end
  ng
end

def check_session_vm_paths(src)
  ng = []
  return ["SessionViewModel.swift が存在しない"] if src.nil?
  ng << "SessionViewModel に terminalCoordinator が無い" unless src =~ /\bterminalCoordinator\b/
  bind = extract_func_body(src, "bindCoordinator")
  if bind.nil?
    ng << "bindCoordinator の本文を括弧対応で切り出せない"
  else
    bind_c = compact(bind)
    ng << "bindCoordinator に onInput が無い" unless bind_c.include?("terminalCoordinator.onInput=")
    ng << "bindCoordinator に onResize が無い" unless bind_c.include?("terminalCoordinator.onResize=")
    ng << "bindCoordinator が handleResize を呼ばない" unless bind_c.include?("handleResize(")
  end
  resize = extract_func_body(src, "handleResize")
  if resize.nil?
    ng << "handleResize の本文を括弧対応で切り出せない"
  else
    resize_c = compact(resize)
    ng << "handleResize の spawn 分岐が無い" unless resize_c.include?("didSpawn")
    ng << "handleResize の resize 分岐が無い" unless resize_c.include?("ptyManager.resize")
  end
  output = extract_func_body(src, "startOutputTask")
  if output.nil?
    ng << "startOutputTask の本文を括弧対応で切り出せない"
  elsif !compact(output).include?("coordinator.feed(")
    ng << "startOutputTask の feed 経路が無い"
  end
  attach_n = code_call_count(src, "TerminalMount.attach")
  detach_n = code_call_count(src, "TerminalMount.detach")
  ng << "SessionViewModel に TerminalMount.attach 呼び出しがある（期待 0）" unless attach_n == 0
  ng << "SessionViewModel に TerminalMount.detach 呼び出しがある（期待 0）" unless detach_n == 0
  ng
end

def check_dashboard_paths(src)
  ng = []
  return ["DashboardView.swift が存在しない"] if src.nil?
  args = extract_call_args(src, "DashboardDetailView")
  if args.nil?
    ng << "DashboardView の DashboardDetailView 呼び出しが無い"
  else
    args_c = compact(args)
    ng << "DashboardDetailView に viewModel: viewModel が無い" unless args_c.include?("viewModel:viewModel")
    ng << "DashboardDetailView に router: router が無い" unless args_c.include?("router:router")
  end
  ng << "DashboardView の viewMode 変更処理が無い" unless src =~ /onChange\(of:\s*router\.viewMode/
  ng << "DashboardView の selectedSession 変更処理が無い" unless src =~ /onChange\(of:\s*router\.selectedSession/
  attach_n = code_call_count(src, "TerminalMount.attach")
  detach_n = code_call_count(src, "TerminalMount.detach")
  ng << "DashboardView に TerminalMount.attach 呼び出しがある（期待 0）" unless attach_n == 0
  ng << "DashboardView に TerminalMount.detach 呼び出しがある（期待 0）" unless detach_n == 0
  ng
end

def check_grid_chat_live_resize(src)
  ng = []
  return ["GridChatColumn.swift が存在しない"] if src.nil?
  body = extract_var_body(src, "body")
  if body.nil?
    ng << "GridChatColumn.body の本文を括弧対応で切り出せない"
    return ng
  end
  body_c = compact(body)
  ng << "GridChatColumn の isLiveResizing が無い" unless src =~ /\bisLiveResizing\b/
  ng << "GridChatColumn の stableWidth が無い" unless src =~ /\bstableWidth\b/
  ng << "willStartLiveResizeNotification が無い" unless body_c.include?("NSWindow.willStartLiveResizeNotification")
  ng << "didEndLiveResizeNotification が無い" unless body_c.include?("NSWindow.didEndLiveResizeNotification")
  ng << "live resize 中の幅凍結が無い" unless body_c.include?("isLiveResizing&&stableWidth>0") || body_c.include?("formattingWidth")
  ng
end

def check_size_drawing(hosting_src, coordinator_src)
  ng = []
  ng.concat(check_missing(PATHS[:hosting], hosting_src, "TerminalHostingView.swift"))
  ng.concat(check_missing(PATHS[:coordinator], coordinator_src, "TerminalCoordinator.swift"))
  if hosting_src
    set_frame = extract_func_body(hosting_src, "setFrameSize")
    if set_frame.nil?
      ng << "setFrameSize の本文を括弧対応で切り出せない"
    else
      c = compact(set_frame)
      ng << "setFrameSize の非同期 refresh が無い" unless c.include?("DispatchQueue.main.async") && c.include?("refresh(")
      ng << "setFrameSize の needsDisplay が無い" unless c.include?("needsDisplay=true")
    end
  end
  if coordinator_src
    size = extract_func_body(coordinator_src, "sizeChanged")
    if size.nil?
      ng << "sizeChanged の本文を括弧対応で切り出せない"
    else
      c = compact(size)
      ng << "sizeChanged が onResize を呼ばない" unless c.include?("onResize(")
    end
  end
  ng
end

def check_whitebox(src)
  ng = []
  return ["TerminalOpenAtBottomWhiteboxTests.swift が存在しない"] if src.nil?
  ng << "Whitebox の sameContainerDoesNotRemount が削除されている" unless src =~ /\bsameContainerDoesNotRemount\b/
  ng << "Whitebox の newContainerRemounts が削除されている" unless src =~ /\bnewContainerRemounts\b/
  unless src.include?(WHITEBOX_GUARD)
    ng << "Whitebox の attach 戻り値ガード検査が弱体化している"
  end
  unless src.include?("coordinator?.scrollToBottom()")
    ng << "Whitebox の非同期スクロール検査が弱体化している"
  end
  ng
end

def check_terminal_mount(src)
  ng = []
  return ["TerminalView.swift が存在しない"] if src.nil?
  mount = extract_enum_body(src, "TerminalMount")
  if mount.nil?
    ng << "enum TerminalMount の本文を括弧対応で切り出せない"
    return ng
  end
  unless mount.match?(/static\s+func\s+attach\s*\(/) && mount.include?("-> Bool")
    ng << "TerminalMount.attach(_:to:) -> Bool が無い"
  end
  unless mount.match?(/static\s+func\s+detach\s*\(/) && mount.include?("-> Bool")
    ng << "TerminalMount.detach(_:from:) -> Bool が無い"
  end
  update = extract_func_body(src, "updateNSView")
  if update.nil?
    ng << "updateNSView の本文を括弧対応で切り出せない"
  else
    masked = mask_strings_and_comments(update)
    if masked =~ /\.addSubview\s*\(/
      ng << "updateNSView が TerminalMount を迂回して addSubview している"
    end
    if masked =~ /removeFromSuperview\s*\(/
      ng << "updateNSView が TerminalMount を迂回して removeFromSuperview している"
    end
  end
  attach_total = code_call_count(src, "TerminalMount.attach")
  ng << "TerminalView.swift の TerminalMount.attach 呼び出しが 0" if attach_total == 0
  unless compact(reachable_code(src)).include?("TerminalMount.attach(coordinator.hostingView")
    ng << "TerminalMount.attach が coordinator.hostingView を渡していない"
  end
  ng.concat(scroll_reservation_errors(src))
  ng
end

def check_dismantle_reaches_detach(src)
  ng = []
  return ["TerminalView.swift が存在しない"] if src.nil?
  dismantle = extract_func_body(src, "dismantleNSView")
  unless dismantle
    ng << "dismantleNSView または同等経路から TerminalMount.detach に到達しない"
    return ng
  end
  reachable = reachable_code(dismantle)
  if count_calls(reachable, "TerminalMount.detach") == 0
    ng << "dismantleNSView から到達可能な TerminalMount.detach が無い（if false・コメントは不可）"
  end
  args = extract_call_args(reachable, "TerminalMount.detach")
  unless args && compact(args).include?("coordinator.hostingView")
    ng << "dismantleNSView の detach が現在の mount が扱う端末（coordinator.hostingView）を引数にしていない"
  end
  if reachable =~ /removeFromSuperview\s*\(/
    ng << "dismantleNSView が owner 判定を迂回して removeFromSuperview している"
  end
  ng
end

def check_investigation(files)
  ng = []
  files.each do |path, src|
    next if src.nil?
    if File.basename(path) == "Bug01Trace.swift"
      ng << "#{path} が製品に残っている"
    end
    investigation_hits(src).each do |hit|
      ng << "#{path} に #{hit} がある"
    end
  end
  ng
end

def check_investigation_walk
  ng = []
  INVESTIGATION_WALK_PREFIXES.each do |prefix|
    next unless File.directory?(prefix)
    Dir.glob(File.join(prefix, "**", "*.swift")).each do |path|
      src = File.read(path)
      ng << "#{path} が製品に残っている" if File.basename(path) == "Bug01Trace.swift"
      ng << "#{path} に [BUG01] がある" if src.include?("[BUG01]")
      ng << "#{path} に Bug01Trace がある" if src.include?("Bug01Trace")
    end
  end
  ng
end

def git_grep_counts(pattern, rev: nil)
  cmd = ["git", "grep", "-I", "-c", "-E", pattern]
  cmd << "--untracked" unless rev
  cmd << rev if rev
  cmd += ["--", *INVESTIGATION_WALK_PREFIXES]
  text = IO.popen(cmd, err: [:child, :out], &:read)
  return {} unless $?.success? || $?.exitstatus == 1
  counts = {}
  text.split("\n").each do |line|
    next if line.empty?
    body = rev ? line.sub(/\A#{Regexp.escape(rev)}:/, "") : line
    path, n = body.rpartition(":").values_at(0, 2)
    next if path.empty? || n !~ /\A\d+\z/
    counts[path] = n.to_i
  end
  counts
end

def check_normalized_unchanged(label, current, previous)
  ng = []
  if current.nil?
    ng << "#{label} が存在しない"
    return ng
  end
  if previous.nil?
    ng << "git show baseline:#{label} に失敗"
    return ng
  end
  if normalize_code(current) != normalize_code(previous)
    ng << "#{label} が TASK39_BASELINE から変化している"
  end
  ng
end

def check_func_unchanged(label, func_name, current, previous)
  ng = []
  if current.nil? || previous.nil?
    ng << "#{label} の #{func_name} を baseline または作業ツリーから切り出せない"
    return ng
  end
  a = extract_func_body(current, func_name)
  b = extract_func_body(previous, func_name)
  if a.nil? || b.nil?
    ng << "#{label} の #{func_name} を括弧対応で切り出せない"
  elsif compact(a) != compact(b)
    ng << "#{label} の #{func_name} が TASK39_BASELINE から変化している"
  end
  ng
end

def check_foreign_mount_calls(current_files, baseline_files)
  ng = []
  current_files.each do |path, src|
    next if src.nil?
    next if path == PATHS[:terminal_view]
    next unless path.end_with?(".swift")
    next if path.include?("/Tests/")
    cur_attach = code_call_count(src, "TerminalMount.attach")
    cur_detach = code_call_count(src, "TerminalMount.detach")
    base_src = baseline_files[path] || ""
    base_attach = code_call_count(base_src, "TerminalMount.attach")
    base_detach = code_call_count(base_src, "TerminalMount.detach")
    if cur_attach != base_attach
      ng << "#{path} の TerminalMount.attach 呼び出しが baseline と一致しない（#{base_attach}→#{cur_attach}）"
    end
    if cur_detach != base_detach
      ng << "#{path} の TerminalMount.detach 呼び出しが baseline と一致しない（#{base_detach}→#{cur_detach}）"
    end
  end
  ng
end

def worktree_product_files
  files = {}
  PRODUCT_SOURCE_PREFIXES.each do |prefix|
    Dir.glob(File.join(prefix, "**", "*.swift")).each do |path|
      files[path] = File.read(path)
    end
  end
  UNCHANGED_PATHS.each do |path|
    files[path] = File.read(path) if File.exist?(path)
  end
  files
end

def investigation_swift_files
  files = {}
  INVESTIGATION_WALK_PREFIXES.each do |prefix|
    next unless File.directory?(prefix)
    Dir.glob(File.join(prefix, "**", "*.swift")).each do |path|
      files[path] = File.read(path)
    end
  end
  files
end

def baseline_investigation_files(rev)
  files = {}
  INVESTIGATION_WALK_PREFIXES.each do |prefix|
    git_ls_files(rev, prefix).each do |path|
      next unless path.end_with?(".swift")
      blob = git_show(rev, path)
      files[path] = blob if blob
    end
  end
  files
end

def baseline_product_files(rev)
  files = {}
  PRODUCT_SOURCE_PREFIXES.each do |prefix|
    git_ls_files(rev, prefix).each do |path|
      next unless path.end_with?(".swift")
      blob = git_show(rev, path)
      files[path] = blob if blob
    end
  end
  UNCHANGED_PATHS.each do |path|
    blob = git_show(rev, path)
    files[path] = blob if blob
  end
  files
end

def good_terminal_view_src
  <<~SWIFT
    public func updateNSView(_ nsView: NSView, context: Context) {
      guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }
      DispatchQueue.main.async { [weak coordinator] in
        coordinator?.scrollToBottom()
      }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: TerminalCoordinator) {
      _ = TerminalMount.detach(coordinator.hostingView, from: nsView)
    }
    enum TerminalMount {
      static func attach(_ terminal: NSView, to container: NSView) -> Bool {
        return true
      }
      static func detach(_ terminal: NSView, from container: NSView) -> Bool {
        return true
      }
    }
  SWIFT
end

def good_detail_src
  <<~SWIFT
    private var detailMainContent: some View {
      switch router.viewMode {
      case .single:
        singleDetail
      case .grid:
        SessionGridView(focusedID: $router.selectedSession)
      case .team:
        TeamTimelineView()
      }
    }
    private var singleDetail: some View {
      if let selectedID = router.selectedSession, let session = viewModel.sessionNode(id: selectedID) {
        switch session {
        case .pty(let session):
          SessionView(viewModel: session)
        case .appServer(let session):
          ChatSessionView(viewModel: session)
        }
      }
    }
  SWIFT
end

def selftest_assert(cond, msg)
  unless cond
    puts "task39-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def run_selftest
  url = %(let url = "https://example.com" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://example.com"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert !strip_comments("let a = 1 /* x */ let b = 2").include?("x"), "正例: /* */ を除去する"

  comment_only = good_detail_src.sub("private var detailMainContent", "// keep\n    private var detailMainContent")
  selftest_assert check_detail_branches(comment_only).empty?, "正例: コメント追加は合格"
  spaced = good_detail_src.gsub("  ", "    ")
  selftest_assert check_detail_branches(spaced).empty?, "正例: 空白だけの変更は合格"

  tv = good_terminal_view_src
  selftest_assert check_terminal_mount(tv).empty?, "正例: 所有権付き TerminalView は合格 (#{check_terminal_mount(tv).inspect})"
  selftest_assert check_dismantle_reaches_detach(tv).empty?, "正例: dismantle から detach に到達"

  helper_tv = <<~SWIFT
    public func updateNSView(_ nsView: NSView, context: Context) {
      attachCurrent(to: nsView)
    }
    private func attachCurrent(to nsView: NSView) {
      guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }
      DispatchQueue.main.async { [weak coordinator] in
        coordinator?.scrollToBottom()
      }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: TerminalCoordinator) {
      _ = TerminalMount.detach(coordinator.hostingView, from: nsView)
    }
    enum TerminalMount {
      static func attach(_ terminal: NSView, to container: NSView) -> Bool { true }
      static func detach(_ terminal: NSView, from container: NSView) -> Bool { true }
    }
  SWIFT
  selftest_assert check_terminal_mount(helper_tv).empty?, "正例: attach が TerminalView 内の helper にあっても合格 (#{check_terminal_mount(helper_tv).inspect})"
  selftest_assert check_dismantle_reaches_detach(helper_tv).empty?, "正例: helper 構成でも dismantle から detach に到達"

  no_single = good_detail_src.sub("case .single:", "case .gone:")
  selftest_assert check_detail_branches(no_single).any? { |m| m.include?("single") }, "負例: single 分岐の削除"

  swapped = good_detail_src.sub("case .grid:", "case .tmp:").sub("case .single:", "case .grid:").sub("case .tmp:", "case .single:")
  selftest_assert check_detail_branches(swapped).any? { |m| m.include?("grid") || m.include?("SessionGridView") || m.include?("single") }, "負例: single/grid の入れ替え"

  session_good = "var body: some View { TerminalView(coordinator: viewModel.terminalCoordinator) }"
  pane_good = <<~SWIFT
    private var tileContent: some View {
      switch session {
      case .pty(let session):
        TerminalView(coordinator: session.terminalCoordinator)
      case .appServer(let session):
        GridChatColumn(viewModel: session, onFocusGained: onSelect)
      }
    }
  SWIFT
  grid_good = "var body: some View { PaneLayoutView(sessions: sessions, tree: paneLayout, focusedID: $focusedID, onRemove: onRemove, onRename: onRename, onChangeWorkspace: onChangeWorkspace, onLayoutAction: onLayoutAction) }"
  selftest_assert check_session_terminal_calls(session_good, pane_good, grid_good).empty?, "正例: 単一とグリッドの TerminalView 配線"

  deleted = "var body: some View { EmptyView() }"
  selftest_assert check_session_terminal_calls(deleted, pane_good, grid_good).any? { |m| m.include?("削除") }, "負例: TerminalView 呼び出しの削除"

  dup = session_good + "\n" + session_good
  selftest_assert check_session_terminal_calls(dup, pane_good, grid_good).any? { |m| m.include?("2 箇所") || m.include?("重複") }, "負例: TerminalView 呼び出しの重複"

  swapped_coord = "var body: some View { TerminalView(coordinator: otherCoordinator) }"
  selftest_assert check_session_terminal_calls(swapped_coord, pane_good, grid_good).any? { |m| m.include?("差し替") }, "負例: 別 coordinator への差し替え"

  bypass = tv.sub("guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }", "nsView.addSubview(coordinator.hostingView)")
  selftest_assert check_terminal_mount(bypass).any? { |m| m.include?("迂回") || m.include?("attach") }, "負例: owner 判定の迂回"

  discarded = tv.sub("guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }", "_ = TerminalMount.attach(coordinator.hostingView, to: nsView)")
  selftest_assert check_terminal_mount(discarded).any? { |m| m.include?("戻り値") || m.include?("スクロール") }, "負例: 戻り値を捨てたスクロール"

  no_dismantle = tv.sub("static func dismantleNSView(_ nsView: NSView, coordinator: TerminalCoordinator) {", "static func otherTeardown(_ nsView: NSView, coordinator: TerminalCoordinator) {")
                   .sub("TerminalMount.detach(coordinator.hostingView, from: nsView)", "nsView.removeFromSuperview()")
  selftest_assert check_dismantle_reaches_detach(no_dismantle).any? { |m| m.include?("detach") }, "負例: detach の未接続"

  if_false_detach = tv.sub(
    "_ = TerminalMount.detach(coordinator.hostingView, from: nsView)",
    "if false { _ = TerminalMount.detach(coordinator.hostingView, from: nsView) }"
  )
  selftest_assert check_dismantle_reaches_detach(if_false_detach).any? { |m| m.include?("到達可能") || m.include?("if false") }, "負例: if false の detach"

  wrong_detach_arg = tv.sub("coordinator.hostingView, from: nsView", "oldTerminal, from: nsView")
  selftest_assert check_dismantle_reaches_detach(wrong_detach_arg).any? { |m| m.include?("coordinator.hostingView") }, "負例: detach 引数が現在の端末ではない"

  uncond_scroll = tv.sub(
    "guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }",
    "DispatchQueue.main.async { coordinator?.scrollToBottom() }\n      guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }"
  )
  selftest_assert check_terminal_mount(uncond_scroll).any? { |m| m.include?("scrollToBottom") }, "負例: 無条件のスクロール予約"

  decoy = <<~SWIFT
    public func updateNSView(_ nsView: NSView, context: Context) {
      EmptyView()
    }
    enum TerminalMount {
      static func attach(_ terminal: NSView, to container: NSView) -> Bool { true }
      static func detach(_ terminal: NSView, from container: NSView) -> Bool { true }
    }
    let comment = "TerminalMount.attach(coordinator.hostingView, to: nsView)"
    // TerminalMount.detach(from: nsView)
  SWIFT
  selftest_assert check_terminal_mount(decoy).any? { |m| m.include?("updateNSView") || m.include?("attach") }, "負例: コメントや文字列だけの呼び出し名は代用にならない"

  vm = <<~SWIFT
    public let terminalCoordinator: TerminalCoordinator
    private func bindCoordinator() {
      terminalCoordinator.onInput = { _ in }
      terminalCoordinator.onResize = { cols, rows in
        Task { await handleResize(cols: cols, rows: rows) }
      }
    }
    private func handleResize(cols: UInt16, rows: UInt16) async {
      if !didSpawn {
        await spawnIfNeeded()
      } else {
        try? await ptyManager.resize(id, cols: cols, rows: rows)
      }
    }
    private func startOutputTask(outputStream: AsyncStream<Data>, rawCapture: Int?) {
      outputTask = Task {
        for await data in outputStream {
          coordinator.feed(data)
        }
      }
    }
  SWIFT
  selftest_assert check_session_vm_paths(vm).empty?, "正例: SessionViewModel の resize/feed"

  vm_bad = vm.sub("ptyManager.resize", "ptyManager.kill")
  selftest_assert check_session_vm_paths(vm_bad).any? { |m| m.include?("resize") }, "負例: SessionViewModel の resize 経路変更"

  vm_feed_bad = vm.sub("coordinator.feed(data)", "let _ = data")
  selftest_assert check_session_vm_paths(vm_feed_bad).any? { |m| m.include?("feed") }, "負例: SessionViewModel の feed 経路変更"

  chat = <<~SWIFT
    @State private var isLiveResizing = false
    @State private var stableWidth: CGFloat = 0
    var body: some View {
      let formattingWidth = (isLiveResizing && stableWidth > 0) ? stableWidth : geo.size.width
      Color.clear
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willStartLiveResizeNotification)) { _ in
          isLiveResizing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { _ in
          isLiveResizing = false
        }
    }
  SWIFT
  selftest_assert check_grid_chat_live_resize(chat).empty?, "正例: live resize 対策"
  chat_bad = chat.sub("willStartLiveResizeNotification", "didResignKeyNotification")
  selftest_assert check_grid_chat_live_resize(chat_bad).any? { |m| m.include?("willStartLiveResize") }, "負例: live resize 対策の除去"

  bug = "func f() { print(\"[BUG01] attach\") }"
  selftest_assert check_investigation("x.swift" => bug).any? { |m| m.include?("[BUG01]") }, "負例: [BUG01] 混入"
  trace = "enum Bug01Trace {}"
  selftest_assert check_investigation("macos/Packages/TerminalUI/Sources/TerminalUI/Bug01Trace.swift" => trace).any? { |m| m.include?("Bug01Trace") }, "負例: Bug01Trace 混入"
  extra_log = check_extra_logs(
    { "a.swift" => "os_log(\"hi\")" },
    { "a.swift" => "let x = 1" }
  )
  selftest_assert extra_log.any? { |m| m.include?("os_log") }, "負例: 追加 os_log"
  print_extra = check_extra_logs({ "p.swift" => "print(\"mount\")" }, { "p.swift" => "let x = 1" })
  selftest_assert print_extra.any? { |m| m.include?("print") }, "負例: 追加 print"
  logger_extra = check_extra_logs({ "l.swift" => "Logger(subsystem: \"s\", category: \"c\")" }, { "l.swift" => "let x = 1" })
  selftest_assert logger_extra.any? { |m| m.include?("logger") }, "負例: 追加 Logger"
  comment_log = check_extra_logs({ "c.swift" => "let x = 1 // os_log(\"hi\")" }, { "c.swift" => "let x = 1" })
  selftest_assert comment_log.empty?, "正例: コメント内 os_log は追加ではない"
  same_line_log = check_extra_logs({ "s.swift" => "os_log(\"a\"); os_log(\"b\")" }, { "s.swift" => "os_log(\"a\")" })
  selftest_assert same_line_log.any? { |m| m.include?("os_log") }, "負例: 同一行への os_log 追加"

  dash = <<~SWIFT
    DashboardDetailView(viewModel: viewModel, router: router)
    .onChange(of: router.viewMode, initial: true) { _, newMode in }
    .onChange(of: router.selectedSession) { _, selectedID in }
  SWIFT
  selftest_assert check_dashboard_paths(dash).empty?, "正例: DashboardView の詳細・モード・選択"

  white = <<~SWIFT
    func sameContainerDoesNotRemount() {}
    func newContainerRemounts() {}
    #expect(source.contains("guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }"))
    coordinator?.scrollToBottom()
  SWIFT
  selftest_assert check_whitebox(white).empty?, "正例: Whitebox 検査文言"
  white_bad = white.sub(WHITEBOX_GUARD, "TerminalMount.attach(coordinator.hostingView, to: nsView)")
  selftest_assert check_whitebox(white_bad).any? { |m| m.include?("弱体化") }, "負例: Whitebox の弱体化"

  hosting = <<~SWIFT
    override func setFrameSize(_ newSize: NSSize) {
      DispatchQueue.main.async {
        terminal.refresh(startRow: 0, endRow: 1)
        self.terminalView.needsDisplay = true
      }
    }
  SWIFT
  coord = <<~SWIFT
    public nonisolated func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
      Task { @MainActor [weak self] in
        self?.onResize(cols, rows)
      }
    }
  SWIFT
  selftest_assert check_size_drawing(hosting, coord).empty?, "正例: setFrameSize / sizeChanged"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_assert unset.nil? && unset_errs.any? { |m| m.include?("未設定") }, "負例: 固定 SHA の欠落"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_assert head_errs.any? { |m| m.include?("HEAD") }, "負例: HEAD 自己比較"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_assert head1_errs.any? { |m| m.include?("HEAD") }, "負例: HEAD~1 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_assert branch_errs.any? { |m| m.include?("ブランチ") || m.include?("SHA") }, "負例: ブランチ名は不正"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"
  selftest_assert !workdir_matches_git_blob?("a", "b"), "負例: git show 内容の不一致"
  selftest_assert git_is_ancestor?(git_full_sha("HEAD"), "HEAD"), "正例: HEAD は HEAD の祖先"
  selftest_assert !baseline_tv_has_detach?(File.read(PATHS[:terminal_view])), "正例: 現行 TerminalView 基準は detach 無し"
  selftest_assert baseline_tv_has_detach?(tv), "負例: 基準時点に detach がある"

  selftest_assert parse_contract_baseline_text("---\nfoo: 1\n") == :missing, "負例: 契約 baseline_commit 欠落"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n") == :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"not-a-sha\"\n") == :invalid, "負例: 契約 baseline_commit 不正"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"abc1234\"\n") == "abc1234", "正例: 契約 baseline_commit が SHA"
  ph_errs = contract_baseline_errors("---\nbaseline_commit: \"PM が凍結時に設定\"\n", "abc1234")
  selftest_assert ph_errs.any? { |m| m.include?("プレースホルダ") }, "負例: プレースホルダは NG"
  mismatch_errs = contract_baseline_errors("---\nbaseline_commit: \"aaaaaaaa\"\n", "bbbbbbbb")
  selftest_assert mismatch_errs.any? { |m| m.include?("一致しない") || m.include?("無効") }, "負例: TASK39_BASELINE と契約の不一致"

  selftest_assert check_terminal_mount(nil).any? { |m| m.include?("存在しない") }, "負例: 必要なファイルが無い"
  selftest_assert check_session_vm_paths("struct X {}").any? { |m| m.include?("bindCoordinator") || m.include?("handleResize") }, "負例: 必要な関数が無い"

  unchanged = check_normalized_unchanged("f.swift", "let a = 1 // x", "let a = 1")
  selftest_assert unchanged.empty?, "正例: 意味を変えないコメントはファイル比較で合格"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task39-wiring --selftest: OK"
  exit 0
end

ng = []

raw = ENV["TASK39_BASELINE"]
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
    ng << "TASK39_BASELINE が無効なコミット: #{baseline}"
    baseline = nil
  else
    ng.concat(check_frozen_baseline(full))
    baseline = full
  end
end

sources = {}
PATHS.each do |key, path|
  sources[key] = read_if_exist(path)
  ng << "#{path} が存在しない" if sources[key].nil?
end

ng.concat(check_dashboard_paths(sources[:dashboard]))
ng.concat(check_detail_branches(sources[:detail]))
ng.concat(check_session_terminal_calls(sources[:session], sources[:pane], sources[:grid]))
ng.concat(check_session_vm_paths(sources[:session_vm]))
ng.concat(check_grid_chat_live_resize(sources[:grid_chat]))
ng.concat(check_size_drawing(sources[:hosting], sources[:coordinator]))
ng.concat(check_whitebox(sources[:whitebox]))
ng.concat(check_terminal_mount(sources[:terminal_view]))
ng.concat(check_dismantle_reaches_detach(sources[:terminal_view]))

current_product = worktree_product_files
ng.concat(check_investigation_walk)

if baseline
  previous_product = baseline_product_files(baseline)
  if previous_product.empty?
    ng << "baseline #{baseline} から製品ソースを読めない（黙示的成功にしない）"
  else
    UNCHANGED_PATHS.each do |path|
      previous = previous_product[path] || git_show(baseline, path)
      ng.concat(check_normalized_unchanged(path, read_if_exist(path), previous))
    end
    ng.concat(check_func_unchanged("TerminalHostingView.swift", "setFrameSize", sources[:hosting], previous_product[PATHS[:hosting]]))
    ng.concat(check_func_unchanged("TerminalCoordinator.swift", "sizeChanged", sources[:coordinator], previous_product[PATHS[:coordinator]]))
    ng.concat(check_foreign_mount_calls(current_product, previous_product))
    ng.concat(check_extra_logs(investigation_swift_files, baseline_investigation_files(baseline)))
    current_product.each_key do |path|
      next unless path.start_with?("macos/Packages/TerminalUI/Sources/")
      next if previous_product.key?(path)
      next if path == PATHS[:terminal_view]
      ng << "対象範囲の新規製品ファイル #{path} がある（許可は TerminalView.swift 内の所有権修正に限る）"
    end
  end
end

ng = ng.uniq
if ng.empty?
  puts "task39-wiring: OK"
else
  ng.each { |m| puts "task39-wiring: NG #{m}" }
  exit 1
end
