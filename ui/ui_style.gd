class_name UiStyle
extends RefCounted

## 界面样式集中在这里，避免每个面板各写一份 StyleBoxFlat。
## main.gd 和屋子/首页共用同一套圆角、描边、配色。

static func panel(alpha: float = 0.92, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UnitData.BG.r, UnitData.BG.g, UnitData.BG.b, alpha)
	sb.border_color = Color(UnitData.WOOD.r, UnitData.WOOD.g, UnitData.WOOD.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


static func button(bg: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


static func apply_button(b: Button, accent: Color = UnitData.WOOD) -> void:
	b.add_theme_stylebox_override("normal", button(Color(0.10, 0.09, 0.08, 0.95), accent))
	b.add_theme_stylebox_override("hover", button(Color(0.20, 0.17, 0.13, 0.98), accent))
	b.add_theme_stylebox_override("pressed", button(Color(0.07, 0.06, 0.05, 1.0), accent))
	b.add_theme_stylebox_override("disabled",
		button(Color(0.11, 0.11, 0.11, 0.55), Color(0.4, 0.4, 0.4, 0.35)))
	b.add_theme_color_override("font_color", UnitData.PAPER)
	b.add_theme_color_override("font_disabled_color", Color(0.62, 0.59, 0.54))
	b.add_theme_color_override("font_hover_color", Color.WHITE)


static func label(text: String, size: int = 16, col: Color = UnitData.PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
