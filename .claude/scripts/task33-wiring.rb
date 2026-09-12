#!/usr/bin/env ruby
# task-33 配線検査: 新規セッションメニューが NewSessionMenuModel に集約され、
# 描画順と createSession 配線が接続され、旧ヘルパーが残っていないこと。
ng = []
view_path = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift"
view = File.read(view_path)
baseline = ENV["TASK33_BASELINE"] || "HEAD"

def compact(s)
  s.gsub(/\s+/, "")
end

def extract_balanced(src, open_idx, open_ch, close_ch)
  depth = 0
  i = open_idx
  while i < src.length
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

def each_call_args(src, fn)
  pos = 0
  re = /\b#{Regexp.escape(fn)}\s*\(/
  while (m = src.match(re, pos))
    open = m.end(0) - 1
    body = extract_balanced(src, open, "(", ")")
    yield body if body
    pos = m.begin(0) + 1
  end
end

def appears_after_button_within?(src, needle, window)
  src.to_enum(:scan, /\bButton\s*[\({]/).any? do
    src[Regexp.last_match.end(0), window].to_s.include?(needle)
  end
end

def git_unchanged?(baseline, path)
  system("git", "diff", "--quiet", baseline, "--", path)
end

menu = extract_func_body(view, "newSessionMenuItems")
if menu.nil?
  ng << "newSessionMenuItems の関数本文を括弧対応で切り出せない"
else
  menu_c = compact(menu)
  ng << "newSessionMenuItems 本文に NewSessionMenuModel.make( が無い" unless menu.include?("NewSessionMenuModel.make(") || menu_c.include?("NewSessionMenuModel.make(")
  ng << "newSessionMenuItems 本文に destinationText が無い" unless menu.include?("destinationText")
  ng << "newSessionMenuItems 本文に if let primary が無い" unless menu =~ /if\s+let\s+primary\b/
  ng << "newSessionMenuItems 本文に .primary が無い" unless menu.include?(".primary")

  section_args = []
  each_call_args(menu, "Section") { |args| section_args << compact(args) }
  ng << "newSessionMenuItems 本文に Section( が無い" if section_args.empty?
  section_args.each do |args|
    ng << "Section( の引数に section.title が無い" unless args.include?("section.title")
  end

  foreach_args = []
  each_call_args(menu, "ForEach") { |args| foreach_args << compact(args) }
  ng << "ForEach( に model.sections が無い" unless foreach_args.any? { |a| a.include?("model.sections") }
  ng << "ForEach( に section.items が無い" unless foreach_args.any? { |a| a.include?("section.items") }

  create_args = []
  each_call_args(menu, "createSession") { |args| create_args << compact(args) }
  ng << "newSessionMenuItems 本文に createSession( が無い" if create_args.empty?
  ng << "Button 内の直後に createSession( が無い" unless appears_after_button_within?(menu, "createSession(", 400)
  unless create_args.any? { |a| a.include?("ref:primary.ref") && a.include?("backend:primary.backend") }
    ng << "createSession( に ref: / backend: が primary から渡っていない"
  end
  unless create_args.any? { |a| a.include?("ref:item.ref") && a.include?("backend:item.backend") }
    ng << "createSession( に ref: / backend: が item から渡っていない"
  end

  ng << "AgentStartCardsModel.modes(for: が newSessionMenuItems 本文に残っている" if menu.include?("AgentStartCardsModel.modes(for:") || menu_c.include?("AgentStartCardsModel.modes(for:")
end

ng << "newSessionMenuTitle が残っている" if view =~ /\bnewSessionMenuTitle\b/
ng << "newSessionMenuSymbol が残っている" if view =~ /\bnewSessionMenuSymbol\b/

[
  "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/AgentStartCards.swift",
  "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift",
  "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamTimelineView.swift",
].each do |path|
  unless git_unchanged?(baseline, path)
    ng << "#{path} が #{baseline} から差分あり"
  end
end

if ng.empty?
  puts "task33-wiring: OK"
else
  ng.each { |m| puts "task33-wiring: NG #{m}" }
  exit 1
end
