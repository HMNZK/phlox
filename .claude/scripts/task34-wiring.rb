#!/usr/bin/env ruby
# task-34 配線検査: 小さなアイコン操作の押せる範囲が DSHitTarget に集約され、
# 絵柄サイズ・フォーカス上書き・32pt 行が保たれていること。
ng = []
top_path = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardTopBarControls.swift"
side_path = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift"
pane_path = "macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift"
top = File.read(top_path)
side = File.read(side_path)
pane = File.read(pane_path)
baseline = ENV["TASK34_BASELINE"] || "HEAD"

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

def extract_struct_body(src, name)
  m = src.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?struct\s+#{Regexp.escape(name)}\b/)
  return nil unless m
  brace = src.index("{", m.begin(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_enclosing_button_body(src, inner_idx)
  prefix = src[0...inner_idx]
  last = nil
  pos = 0
  while (m = prefix.match(/\bButton\b/, pos))
    last = m.begin(0)
    pos = m.begin(0) + 1
  end
  return nil if last.nil?
  rest_start = last
  first_paren = src.index("(", rest_start)
  first_brace = src.index("{", rest_start)
  return nil unless first_brace
  if first_paren && first_paren < first_brace
    params = extract_balanced(src, first_paren, "(", ")")
    return nil if params.nil?
    after = first_paren + 1 + params.length + 1
    brace = src.index("{", after)
    return nil unless brace
    extract_balanced(src, brace, "{", "}")
  else
    extract_balanced(src, first_brace, "{", "}")
  end
end

def git_show(rev, path)
  text = IO.popen(["git", "show", "#{rev}:#{path}"], err: [:child, :out], &:read)
  return text if $?.success?
  nil
end

mode_body = extract_struct_body(top, "ModeSegmentButton")
if mode_body.nil?
  ng << "ModeSegmentButton の struct 本文を括弧対応で切り出せない"
else
  mode_c = compact(mode_body)
  unless mode_c.include?("DSHitTarget.modeSegmentWidth") && mode_c.include?("DSHitTarget.modeSegmentHeight") && mode_c.include?("frame(")
    ng << "ModeSegmentButton 本文に DSHitTarget.modeSegmentWidth / modeSegmentHeight の frame が無い"
  end
  ng << "ModeSegmentButton 本文に size: 13 が無い" unless mode_body =~ /size:\s*13\b/
end

icon_frames = side.scan(/\.frame\(\s*width:\s*DSHitTarget\.icon\s*,\s*height:\s*DSHitTarget\.icon\s*\)/)
ng << "DashboardSidebarView.swift の DSHitTarget.icon の frame が #{icon_frames.size} 箇所（期待 3 以上）" unless icon_frames.size >= 3
ng << "DashboardSidebarView.swift に width: 22, height: 22 が残っている" if side =~ /width:\s*22\s*,\s*height:\s*22/
ng << "DashboardSidebarView.swift に width: 20, height: 20 が残っている" if side =~ /width:\s*20\s*,\s*height:\s*20/

xmark_idx = pane.index('"xmark"')
if xmark_idx.nil?
  ng << "PaneLayoutView.swift に xmark が無い"
else
  xmark_body = extract_enclosing_button_body(pane, xmark_idx)
  if xmark_body.nil?
    ng << "PaneLayoutView.swift の xmark Button 本文を括弧対応で切り出せない"
  else
    ng << "PaneLayoutView.swift の xmark Button 内に DSHitTarget.icon が無い" unless xmark_body.include?("DSHitTarget.icon")
    ng << "PaneLayoutView.swift の xmark Button 内に width: 20, height: 20 が残っている" if xmark_body =~ /width:\s*20\s*,\s*height:\s*20/
  end
end

%w[focusable( focusEffectDisabled( accessibilityHidden(].each do |needle|
  [top_path, side_path, pane_path].each do |path|
    current = File.read(path)
    previous = git_show(baseline, path)
    if previous.nil?
      ng << "git show #{baseline}:#{path} に失敗"
      next
    end
    got = current.scan(needle).size
    want = previous.scan(needle).size
    unless got == want
      ng << "#{path} の #{needle} 出現数が #{got}（基準 #{baseline} は #{want}）"
    end
  end
end

ng << "DashboardTopBarControls.swift に .frame(height: 32) が無い" unless top =~ /\.frame\(\s*height:\s*32\s*\)/

if ng.empty?
  puts "task34-wiring: OK"
else
  ng.each { |m| puts "task34-wiring: NG #{m}" }
  exit 1
end
