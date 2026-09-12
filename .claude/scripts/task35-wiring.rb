#!/usr/bin/env ruby
# task-35 配線検査: ThemePreviewModel が見本の唯一の入力になり、
# SettingsView のテーマ行が同じ model でアプリ見本と色帯を描き、
# 製品側の選択面・入力面・枠・輝度判定レシピが契約どおりであること。
ng = []
model_path = "macos/Packages/DesignSystem/Sources/DesignSystem/ThemePreviewModel.swift"
settings_path = "macos/App/SettingsView.swift"
tokens_path = "macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift"
theme_path = "macos/Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift"
composer_path = "macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift"
grid_path = "macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift"

baseline = ENV["TASK35_BASELINE"]
if baseline.nil? || baseline.empty?
  ng << "TASK35_BASELINE が未設定（HEAD にフォールバックしない）"
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
  brace = src.index("{", m.end(0))
  return nil unless brace
  extract_balanced(src, brace, "{", "}")
end

def extract_call_args(src, callee)
  m = src.match(/#{Regexp.escape(callee)}\s*\(/)
  return nil unless m
  extract_balanced(src, m.end(0) - 1, "(", ")")
end

def labeled_arg(args, label)
  return nil if args.nil?
  m = compact(args).match(/#{Regexp.escape(label)}:([A-Za-z_][A-Za-z0-9_]*)/)
  m && m[1]
end

def replace_struct(src, name, placeholder)
  m = src.match(/(?:private\s+|public\s+|fileprivate\s+|internal\s+)?struct\s+#{Regexp.escape(name)}\b/)
  return src unless m
  brace = src.index("{", m.begin(0))
  return src unless brace
  body = extract_balanced(src, brace, "{", "}")
  return src if body.nil?
  close = brace + 1 + body.length + 1
  src[0...m.begin(0)] + placeholder + src[close..]
end

def git_show(rev, path)
  text = IO.popen(["git", "show", "#{rev}:#{path}"], err: [:child, :out], &:read)
  return text if $?.success?
  nil
end

def git_unchanged?(rev, path)
  system("git", "diff", "--quiet", rev, "--", path)
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

# --- ThemePreviewModel.swift ---
unless File.exist?(model_path)
  ng << "#{model_path} が存在しない"
else
  model_src = strip_comments(File.read(model_path))
  model_c = compact(model_src)
  ng << "ThemePreviewModel.swift が SwiftUI を import している" if model_src =~ /^\s*import\s+SwiftUI\b/
  ng << "ThemePreviewModel.swift が AppKit を import している" if model_src =~ /^\s*import\s+AppKit\b/
  ng << "ThemePreviewModel.swift に Color がある" if model_src =~ /\bColor\b/
  ng << "ThemePreviewModel.swift に View がある" if model_src =~ /\bView\b/
  ng << "ThemePreviewModel.swift に ColorScheme がある" if model_src =~ /\bColorScheme\b/
  ng << "ThemePreviewModel.swift に ThemeStore.active がある" if model_c.include?("ThemeStore.active")
  ng << "ThemePreviewModel.swift に UserDefaults がある" if model_src =~ /\bUserDefaults\b/
  unless model_c.include?("staticfuncmake(theme:AppTheme)") || model_src =~ /\bstatic\s+func\s+make\s*\(\s*theme\s*:/
    ng << "ThemePreviewModel.swift に static func make(theme: が無い"
  end
  unless model_src =~ /\bstruct\s+ThemePreviewModel\b/
    ng << "ThemePreviewModel.swift に struct ThemePreviewModel が無い"
  end
  unless model_src =~ /\bstruct\s+Layer\b/
    ng << "ThemePreviewModel.swift に struct Layer が無い"
  end
end

# --- SettingsView テーマ行 ---
unless File.exist?(settings_path)
  ng << "#{settings_path} が存在しない"
else
  settings = File.read(settings_path)
  settings_src = strip_comments(settings)
  settings_c = compact(settings_src)

  unless settings_c.include?("ForEach(ThemeStore.all)")
    ng << "SettingsView に ForEach(ThemeStore.all) が無い"
  end
  unless settings_c.include?("ThemeRowView(theme:theme")
    ng << "SettingsView に ThemeRowView(theme: theme が無い"
  end
  unless settings_c.include?("themeID=theme.id")
    ng << "SettingsView に themeID = theme.id が無い"
  end

  row = extract_struct_body(settings_src, "ThemeRowView")
  if row.nil?
    ng << "ThemeRowView の struct 本文を括弧対応で切り出せない"
  else
    row_c = compact(row)
    unless row_c.include?("Button(action:onSelect)")
      ng << "ThemeRowView 本文に Button(action: onSelect) が無い"
    end
    unless row_c.include?('Image(systemName:"checkmark")')
      ng << "ThemeRowView 本文に選択チェック checkmark が無い"
    end
    unless row_c.include?("Text(theme.name)") || row_c.include?("Text(model.themeName)")
      ng << "ThemeRowView 本文に Text(theme.name) も Text(model.themeName) も無い"
    end
    unless row_c.include?("Text(model.appLabel)")
      ng << "ThemeRowView 本文に Text(model.appLabel) が無い"
    end
    unless row_c.include?("Text(model.terminalLabel)")
      ng << "ThemeRowView 本文に Text(model.terminalLabel) が無い"
    end

    make_count = count_calls(row, "ThemePreviewModel.make")
    ng << "ThemeRowView 本文の ThemePreviewModel.make( が #{make_count} 回（期待 1）" unless make_count == 1
    make_args = extract_call_args(row, "ThemePreviewModel.make")
    if make_args.nil?
      ng << "ThemeRowView 本文に ThemePreviewModel.make( が無い"
    else
      theme_arg = labeled_arg(make_args, "theme")
      unless theme_arg == "theme"
        ng << "ThemePreviewModel.make の theme: 引数が theme ではない（#{theme_arg.inspect}）"
      end
    end

    app_args = extract_call_args(row, "ThemeAppPreview")
    strip_args = extract_call_args(row, "ThemeSwatchStrip")
    if app_args.nil?
      ng << "ThemeRowView 本文に ThemeAppPreview( が無い"
    end
    if strip_args.nil?
      ng << "ThemeRowView 本文に ThemeSwatchStrip( が無い"
    end
    unless app_args.nil? || strip_args.nil?
      app_model = labeled_arg(app_args, "model")
      strip_model = labeled_arg(strip_args, "model")
      if app_model.nil? || strip_model.nil?
        ng << "ThemeAppPreview / ThemeSwatchStrip の model: 引数を取れない"
      elsif app_model != strip_model
        ng << "ThemeAppPreview と ThemeSwatchStrip に渡す model が異なる（#{app_model} vs #{strip_model}）"
      end
    end
  end

  preview = extract_struct_body(settings_src, "ThemeAppPreview")
  if preview.nil?
    ng << "ThemeAppPreview の struct 本文を括弧対応で切り出せない"
  else
    preview_c = compact(preview)
    %w[
      model.background
      model.textPrimary
      model.selectedRow
      model.currentMarker
      model.inputFill
      model.inputBorder
      model.bodyText
      model.selectedRowText
      model.inputText
    ].each do |needle|
      ng << "ThemeAppPreview 本文に #{needle} が無い" unless preview_c.include?(needle)
    end
    bg_count = preview_c.scan("model.background.color").size
    unless bg_count >= 2
      ng << "ThemeAppPreview 本文の model.background.color が #{bg_count} 回（selectedRow と inputFill の不透明下地として 2 以上）"
    end
    unless preview_c.include?("model.selectedRow.rgb.color.opacity(model.selectedRow.opacity)")
      ng << "ThemeAppPreview 本文に model.selectedRow.rgb.color.opacity(model.selectedRow.opacity) が無い"
    end
    unless preview_c.include?("model.inputFill.rgb.color.opacity(model.inputFill.opacity)")
      ng << "ThemeAppPreview 本文に model.inputFill.rgb.color.opacity(model.inputFill.opacity) が無い"
    end
    unless preview_c.include?("model.inputBorder.rgb.color.opacity(model.inputBorder.opacity)")
      ng << "ThemeAppPreview 本文に model.inputBorder.rgb.color.opacity(model.inputBorder.opacity) が無い"
    end
    ng << "ThemeAppPreview 本文に DSColor がある" if preview =~ /\bDSColor\b/
    ng << "ThemeAppPreview 本文に ThemeStore.active がある" if preview_c.include?("ThemeStore.active")
    ng << "ThemeAppPreview 本文に UserDefaults がある" if preview =~ /\bUserDefaults\b/
    ng << "ThemeAppPreview 本文に TextField がある" if preview =~ /\bTextField\b/
    ng << "ThemeAppPreview 本文に TextEditor がある" if preview =~ /\bTextEditor\b/
    ng << "ThemeAppPreview 本文に terminalBackground がある" if preview_c.include?("terminalBackground")
    ng << "ThemeAppPreview 本文に .ansi がある" if preview_c.include?(".ansi")
  end

  strip = extract_struct_body(settings_src, "ThemeSwatchStrip")
  if strip.nil?
    ng << "ThemeSwatchStrip の struct 本文を括弧対応で切り出せない"
  else
    strip_c = compact(strip)
    unless strip_c.include?("model.terminalSwatches")
      ng << "ThemeSwatchStrip 本文に model.terminalSwatches が無い"
    end
    ng << "ThemeSwatchStrip 本文に DSColor がある" if strip =~ /\bDSColor\b/
    ng << "ThemeSwatchStrip 本文に ThemeStore.active がある" if strip_c.include?("ThemeStore.active")
    ng << "ThemeSwatchStrip 本文に UserDefaults がある" if strip =~ /\bUserDefaults\b/
    ng << "ThemeSwatchStrip 本文に TextField がある" if strip =~ /\bTextField\b/
    ng << "ThemeSwatchStrip 本文に TextEditor がある" if strip =~ /\bTextEditor\b/
  end
end

# --- 製品側レシピ（変更されても落とす） ---
{
  tokens_path => File.exist?(tokens_path) ? strip_comments(File.read(tokens_path)) : nil,
  theme_path => File.exist?(theme_path) ? strip_comments(File.read(theme_path)) : nil,
  composer_path => File.exist?(composer_path) ? strip_comments(File.read(composer_path)) : nil,
  grid_path => File.exist?(grid_path) ? strip_comments(File.read(grid_path)) : nil,
}.each do |path, src|
  ng << "#{path} が存在しない" if src.nil?
end

if File.exist?(tokens_path)
  tokens_c = compact(strip_comments(File.read(tokens_path)))
  unless tokens_c.include?("fillSelected:Color{theme.textPrimary.color.opacity(AppTheme.sidebarSelectedOpacity)}")
    ng << "Tokens.swift の fillSelected が theme.textPrimary.color.opacity(AppTheme.sidebarSelectedOpacity) ではない"
  end
  unless tokens_c.include?("sessionRowSelected:Color{fillSelected}")
    ng << "Tokens.swift の sessionRowSelected が fillSelected ではない"
  end
  unless tokens_c.include?("composerBorder:Color{theme.preferredColorScheme==.light?theme.textPrimary.color.opacity(0.86):Color.white.opacity(0.06)}")
    ng << "Tokens.swift の composerBorder が明色 textPrimary 86% / 暗色 white 6% ではない"
  end
end

if File.exist?(theme_path)
  theme_src = strip_comments(File.read(theme_path))
  theme_c = compact(theme_src)
  unless theme_c.include?("sidebarSelectedOpacity=0.10")
    ng << "AppTheme.swift に sidebarSelectedOpacity = 0.10 が無い"
  end
  scheme = extract_var_body(theme_src, "preferredColorScheme")
  if scheme.nil?
    ng << "AppTheme.preferredColorScheme の本文を括弧対応で切り出せない"
  else
    unless compact(scheme).include?("background.relativeLuminance>=0.5")
      ng << "preferredColorScheme に background.relativeLuminance >= 0.5 が無い"
    end
  end
  from_palette = extract_func_body(theme_src, "fromPalette")
  if from_palette.nil?
    ng << "AppTheme.fromPalette の本文を括弧対応で切り出せない"
  else
    unless compact(from_palette).include?("background=bg.grayscale")
      ng << "fromPalette に background = bg.grayscale が無い"
    end
  end
end

[composer_path, grid_path].each do |path|
  next unless File.exist?(path)
  src_c = compact(strip_comments(File.read(path)))
  unless src_c.include?(".fill(DSColor.chatBackground)")
    ng << "#{path} に .fill(DSColor.chatBackground) が無い"
  end
  unless src_c.include?(".fill(Color.white.opacity(0.04))")
    ng << "#{path} に .fill(Color.white.opacity(0.04)) が無い"
  end
end

# --- 固定 SHA との差分（テーマ行・見本以外の欠落） ---
if baseline
  [
    tokens_path,
    theme_path,
    composer_path,
    grid_path,
  ].each do |path|
    unless git_unchanged?(baseline, path)
      ng << "#{path} が #{baseline} から差分あり"
    end
  end

  current = File.exist?(settings_path) ? File.read(settings_path) : nil
  previous = git_show(baseline, settings_path)
  if current.nil?
    ng << "#{settings_path} が存在しないため #{baseline} と比較できない"
  elsif previous.nil?
    ng << "git show #{baseline}:#{settings_path} に失敗"
  else
    cur_rest = strip_comments(current)
    prev_rest = strip_comments(previous)
    %w[ThemeRowView ThemeAppPreview ThemeSwatchStrip].each do |name|
      cur_rest = replace_struct(cur_rest, name, "/*stripped:#{name}*/")
      prev_rest = replace_struct(prev_rest, name, "/*stripped:#{name}*/")
    end
    unless compact(cur_rest) == compact(prev_rest)
      ng << "SettingsView.swift のテーマ行・見本以外が #{baseline} から差分あり"
    end
  end
end

if ng.empty?
  puts "task35-wiring: OK"
else
  ng.each { |m| puts "task35-wiring: NG #{m}" }
  exit 1
end
