#!/usr/bin/env ruby
# task-38 配線検査: SettingsGroup.all が TabView の 5 タブに接続され、
# 14 Section の所属・順序・コントロール・footer・Binding が契約どおりで、
# TASK38_BASELINE から Section 内容が欠落していないこと。

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

def skip_ws(src, i)
  i += 1 while i < src.length && src[i] =~ /\s/
  i
end

def extract_struct_body(src, name)
  m = src.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?struct\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_func_body(src, name)
  m = src.match(/(?:^|\n)[ \t]*(?:@\w+[ \t]*)*(?:private\s+|public\s+|fileprivate\s+|internal\s+)?(?:static\s+)?func\s+#{Regexp.escape(name)}\s*\(/)
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
  i = skip_ws(src, m.end(0))
  if i < src.length && src[i] == ":"
    i = skip_type(src, i + 1)
    i = skip_ws(src, i)
  end
  return nil unless i < src.length && src[i] == "{"
  extract_balanced(src, i, "{", "}")
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

def parse_trailing_labeled_closures(src, i)
  found = {}
  loop do
    i = skip_ws(src, i)
    break if i >= src.length
    rest = src[i..]
    break unless rest =~ /\A(header|footer)[ \t]*:/
    label = Regexp.last_match(1)
    colon = src.index(":", i)
    break unless colon
    j = skip_ws(src, colon + 1)
    break unless src[j] == "{"
    body = extract_balanced(src, j, "{", "}")
    break if body.nil?
    found[label] = body
    i = j + 1 + body.length + 1
  end
  [found, i]
end

def header_title(header)
  return nil if header.nil?
  m = header.match(/Text\s*\(\s*"((?:\\.|[^"\\])*)"/)
  m && m[1]
end

def extract_all_sections(src)
  sections = []
  pos = 0
  while (m = src.match(/\bSection\b/, pos))
    i = skip_ws(src, m.end(0))
    args = nil
    if i < src.length && src[i] == "("
      args = extract_balanced(src, i, "(", ")")
      if args.nil?
        pos = m.end(0)
        next
      end
      i = skip_ws(src, i + 1 + args.length + 1)
    end
    unless i < src.length && src[i] == "{"
      pos = m.end(0)
      next
    end
    content = extract_balanced(src, i, "{", "}")
    if content.nil?
      pos = m.end(0)
      next
    end
    close = i + 1 + content.length + 1
    trailing, finish = parse_trailing_labeled_closures(src, close)
    sections << {
      title: header_title(trailing["header"]),
      content: content,
      header: trailing["header"],
      footer: trailing["footer"],
      args: args,
      start: m.begin(0),
      finish: finish,
    }
    pos = finish
  end
  sections
end

def section_title_duplicates(src)
  titles = section_titles_in_order(src)
  titles.group_by { |t| t }.select { |_, v| v.size > 1 }.keys
end

def section_map(src)
  map = {}
  extract_all_sections(strip_comments(src)).each do |sec|
    next if sec[:title].nil?
    next if map.key?(sec[:title])
    map[sec[:title]] = normalize_code(sec[:content].to_s + "\n" + sec[:footer].to_s)
  end
  map
end

def section_titles_in_order(src)
  extract_all_sections(strip_comments(src)).map { |sec| sec[:title] }.compact
end

def section_contents_match?(a, b)
  return false unless section_title_duplicates(a).empty? && section_title_duplicates(b).empty?
  ma = section_map(a)
  mb = section_map(b)
  return false if ma.empty? || mb.empty?
  return false unless ma.keys.sort == mb.keys.sort
  ma.all? { |title, body| body == mb[title] }
end

def literals_in_order?(src, literals)
  pos = 0
  literals.all? do |lit|
    i = src.index(lit, pos)
    if i
      pos = i + lit.length
      true
    else
      false
    end
  end
end

def extract_tabview_body(src)
  m = src.match(/\bTabView\b/)
  return nil unless m
  i = skip_ws(src, m.end(0))
  if i < src.length && src[i] == "("
    args = extract_balanced(src, i, "(", ")")
    return nil if args.nil?
    i = skip_ws(src, i + 1 + args.length + 1)
  end
  return nil unless i < src.length && src[i] == "{"
  extract_balanced(src, i, "{", "}")
end

