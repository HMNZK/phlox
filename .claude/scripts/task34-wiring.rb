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
baseline = ENV["TASK34_BASELINE"]
if baseline.nil? || baseline.empty?
  ng << "TASK34_BASELINE が未設定（HEAD にフォールバックしない）"
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

def git_show(rev, path)
  text = IO.popen(["git", "show", "#{rev}:#{path}"], err: [:child, :out], &:read)
  return text if $?.success?
  nil
end

def count_needles(src)
  n = compact(strip_comments(src))
  {
    "focusable(" => n.scan("focusable(").size,
    "focusEffectDisabled(" => n.scan("focusEffectDisabled(").size,
    "accessibilityHidden(true)" => n.scan("accessibilityHidden(true)").size,
    ".contentShape(Rectangle())" => n.scan(".contentShape(Rectangle())").size,
    ".help(" => n.scan(".help(").size,
  }
end

top_src = strip_comments(top)
side_src = strip_comments(side)
pane_src = strip_comments(pane)
side_c = compact(side_src)
pane_c = compact(pane_src)

mode_body = extract_struct_body(top_src, "ModeSegmentButton")
if mode_body.nil?
  ng << "ModeSegmentButton の struct 本文を括弧対応で切り出せない"
else
  mode_c = compact(mode_body)
  frame = ".frame(width:DSHitTarget.modeSegmentWidth,height:DSHitTarget.modeSegmentHeight)"
  frame_count = mode_c.scan(frame).size
  ng << "ModeSegmentButton 本文に #{frame} が #{frame_count} 回（期待 1）" unless frame_count == 1
  ng << "ModeSegmentButton 本文に width:26,height:20 が残っている" if mode_c.include?("width:26,height:20")
  ng << "ModeSegmentButton 本文に size:13 が無い" unless mode_c.include?("size:13")
  ng << "ModeSegmentButton 本文に .contentShape(Rectangle()) が無い" unless mode_c.include?(".contentShape(Rectangle())")
  ng << "ModeSegmentButton 本文に .help(help) が無い" unless mode_c.include?(".help(help)")
  ng << "ModeSegmentButton 本文に .accessibilityAddTraits が無い" unless mode_c.include?(".accessibilityAddTraits")
  ng << "ModeSegmentButton 本文に .pointingHandCursor() が無い" unless mode_c.include?(".pointingHandCursor()")
  ng << "ModeSegmentButton 本文に .accessibilityIdentifier(identifier) が無い" unless mode_c.include?(".accessibilityIdentifier(identifier)")
end

toggle_body = extract_struct_body(top_src, "ViewModeToggle")
if toggle_body.nil?
  ng << "ViewModeToggle の struct 本文を括弧対応で切り出せない"
else
  toggle_c = compact(toggle_body)
  ng << "ViewModeToggle 本文に .padding(DSSpacing.xxs) が無い" unless toggle_c.include?(".padding(DSSpacing.xxs)")
end

icon_frame = ".frame(width:DSHitTarget.icon,height:DSHitTarget.icon)"
icon_frames = side_c.scan(icon_frame).size
ng << "DashboardSidebarView.swift の #{icon_frame} が #{icon_frames} 箇所（期待 3 以上）" unless icon_frames >= 3
ng << "DashboardSidebarView.swift に width:22,height:22 が残っている" if side_c.include?("width:22,height:22")
ng << "DashboardSidebarView.swift に width:20,height:20 が残っている" if side_c.include?("width:20,height:20")

xmark_idx = pane_c.index('"xmark"')
if xmark_idx.nil?
  ng << "PaneLayoutView.swift に xmark が無い"
else
  help_idx = pane_c.index(".help(", xmark_idx)
  if help_idx.nil?
    ng << "PaneLayoutView.swift の \"xmark\" の直後に .help( が無い"
  else
    range = pane_c[xmark_idx...help_idx]
    ng << "PaneLayoutView.swift の xmark〜.help( に #{icon_frame} が無い" unless range.include?(icon_frame)
    ng << "PaneLayoutView.swift の xmark〜.help( に .contentShape(Rectangle()) が無い" unless range.include?(".contentShape(Rectangle())")
    ng << "PaneLayoutView.swift の xmark〜.help( に width:20,height:20 が残っている" if range.include?("width:20,height:20")
  end
end

if baseline
  [top_path, side_path, pane_path].each do |path|
    current = File.read(path)
    previous = git_show(baseline, path)
    if previous.nil?
      ng << "git show #{baseline}:#{path} に失敗"
      next
    end
    got = count_needles(current)
    want = count_needles(previous)
    got.each do |needle, n|
      w = want[needle]
      unless n == w
        ng << "#{path} の #{needle} 出現数が #{n}（基準 #{baseline} は #{w}）"
      end
    end
  end
end

trailing_struct = extract_struct_body(top_src, "DashboardTrailingTopBarControls")
if trailing_struct.nil?
  ng << "DashboardTrailingTopBarControls の struct 本文を括弧対応で切り出せない"
else
  body = extract_var_body(trailing_struct, "body")
  if body.nil?
    ng << "DashboardTrailingTopBarControls.body を括弧対応で切り出せない"
  else
    body_c = compact(body)
    unless body_c.include?("trailingControls")
      ng << "DashboardTrailingTopBarControls.body に trailingControls が無い"
    end
    unless body_c.include?(".frame(height:32)")
      ng << "DashboardTrailingTopBarControls.body に .frame(height:32) が無い"
    end
  end
end

if ng.empty?
  puts "task34-wiring: OK"
else
  ng.each { |m| puts "task34-wiring: NG #{m}" }
  exit 1
end
