class_name MilitaryCamp
extends Node2D

var nation_id: int
var hex_pos: Vector2i
var hp: int = 2000
var max_hp: int = 2000
var attack: int = 60
var nation_color: Color = Color.WHITE

const HEX_SIZE = 55.0

func _draw():
	var s = 14.0
	# 营地底座
	draw_rect(Rect2(-s, -s * 0.4, s * 2, s * 1.2), nation_color.darkened(0.2))
	draw_rect(Rect2(-s, -s * 0.4, s * 2, s * 1.2), Color.BLACK, false, 2.0)
	# 帐篷顶（三角形）
	var roof = PackedVector2Array([
		Vector2(-s - 2, -s * 0.4),
		Vector2(0, -s * 1.6),
		Vector2(s + 2, -s * 0.4)
	])
	draw_colored_polygon(roof, nation_color)
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[0]]), Color.BLACK, 2.0)
	# 旗杆 + 旗
	draw_line(Vector2(0, -s * 1.6), Vector2(0, -s * 2.4), Color.BLACK, 2.0)
	var flag = PackedVector2Array([
		Vector2(0, -s * 2.4),
		Vector2(s * 0.65, -s * 2.05),
		Vector2(0, -s * 1.6)
	])
	draw_colored_polygon(flag, nation_color.lightened(0.4))
	# 血条（蓝色）
	var bar_y = s * 0.95
	draw_rect(Rect2(-16, bar_y, 32, 5), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(-16, bar_y, 32.0 * hp / max_hp, 5), Color(0.2, 0.6, 1.0))

func set_hex_pos(hex: Vector2i):
	hex_pos = hex
	position = _hex_to_pixel(hex)

func _hex_to_pixel(hex: Vector2i) -> Vector2:
	var x = HEX_SIZE * (3.0 / 2.0 * hex.x)
	var y = HEX_SIZE * (sqrt(3) / 2.0 * hex.x + sqrt(3) * hex.y)
	return Vector2(x, y)

func take_damage(amount: int) -> bool:
	hp -= amount
	hp = max(0, hp)
	queue_redraw()
	return hp <= 0

func receive_hp(amount: int):
	hp = min(hp + amount, max_hp)
	queue_redraw()
