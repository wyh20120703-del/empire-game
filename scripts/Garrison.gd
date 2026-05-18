class_name Garrison
extends Node2D

var nation_id: int
var hex_pos: Vector2i
var hp: int = 1200
var max_hp: int = 1200
var attack: int = 80
var nation_color: Color = Color.WHITE
var is_capital: bool = false

const HEX_SIZE = 55.0

func _draw():
	if is_capital:
		# 首都只显示血条（五角星由 HexMap 绘制）
		draw_rect(Rect2(-20, 18, 40, 7), Color.RED)
		draw_rect(Rect2(-20, 18, 40.0 * hp / max_hp, 7), Color.GREEN)
		return

	var s = 13.0
	# 城墙主体
	draw_rect(Rect2(-s, -s * 0.6, s * 2, s * 1.6), nation_color)
	draw_rect(Rect2(-s, -s * 0.6, s * 2, s * 1.6), Color.BLACK, false, 2.0)
	# 城垛（顶部凸起）
	for i in range(3):
		var bx = -s + i * s
		draw_rect(Rect2(bx, -s - 7, s * 0.7, 8), nation_color)
		draw_rect(Rect2(bx, -s - 7, s * 0.7, 8), Color.BLACK, false, 1.5)
	# 城门
	draw_rect(Rect2(-4, s * 0.2, 8, s * 0.8), Color(0.1, 0.05, 0.0))
	# 血条
	var bar_y = -s - 16.0
	draw_rect(Rect2(-16, bar_y, 32, 5), Color.RED)
	draw_rect(Rect2(-16, bar_y, 32.0 * hp / max_hp, 5), Color.GREEN)

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
