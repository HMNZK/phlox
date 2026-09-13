#!/usr/bin/env ruby
# task-17 配線検査: 設定の補助 3 Button を標準 .bordered にし、
# RichButtonStyle 定義・使用と対象 3 箇所の focusEffectDisabled を除去したこと。
# 比較対象は必ず git show <TASK17_BASELINE>:macos/App/SettingsView.swift の blob。

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

def blank_strings(src)
  out = +""
  i = 0
  while i < src.length
    if src[i, 3] == '"""' || src[i] == '"'
      j = index_after_string(src, i)
      out << (" " * (j - i))
      i = j
    else
      out << src[i]
      i += 1
    end
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
  m = src.match(/\bfunc\s+#{Regexp.escape(name)}\s*\(/)
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
  m = src.match(/\bvar\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  i = skip_ws(src, m.end(0))
  if i < src.length && src[i] == ":"
    i = skip_type(src, i + 1)
    i = skip_ws(src, i)
  end
  return nil unless i < src.length && src[i] == "{"
  extract_balanced(src, i, "{", "}")
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

def workdir_matches_git_blob?(workdir_text, git_blob)
  return false if git_blob.nil? || workdir_text.nil?
  workdir_text == git_blob
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
        return [:unparseable, []]
      end
      i = skip_ws(src, i + 1 + args.length + 1)
    end
    unless i < src.length && src[i] == "{"
      pos = m.end(0)
      next
    end
    content = extract_balanced(src, i, "{", "}")
    return [:unparseable, []] if content.nil?
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
  [:ok, sections]
end

def section_title_duplicates(src)
  status, sections = extract_all_sections(strip_comments(src))
  return [:unparseable, []] if status == :unparseable
  titles = sections.map { |sec| sec[:title] }.compact
  dups = titles.group_by { |t| t }.select { |_, v| v.size > 1 }.keys
  [:ok, dups]
end

def section_map(src)
  status, sections = extract_all_sections(strip_comments(src))
  return [:unparseable, {}] if status == :unparseable
  map = {}
  sections.each do |sec|
    next if sec[:title].nil?
    next if map.key?(sec[:title])
    map[sec[:title]] = normalize_code(sec[:content].to_s + "\n" + sec[:footer].to_s)
  end
  [:ok, map]
end

def section_titles_in_order(src)
  status, sections = extract_all_sections(strip_comments(src))
  return [:unparseable, []] if status == :unparseable
  [:ok, sections.map { |sec| sec[:title] }.compact]
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
  helper_cache = {}
  queue = [start_blob.to_s]
  while (blob = queue.shift)
    blob.scan(/\b([A-Za-z_][A-Za-z0-9_]*)\b/).flatten.uniq.each do |name|
      next if SWIFTUI_SKIP.include?(name)
      next if seen[name]
      seen[name] = true
      unless helper_cache.key?(name)
        helper_cache[name] = extract_var_body(src, name) || extract_func_body(src, name) || extract_struct_body(src, name)
      end
      helper = helper_cache[name]
      next if helper.nil?
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

def group_drawing_from_parts(stripped, reachable, gid)
  blob = +""
  cases, = parse_switch_cases(reachable)
  blob << cases[gid] if cases[gid]
  blob << extract_if_eq_block(reachable, gid)
  erase_if_false(collect_reachable(stripped, blob))
end

def group_drawing_src(settings_src, gid)
  stripped = strip_comments(settings_src)
  reachable = reachable_from_body(settings_src)
  group_drawing_from_parts(stripped, reachable, gid)
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
    if src[i, 20] =~ /\A(private|public|fileprivate|internal|static|override|final|mutating)\s+/
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

def parse_trailing_closures(src, j)
  loop do
    j = skip_ws(src, j)
    break if j >= src.length
    if src[j] == "{"
      body = extract_balanced(src, j, "{", "}")
      return nil if body.nil?
      j = j + 1 + body.length + 1
      next
    end
    rest = src[j..]
    if rest =~ /\A([A-Za-z_][A-Za-z0-9_]*)[ \t]*:/
      colon = src.index(":", j)
      return j unless colon
      k = skip_ws(src, colon + 1)
      break unless k < src.length && src[k] == "{"
      body = extract_balanced(src, k, "{", "}")
      return nil if body.nil?
      j = k + 1 + body.length + 1
      next
    end
    break
  end
  j
end

def button_keyword?(src, i)
  return false if i + 6 > src.length
  return false unless src[i, 6] == "Button"
  return false if i > 0 && src[i - 1] =~ /[A-Za-z0-9_]/
  return false if i + 6 < src.length && src[i + 6] =~ /[A-Za-z0-9_]/
  true
end

def next_button_keyword(blank, pos)
  i = pos
  while (j = blank.index("Button", i))
    return j if button_keyword?(blank, j)
    i = j + 6
  end
  nil
end

def extract_button_at(src, i)
  return nil unless button_keyword?(src, i)
  j = skip_ws(src, i + 6)
  if j < src.length && src[j] == "("
    args = extract_balanced(src, j, "(", ")")
    return nil if args.nil?
    j = skip_ws(src, j + 1 + args.length + 1)
  end
  j = parse_trailing_closures(src, j)
  return nil if j.nil?
  modifiers = []
  loop do
    j = skip_ws(src, j)
    break if j >= src.length
    break unless src[j] == "."
    k = j + 1
    break unless src[k..] =~ /\A[A-Za-z_][A-Za-z0-9_]*/
    name = Regexp.last_match(0)
    ident_end = k + name.length
    m = skip_ws(src, ident_end)
    args = nil
    if m < src.length && src[m] == "("
      args = extract_balanced(src, m, "(", ")")
      return nil if args.nil?
      m = m + 1 + args.length + 1
    end
    after_closures = parse_trailing_closures(src, m)
    return nil if after_closures.nil?
    modifiers << { name: name, args: args, start: j, finish: after_closures }
    break if after_closures <= j
    j = after_closures
  end
  finish = modifiers.empty? ? j : modifiers.last[:finish]
  {
    start: i,
    finish: finish,
    text: src[i...finish],
    modifiers: modifiers,
  }
end

def extract_all_buttons(src)
  stripped = strip_comments(src)
  blank = blank_strings(stripped)
  buttons = []
  pos = 0
  while (i = next_button_keyword(blank, pos))
    btn = extract_button_at(stripped, i)
    return [:unparseable, []] if btn.nil?
    buttons << btn
    pos = [btn[:finish], i + 6].max
  end
  [:ok, buttons]
end

NOTIFY_LABEL = "通知テスト"
UPDATE_LABEL = "今すぐ確認"
AGENT_LABEL = "エージェント管理を開く"
AGENT_ICON = "wrench.and.screwdriver"
AGENT_LABEL_COMPACT = %(Label("#{AGENT_LABEL}",systemImage:"#{AGENT_ICON}"))

TARGETS = [
  { id: :notify, label: NOTIFY_LABEL, section: "通知", form: "generalForm" },
  { id: :update, label: UPDATE_LABEL, section: "アップデート", form: "generalForm" },
  { id: :agent, label: AGENT_LABEL, section: "エージェント", form: "agentsForm" },
].freeze

GROUP_SECTION_TITLES = {
  "general" => %w[言語 セッション 通知 アップデート],
  "appearance" => %w[外観 アプリアイコン],
  "agents" => %w[権限 エージェント],
  "connection" => %w[モバイル接続 接続済みの端末],
  "advanced" => %w[チームビュー討論 使用量 プライバシー このアプリについて],
}.freeze

def button_paren_first_string(text)
  return nil unless text.start_with?("Button")
  j = skip_ws(text, 6)
  return nil unless j < text.length && text[j] == "("
  args = extract_balanced(text, j, "(", ")")
  return nil unless args
  m = args.match(/\A\s*"((?:\\.|[^"\\])*)"/)
  m && m[1]
