#!/usr/bin/env ruby
# task-33 配線検査: 新規セッションメニューが NewSessionMenuModel に集約され、
# 描画順と createSession 配線が接続され、旧ヘルパーが残っていないこと。
ng = []
view_path = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift"
model_path = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/NewSessionMenuModel.swift"
view = File.read(view_path)
baseline = ENV["TASK33_BASELINE"]
if baseline.nil? || baseline.empty?
  ng << "TASK33_BASELINE が未設定（HEAD にフォールバックしない）"
  baseline = nil
end

def compact(s)
  s.gsub(/\s+/, "")
end

def strip_comments(src)
  src.gsub(/\/\/[^\n]*/, "")
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

def extract_call_args(src, callee)
  m = src.match(/#{Regexp.escape(callee)}\s*\(/)
  return nil unless m
  extract_balanced(src, m.end(0) - 1, "(", ")")
end

def button_label_bodies(src)
  bodies = []
  pos = 0
  while (m = src.match(/\blabel\s*:\s*\{/, pos))
    open = m.end(0) - 1
    body = extract_balanced(src, open, "{", "}")
    bodies << body if body
    pos = m.begin(0) + 1
  end
  pos = 0
  while (m = src.match(/\bButton\s*\(\s*action\s*:/, pos))
    paren = src.index("(", m.begin(0))
    params = extract_balanced(src, paren, "(", ")")
    unless params.nil?
      after = paren + 1 + params.length + 1
      brace = src.index("{", after)
      between = brace ? src[after...brace] : ""
      if brace && between !~ /\blabel\s*:/
        body = extract_balanced(src, brace, "{", "}")
        bodies << body if body
      end
    end
    pos = m.begin(0) + 1
  end
  bodies
end

def git_unchanged?(rev, path)
  system("git", "diff", "--quiet", rev, "--", path)
end

view_src = strip_comments(view)
menu = extract_func_body(view_src, "newSessionMenuItems")
if menu.nil?
  ng << "newSessionMenuItems の関数本文を括弧対応で切り出せない"
else
  menu_c = compact(menu)

  make_args = extract_call_args(menu, "NewSessionMenuModel.make")
  if make_args.nil?
    ng << "newSessionMenuItems 本文に NewSessionMenuModel.make( が無い"
  else
    make_c = compact(make_args)
    ng << "NewSessionMenuModel.make( の引数に projectName: が無い" unless make_c.include?("projectName:")
    ng << "NewSessionMenuModel.make( の引数に projectID が無い" unless make_args =~ /\bprojectID\b/
    ng << "NewSessionMenuModel.make( の引数に projects が無い" unless make_args =~ /\bprojects\b/
    unless make_c.include?("descriptors:viewModel.availableAgentDescriptors")
      ng << "NewSessionMenuModel.make( の引数に descriptors:viewModel.availableAgentDescriptors が無い"
    end
  end

  unless menu_c.include?("Text(model.destinationText)")
    ng << "newSessionMenuItems 本文に Text(model.destinationText) が無い"
  end
  if button_label_bodies(menu).any? { |body| compact(body).include?("Text(model.destinationText)") }
    ng << "Text(model.destinationText) が Button の label クロージャ本文に含まれている"
  end

  unless menu =~ /if\s+let\s+\w+\s*=\s*model\.primary/
    ng << "newSessionMenuItems 本文に if let <name> = model.primary が無い"
  end

  unless menu_c.include?("Section(section.title)") || menu_c.include?("header:{Text(section.title)}")
    ng << "newSessionMenuItems 本文に Section(section.title) も header:{Text(section.title)} も無い"
  end

  ng << "ForEach( に model.sections が無い" unless menu_c.include?("ForEach(model.sections")
  ng << "ForEach( に section.items が無い" unless menu_c.include?("ForEach(section.items")

  create_args = []
  each_call_args(menu, "createSession") { |args| create_args << compact(args) }
  ng << "newSessionMenuItems 本文に createSession( が無い" if create_args.empty?
  unless create_args.any? { |a| a.include?("ref:primary.ref,projectID:projectID,backend:primary.backend") }
    ng << "createSession( に ref:primary.ref,projectID:projectID,backend:primary.backend が無い"
  end
  unless create_args.any? { |a| a.include?("ref:item.ref,projectID:projectID,backend:item.backend") }
    ng << "createSession( に ref:item.ref,projectID:projectID,backend:item.backend が無い"
  end

  unless menu_c.include?("Label(primary.title,systemImage:primary.systemImage)")
    ng << "Label(primary.title, systemImage: primary.systemImage) が無い"
  end
  unless menu_c.include?("Label(item.title,systemImage:item.systemImage)")
    ng << "Label(item.title, systemImage: item.systemImage) が無い"
  end

  i_dest = menu_c.index("Text(model.destinationText)")
  i_primary = menu_c.index("model.primary")
  i_sections = menu_c.index("ForEach(model.sections")
  if i_dest.nil? || i_primary.nil? || i_sections.nil?
    ng << "出現順検査に必要な Text(model.destinationText) / model.primary / ForEach(model.sections が見つからない"
  elsif !(i_dest < i_primary && i_primary < i_sections)
    ng << "出現順が Text(model.destinationText) < model.primary < ForEach(model.sections ではない"
  end

  if menu.include?("AgentStartCardsModel.modes(for:") || menu_c.include?("AgentStartCardsModel.modes(for:")
    ng << "AgentStartCardsModel.modes(for: が newSessionMenuItems 本文に残っている"
  end
end

ng << "newSessionMenuTitle が残っている" if view_src =~ /\bnewSessionMenuTitle\b/
ng << "newSessionMenuSymbol が残っている" if view_src =~ /\bnewSessionMenuSymbol\b/

unless File.exist?(model_path)
  ng << "#{model_path} が存在しない"
else
  model_src = strip_comments(File.read(model_path))
  model_c = compact(model_src)
  unless model_src.include?("AgentStartCardsModel.modes(for:") || model_c.include?("AgentStartCardsModel.modes(for:")
    ng << "NewSessionMenuModel.swift に AgentStartCardsModel.modes(for: が無い"
  end
  ng << "NewSessionMenuModel.swift に .backend が無い" unless model_c.include?(".backend")
  ng << "NewSessionMenuModel.swift に .appServer リテラルがある" if model_c.include?(".appServer")
  ng << "NewSessionMenuModel.swift に .pty リテラルがある" if model_c.include?(".pty")
end

if baseline
  [
    "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/AgentStartCards.swift",
    "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamTimelineView.swift",
  ].each do |path|
    unless git_unchanged?(baseline, path)
      ng << "#{path} が #{baseline} から差分あり"
    end
  end
end

if ng.empty?
  puts "task33-wiring: OK"
else
  ng.each { |m| puts "task33-wiring: NG #{m}" }
  exit 1
end