def parse_switch_cases(src)
  m = src.match(/\bswitch\s+(?:group\.id|\.id|id)\b/)
  return [{}, []] unless m
  brace = src.index("{", m.end(0))
  return [{}, []] unless brace
  body = extract_balanced(src, brace, "{", "}")
  return [{}, []] if body.nil?
  cases = {}
  dups = []
  pos = 0
  while (cm = body.match(/case\s+"([^"]+)"\s*:/, pos))
    after = cm.end(0)
    nxt = body.index(/case\s+"/, after) || body.index(/\bdefault\s*:/, after) || body.length
    id = cm[1]
    chunk = body[after...nxt]
    if cases.key?(id)
      dups << id
      cases[id] = cases[id] + "\n" + chunk
    else
      cases[id] = chunk
    end
    pos = after
  end
  [cases, dups.uniq]
end

def extract_if_eq_block(src, gid)
  bodies = []
  pos = 0
  re = /(?:group\.id|id)\s*==\s*"#{Regexp.escape(gid)}"/
  while (m = src.match(re, pos))
    i = skip_ws(src, m.end(0))
    if i < src.length && src[i] == "{"
      body = extract_balanced(src, i, "{", "}")
      bodies << body if body
    end
    pos = m.end(0)
  end
  bodies.join("\n")
end

SWIFTUI_SKIP = %w[
  Form Section Text Label Toggle Picker Button ForEach TabView Binding Image Link
  LabeledContent Color View EmptyView Spacer Divider Group VStack HStack ZStack
  Tab Item TextField SettingsView SettingsGroup Bool String Int Double Optional
  true false nil some any body Task URL Bundle
].freeze

def collect_reachable(src, start_blob)
  result = start_blob.to_s.dup
  seen = {}
  queue = [start_blob.to_s]
  while (blob = queue.shift)
    blob.scan(/\b([A-Za-z_][A-Za-z0-9_]*)\b/).flatten.uniq.each do |name|
      next if SWIFTUI_SKIP.include?(name)
      next if seen[name]
      helper = extract_var_body(src, name) || extract_func_body(src, name) || extract_struct_body(src, name)
      next if helper.nil?
      seen[name] = true
      next unless helper =~ /\bSection\b/ || helper.include?("MobileTokenSection") || helper =~ /\bTabView\b/ || helper =~ /\bswitch\b/ || helper =~ /\bgroup\.id\b/ || helper.include?("SettingsGroup.all")
      result << "\n" << helper
      queue << helper
    end
  end
  result
end

def erase_if_false(src)
  result = src.dup
  loop do
    m = result.match(/\bif\s+false\b/)
    break unless m
    i = skip_ws(result, m.end(0))
    unless i < result.length && result[i] == "{"
      result[m.begin(0)...m.end(0)] = " "
      next
    end
    body = extract_balanced(result, i, "{", "}")
    break if body.nil?
    close = i + 1 + body.length + 1
    result[m.begin(0)...close] = " "
  end
  result
end

def reachable_from_body(settings_src)
  stripped = strip_comments(settings_src)
  body = extract_var_body(stripped, "body")
  return "" if body.nil?
  erase_if_false(collect_reachable(stripped, body))
end

def group_drawing_src(settings_src, gid)
  stripped = strip_comments(settings_src)
  body = extract_var_body(stripped, "body")
  return "" if body.nil?
  reachable = erase_if_false(collect_reachable(stripped, body))
  blob = +""
  cases, = parse_switch_cases(reachable)
  blob << cases[gid] if cases[gid]
  blob << extract_if_eq_block(reachable, gid)
  erase_if_false(collect_reachable(stripped, blob))
end

def foreach_all_errors(src)
  ng = []
  found_direct = false
  pos = 0
  while (m = src.match(/\bForEach\s*\(/, pos))
    args = extract_balanced(src, m.end(0) - 1, "(", ")")
    pos = m.end(0)
    next if args.nil?
    next unless compact(args).include?("SettingsGroup.all")
    c = compact(args)
    if c =~ /SettingsGroup\.all\.(reversed|sorted|shuffled|filter|map|prefix|suffix|drop|dropLast|dropFirst)\(/ ||
       c =~ /SettingsGroup\.all\[/ ||
       c.include?("Array(SettingsGroup.all")
      ng << "ForEach(SettingsGroup.all) が reversed / 並べ替え / 部分列になっている"
    elsif c =~ /\ASettingsGroup\.all\z/ || c =~ /\ASettingsGroup\.all,/
      found_direct = true
    else
      ng << "ForEach(SettingsGroup.all) が reversed / 並べ替え / 部分列になっている"
    end
  end
  ng << "ForEach(SettingsGroup.all) 直列挙が無い" unless found_direct
  ng
end

def extract_foreach_all_closure(src)
  pos = 0
  while (m = src.match(/\bForEach\s*\(/, pos))
    open = m.end(0) - 1
    args = extract_balanced(src, open, "(", ")")
    pos = m.end(0)
    next if args.nil?
    c = compact(args)
    next unless c =~ /\ASettingsGroup\.all\z/ || c =~ /\ASettingsGroup\.all,/
    after = open + 1 + args.length + 1
    j = skip_ws(src, after)
    return nil unless j < src.length && src[j] == "{"
    return extract_balanced(src, j, "{", "}")
  end
  nil
end

def extract_modifier_closures(src, name)
  bodies = []
  pos = 0
  while (m = src.match(/\.#{Regexp.escape(name)}\s*\{/, pos))
    brace = src.index("{", m.begin(0))
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

def accessibility_identifier_on_group_id?(src)
  pos = 0
  while (m = src.match(/\.accessibilityIdentifier\s*\(/, pos))
    args = extract_balanced(src, m.end(0) - 1, "(", ")")
    pos = m.end(0)
    next if args.nil?
    return true if args.include?('settings-group-\(group.id)')
  end
  false
end

def skip_attributes_and_modifiers(src, i)
  loop do
    i = skip_ws(src, i)
    break if i >= src.length
    if src[i] == "@"
      j = i + 1
      j += 1 while j < src.length && src[j] =~ /[A-Za-z0-9_.]/
      k = skip_ws(src, j)
      if k < src.length && src[k] == "("
        args = extract_balanced(src, k, "(", ")")
        return j if args.nil?
        i = k + 1 + args.length + 1
      else
        i = j
      end
      next
    end
    if src[i..] =~ /\A(private|public|fileprivate|internal|static|override|final|mutating)\s+/
      i += Regexp.last_match(1).length
      next
    end
    break
  end
  i
end

def skip_type(src, i)
  depth_a = 0
  depth_p = 0
  while i < src.length
    if src[i] == '"'
      i = index_after_string(src, i)
      next
    end
    if depth_a == 0 && depth_p == 0
      break if src[i] == "{" || src[i] == "=" || src[i] == "\n"
    end
    depth_a += 1 if src[i] == "<"
    depth_a -= 1 if src[i] == ">"
    depth_p += 1 if src[i] == "("
    depth_p -= 1 if src[i] == ")"
    i += 1
  end
  i
end

def end_of_expr(src, i)
  depth = 0
  while i < src.length
    if src[i] == '"'
      i = index_after_string(src, i)
      next
    end
    case src[i]
    when "(", "[", "{" then depth += 1
    when ")", "]", "}" then depth -= 1
    when "\n"
      return i if depth <= 0
    end
    i += 1
  end
  i
end

def extract_top_level_decls(struct_body)
  decls = {}
  src = struct_body
  i = 0
  while i < src.length
    i = skip_ws(src, i)
    break if i >= src.length
    if src[i] =~ /[;{}]/
      i += 1
      next
    end
    start = i
    i2 = skip_attributes_and_modifiers(src, i)
    rest = src[i2..]
    if rest =~ /\Astruct\s+([A-Za-z_][A-Za-z0-9_]*)/
      name = Regexp.last_match(1)
      brace = src.index("{", i2)
      break unless brace
      inner = extract_balanced(src, brace, "{", "}")
      break unless inner
      close = brace + 1 + inner.length + 1
      decls[name] = normalize_code(src[start...close])
      i = close
    elsif rest =~ /\Ainit\b/
      paren = src.index("(", i2)
      unless paren
        i += 1
        next
      end
      params = extract_balanced(src, paren, "(", ")")
      unless params
        i += 1
        next
      end
      after = paren + 1 + params.length + 1
      brace = src.index("{", after)
      unless brace
        i += 1
        next
      end
      inner = extract_balanced(src, brace, "{", "}")
      break unless inner
      close = brace + 1 + inner.length + 1
      decls["init"] = normalize_code(src[start...close])
      i = close
    elsif rest =~ /\Afunc\s+([A-Za-z_][A-Za-z0-9_]*)/
      name = Regexp.last_match(1)
      paren = src.index("(", i2)
      unless paren
        i += 1
        next
      end
      params = extract_balanced(src, paren, "(", ")")
      unless params
        i += 1
        next
      end
      after = paren + 1 + params.length + 1
      brace = src.index("{", after)
      unless brace
        i += 1
        next
      end
      inner = extract_balanced(src, brace, "{", "}")
      break unless inner
      close = brace + 1 + inner.length + 1
      decls[name] = normalize_code(src[start...close])
      i = close
    elsif rest =~ /\A(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)/
      name = Regexp.last_match(1)
      name_end = i2 + Regexp.last_match(0).length
      j = skip_ws(src, name_end)
      j = skip_type(src, j + 1) if j < src.length && src[j] == ":"
      j = skip_ws(src, j)
      if j < src.length && src[j] == "{"
        inner = extract_balanced(src, j, "{", "}")
        break unless inner
        close = j + 1 + inner.length + 1
        decls[name] = normalize_code(src[start...close])
        i = close
      elsif j < src.length && src[j] == "="
        close = end_of_expr(src, j + 1)
        decls[name] = normalize_code(src[start...close])
        i = close
      else
        close = name_end
        close += 1 while close < src.length && src[close] != "\n"
        decls[name] = normalize_code(src[start...close])
        i = close
      end
    else
      i += 1
    end
  end
  decls
end

def settings_view_decl_map(src)
  inner = extract_struct_body(src, "SettingsView")
  return {} if inner.nil?
  extract_top_level_decls(inner)
end

def non_section_decl_messages(current, previous, skip: [])
  msgs = []
  prev_map = settings_view_decl_map(previous)
  cur_map = settings_view_decl_map(current)
  if prev_map.empty?
    msgs << "baseline の SettingsView 宣言を切り出せない"
    return msgs
  end
  if cur_map.empty?
    msgs << "HEAD の SettingsView 宣言を切り出せない"
    return msgs
  end
  skip_set = skip.map(&:to_s)
  prev_map.each do |name, body|
    next if skip_set.include?(name)
    if !cur_map.key?(name)
      msgs << "宣言 #{name} が欠落している"
    elsif cur_map[name] != body
      msgs << "宣言 #{name} が baseline から変化している"
    end
  end
  msgs
end

def extract_app_storage_units(src)
  units = []
  stripped = strip_comments(src)
  pos = 0
  while (m = stripped.match(/@AppStorage\s*\(/, pos))
    open = m.end(0) - 1
    args = extract_balanced(stripped, open, "(", ")")
    unless args
      pos = m.end(0)
      next
    end
    after = open + 1 + args.length + 1
    rest = stripped[after..]
    vm = rest.match(/\A[\s\w]*?\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*/)
    unless vm
      pos = after
      next
    end
    name = vm[1]
    default_start = after + vm.end(0)
    close = end_of_expr(stripped, default_start)
    text = stripped[m.begin(0)...close]
    units << {
      key: compact(args),
      name: name,
      default: compact(stripped[default_start...close]),
      text: normalize_code(text),
    }
    pos = close
  end
  units
end

def app_storage_decl_assignment?(src, assign_begin, var)
  last = src.rindex("@AppStorage", assign_begin)
  return false unless last
  chunk = compact(src[last...assign_begin])
  chunk.match?(/\A@AppStorage\([^)]*\)(?:private|public|fileprivate|internal)*var#{Regexp.escape(var)}\z/)
end

def extract_assignment_stmt(src, ident_begin)
  eq = src.index("=", ident_begin)
  return src[ident_begin, 40] unless eq
  close = end_of_expr(src, eq + 1)
  src[ident_begin...close]
end

def storage_write_sites(src)
  stripped = strip_comments(src)
  sites = []
  STORAGE_VARS.each do |var|
    pos = 0
    re = /\b#{Regexp.escape(var)}\s*=(?!=)/
    while (m = stripped.match(re, pos))
      unless app_storage_decl_assignment?(stripped, m.begin(0), var)
        sites << normalize_code(extract_assignment_stmt(stripped, m.begin(0)))
      end
      pos = m.end(0)
    end
  end
  pos = 0
  while (m = stripped.match(/\bappUpdater\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)/, pos))
    ident_end = m.end(0)
    j = skip_ws(stripped, ident_end)
    if j < stripped.length && stripped[j] == "("
      args = extract_balanced(stripped, j, "(", ")")
      snippet = args ? stripped[m.begin(0)...(j + 1 + args.length + 1)] : m[0]
      sites << normalize_code(snippet)
    elsif j < stripped.length && stripped[j] == "=" && stripped[j + 1] != "="
      sites << normalize_code(extract_assignment_stmt(stripped, m.begin(0)))
    else
      sites << normalize_code(m[0])
    end
    pos = m.end(0)
  end
  pos = 0
  while (m = stripped.match(/\bNSApp\.applicationIconImage\s*=(?!=)/, pos))
    sites << normalize_code(extract_assignment_stmt(stripped, m.begin(0)))
    pos = m.end(0)
  end
  pos = 0
  while (m = stripped.match(/\bUserDefaults\b/, pos))
    window = stripped[m.begin(0), [160, stripped.length - m.begin(0)].min]
    if compact(window).include?(".set(") || compact(window).include?("removeObject") || compact(window).include?("removePersistentDomain")
      sites << normalize_code(window)
    end
    pos = m.end(0)
  end
  pos = 0
  while (m = stripped.match(/\bThemeStore\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)/, pos))
    sites << normalize_code(extract_assignment_stmt(stripped, m.begin(0)))
    pos = m.end(0)
  end
  sites.sort
end

def workdir_matches_git_blob?(workdir_text, git_blob)
  return false if git_blob.nil? || workdir_text.nil?
  workdir_text == git_blob
end

GROUP_PATH = "macos/Packages/DesignSystem/Sources/DesignSystem/SettingsGroup.swift"
SETTINGS_PATH = "macos/App/SettingsView.swift"
TEST_PATH = "macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceSettingsGroupingModelTests.swift"
RB_PATH = ".claude/scripts/task38-wiring.rb"

GROUP_ORDER = %w[general appearance agents connection advanced].freeze
GROUP_TITLES = %w[一般 外観 エージェント 接続 詳細].freeze
GROUP_IMAGES = ["gearshape", "paintpalette", "wrench.and.screwdriver", "network", "slider.horizontal.3"].freeze
AX_IDS = %w[
  settings-group-general
  settings-group-appearance
  settings-group-agents
  settings-group-connection
  settings-group-advanced
].freeze

GROUP_SECTION_TITLES = {
  "general" => %w[言語 セッション 通知 アップデート],
  "appearance" => %w[外観 アプリアイコン],
  "agents" => %w[権限 エージェント],
  "connection" => %w[モバイル接続 接続済みの端末],
  "advanced" => %w[チームビュー討論 使用量 プライバシー このアプリについて],
}.freeze

ALL_SECTION_TITLES = [
  "外観", "アプリアイコン", "言語", "セッション", "チームビュー討論", "権限",
  "モバイル接続", "接続済みの端末", "通知", "使用量", "エージェント", "プライバシー",
  "アップデート", "このアプリについて",
].freeze

SECTION_CONTROLS = {
  "外観" => ["ForEach(ThemeStore.all)", "ThemeRowView("],
  "アプリアイコン" => ["ForEach(AppIconStore.all)", "AppIconRowView("],
  "言語" => [
    'Text("システム")',
    'Text("日本語")',
    'Text("English")',
    'Label("表示言語", systemImage: "globe")',
  ],
  "セッション" => [
    'Text("チャット")',
    'Text("ターミナル")',
    'Label("デフォルトの開き方", systemImage: "rectangle.on.rectangle")',
  ],
  "チームビュー討論" => [
    'TextField("最大発言数"',
    'TextField("最大エージェント数"',
    'TextField("ターンタイムアウト（秒）"',
    'Text("自由発言")',
    'Text("ラウンドロビン")',
    'Label("スケジューラ", systemImage: "arrow.triangle.2.circlepath")',
  ],
  "権限" => ["ForEach(agentCatalog.allDescriptors, id: \\.ref)", "BypassToggleRow("],
  "モバイル接続" => [
    'TextField("端末名"',
    'Label("QR コードを表示", systemImage: "qrcode")',
  ],
  "接続済みの端末" => ["ForEach(viewModel.devices)", "MobileDeviceRow("],
  "通知" => [
    'Label("セッション完了をバナーで通知", systemImage: "bell")',
    'Label("完了サウンド（Glass）を鳴らす", systemImage: "speaker.wave.2")',
    'Button("通知テスト")',
  ],
  "使用量" => [
    'Label("使用量サイドバーを自動更新", systemImage: "arrow.clockwise")',
    'Label("Claudeの使用量を取得", systemImage: "sparkles")',
    'Label("未取得のCLIも表示", systemImage: "eye.slash")',
    'Label("ヘッダーに使用量を表示", systemImage: "menubar.rectangle")',
  ],
  "エージェント" => ['Label("エージェント管理を開く", systemImage: "wrench.and.screwdriver")'],
  "プライバシー" => [
    "https://phlox.cc/privacy",
    'Label("プライバシーポリシー", systemImage: "hand.raised")',
  ],
  "アップデート" => [
    'Label("起動時に自動でアップデートを確認", systemImage: "clock.arrow.circlepath")',
    'Button("今すぐ確認")',
  ],
  "このアプリについて" => [
    'LabeledContent("アプリ", value: AppFlavor.current.displayName)',
    'LabeledContent("バージョン", value: appVersion)',
    'LabeledContent("ビルド", value: buildNumber)',
  ],
}.freeze

SECTION_FOOTERS = {
  "外観" => "テーマ（ターミナルの配色とアプリ全体）を切り替えます。変更は即座に反映されます。",
  "アプリアイコン" => "Dock とアプリのアイコンを切り替えます。変更は即座に反映されます。",
  "セッション" => "新規セッションをチャット画面かターミナルで開くかの既定です。チャット非対応のエージェントはターミナルで開きます。",
  "チームビュー討論" => "チームビュー討論の上限・タイムアウト・発言順の既定です。変更は次回の討論開始から反映されます。",
  "権限" => "変更は次回セッション開始から反映されます。OFF は通常の安全モード（Claude Auto／Codex Auto／Cursor Auto-review）、ON は承認なしのフルアクセスです。信頼できるプロジェクトでのみ有効にしてください。",
  "モバイル接続" => "iPhone アプリで QR コードを読み取ると、同一 Tailscale ネットワーク経由で接続できます。「QR コードを表示」を押すたびに新しい端末として発行されます。既存の端末は影響を受けません。",
  "使用量" => "Codex・Cursor の使用量は自動で表示されます。Claude は Phlox 内で起動したセッションの使用量を表示します（直近に Phlox 内で Claude を起動していないと最新の値にならない場合があります）。",
  "エージェント" => "Claude Code・Codex・Cursor の設定をここから操作できます。対話 TUI のスラッシュコマンド（/plugin・/permissions 等）や、設定ファイルの手編集でしか触れない項目が対象です。",
}.freeze

NO_FOOTER_TITLES = %w[言語 接続済みの端末 通知 プライバシー アップデート このアプリについて].freeze

APP_STORAGE = [
  ["NotificationSettings.bannerKey", "bannerNotificationEnabled", "true"],
  ["NotificationSettings.soundKey", "completionSoundEnabled", "true"],
  ["UsageSettings.autoRefreshKey", "usageAutoRefresh", "true"],
  ["UsageSettings.claudeScrapeKey", "claudeScrape", "true"],
  ["UsageSettings.showUnavailableKey", "showUnavailableUsage", "false"],
  ["UsageSettings.showInHeaderKey", "showUsageInHeader", "true"],
  ["ThemeStore.themeKey", "themeID", "AppTheme.phlox.id"],
  ["AppIconStore.iconKey", "appIconID", "AppIconStore.defaultOption.id"],
  ["LanguageSettings.languageKey", "appLanguageRaw", "AppLanguage.system.rawValue"],
  ["DefaultSessionBackendPreference.storageKey", "defaultSessionBackendRaw", "DefaultSessionBackendPreference.chat.rawValue"],
  ["AgoraDiscussionSettings.maxUtterancesKey", "agoraMaxUtterances", "30"],
  ["AgoraDiscussionSettings.maxAgentsKey", "agoraMaxAgents", "5"],
  ["AgoraDiscussionSettings.turnTimeoutSecondsKey", "agoraTurnTimeoutSeconds", "180"],
  ["AgoraDiscussionSettings.schedulerKey", "agoraSchedulerRaw", "AgoraSchedulerKind.freeSpeech.rawValue"],
].freeze

STORAGE_VARS = APP_STORAGE.map { |_, var, _| var }.freeze

SHA_VARS = %w[
  appLanguageBinding
  defaultSessionBackendBinding
  agoraSchedulerBinding
  appVersion
  buildNumber
  header
].freeze

SHA_STRUCTS = %w[
  BypassToggleRow
  MobileTokenSection
  MobileDeviceRow
  ThemeRowView
  ThemeAppPreview
  ThemeSwatchStrip
  AppIconRowView
  RichButtonStyle
].freeze

DECL_SKIP = %w[body].freeze

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK38_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0"
    errs << "TASK38_BASELINE にリテラル HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK38_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
    return [nil, errs]
  end
  [value, errs]
end

def check_frozen_baseline(baseline)
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK38_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  unless git_is_ancestor?(full, "HEAD")
    ng << "TASK38_BASELINE が HEAD の祖先ではない"
  end
  group_blob = git_show(full, GROUP_PATH)
  settings_blob = git_show(full, SETTINGS_PATH)
  ng << "基準時点で SettingsGroup.swift が存在する（実装前の凍結ではない）" if group_blob
  if settings_blob.nil?
    ng << "基準時点の SettingsView.swift を git show できない"
  elsif settings_blob =~ /\bTabView\b/
    ng << "基準時点の SettingsView に TabView がある（実装前の凍結ではない）"
  end
  test_blob = git_show(full, TEST_PATH)
  rb_blob = git_show(full, RB_PATH)
  test_now = File.exist?(TEST_PATH) ? File.read(TEST_PATH) : nil
  rb_now = File.exist?(RB_PATH) ? File.read(RB_PATH) : nil
  unless workdir_matches_git_blob?(test_now, test_blob)
    ng << "基準時点の受け入れテストが現在と同一ではない"
  end
  unless workdir_matches_git_blob?(rb_now, rb_blob)
    ng << "基準時点の rb 自身が現在と同一ではない"
  end
  ng
end

def check_all_is_literal_inits(src)
  ng = []
  m = src.match(/\bstatic\s+let\s+all\b/)
  unless m
    ng << "SettingsGroup.swift に static let all が無い"
    return ng
  end
  eq = src.index("=", m.end(0))
  unless eq
    ng << "SettingsGroup.all に = が無い"
    return ng
  end
  i = skip_ws(src, eq + 1)
  if src[i] == "{"
    ng << "SettingsGroup.all がクロージャで初期化されている"
    return ng
  end
  unless src[i] == "["
    ng << "SettingsGroup.all がリテラル配列ではない"
    return ng
  end
  body = extract_balanced(src, i, "[", "]")
  unless body
    ng << "SettingsGroup.all の配列を切り出せない"
    return ng
  end
  stripped = strip_comments(body)
  if stripped.include?("{")
    ng << "SettingsGroup.all の配列にクロージャがある"
  end
  if stripped =~ /\bprint\s*\(/
    ng << "SettingsGroup.all に print がある"
  end
  elements = 0
  pos = 0
  wiped = stripped.dup
  replacements = []
  while (cm = stripped.match(/\bSettingsGroup\s*\(/, pos))
    args = extract_balanced(stripped, cm.end(0) - 1, "(", ")")
    break unless args
    close = (cm.end(0) - 1) + 1 + args.length + 1
    replacements << [cm.begin(0), close]
    elements += 1
    pos = close
  end
  replacements.reverse_each { |a, b| wiped[a...b] = " " }
  remainder = compact(wiped).delete(",")
  unless remainder.empty?
    ng << "SettingsGroup.all にイニシャライザ以外の要素がある"
  end
  if elements != 5
    ng << "SettingsGroup.all の SettingsGroup(...) が #{elements} 個（期待 5）"
  end
  ng
end

def check_settings_group(src)
  ng = []
  if src.nil?
    ng << "SettingsGroup.swift が存在しない"
    return ng
  end
  stripped = strip_comments(src)
  ng << "SettingsGroup.swift が SwiftUI を import している" if stripped =~ /^\s*import\s+SwiftUI\b/
  ng << "SettingsGroup.swift が AppKit を import している" if stripped =~ /^\s*import\s+AppKit\b/
  ng << "SettingsGroup.swift が Foundation を import している" if stripped =~ /^\s*import\s+Foundation\b/
  %w[UserDefaults FileManager Process URLSession NotificationCenter Binding View Color].each do |tok|
    ng << "SettingsGroup.swift に #{tok} がある" if stripped =~ /\b#{tok}\b/
  end
  ng << "SettingsGroup.swift に Date( がある" if stripped.include?("Date(")
  ng << "SettingsGroup.swift に struct SettingsGroup が無い" unless stripped =~ /\bstruct\s+SettingsGroup\b/
  ng << "SettingsGroup.swift に static let all が無い" unless stripped =~ /\bstatic\s+let\s+all\b/
  GROUP_ORDER.each do |gid|
    ng << "SettingsGroup.swift に id \"#{gid}\" が無い" unless stripped.include?(%("#{gid}"))
  end
  GROUP_TITLES.each do |title|
    ng << "SettingsGroup.swift に title \"#{title}\" が無い" unless stripped.include?(%("#{title}"))
  end
  unless literals_in_order?(stripped, GROUP_ORDER.map { |id| %("#{id}") })
    ng << "SettingsGroup.all の id 順序が契約と違う"
  end
  ng.concat(check_all_is_literal_inits(stripped))
  ng
end

def check_tab_and_sections(src)
  ng = []
  if src.nil?
    ng << "SettingsView.swift が存在しない"
    return ng
  end
  stripped = strip_comments(src)
  body = extract_var_body(stripped, "body")
  ng << "SettingsView の body を括弧対応で切り出せない" if body.nil?
  body ||= ""
  reachable = reachable_from_body(stripped)

  unless body =~ /\bTabView\b/ || reachable =~ /\bTabView\b/
    ng << "SettingsView の body に TabView が無い"
  end
  tab = extract_tabview_body(reachable)
  tab ||= extract_tabview_body(body)
  if tab.nil?
    ng << "body から到達する TabView を切り出せない" unless ng.any? { |m| m.include?("TabView") }
  else
    ng.concat(foreach_all_errors(tab))
    foreach_body = extract_foreach_all_closure(tab)
    if foreach_body.nil?
      ng << "ForEach(SettingsGroup.all) のクロージャを切り出せない" unless ng.any? { |m| m.include?("直列挙") }
    else
      tabitems = extract_modifier_closures(foreach_body, "tabItem")
      tabitem_src = tabitems.join("\n")
      unless tabitem_src.include?("group.title")
        ng << "タブタイトルが group.title から描かれていない"
      end
      unless tabitem_src.include?("group.systemImage")
        ng << "タブシンボルが group.systemImage から描かれていない"
      end
      unless accessibility_identifier_on_group_id?(foreach_body)
        ng << '.accessibilityIdentifier("settings-group-\\(group.id)") がタブ側に無い'
      end
    end
    unless tab.include?("SettingsGroup.all")
      ng << "TabView が SettingsGroup.all からタブを供給していない"
    end
  end
  unless stripped.include?("SettingsGroup.all")
    ng << "SettingsView が SettingsGroup.all を使っていない（モデル未使用）"
  end

  c = compact(stripped)
  unless c =~ /@State[^=]*="general"/ || (c.include?('="general"') && c.include?("@State"))
    ng << 'タブ選択の @State 初期値が "general" ではない'
  end
  ng << "タブ選択が @AppStorage に保存されている" if stripped =~ /@AppStorage[^\n]*selected|@AppStorage[^\n]*group/i
  ng << "タブ選択が @SceneStorage に保存されている" if stripped =~ /@SceneStorage\b/

  dups = section_title_duplicates(reachable)
  dups.each { |title| ng << "同名 Section「#{title}」が重複している" }

  titles = section_titles_in_order(reachable)
  ALL_SECTION_TITLES.each do |title|
    ng << "見出し「#{title}」の Section が無い" unless titles.include?(title)
  end
  extra = titles.uniq - ALL_SECTION_TITLES
  extra.each { |title| ng << "契約外の Section 見出し「#{title}」がある" }

  sections = extract_all_sections(strip_comments(reachable))
  by_title = {}
  sections.each do |sec|
    next if sec[:title].nil?
    by_title[sec[:title]] = sec unless by_title.key?(sec[:title])
  end

  SECTION_CONTROLS.each do |title, needles|
    sec = by_title[title]
    if sec.nil?
      ng << "Section「#{title}」を括弧対応で切り出せない"
      next
    end
    unless literals_in_order?(sec[:content], needles)
      ng << "Section「#{title}」のコントロールまたは選択肢が欠落・順序違い"
    end
  end

  SECTION_FOOTERS.each do |title, text|
    sec = by_title[title]
    next if sec.nil?
    if sec[:footer].nil? || !sec[:footer].include?(%("#{text}"))
      ng << "Section「#{title}」の footer が契約と一致しない"
    end
  end
  NO_FOOTER_TITLES.each do |title|
    sec = by_title[title]
    next if sec.nil?
    ng << "Section「#{title}」に footer が新設されている" unless sec[:footer].nil?
  end

  mobile_calls = count_calls(reachable, "MobileTokenSection")
  unless mobile_calls == 1
    ng << "MobileTokenSection( が #{mobile_calls} 回（期待 1）"
  end
  unless compact(reachable).include?("MobileTokenSection(viewModel:")
    ng << "MobileTokenSection(viewModel:) 呼び出しが無い"
  end
  unless reachable.include?("MobileConnectionGuidePolicy.showsSettingsConnectionSection")
    ng << "モバイル接続の既存表示条件が無い"
  end
  unless reachable.include?("!viewModel.devices.isEmpty") || compact(reachable).include?("!viewModel.devices.isEmpty")
    ng << "接続済み端末の既存表示条件が無い"
  end

  cases, case_dups = parse_switch_cases(reachable)
  case_dups.each { |id| ng << "グループ #{id} の描画分岐が重複している" }

  GROUP_SECTION_TITLES.each do |gid, expected_titles|
    blob = group_drawing_src(stripped, gid)
    if gid == "connection"
      unless blob.include?("MobileTokenSection")
        ng << "接続グループの描画分岐で MobileTokenSection を呼んでいない"
      end
      next
    end
    got = section_titles_in_order(blob)
    if got.empty? && blob.strip.empty?
      ng << "グループ #{gid} の描画分岐を切り出せない"
      next
    end
    unless got == expected_titles
      ng << "グループ #{gid} の Section 見出し順が #{got.inspect}（期待 #{expected_titles.inspect}）"
    end
  end

  unless compact(body).include?(".frame(width:520,height:640)") || compact(stripped).include?(".frame(width:520,height:640)")
    ng << ".frame(width: 520, height: 640) が無い"
  end
  %w[.formStyle(.grouped) .scrollContentBackground(.hidden) .tint(DSColor.accent) .toggleStyle(AccentSwitchToggleStyle())].each do |mod|
    ng << "#{mod} が無い" unless compact(stripped).include?(compact(mod))
  end
  unless compact(stripped).include?(".preferredColorScheme(ThemeStore.active.preferredColorScheme)")
    ng << "ThemeStore.active.preferredColorScheme への追随が無い"
  end
  unless stripped.include?('Text("設定")')
    ng << '共通ヘッダーの Text("設定") が無い'
  end

  ng
end

def check_invariants(current, baseline)
  ng = []
  return ng if current.nil? || baseline.nil?
  cur = strip_comments(current)
  prev = strip_comments(baseline)

  cur_units = extract_app_storage_units(cur)
  prev_units = extract_app_storage_units(prev)
  cur_by_name = cur_units.map { |u| [u[:name], u] }.to_h
  prev_by_name = prev_units.map { |u| [u[:name], u] }.to_h
  APP_STORAGE.each do |key, var, default|
    unit = cur_by_name[var]
    if unit.nil?
      ng << "@AppStorage #{var} の宣言が無い"
      next
    end
    unless unit[:key] == compact(key)
      ng << "@AppStorage #{var} のキーが #{key} ではない"
    end
    unless unit[:default] == compact(default)
      ng << "@AppStorage #{var} の既定値が #{default} ではない"
    end
    prev_unit = prev_by_name[var]
    if prev_unit.nil?
      ng << "@AppStorage #{var} が baseline に無い"
    elsif unit[:text] != prev_unit[:text]
      ng << "@AppStorage #{var} の宣言が TASK38_BASELINE から変化している"
    end
  end
  if cur_units.map { |u| u[:text] }.sort != prev_units.map { |u| u[:text] }.sort
    ng << "@AppStorage 宣言単位の集合が TASK38_BASELINE と一致しない"
  end

  SHA_VARS.each do |name|
    a = extract_var_body(prev, name)
    b = extract_var_body(cur, name)
    if a.nil? || b.nil?
      ng << "#{name} の本文を baseline または HEAD から切り出せない"
    elsif normalize_code(a) != normalize_code(b)
      ng << "#{name} が TASK38_BASELINE から変化している"
    end
  end

  SHA_STRUCTS.each do |name|
    a = extract_struct_body(prev, name)
    b = extract_struct_body(cur, name)
    if a.nil? || b.nil?
      ng << "#{name} の struct 本文を baseline または HEAD から切り出せない"
    elsif normalize_code(a) != normalize_code(b)
      ng << "#{name} 内部が TASK38_BASELINE から変化している"
    end
  end

  dups = section_title_duplicates(current)
  dups.each { |title| ng << "同名 Section「#{title}」が重複している" }
  prev_dups = section_title_duplicates(baseline)
  prev_dups.each { |title| ng << "baseline の同名 Section「#{title}」が重複している" }

  unless dups.empty? && prev_dups.empty?
    # 後勝ち比較をしない
  else
    cur_map = section_map(current)
    prev_map = section_map(baseline)
    if prev_map.empty?
      ng << "baseline の Section を見出しリテラルで切り出せない"
    elsif cur_map.empty?
      ng << "HEAD の Section を見出しリテラルで切り出せない"
    else
      prev_map.each do |title, body|
        if !cur_map.key?(title)
          ng << "Section「#{title}」が TASK38_BASELINE から欠落している"
        elsif cur_map[title] != body
          ng << "Section「#{title}」の内容が TASK38_BASELINE から改変されている"
        end
      end
    end
  end

  ng.concat(non_section_decl_messages(current, baseline, skip: DECL_SKIP))

  if storage_write_sites(current) != storage_write_sites(baseline)
    ng << "保存対象への代入・呼び出し箇所の集合が TASK38_BASELINE から変化している"
  end

  %w[themeID=theme.id NSApp.applicationIconImage SessionCompletionNotifier.notifyCompleted openWindow(id:AgentConsoleCommands.windowID) appUpdater.checkForUpdates() .disabled(!appUpdater.canCheckForUpdates) .buttonStyle(RichButtonStyle()) .focusEffectDisabled()].each do |needle|
    unless compact(cur).include?(compact(needle))
      ng << "#{needle} が無い"
    end
  end

  ng
end

def check_write_on_display(settings_src, group_src)
  ng = []
  ng.concat(check_settings_group(group_src))
  return ng if settings_src.nil?
  stripped = strip_comments(settings_src)
  body = extract_var_body(stripped, "body") || ""
  if body =~ /UserDefaults/ || body =~ /\.set\s*\(/
    ng << "body から UserDefaults / set への書き込みがある"
  end
  init_m = stripped.match(/\binit\s*\(/)
  if init_m
    paren = stripped.index("(", init_m.begin(0))
    params = extract_balanced(stripped, paren, "(", ")")
    after = paren + 1 + (params ? params.length : 0) + 1
    brace = stripped.index("{", after)
    if brace
      init_body = extract_balanced(stripped, brace, "{", "}")
      if init_body && (init_body =~ /UserDefaults/ || init_body =~ /@AppStorage/)
        ng << "SettingsView init から設定書き込みがある"
      end
    end
  end
  if stripped =~ /\.onChange\s*\([^)]*(selected|group|tab)/i
    ng << "タブ変更の onChange がある"
  end
  ng
end

def selftest_assert(cond, msg)
  unless cond
    puts "task38-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def mini_section(title, inner, footer: nil)
  s = %(Section { #{inner} } header: { Text("#{title}") })
  s += %( footer: { Text("#{footer}") }) if footer
  s
end

def good_group_src
  <<~SWIFT
    public struct SettingsGroup: Identifiable, Equatable, Sendable {
      public let id: String
      public let title: String
      public let systemImage: String
      public let sectionIDs: [String]
      public static let all: [SettingsGroup] = [
        SettingsGroup(id: "general", title: "一般", systemImage: "gearshape", sectionIDs: ["language", "sessions", "notifications", "updates"]),
        SettingsGroup(id: "appearance", title: "外観", systemImage: "paintpalette", sectionIDs: ["theme", "app-icon"]),
        SettingsGroup(id: "agents", title: "エージェント", systemImage: "wrench.and.screwdriver", sectionIDs: ["permissions", "agent-management"]),
        SettingsGroup(id: "connection", title: "接続", systemImage: "network", sectionIDs: ["mobile-connection", "paired-devices"]),
        SettingsGroup(id: "advanced", title: "詳細", systemImage: "slider.horizontal.3", sectionIDs: ["discussion", "usage", "privacy", "about"]),
      ]
    }
  SWIFT
end

def good_settings_src
  <<~SWIFT
    struct SettingsView: View {
      @AppStorage(NotificationSettings.bannerKey) private var bannerNotificationEnabled = true
      @AppStorage(NotificationSettings.soundKey) private var completionSoundEnabled = true
      @AppStorage(UsageSettings.autoRefreshKey) private var usageAutoRefresh = true
      @AppStorage(UsageSettings.claudeScrapeKey) private var claudeScrape = true
      @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailableUsage = false
      @AppStorage(UsageSettings.showInHeaderKey) private var showUsageInHeader = true
      @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
      @AppStorage(AppIconStore.iconKey) private var appIconID = AppIconStore.defaultOption.id
      @AppStorage(LanguageSettings.languageKey) private var appLanguageRaw = AppLanguage.system.rawValue
      @AppStorage(DefaultSessionBackendPreference.storageKey) private var defaultSessionBackendRaw = DefaultSessionBackendPreference.chat.rawValue
      @AppStorage(AgoraDiscussionSettings.maxUtterancesKey) private var agoraMaxUtterances = 30
      @AppStorage(AgoraDiscussionSettings.maxAgentsKey) private var agoraMaxAgents = 5
      @AppStorage(AgoraDiscussionSettings.turnTimeoutSecondsKey) private var agoraTurnTimeoutSeconds = 180
      @AppStorage(AgoraDiscussionSettings.schedulerKey) private var agoraSchedulerRaw = AgoraSchedulerKind.freeSpeech.rawValue
      @State private var selectedGroupID = "general"
      private var appLanguageBinding: Binding<AppLanguage> { Binding(get: { AppLanguage(rawValue: appLanguageRaw) ?? .system }, set: { appLanguageRaw = $0.rawValue }) }
      private var defaultSessionBackendBinding: Binding<DefaultSessionBackendPreference> { Binding(get: { DefaultSessionBackendPreference(rawValue: defaultSessionBackendRaw) ?? .chat }, set: { defaultSessionBackendRaw = $0.rawValue }) }
      private var agoraSchedulerBinding: Binding<AgoraSchedulerKind> { Binding(get: { AgoraSchedulerKind(rawValue: agoraSchedulerRaw) ?? .freeSpeech }, set: { agoraSchedulerRaw = $0.rawValue }) }
      var body: some View {
        VStack {
          header
          TabView(selection: $selectedGroupID) {
            ForEach(SettingsGroup.all) { group in
              groupForm(group)
                .tabItem { Label(group.title, systemImage: group.systemImage) }
                .tag(group.id)
                .accessibilityIdentifier("settings-group-\\(group.id)")
            }
          }
        }
        .frame(width: 520, height: 640)
        .background(DSColor.background)
        .preferredColorScheme(ThemeStore.active.preferredColorScheme)
      }
      private var header: some View {
        HStack { Text(AppFlavor.current.displayName); Text("設定") }
      }
      @ViewBuilder
      private func groupForm(_ group: SettingsGroup) -> some View {
        Form {
          switch group.id {
          case "general": generalForm
          case "appearance": appearanceForm
          case "agents": agentsForm
          case "connection":
            if let mobileToken, MobileConnectionGuidePolicy.showsSettingsConnectionSection {
              MobileTokenSection(viewModel: mobileToken)
            }
          case "advanced": advancedForm
          default: EmptyView()
          }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tint(DSColor.accent)
        .toggleStyle(AccentSwitchToggleStyle())
      }
      @ViewBuilder private var generalForm: some View {
        #{mini_section("言語", 'Picker(selection: appLanguageBinding) { Text("システム").tag(AppLanguage.system); Text("日本語").tag(AppLanguage.ja); Text("English").tag(AppLanguage.en) } label: { Label("表示言語", systemImage: "globe") }')}
        #{mini_section("セッション", 'Picker(selection: defaultSessionBackendBinding) { Text("チャット").tag(DefaultSessionBackendPreference.chat); Text("ターミナル").tag(DefaultSessionBackendPreference.terminal) } label: { Label("デフォルトの開き方", systemImage: "rectangle.on.rectangle") }', footer: "新規セッションをチャット画面かターミナルで開くかの既定です。チャット非対応のエージェントはターミナルで開きます。")}
        #{mini_section("通知", 'Toggle(isOn: $bannerNotificationEnabled) { Label("セッション完了をバナーで通知", systemImage: "bell") }; Toggle(isOn: $completionSoundEnabled) { Label("完了サウンド（Glass）を鳴らす", systemImage: "speaker.wave.2") }; Button("通知テスト") { SessionCompletionNotifier.notifyCompleted(sessionName: String(localized: "テスト")) }.buttonStyle(RichButtonStyle()).focusEffectDisabled()')}
        #{mini_section("アップデート", 'Toggle(isOn: Binding(get: { appUpdater.automaticallyChecksForUpdates }, set: { appUpdater.automaticallyChecksForUpdates = $0 })) { Label("起動時に自動でアップデートを確認", systemImage: "clock.arrow.circlepath") }; Button("今すぐ確認") { appUpdater.checkForUpdates() }.buttonStyle(RichButtonStyle()).disabled(!appUpdater.canCheckForUpdates).focusEffectDisabled()')}
      }
      @ViewBuilder private var appearanceForm: some View {
        #{mini_section("外観", "ForEach(ThemeStore.all) { theme in ThemeRowView(theme: theme, isSelected: theme.id == themeID) { themeID = theme.id } }", footer: "テーマ（ターミナルの配色とアプリ全体）を切り替えます。変更は即座に反映されます。")}
        #{mini_section("アプリアイコン", "ForEach(AppIconStore.all) { option in AppIconRowView(option: option, isSelected: option.id == appIconID) { appIconID = option.id; if let image = NSImage(named: option.assetName) { NSApp.applicationIconImage = image } } }", footer: "Dock とアプリのアイコンを切り替えます。変更は即座に反映されます。")}
      }
      @ViewBuilder private var agentsForm: some View {
        #{mini_section("権限", 'ForEach(agentCatalog.allDescriptors, id: \.ref) { descriptor in BypassToggleRow(descriptor: descriptor) }', footer: "変更は次回セッション開始から反映されます。OFF は通常の安全モード（Claude Auto／Codex Auto／Cursor Auto-review）、ON は承認なしのフルアクセスです。信頼できるプロジェクトでのみ有効にしてください。")}
        #{mini_section("エージェント", 'Button { openWindow(id: AgentConsoleCommands.windowID) } label: { Label("エージェント管理を開く", systemImage: "wrench.and.screwdriver") }.buttonStyle(RichButtonStyle()).focusEffectDisabled()', footer: "Claude Code・Codex・Cursor の設定をここから操作できます。対話 TUI のスラッシュコマンド（/plugin・/permissions 等）や、設定ファイルの手編集でしか触れない項目が対象です。")}
      }
      @ViewBuilder private var advancedForm: some View {
        #{mini_section("チームビュー討論", 'TextField("最大発言数", value: $agoraMaxUtterances, format: .number); TextField("最大エージェント数", value: $agoraMaxAgents, format: .number); TextField("ターンタイムアウト（秒）", value: $agoraTurnTimeoutSeconds, format: .number); Picker(selection: agoraSchedulerBinding) { Text("自由発言").tag(AgoraSchedulerKind.freeSpeech); Text("ラウンドロビン").tag(AgoraSchedulerKind.roundRobin) } label: { Label("スケジューラ", systemImage: "arrow.triangle.2.circlepath") }', footer: "チームビュー討論の上限・タイムアウト・発言順の既定です。変更は次回の討論開始から反映されます。")}
        #{mini_section("使用量", 'Toggle(isOn: $usageAutoRefresh) { Label("使用量サイドバーを自動更新", systemImage: "arrow.clockwise") }; Toggle(isOn: $claudeScrape) { Label("Claudeの使用量を取得", systemImage: "sparkles") }; Toggle(isOn: $showUnavailableUsage) { Label("未取得のCLIも表示", systemImage: "eye.slash") }; Toggle(isOn: $showUsageInHeader) { Label("ヘッダーに使用量を表示", systemImage: "menubar.rectangle") }', footer: "Codex・Cursor の使用量は自動で表示されます。Claude は Phlox 内で起動したセッションの使用量を表示します（直近に Phlox 内で Claude を起動していないと最新の値にならない場合があります）。")}
        #{mini_section("プライバシー", 'Link(destination: URL(string: "https://phlox.cc/privacy")!) { Label("プライバシーポリシー", systemImage: "hand.raised") }')}
        #{mini_section("このアプリについて", 'LabeledContent("アプリ", value: AppFlavor.current.displayName); LabeledContent("バージョン", value: appVersion); LabeledContent("ビルド", value: buildNumber)')}
      }
      private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
      private var buildNumber: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }
      private struct BypassToggleRow: View {
        var body: some View { Toggle(isOn: $isEnabled) { Label("\\(descriptor.displayName): フルアクセス（bypass）", systemImage: descriptor.symbolName) } }
      }
      private struct MobileTokenSection: View {
        var body: some View {
          #{mini_section("モバイル接続", 'TextField("端末名", text: $newDeviceName); Button { } label: { Label("QR コードを表示", systemImage: "qrcode") }', footer: "iPhone アプリで QR コードを読み取ると、同一 Tailscale ネットワーク経由で接続できます。「QR コードを表示」を押すたびに新しい端末として発行されます。既存の端末は影響を受けません。")}
          if !viewModel.devices.isEmpty {
            #{mini_section("接続済みの端末", 'ForEach(viewModel.devices) { device in MobileDeviceRow(device: device) { } }')}
          }
        }
      }
      private struct MobileDeviceRow: View {
        var body: some View { Text(device.name); Button("失効", role: .destructive, action: onRevoke); Text(pairedAtText) }
      }
      private struct ThemeRowView: View { var body: some View { Button(action: onSelect) { Text(theme.name) } } }
      private struct ThemeAppPreview: View { var body: some View { Text(model.bodyText) } }
      private struct ThemeSwatchStrip: View { var body: some View { Text("swatch") } }
      private struct AppIconRowView: View { var body: some View { Text(option.name) } }
      private struct RichButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label } }
    }
  SWIFT
end

def lang_section
  mini_section("言語", 'Picker(selection: appLanguageBinding) { Text("システム").tag(AppLanguage.system); Text("日本語").tag(AppLanguage.ja); Text("English").tag(AppLanguage.en) } label: { Label("表示言語", systemImage: "globe") }')
end

def sess_section
  mini_section("セッション", 'Picker(selection: defaultSessionBackendBinding) { Text("チャット").tag(DefaultSessionBackendPreference.chat); Text("ターミナル").tag(DefaultSessionBackendPreference.terminal) } label: { Label("デフォルトの開き方", systemImage: "rectangle.on.rectangle") }', footer: "新規セッションをチャット画面かターミナルで開くかの既定です。チャット非対応のエージェントはターミナルで開きます。")
end

def run_selftest
  url = %(let url = "https://phlox.cc/privacy" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://phlox.cc/privacy"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert !strip_comments("let a = 1 /* x */ let b = 2").include?("x"), "正例: /* */ を除去する"

  interp = %(let id = "settings-group-\\(group.id)")
  selftest_assert strip_comments(interp).include?("settings-group-"), "正例: 補間文字列を保持する"

  parens = %(let s = "foo(bar)"; Section { Text(s) } header: { Text("言語") })
  secs = extract_all_sections(parens)
  selftest_assert secs.size == 1 && secs[0][:title] == "言語", "正例: 文字列中の括弧を壊さず Section を切り出す"

  spaced = %(Section { Text("hello world") } header: { Text("言語") })
  selftest_assert section_map(spaced)["言語"].include?("hello world"), "正例: 文字列内空白を正規化で消さない"
  changed_space = %(Section { Text("helloworld") } header: { Text("言語") })
  selftest_assert section_map(spaced)["言語"] != section_map(changed_space)["言語"], "負例: 文字列内空白の改変を検出する"

  selftest_assert extract_balanced(" { a ", 0, "{", "}").nil?, "負例: 構文切り出し失敗は nil"

  moved = <<~SWIFT
    Form {
      #{mini_section("通知", 'Toggle("x")')}
    }
    Form {
      #{mini_section("言語", 'Picker { Text("システム") }')}
    }
  SWIFT
  original = <<~SWIFT
    Form {
      #{mini_section("言語", 'Picker { Text("システム") }')}
      #{mini_section("通知", 'Toggle("x")')}
    }
  SWIFT
  selftest_assert section_contents_match?(original, moved), "正例: 契約どおりの Section 移動"

  helper = <<~SWIFT
    var body: some View {
      switch group.id {
      case "general": generalForm
      default: EmptyView()
      }
    }
    private var generalForm: some View {
      #{mini_section("言語", 'Text("システム")')}
    }
  SWIFT
  blob = group_drawing_src(helper, "general")
  selftest_assert section_titles_in_order(blob) == ["言語"], "正例: 描画ヘルパー抽出"

  state = %(@State private var selectedGroupID = "general")
  selftest_assert compact(state).include?('="general"') && compact(state).include?("@State"), "正例: 非永続タブ選択"

  mobile = <<~SWIFT
    if let mobileToken, MobileConnectionGuidePolicy.showsSettingsConnectionSection {
      MobileTokenSection(viewModel: mobileToken)
    }
    private struct MobileTokenSection: View {
      var body: some View {
        #{mini_section("モバイル接続", 'TextField("端末名", text: $newDeviceName)')}
        if !viewModel.devices.isEmpty {
          #{mini_section("接続済みの端末", "ForEach(viewModel.devices) { }")}
        }
      }
    }
  SWIFT
  titles = section_titles_in_order(mobile)
  selftest_assert titles == ["モバイル接続", "接続済みの端末"], "正例: 既存の条件付きモバイル2 Section"
  selftest_assert count_calls(mobile, "MobileTokenSection") == 1, "正例: MobileTokenSection は一度だけ"

  good = good_settings_src
  group = good_group_src
  tab_ng = check_tab_and_sections(good)
  selftest_assert tab_ng.empty?, "正例: 契約どおりの配線は空 NG (#{tab_ng.inspect})"
  selftest_assert check_settings_group(group).empty?, "正例: 純粋モデルは空 NG (#{check_settings_group(group).inspect})"
  selftest_assert check_invariants(good, good).empty?, "正例: 同一 fixture の不変条件は空 NG (#{check_invariants(good, good).inspect})"

  missing_group = good.sub('case "advanced": advancedForm', "")
  selftest_assert check_tab_and_sections(missing_group).any? { |m| m.include?("advanced") }, "負例: グループ欠落"

  dup = good.sub('case "general": generalForm', 'case "general": generalForm\n          case "general": generalForm')
  selftest_assert check_tab_and_sections(dup).any? { |m| m.include?("重複") }, "負例: 重複分岐"

  drop_lang = good.sub(lang_section, "")
  selftest_assert check_tab_and_sections(drop_lang).any? { |m| m.include?("言語") }, "負例: Section 欠落"

  reordered = good.sub(lang_section, "__LANG_SEC__")
  reordered = reordered.sub(sess_section, lang_section)
  reordered = reordered.sub("__LANG_SEC__", sess_section)
  selftest_assert reordered != good, "並べ替え fixture が正例と異なること"
  selftest_assert check_tab_and_sections(reordered).any? { |m| m.include?("general") && m.include?("見出し順") }, "負例: 並べ替え (#{check_tab_and_sections(reordered).inspect})"

  unused_helper = good.sub("groupForm(group)", 'Text("空")')
  unused_ng = check_tab_and_sections(unused_helper)
  selftest_assert unused_ng.any? { |m| m.include?("描画分岐") || m.include?("言語") || m.include?("general") }, "負例: 未使用ヘルパーを配線済みとしない (#{unused_ng.inspect})"

  decoy_only = good.sub(lang_section, "") + %(\n    var decoy: some View { Section { Text("x") } header: { Text("言語") } }\n)
  decoy_ng = check_tab_and_sections(decoy_only)
  selftest_assert decoy_ng.any? { |m| m.include?("言語") }, "負例: 同じラベルを未使用コードへ残す偽装 (#{decoy_ng.inspect})"

  iff = good.sub(lang_section, "if false { #{lang_section} }")
  iff_ng = check_tab_and_sections(iff)
  selftest_assert iff_ng.any? { |m| m.include?("言語") }, "負例: if false 包み (#{iff_ng.inspect})"

  reversed = good.sub("ForEach(SettingsGroup.all)", "ForEach(SettingsGroup.all.reversed())")
  selftest_assert check_tab_and_sections(reversed).any? { |m| m.include?("reversed") || m.include?("直列挙") || m.include?("並べ替え") }, "負例: ForEach reversed"

  hardcoded = good.sub("Label(group.title, systemImage: group.systemImage)", 'Label("一般", systemImage: "gearshape")')
  selftest_assert check_tab_and_sections(hardcoded).any? { |m| m.include?("group.title") || m.include?("group.systemImage") }, "負例: タブ属性のハードコード"

  help_ax = good.sub('.accessibilityIdentifier("settings-group-\\(group.id)")', '.help("settings-group-\\(group.id)")')
  selftest_assert check_tab_and_sections(help_ax).any? { |m| m.include?("accessibilityIdentifier") }, "負例: AX を help に置換"

  dup_sec = good.sub(lang_section, "#{lang_section}\n        #{lang_section}")
  selftest_assert check_tab_and_sections(dup_sec).any? { |m| m.include?("重複") }, "負例: 同名 Section 重複"

  bad_order_group = group.sub(
    'id: "general", title: "一般", systemImage: "gearshape"',
    'id: "zzz-first", title: "一般", systemImage: "gearshape"'
  )
  selftest_assert check_settings_group(bad_order_group).any? { |m| m.include?("順序") }, "負例: グループ順序違い"

  dup_group = group.sub('id: "appearance"', 'id: "general"')
  selftest_assert check_settings_group(dup_group).any? { |m| m.include?("順序") || m.include?("重複") || m.include?("appearance") }, "負例: グループ欠落・重複"

  bad_title = group.sub("一般", "基本")
  selftest_assert check_settings_group(bad_title).any? { |m| m.include?("一般") }, "負例: タイトル違い"

  wrong_home = good.sub("case \"general\": generalForm", "case \"general\": appearanceForm")
  selftest_assert check_tab_and_sections(wrong_home).any? { |m| m.include?("general") }, "負例: 所属違い"

  unused = good.gsub("SettingsGroup.all", "[]")
  selftest_assert check_tab_and_sections(unused).any? { |m| m.include?("モデル未使用") || m.include?("直列挙") }, "負例: モデル未使用"

  no_ax = good.gsub('accessibilityIdentifier("settings-group-\\(group.id)")', "")
  selftest_assert check_tab_and_sections(no_ax).any? { |m| m.include?("accessibilityIdentifier") || m.include?("identifier") }, "負例: AX identifier 欠落"

  no_tab = good.gsub("TabView", "VStack")
  selftest_assert check_tab_and_sections(no_tab).any? { |m| m.include?("TabView") }, "負例: TabView 欠落"

  picker_drop = good.sub('Text("English")', 'Text("Deutsch")')
  selftest_assert check_tab_and_sections(picker_drop).any? { |m| m.include?("言語") }, "負例: Picker 選択肢の欠落"

  footer_bad = good.sub("変更は即座に反映されます。", "すぐに反映されます。")
  selftest_assert check_tab_and_sections(footer_bad).any? { |m| m.include?("footer") }, "負例: footer の変更"

  storage_bad = good.sub("bannerNotificationEnabled = true", "bannerNotificationEnabled = false")
  selftest_assert check_invariants(storage_bad, good).any? { |m| m.include?("bannerNotificationEnabled") }, "負例: 既定値の変更"

  swapped = good.sub(
    "@AppStorage(NotificationSettings.bannerKey) private var bannerNotificationEnabled = true",
    "@AppStorage(NotificationSettings.soundKey) private var bannerNotificationEnabled = true"
  ).sub(
    "@AppStorage(NotificationSettings.soundKey) private var completionSoundEnabled = true",
    "@AppStorage(NotificationSettings.bannerKey) private var completionSoundEnabled = true"
  )
  swap_ng = check_invariants(swapped, good)
  selftest_assert swap_ng.any? { |m| m.include?("AppStorage") || m.include?("banner") || m.include?("宣言") }, "負例: @AppStorage キー交換 (#{swap_ng.inspect})"

  bind_bad = good.sub("appLanguageRaw = $0.rawValue", "appLanguageRaw = AppLanguage.ja.rawValue")
  selftest_assert check_invariants(bind_bad, good).any? { |m| m.include?("appLanguageBinding") }, "負例: Binding 先の変更"

  key_bad = good.sub("NotificationSettings.bannerKey", '"phlox.notify.banner"')
  selftest_assert check_invariants(key_bad, good).any? { |m| m.include?("bannerKey") || m.include?("AppStorage") }, "負例: 保存キーの変更"

  action_bad = good.sub("appUpdater.checkForUpdates()", "appUpdater.checkForUpdates(force: true)")
  selftest_assert check_invariants(action_bad, good).any? { |m| m.include?("checkForUpdates") || m.include?("代入") || m.include?("内容") }, "負例: action の変更"

  disabled_bad = good.sub(".disabled(!appUpdater.canCheckForUpdates)", ".disabled(false)")
  selftest_assert check_invariants(disabled_bad, good).any? { |m| m.include?("disabled") || m.include?("内容") }, "負例: disabled の変更"

  style_bad = good.sub(".buttonStyle(RichButtonStyle())", ".buttonStyle(.bordered)")
  selftest_assert check_invariants(style_bad, good).any? { |m| m.include?("RichButtonStyle") || m.include?("内容") }, "負例: ボタン様式の変更"

  inner_bad = good.sub("Text(model.bodyText)", "Text(\"seeed\")")
  selftest_assert check_invariants(inner_bad, good).any? { |m| m.include?("ThemeAppPreview") }, "負例: 独自 View 内部の変更"

  icon_bad = good.sub("Text(option.name)", "Text(\"gone\")")
  selftest_assert check_invariants(icon_bad, good).any? { |m| m.include?("AppIconRowView") }, "負例: AppIconRowView 内部の変更"

  appear = good.sub(".frame(width: 520, height: 640)", ".onAppear { bannerNotificationEnabled = false }\n        .frame(width: 520, height: 640)")
  appear_ng = check_invariants(appear, good)
  selftest_assert appear_ng.any? { |m| m.include?("代入") || m.include?("書き込み") || m.include?("bannerNotificationEnabled") }, "負例: onAppear からの書き込み (#{appear_ng.inspect})"

  write_body = good.sub("header", "header; let _ = UserDefaults.standard.set(true, forKey: \"x\")")
  selftest_assert check_write_on_display(write_body, group).any? { |m| m.include?("UserDefaults") || m.include?("書き込み") }, "負例: 設定画面の構築からの書き込み"

  io_model = group.sub("Sendable {", "Sendable {\n  init() { _ = FileManager.default }")
  selftest_assert check_settings_group(io_model).any? { |m| m.include?("FileManager") }, "負例: モデル初期化の I/O"

  closed_all = group.sub(
    "public static let all: [SettingsGroup] = [",
    "public static let all: [SettingsGroup] = { print(\"生成\"); return ["
  ).sub(
    "      ]\n    }",
    "      ] }()\n    }"
  )
  closed_ng = check_settings_group(closed_all)
  selftest_assert closed_ng.any? { |m| m.include?("クロージャ") || m.include?("print") || m.include?("リテラル") }, "負例: SettingsGroup.all のクロージャ初期化 (#{closed_ng.inspect})"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_assert unset.nil? && unset_errs.any? { |m| m.include?("未設定") }, "負例: 固定 SHA の欠落"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_assert head_errs.any? { |m| m.include?("HEAD") }, "負例: リテラル HEAD"
  _, branch_errs = baseline_env_errors("main")
  selftest_assert branch_errs.any? { |m| m.include?("ブランチ") || m.include?("SHA") }, "負例: ブランチ名は不正"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"
  selftest_assert !workdir_matches_git_blob?("a", "b"), "負例: git show 内容の不一致"

  scene = good.sub('@State private var selectedGroupID = "general"', '@SceneStorage("tab") private var selectedGroupID = "general"')
  selftest_assert check_tab_and_sections(scene).any? { |m| m.include?("SceneStorage") }, "負例: タブ変更からの永続化"

  header_bad = good.sub('Text("設定")', 'Text("Settings")')
  header_ng = check_invariants(header_bad, good)
  selftest_assert header_ng.any? { |m| m.include?("header") }, "負例: Section 外の宣言改変 (#{header_ng.inspect})"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task38-wiring --selftest: OK"
  exit 0
end

ng = []
raw = ENV["TASK38_BASELINE"]
baseline, env_errs = baseline_env_errors(raw)
ng.concat(env_errs)

if baseline
  ng.concat(check_frozen_baseline(baseline))
end

group_src = File.exist?(GROUP_PATH) ? File.read(GROUP_PATH) : nil
settings_src = File.exist?(SETTINGS_PATH) ? File.read(SETTINGS_PATH) : nil
ng << "#{GROUP_PATH} が存在しない" if group_src.nil?
ng << "#{SETTINGS_PATH} が存在しない" if settings_src.nil?

ng.concat(check_write_on_display(settings_src, group_src))
ng.concat(check_tab_and_sections(settings_src))

if baseline
  previous = git_show(baseline, SETTINGS_PATH)
  if previous.nil?
    ng << "git show #{baseline}:#{SETTINGS_PATH} に失敗"
  elsif settings_src
    ng.concat(check_invariants(settings_src, previous))
  end
end

ng = ng.uniq
if ng.empty?
  puts "task38-wiring: OK"
else
  ng.each { |m| puts "task38-wiring: NG #{m}" }
  exit 1
end