end

def classify_button(btn)
  text = btn.is_a?(Hash) ? btn[:text] : btn.to_s
  title = button_paren_first_string(text)
  return :notify if title == NOTIFY_LABEL
  return :update if title == UPDATE_LABEL
  return :agent if compact(text).include?(AGENT_LABEL_COMPACT)
  :other
end

def find_buttons_by_id(buttons, id)
  buttons.select { |b| classify_button(b) == id }
end

def modifier_args_compact(mod)
  compact(mod[:args].to_s)
end

def has_direct_bordered?(btn)
  btn[:modifiers].any? { |mod| mod[:name] == "buttonStyle" && modifier_args_compact(mod) == ".bordered" }
end

def has_direct_rich_style?(btn)
  btn[:modifiers].any? { |mod| mod[:name] == "buttonStyle" && modifier_args_compact(mod) == "RichButtonStyle()" }
end

def has_direct_focus_disabled?(btn)
  btn[:modifiers].any? { |mod| mod[:name] == "focusEffectDisabled" }
end

def count_ident_calls(src, name)
  count_calls(mask_strings_and_comments(src), name)
end

def count_struct_defs(src, name)
  mask_strings_and_comments(src).scan(/\bstruct\s+#{Regexp.escape(name)}\b/).size
end

def count_focus_disabled(src)
  n = 0
  pos = 0
  masked = mask_strings_and_comments(src)
  while (m = masked.match(/\.focusEffectDisabled\b/, pos))
    n += 1
    pos = m.end(0)
  end
  n
end

def allowed_modifier?(mod)
  return true if mod[:name] == "focusEffectDisabled"
  return false unless mod[:name] == "buttonStyle"
  arg = modifier_args_compact(mod)
  arg == "RichButtonStyle()" || arg == ".bordered"
end

def strip_allowed_modifiers(btn)
  head_end = btn[:modifiers].empty? ? btn[:text].length : (btn[:modifiers].first[:start] - btn[:start])
  head = btn[:text][0...head_end]
  kept = btn[:modifiers].reject { |mod| allowed_modifier?(mod) }
  rebuilt = +head
  kept.each do |mod|
    rebuilt << btn[:text][(mod[:start] - btn[:start])...(mod[:finish] - btn[:start])]
  end
  rebuilt
end

def named_struct_range(src, name)
  m = src.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?struct\s+#{Regexp.escape(name)}\b/)
  return :missing unless m
  brace = src.index("{", m.begin(0))
  return :unparseable unless brace
  inner = extract_balanced(src, brace, "{", "}")
  return :unparseable if inner.nil?
  close = brace + 1 + inner.length + 1
  start = m.begin(0)
  start -= 1 while start > 0 && src[start - 1] =~ /[ \t]/
  start -= 1 if start > 0 && src[start - 1] == "\n"
  [start, close]
end

def remove_named_struct(src, name)
  range = named_struct_range(src, name)
  return range if range == :missing || range == :unparseable
  start, close = range
  src[0...start] + src[close..]
end

def strip_allowed_diffs(src)
  stripped = strip_comments(src)
  removed = remove_named_struct(stripped, "RichButtonStyle")
  return :unparseable if removed == :unparseable
  stripped = removed == :missing ? stripped : removed
  status, buttons = extract_all_buttons(stripped)
  return :unparseable if status == :unparseable
  targets = buttons.select { |b| classify_button(b) != :other }
  result = stripped.dup
  targets.sort_by { |b| -b[:start] }.each do |b|
    result[b[:start]...b[:finish]] = strip_allowed_modifiers(b)
  end
  result
end

def section_containing(sections, id)
  hits = []
  sections.each do |sec|
    st, btns = extract_all_buttons(sec[:content].to_s)
    return :unparseable if st == :unparseable
    hits << sec if btns.any? { |b| classify_button(b) == id }
  end
  hits
end

def baseline_settings_is_pre_ui05?(src)
  return false if src.nil?
  stripped = strip_comments(src)
  return false unless stripped =~ /\bTabView\b/
  return false unless stripped.include?("SettingsGroup.all")
  return false if count_struct_defs(stripped, "RichButtonStyle") < 1
  status, buttons = extract_all_buttons(stripped)
  return false if status == :unparseable
  TARGETS.each do |spec|
    found = find_buttons_by_id(buttons, spec[:id])
    return false unless found.size == 1
    return false unless has_direct_rich_style?(found[0])
    return false unless has_direct_focus_disabled?(found[0])
  end
  true
end

def frozen_script_errors(rb_now, rb_blob)
  if rb_blob.nil?
    ["基準時点の rb 自身を git show できない（git show <SHA>:#{WIRING_RB_PATH}）"]
  elsif !workdir_matches_git_blob?(rb_now, rb_blob)
    ["基準時点の rb 自身が現在と同一ではない"]
  else
    []
  end
end

CONTRACT_PATH = "tasks/task-17.md"
SETTINGS_PATH = "macos/App/SettingsView.swift"
WIRING_RB_PATH = ".claude/scripts/task17-wiring.rb"
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
        errs << "TASK17_BASELINE が契約 baseline_commit と一致しない"
      end
    end
    errs
  end
end

def baseline_env_errors(raw)
  errs = []
  if raw.nil? || raw.strip.empty?
    errs << "TASK17_BASELINE が未設定（HEAD にフォールバックしない）"
    return [nil, errs]
  end
  value = raw.strip
  if value == "HEAD" || value == "@" || value == "HEAD~0" || value.start_with?("HEAD~") || value.start_with?("HEAD^")
    errs << "TASK17_BASELINE に HEAD は使えない（短い SHA を渡す）"
    return [nil, errs]
  end
  unless value.match?(/\A[0-9a-fA-F]{7,40}\z/)
    errs << "TASK17_BASELINE がコミット SHA ではない（ブランチ名は使えない）: #{value}"
    return [nil, errs]
  end
  [value, errs]
end

def check_frozen_baseline(baseline)
  ng = []
  full = git_full_sha(baseline)
  if full.nil?
    ng << "TASK17_BASELINE が無効なコミット: #{baseline}"
    return ng
  end
  unless git_is_ancestor?(full, "HEAD")
    ng << "TASK17_BASELINE が HEAD の祖先ではない"
  end
  settings_blob = git_show(full, SETTINGS_PATH)
  if settings_blob.nil?
    ng << "基準時点の SettingsView.swift を git show できない（git show #{full}:#{SETTINGS_PATH}）"
  elsif !baseline_settings_is_pre_ui05?(settings_blob)
    ng << "基準時点の SettingsView.swift が UI-05 実装前（5タブ・RichButtonStyle 定義と対象 3 Button の旧スタイル／焦点抑制）ではない"
  end
  rb_blob = git_show(full, WIRING_RB_PATH)
  rb_now = File.exist?(WIRING_RB_PATH) ? File.read(WIRING_RB_PATH) : nil
  ng.concat(frozen_script_errors(rb_now, rb_blob))
  ng
end

def check_tab_connection(src)
  ng = []
  stripped = strip_comments(src)
  body = extract_var_body(stripped, "body")
  if body.nil?
    ng << "SettingsView の body を括弧対応で切り出せない"
    return ng
  end
  reachable = reachable_from_body(stripped)
  unless body =~ /\bTabView\b/ || reachable =~ /\bTabView\b/
    ng << "SettingsView の body に TabView が無い"
  end
  tab = extract_tabview_body(reachable)
  tab ||= extract_tabview_body(body)
  if tab.nil?
    ng << "body から到達する TabView を切り出せない" unless ng.any? { |m| m.include?("TabView") }
  else
    unless tab.include?("SettingsGroup.all")
      ng << "TabView が SettingsGroup.all からタブを供給していない"
    end
    unless compact(tab).include?("groupForm(group)") || compact(tab).include?("groupForm(group,")
      ng << "TabView が groupForm 経由で Form を描画していない"
    end
  end
  unless stripped.include?("SettingsGroup.all")
    ng << "SettingsView が SettingsGroup.all を使っていない（モデル未使用）"
  end
  ng
end

def check_section_layout(current, baseline)
  ng = []
  cur_reach = reachable_from_body(current)
  prev_reach = reachable_from_body(baseline)
  cur_stripped = strip_comments(current)
  cur_st, cur_titles = section_titles_in_order(cur_reach)
  prev_st, prev_titles = section_titles_in_order(prev_reach)
  if cur_st == :unparseable || prev_st == :unparseable
    ng << "Section を括弧対応で切り出せない"
    return ng
  end
  dup_st, cur_dups = section_title_duplicates(cur_reach)
  prev_dup_st, prev_dups = section_title_duplicates(prev_reach)
  if dup_st == :unparseable || prev_dup_st == :unparseable
    ng << "Section を括弧対応で切り出せない"
    return ng
  end
  cur_dups.each { |title| ng << "同名 Section「#{title}」が重複している" }
  prev_dups.each { |title| ng << "baseline の同名 Section「#{title}」が重複している" }
  prev_titles.each do |title|
    ng << "Section「#{title}」が欠落している" unless cur_titles.include?(title)
  end
  extra = cur_titles.uniq - prev_titles.uniq
  extra.each { |title| ng << "契約外の Section 見出し「#{title}」がある" }
  unless cur_titles == prev_titles
    ng << "到達可能な Section の順序が基準から変化している: #{cur_titles.inspect}"
  end
  GROUP_SECTION_TITLES.each do |gid, expected|
    blob = group_drawing_from_parts(cur_stripped, cur_reach, gid)
    got_st, got = section_titles_in_order(blob)
    if got_st == :unparseable
      ng << "グループ #{gid} の Section を括弧対応で切り出せない"
      next
    end
    if got.empty? && blob.to_s.strip.empty?
      ng << "グループ #{gid} の描画分岐を切り出せない"
      next
    end
    unless got == expected
      ng << "グループ #{gid} の Section 見出し順が #{got.inspect}（期待 #{expected.inspect}）"
    end
  end
  ng
end

def check_product(current, baseline)
  ng = []
  if current.nil?
    ng << "#{SETTINGS_PATH} が存在しない"
    return ng
  end
  if baseline.nil?
    ng << "基準時点の SettingsView.swift を git show できない"
    return ng
  end

  cur = strip_comments(current)
  prev = strip_comments(baseline)

  if extract_struct_body(cur, "SettingsView").nil? || extract_struct_body(prev, "SettingsView").nil?
    ng << "SettingsView を括弧対応で切り出せない"
    return ng
  end

  btn_st, cur_buttons = extract_all_buttons(cur)
  prev_btn_st, prev_buttons = extract_all_buttons(prev)
  if btn_st == :unparseable || prev_btn_st == :unparseable
    ng << "Button 宣言を括弧対応で切り出せない"
    return ng
  end

  sec_st, _ = extract_all_sections(cur)
  prev_sec_st, _ = extract_all_sections(prev)
  if sec_st == :unparseable || prev_sec_st == :unparseable
    ng << "Section を括弧対応で切り出せない"
    return ng
  end

  def_count = count_struct_defs(cur, "RichButtonStyle")
  use_count = count_ident_calls(cur, "RichButtonStyle")
  ng << "RichButtonStyle の定義が #{def_count} 件（期待 0）" unless def_count == 0
  ng << "RichButtonStyle の使用が #{use_count} 件（期待 0）" unless use_count == 0

  reach = reachable_from_body(current)
  reach_sec_st, reach_sections = extract_all_sections(reach)
  if reach_sec_st == :unparseable
    ng << "到達可能な Section を括弧対応で切り出せない"
    return ng
  end

  TARGETS.each do |spec|
    found = find_buttons_by_id(cur_buttons, spec[:id])
    prev_found = find_buttons_by_id(prev_buttons, spec[:id])
    if found.size != 1
      ng << "Button「#{spec[:label]}」が #{found.size} 件（期待 1）"
      next
    end
    if prev_found.size != 1
      ng << "基準の Button「#{spec[:label]}」が #{prev_found.size} 件（期待 1）"
    end
    unless has_direct_bordered?(found[0])
      ng << "Button「#{spec[:label]}」に直接 .buttonStyle(.bordered) が無い"
    end
    owners = section_containing(reach_sections, spec[:id])
    if owners == :unparseable
      ng << "Button「#{spec[:label]}」の所属 Section を切り出せない"
    elsif owners.empty?
      ng << "Button「#{spec[:label]}」が到達可能な Section「#{spec[:section]}」に無い（移設・未使用・if false の可能性）"
    elsif owners.size != 1
      ng << "Button「#{spec[:label]}」の所属 Section が一意ではない"
    elsif owners[0][:title] != spec[:section]
      ng << "Button「#{spec[:label]}」の所属が Section「#{owners[0][:title]}」（期待「#{spec[:section]}」）"
    end
    form_body = extract_var_body(cur, spec[:form]) || extract_func_body(cur, spec[:form])
    if form_body.nil?
      ng << "#{spec[:form]} を切り出せない"
    else
      form_st, form_buttons = extract_all_buttons(form_body)
      if form_st == :unparseable
        ng << "#{spec[:form]} 内の Button を切り出せない"
      elsif find_buttons_by_id(form_buttons, spec[:id]).size != 1
        ng << "Button「#{spec[:label]}」が #{spec[:form]} 内に 1 件ではない"
      end
    end
  end

  base_fed = count_focus_disabled(prev)
  cur_fed = count_focus_disabled(cur)
  delta = base_fed - cur_fed
  unless delta == 3
    ng << ".focusEffectDisabled() が #{cur_fed} 件で基準から #{delta} 件減少（期待ちょうど 3）"
  end

  TARGETS.each do |spec|
    found = find_buttons_by_id(cur_buttons, spec[:id])
    prev_found = find_buttons_by_id(prev_buttons, spec[:id])
    next unless found.size == 1 && prev_found.size == 1
    unless has_direct_focus_disabled?(prev_found[0])
      ng << "基準の Button「#{spec[:label]}」に .focusEffectDisabled() が無い"
    end
    if has_direct_focus_disabled?(found[0])
      ng << "Button「#{spec[:label]}」に .focusEffectDisabled() が残っている"
    end
  end

  prev_target_fed = TARGETS.sum do |spec|
    found = find_buttons_by_id(prev_buttons, spec[:id])
    found.size == 1 && has_direct_focus_disabled?(found[0]) ? 1 : 0
  end
  cur_target_fed = TARGETS.sum do |spec|
    found = find_buttons_by_id(cur_buttons, spec[:id])
    found.size == 1 && has_direct_focus_disabled?(found[0]) ? 1 : 0
  end
  prev_other_fed = base_fed - prev_target_fed
  cur_other_fed = cur_fed - cur_target_fed
  unless prev_other_fed == cur_other_fed
    ng << "対象外の .focusEffectDisabled() の件数または所属が変化している（基準 #{prev_other_fed} / 現在 #{cur_other_fed}）"
  end

  ng.concat(check_tab_connection(current))
  ng.concat(check_section_layout(current, baseline))

  cur_stripped = strip_allowed_diffs(current)
  prev_stripped = strip_allowed_diffs(baseline)
  if cur_stripped == :unparseable || prev_stripped == :unparseable
    ng << "許可差分の局所除去に失敗した（括弧対応・宣言境界を確認できない）"
    return ng.uniq
  end

  unless normalize_code(cur_stripped) == normalize_code(prev_stripped)
    ng << "許可差分（3 置換・3 削除・旧定義削除）を局所除去した残余が基準と同一ではない"
  end

  TARGETS.each do |spec|
    cur_found = find_buttons_by_id(cur_buttons, spec[:id])
    prev_found = find_buttons_by_id(prev_buttons, spec[:id])
    next unless cur_found.size == 1 && prev_found.size == 1
    unless normalize_code(strip_allowed_modifiers(cur_found[0])) == normalize_code(strip_allowed_modifiers(prev_found[0]))
      ng << "Button「#{spec[:label]}」の許可差分以外（action・ラベル・アイコン・disabled・修飾の残部）が基準と異なる"
    end
  end

  cur_map_st, cur_map = section_map(cur_stripped)
  prev_map_st, prev_map = section_map(prev_stripped)
  if cur_map_st == :unparseable || prev_map_st == :unparseable
    ng << "残余 Section を括弧対応で切り出せない"
  elsif prev_map.empty?
    ng << "baseline の Section を見出しリテラルで切り出せない"
  else
    prev_map.each do |title, body|
      if !cur_map.key?(title)
        ng << "Section「#{title}」が残余比較で欠落している"
      elsif cur_map[title] != body
        ng << "Section「#{title}」の許可差分以外が基準から変化している"
      end
    end
  end

  prev_decls = settings_view_decl_map(prev_stripped)
  cur_decls = settings_view_decl_map(cur_stripped)
  if prev_decls.empty? || cur_decls.empty?
    ng << "SettingsView 宣言単位を切り出せない"
  else
    prev_decls.each do |name, body|
      next if name == "RichButtonStyle"
      if !cur_decls.key?(name)
        ng << "宣言 #{name} が欠落している"
      elsif cur_decls[name] != body
        ng << "宣言 #{name} が基準から変化している"
      end
    end
    extra_decls = cur_decls.keys - prev_decls.keys - ["RichButtonStyle"]
    extra_decls.each { |name| ng << "宣言 #{name} が追加されている" }
  end

  revoke_needles = [
    'Button("失効", role: .destructive, action: onRevoke)',
    ".buttonStyle(.borderless)",
    ".foregroundStyle(DSColor.statusError)",
  ]
  revoke_needles.each do |needle|
    unless compact(cur).include?(compact(needle))
      ng << "失効 Button の #{needle} が無い"
    end
  end
  unless compact(cur).include?(compact("viewModel.showPairingQR"))
    ng << "QR 発行 showPairingQR が無い"
  end

  ng.uniq
end

def selftest_assert(cond, msg)
  unless cond
    puts "task17-wiring --selftest: FAIL #{msg}"
    exit 1
  end
end

def mini_section(title, inner, footer: nil)
  s = %(Section { #{inner} } header: { Text("#{title}") })
  s += %( footer: { Text("#{footer}") }) if footer
  s
end

NOTIFY_OLD = %q{Button("通知テスト") { SessionCompletionNotifier.notifyCompleted(sessionName: String(localized: "テスト")) }.buttonStyle(RichButtonStyle()).focusEffectDisabled()}
NOTIFY_NEW = %q{Button("通知テスト") { SessionCompletionNotifier.notifyCompleted(sessionName: String(localized: "テスト")) }.buttonStyle(.bordered)}
UPDATE_OLD = %q{Button("今すぐ確認") { appUpdater.checkForUpdates() }.buttonStyle(RichButtonStyle()).disabled(!appUpdater.canCheckForUpdates).focusEffectDisabled()}
UPDATE_NEW = %q{Button("今すぐ確認") { appUpdater.checkForUpdates() }.buttonStyle(.bordered).disabled(!appUpdater.canCheckForUpdates)}
AGENT_OLD = %q{Button { openWindow(id: AgentConsoleCommands.windowID) } label: { Label("エージェント管理を開く", systemImage: "wrench.and.screwdriver") }.buttonStyle(RichButtonStyle()).focusEffectDisabled()}
AGENT_NEW = %q{Button { openWindow(id: AgentConsoleCommands.windowID) } label: { Label("エージェント管理を開く", systemImage: "wrench.and.screwdriver") }.buttonStyle(.bordered)}
RICH_DEF = "private struct RichButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label } }"
REVOKE = %q{Button("失効", role: .destructive, action: onRevoke).buttonStyle(.borderless).foregroundStyle(DSColor.statusError)}
QR = %q{Button { Task { await viewModel.showPairingQR(deviceName: "iPhone") } } label: { Label("QR コードを表示", systemImage: "qrcode") }.disabled(!viewModel.isPairingQREnabled)}

def settings_scaffold(notify:, update:, agent:, revoke: REVOKE, extra_top: "", rich: true)
  rich_line = rich ? "      #{RICH_DEF}\n" : ""
  <<~SWIFT
    import SwiftUI
    struct SettingsView: View {
      @AppStorage(NotificationSettings.bannerKey) private var bannerNotificationEnabled = true
      @AppStorage(NotificationSettings.soundKey) private var completionSoundEnabled = true
      @State private var selectedGroupID = "general"
      private var appLanguageBinding: Binding<AppLanguage> { Binding(get: { AppLanguage(rawValue: appLanguageRaw) ?? .system }, set: { appLanguageRaw = $0.rawValue }) }
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
      }
      @ViewBuilder private var generalForm: some View {
        #{mini_section("言語", 'Picker(selection: appLanguageBinding) { Text("システム").tag(AppLanguage.system); Text("日本語").tag(AppLanguage.ja); Text("English").tag(AppLanguage.en) } label: { Label("表示言語", systemImage: "globe") }')}
        #{mini_section("セッション", 'Picker(selection: defaultSessionBackendBinding) { Text("チャット").tag(DefaultSessionBackendPreference.chat); Text("ターミナル").tag(DefaultSessionBackendPreference.terminal) } label: { Label("デフォルトの開き方", systemImage: "rectangle.on.rectangle") }', footer: "新規セッションをチャット画面かターミナルで開くかの既定です。")}
        #{mini_section("通知", %(Toggle(isOn: $bannerNotificationEnabled) { Label("セッション完了をバナーで通知", systemImage: "bell") }; #{notify}))}
        #{mini_section("アップデート", %(Toggle(isOn: Binding(get: { appUpdater.automaticallyChecksForUpdates }, set: { appUpdater.automaticallyChecksForUpdates = $0 })) { Label("起動時に自動でアップデートを確認", systemImage: "clock.arrow.circlepath") }; #{update}))}
      }
      @ViewBuilder private var appearanceForm: some View {
        #{mini_section("外観", "ForEach(ThemeStore.all) { theme in ThemeRowView(theme: theme, isSelected: theme.id == themeID) { themeID = theme.id } }", footer: "テーマ（ターミナルの配色とアプリ全体）を切り替えます。変更は即座に反映されます。")}
        #{mini_section("アプリアイコン", "ForEach(AppIconStore.all) { option in AppIconRowView(option: option, isSelected: option.id == appIconID) { appIconID = option.id } }", footer: "Dock とアプリのアイコンを切り替えます。")}
      }
      @ViewBuilder private var agentsForm: some View {
        #{mini_section("権限", "ForEach(agentCatalog.allDescriptors, id: \\.ref) { descriptor in BypassToggleRow(descriptor: descriptor) }", footer: "変更は次回セッション開始から反映されます。")}
        #{mini_section("エージェント", agent, footer: "Claude Code・Codex・Cursor の設定をここから操作できます。")}
      }
      @ViewBuilder private var advancedForm: some View {
        #{mini_section("チームビュー討論", 'TextField("最大発言数", value: $agoraMaxUtterances, format: .number)', footer: "チームビュー討論の上限です。")}
        #{mini_section("使用量", 'Toggle(isOn: $usageAutoRefresh) { Label("使用量サイドバーを自動更新", systemImage: "arrow.clockwise") }')}
        #{mini_section("プライバシー", 'Link(destination: URL(string: "https://phlox.cc/privacy")!) { Label("プライバシーポリシー", systemImage: "hand.raised") }')}
        #{mini_section("このアプリについて", 'LabeledContent("アプリ", value: AppFlavor.current.displayName)')}
      }
      private struct MobileTokenSection: View {
        var body: some View {
          #{mini_section("モバイル接続", QR, footer: "iPhone アプリで QR コードを読み取ると接続できます。")}
          if !viewModel.devices.isEmpty {
            #{mini_section("接続済みの端末", "ForEach(viewModel.devices) { device in MobileDeviceRow(device: device) { } }")}
          }
        }
      }
      private struct MobileDeviceRow: View {
        var body: some View { Text(device.name); #{revoke} }
      }
      private struct ThemeRowView: View { var body: some View { Button(action: onSelect) { Text(theme.name) } } }
      private struct ThemeAppPreview: View { var body: some View { Text(model.bodyText) } }
      private struct AppIconRowView: View { var body: some View { Text(option.name) } }
    #{rich_line}#{extra_top}    }
  SWIFT
end

def good_baseline_src
  settings_scaffold(notify: NOTIFY_OLD, update: UPDATE_OLD, agent: AGENT_OLD, rich: true)
end

def good_current_src
  settings_scaffold(notify: NOTIFY_NEW, update: UPDATE_NEW, agent: AGENT_NEW, rich: false)
end

def ng_of(current, baseline)
  check_product(current, baseline)
end

def has_ng?(current, baseline, *needles)
  msgs = ng_of(current, baseline)
  needles.any? { |n| msgs.any? { |m| m.include?(n) } }
end

def run_selftest
  $stdout.sync = true
  url = %(let url = "https://phlox.cc/privacy" // trailing\n)
  stripped = strip_comments(url)
  selftest_assert stripped.include?("https://phlox.cc/privacy"), "正例: 文字列内の // を残す"
  selftest_assert !stripped.include?("trailing"), "正例: 行コメントを除去する"
  selftest_assert !strip_comments("let a = 1 /* x */ let b = 2").include?("x"), "正例: /* */ を除去する"

  interp = %(let id = "settings-group-\\(group.id)")
  selftest_assert strip_comments(interp).include?("settings-group-"), "正例: 補間文字列を保持する"

  parens = %(let s = "foo(bar)"; Section { Text(s) } header: { Text("言語") })
  st, secs = extract_all_sections(parens)
  selftest_assert st == :ok && secs.size == 1 && secs[0][:title] == "言語", "正例: 文字列中の括弧を壊さず Section を切り出す"

  spaced = %(Section { Text("hello world") } header: { Text("言語") })
  sm_st, sm = section_map(spaced)
  selftest_assert sm_st == :ok && sm["言語"].include?("hello world"), "正例: 文字列内空白を正規化で消さない"
  changed_space = %(Section { Text("helloworld") } header: { Text("言語") })
  _, sm2 = section_map(changed_space)
  selftest_assert sm["言語"] != sm2["言語"], "負例: 文字列内空白の改変を検出する"

  selftest_assert extract_balanced(" { a ", 0, "{", "}").nil?, "負例: 構文切り出し失敗は nil"

  realish = <<~SWIFT
    struct SettingsView: View {
      var body: some View { TabView { groupForm(group) }; ForEach(SettingsGroup.all) { _ in } }
      @ViewBuilder
      private var generalForm: some View {
        Section {
          Button("通知テスト") {
            SessionCompletionNotifier.notifyCompleted(sessionName: String(localized: "テスト"))
          }
          .buttonStyle(RichButtonStyle())
          .focusEffectDisabled()
        } header: {
          Text("通知")
        }
      }
      private struct RichButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label } }
    }
  SWIFT
  selftest_assert !extract_var_body(realish, "generalForm").nil?, "正例: @ViewBuilder 改行の var を切り出す"
  st, btns = extract_all_buttons(realish)
  selftest_assert st == :ok && find_buttons_by_id(btns, :notify).size == 1, "正例: 複数行 Button を切り出す"
  selftest_assert has_direct_rich_style?(find_buttons_by_id(btns, :notify)[0]), "正例: 対象 Button の RichButtonStyle を直接修飾として見る"
  selftest_assert count_struct_defs(%(let s = "struct RichButtonStyle {}"\nstruct RichButtonStyle: ButtonStyle { }), "RichButtonStyle") == 1, "正例: 文字列中の RichButtonStyle は定義に数えない"

  baseline = good_baseline_src
  current = good_current_src
  selftest_assert baseline_settings_is_pre_ui05?(baseline), "正例: 実装前 blob は基準として受理"
  good_ng = ng_of(current, baseline)
  selftest_assert good_ng.empty?, "正例: 契約どおりの3置換・3削除・旧定義削除 (#{good_ng.inspect})"

  commented = current.sub("Text(\"設定\")", "Text(\"設定\") // note (paren)\n      /* keep https://phlox.cc/privacy \\(x) */")
  commented = commented.sub(NOTIFY_NEW, "#{NOTIFY_NEW}\n")
  selftest_assert ng_of(commented, baseline).empty?, "正例: コメント・改行・文字列中の括弧・URL・補間を正しく扱う (#{ng_of(commented, baseline).inspect})"

  extra_base = settings_scaffold(notify: NOTIFY_OLD, update: UPDATE_OLD, agent: AGENT_OLD, revoke: "#{REVOKE}.focusEffectDisabled()", rich: true)
  extra_cur = settings_scaffold(notify: NOTIFY_NEW, update: UPDATE_NEW, agent: AGENT_NEW, revoke: "#{REVOKE}.focusEffectDisabled()", rich: false)
  selftest_assert ng_of(extra_cur, extra_base).empty?, "正例: 対象外に焦点抑制がある基準でも対象3件だけ削除 (#{ng_of(extra_cur, extra_base).inspect})"

  unimplemented = ng_of(baseline, baseline)
  selftest_assert unimplemented.any? { |m| m.include?("RichButtonStyle") }, "負例: 未実装 (#{unimplemented.inspect})"
  selftest_assert unimplemented.any? { |m| m.include?(".bordered") || m.include?("減少") }, "負例: 未実装は旧3ボタン／焦点抑制を理由にする"

  one_old = settings_scaffold(notify: NOTIFY_OLD, update: UPDATE_NEW, agent: AGENT_NEW, rich: false)
  selftest_assert has_ng?(one_old, baseline, "RichButtonStyle", "通知テスト", ".bordered"), "負例: 1ボタンだけ旧スタイル"

  def_left = settings_scaffold(notify: NOTIFY_NEW, update: UPDATE_NEW, agent: AGENT_NEW, rich: true)
  selftest_assert has_ng?(def_left, baseline, "RichButtonStyle"), "負例: 旧定義残存"

  missing_style = current.sub(".buttonStyle(.bordered)", "")
  selftest_assert has_ng?(missing_style, baseline, "通知テスト", ".bordered"), "負例: 標準スタイルの欠落"

  other_bordered = current.sub(REVOKE, %q{Button("失効", role: .destructive, action: onRevoke).buttonStyle(.bordered).foregroundStyle(DSColor.statusError)})
  selftest_assert has_ng?(other_bordered, baseline, "失効", "borderless", "残余", "MobileDeviceRow"), "負例: 別ボタンへの適用"

  prominent = current.sub(NOTIFY_NEW, NOTIFY_NEW.sub(".bordered", ".borderedProminent"))
  selftest_assert has_ng?(prominent, baseline, "通知テスト", ".bordered"), "負例: 強調スタイルへの置換"

  fed_left = settings_scaffold(notify: "#{NOTIFY_NEW}.focusEffectDisabled()", update: UPDATE_NEW, agent: AGENT_NEW, rich: false)
  selftest_assert has_ng?(fed_left, baseline, "focusEffectDisabled", "通知テスト"), "負例: 焦点抑制の残存"

  extra_removed = settings_scaffold(notify: NOTIFY_NEW, update: UPDATE_NEW, agent: AGENT_NEW, revoke: REVOKE, rich: false)
  selftest_assert has_ng?(extra_removed, extra_base, "対象外", "focusEffectDisabled"), "負例: 対象外の削除"

  parent_move = current.sub(
    mini_section("通知", %(Toggle(isOn: $bannerNotificationEnabled) { Label("セッション完了をバナーで通知", systemImage: "bell") }; #{NOTIFY_NEW})),
    mini_section("通知", %(Toggle(isOn: $bannerNotificationEnabled) { Label("セッション完了をバナーで通知", systemImage: "bell") }; #{NOTIFY_NEW})) + ".focusEffectDisabled()"
  )
  selftest_assert parent_move != current, "親移設 fixture が正例と異なること"
  selftest_assert has_ng?(parent_move, baseline, "focusEffectDisabled", "対象外", "減少"), "負例: 親への移設"

  focusable = current.sub(NOTIFY_NEW, "#{NOTIFY_NEW}.focusable(false)")
  selftest_assert has_ng?(focusable, baseline, "通知テスト", "残余", "許可差分"), "負例: 焦点無効化の追加"

  action_notify = current.sub('String(localized: "テスト")', 'String(localized: "本番")')
  selftest_assert has_ng?(action_notify, baseline, "通知テスト", "action", "残余"), "負例: 通知 action の変更"

  action_agent = current.sub("AgentConsoleCommands.windowID", '"other-window"')
  selftest_assert has_ng?(action_agent, baseline, "エージェント", "action", "残余", "openWindow"), "負例: 管理 action の変更"

  action_update = current.sub("appUpdater.checkForUpdates()", "appUpdater.checkForUpdates(force: true)")
  selftest_assert has_ng?(action_update, baseline, "今すぐ確認", "checkForUpdates", "残余"), "負例: 更新 action の変更"

  disabled_bad = current.sub(".disabled(!appUpdater.canCheckForUpdates)", ".disabled(false)")
  selftest_assert has_ng?(disabled_bad, baseline, "disabled", "今すぐ確認", "残余"), "負例: 更新の disabled 条件の変更"

  icon_bad = current.sub('systemImage: "wrench.and.screwdriver"', 'systemImage: "gear"')
  selftest_assert has_ng?(icon_bad, baseline, "エージェント", "wrench", "件数", "残余"), "負例: 管理アイコンの変更"

  label_bad = current.sub('Button("通知テスト")', 'Button("通知を試す")')
  selftest_assert has_ng?(label_bad, baseline, "通知テスト"), "負例: ラベルの変更"

  footer_bad = current.sub("Claude Code・Codex・Cursor の設定をここから操作できます。", "操作できません。")
  selftest_assert has_ng?(footer_bad, baseline, "footer", "エージェント", "残余"), "負例: footer の変更"

  role_bad = current.sub("role: .destructive, ", "")
  selftest_assert has_ng?(role_bad, baseline, "destructive", "失効"), "負例: 失効の destructive role"

  color_bad = current.sub("DSColor.statusError", "DSColor.accent")
  selftest_assert has_ng?(color_bad, baseline, "statusError", "失効", "残余", "MobileDeviceRow"), "負例: 失効の色"

  revoke_action_bad = current.sub("action: onRevoke", "action: {}")
  selftest_assert has_ng?(revoke_action_bad, baseline, "onRevoke", "失効"), "負例: 失効 action"

  qr_bad = current.sub("viewModel.showPairingQR", "viewModel.revoke")
  selftest_assert has_ng?(qr_bad, baseline, "showPairingQR", "QR", "残余", "MobileTokenSection"), "負例: QR 処理"

  bind_bad = current.sub("appLanguageRaw = $0.rawValue", "appLanguageRaw = AppLanguage.ja.rawValue")
  selftest_assert has_ng?(bind_bad, baseline, "appLanguageBinding", "宣言", "残余"), "負例: Binding の変更"

  key_bad = current.sub("NotificationSettings.bannerKey", '"phlox.notify.banner"')
  selftest_assert has_ng?(key_bad, baseline, "bannerKey", "AppStorage", "宣言", "残余"), "負例: 保存キーの変更"

  default_bad = current.sub("bannerNotificationEnabled = true", "bannerNotificationEnabled = false")
  selftest_assert has_ng?(default_bad, baseline, "bannerNotificationEnabled", "宣言", "残余"), "負例: 既定値の変更"

  drop_lang = current.sub(mini_section("言語", 'Picker(selection: appLanguageBinding) { Text("システム").tag(AppLanguage.system); Text("日本語").tag(AppLanguage.ja); Text("English").tag(AppLanguage.en) } label: { Label("表示言語", systemImage: "globe") }'), "")
  selftest_assert has_ng?(drop_lang, baseline, "言語"), "負例: Section の欠落"

  lang_sec = mini_section("言語", 'Picker(selection: appLanguageBinding) { Text("システム").tag(AppLanguage.system); Text("日本語").tag(AppLanguage.ja); Text("English").tag(AppLanguage.en) } label: { Label("表示言語", systemImage: "globe") }')
  dup_sec = current.sub(lang_sec, "#{lang_sec}\n        #{lang_sec}")
  selftest_assert has_ng?(dup_sec, baseline, "重複"), "負例: Section の重複"

  moved = current.sub(lang_sec, "")
  appear_inner = 'ForEach(ThemeStore.all) { theme in ThemeRowView(theme: theme, isSelected: theme.id == themeID) { themeID = theme.id } }'
  moved = moved.sub(mini_section("外観", appear_inner, footer: "テーマ（ターミナルの配色とアプリ全体）を切り替えます。変更は即座に反映されます。"), "#{lang_sec}\n        #{mini_section("外観", appear_inner, footer: "テーマ（ターミナルの配色とアプリ全体）を切り替えます。変更は即座に反映されます。")}")
  selftest_assert moved != current, "移動 fixture が正例と異なること"
  selftest_assert has_ng?(moved, baseline, "言語", "見出し順", "順序", "general", "appearance"), "負例: Section の移動"

  sess_sec = mini_section("セッション", 'Picker(selection: defaultSessionBackendBinding) { Text("チャット").tag(DefaultSessionBackendPreference.chat); Text("ターミナル").tag(DefaultSessionBackendPreference.terminal) } label: { Label("デフォルトの開き方", systemImage: "rectangle.on.rectangle") }', footer: "新規セッションをチャット画面かターミナルで開くかの既定です。")
  reordered = current.sub(lang_sec, "__LANG__")
  reordered = reordered.sub(sess_sec, lang_sec)
  reordered = reordered.sub("__LANG__", sess_sec)
  selftest_assert reordered != current, "並べ替え fixture が正例と異なること"
  selftest_assert has_ng?(reordered, baseline, "見出し順", "順序", "general"), "負例: Section の順序変更"

  tab_bad = current.sub("groupForm(group)", 'Text("空")')
  selftest_assert has_ng?(tab_bad, baseline, "groupForm", "TabView", "描画分岐", "言語", "モデル"), "負例: TabView 接続変更"

  unused = current.sub(
    mini_section("通知", %(Toggle(isOn: $bannerNotificationEnabled) { Label("セッション完了をバナーで通知", systemImage: "bell") }; #{NOTIFY_NEW})),
    mini_section("通知", 'Toggle(isOn: $bannerNotificationEnabled) { Label("セッション完了をバナーで通知", systemImage: "bell") }')
  ) + %(\n    private var decoy: some View { #{NOTIFY_NEW} }\n)
  selftest_assert has_ng?(unused, baseline, "通知テスト", "移設", "未使用", "generalForm", "件数"), "負例: 未使用コードへの退避"

  hidden = current.sub(NOTIFY_NEW, "if false { #{NOTIFY_NEW} }")
  selftest_assert has_ng?(hidden, baseline, "通知テスト", "if false", "移設", "到達"), "負例: 常時非表示への退避"

  header_bad = current.sub('Text("設定")', 'Text("Settings")')
  selftest_assert has_ng?(header_bad, baseline, "header", "設定", "宣言", "残余"), "負例: ヘッダーなど対象外宣言の変更"

  theme_bad = current.sub("Text(model.bodyText)", 'Text("seeed")')
  selftest_assert has_ng?(theme_bad, baseline, "ThemeAppPreview", "宣言", "残余"), "負例: テーマ見本など対象外宣言の変更"

  space_bad = current.sub("変更は即座に反映されます。", "変更は 即座に反映されます。")
  selftest_assert has_ng?(space_bad, baseline, "外観", "残余", "空白", "footer"), "負例: 文字列内空白の変更"

  unparsed = current.sub(NOTIFY_NEW, 'Button("通知テスト") {')
  unparsed_ng = ng_of(unparsed, baseline)
  selftest_assert unparsed_ng.any? { |m| m.include?("切り出せない") || m.include?("括弧") }, "負例: 構文切り出し失敗 (#{unparsed_ng.inspect})"

  unset, unset_errs = baseline_env_errors(nil)
  selftest_assert unset.nil? && unset_errs.any? { |m| m.include?("未設定") }, "負例: SHA 欠落"
  _, invalid_errs = baseline_env_errors("not-a-sha")
  selftest_assert invalid_errs.any? { |m| m.include?("SHA") || m.include?("ブランチ") }, "負例: SHA 不正"
  _, head_errs = baseline_env_errors("HEAD")
  selftest_assert head_errs.any? { |m| m.include?("HEAD") }, "負例: HEAD 指定"
  _, head1_errs = baseline_env_errors("HEAD~1")
  selftest_assert head1_errs.any? { |m| m.include?("HEAD") }, "負例: HEAD~1 指定"
  _, at_errs = baseline_env_errors("@")
  selftest_assert at_errs.any? { |m| m.include?("HEAD") }, "負例: @ 指定"
  _, branch_errs = baseline_env_errors("main")
  selftest_assert branch_errs.any? { |m| m.include?("ブランチ") || m.include?("SHA") }, "負例: ブランチ名は不正"
  sha, sha_errs = baseline_env_errors("abc1234")
  selftest_assert sha == "abc1234" && sha_errs.empty?, "正例: HEAD と一致し得る SHA 形式は拒否しない"

  selftest_assert parse_contract_baseline_text("---\nfoo: 1\n") == :missing, "負例: 契約 baseline_commit 欠落"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"PM が凍結時に設定\"\n") == :placeholder, "負例: 契約 baseline_commit プレースホルダ"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"not-a-sha\"\n") == :invalid, "負例: 契約 baseline_commit 不正"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: \"abc1234\"\n") == "abc1234", "正例: 契約 baseline_commit がクォート付き SHA"
  selftest_assert parse_contract_baseline_text("---\nbaseline_commit: abc1234\n") == "abc1234", "正例: 契約 baseline_commit がクォート無し SHA"
  mismatch_errs = contract_baseline_errors("---\nbaseline_commit: \"aaaaaaaa\"\n", "bbbbbbbb")
  selftest_assert mismatch_errs.any? { |m| m.include?("一致しない") || m.include?("無効") }, "負例: 環境変数との不一致"

  selftest_assert ng_of(current, nil).any? { |m| m.include?("git show") }, "負例: blob 欠落"
  selftest_assert !baseline_settings_is_pre_ui05?(current), "負例: 実装済み基準"
  selftest_assert frozen_script_errors("now", "frozen").any? { |m| m.include?("同一ではない") }, "負例: 凍結検査の改変"
  selftest_assert frozen_script_errors("same", "same").empty?, "正例: 凍結 rb と作業ツリーが同一"
  selftest_assert workdir_matches_git_blob?("a", "a"), "正例: git show と作業ツリーが同一"
  selftest_assert !workdir_matches_git_blob?("a", nil), "負例: git show 失敗は同一ではない"
end

if ARGV.include?("--selftest")
  run_selftest
  puts "task17-wiring --selftest: OK"
  exit 0
end

ng = []
raw = ENV["TASK17_BASELINE"]
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
    ng << "TASK17_BASELINE が無効なコミット: #{baseline}"
    baseline = nil
  else
    ng.concat(check_frozen_baseline(full))
    previous = git_show(full, SETTINGS_PATH)
    if previous.nil?
      ng << "基準時点の SettingsView.swift を git show できない（git show #{full}:#{SETTINGS_PATH}）"
    else
      current = File.exist?(SETTINGS_PATH) ? File.read(SETTINGS_PATH) : nil
      ng.concat(check_product(current, previous))
    end
  end
end

ng = ng.uniq
if ng.empty?
  puts "task17-wiring: OK"
else
  ng.each { |m| puts "task17-wiring: NG #{m}" }
  exit 1
end
