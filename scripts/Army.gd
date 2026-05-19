class_name Army
extends Node2D

var nation_id: int
var hex_pos: Vector2i
var hp: int = 1000
var max_hp: int = 1000
var attack: int = 350
var nation_color: Color = Color.WHITE
var move_cooldown: float = 0.0
var stamina: int = 4
var max_stamina: int = 4
var stamina_regen_timer: float = 0.0
var deploy_target: Vector2i = Vector2i(-999, -999)

const HEX_SIZE = 55.0

func _draw():
	var s = 11.0
	# 黑色粗描边
	draw_line(Vector2(-s, -s), Vector2(s,  s), Color.BLACK, 6.0)
	draw_line(Vector2( s, -s), Vector2(-s, s), Color.BLACK, 6.0)
	# 国家颜色剑身
	draw_line(Vector2(-s, -s), Vector2(s,  s), nation_color, 3.5)
	draw_line(Vector2( s, -s), Vector2(-s, s), nation_color, 3.5)
	# 护手（白色横线，靠近剑柄端）
	var g = s * 0.45
	draw_line(Vector2(-g - 4,  g), Vector2(-g + 4,  g), Color.WHITE, 2.5)  # 左下剑护手
	draw_line(Vector2( g, -g - 4), Vector2( g, -g + 4), Color.WHITE, 2.5)  # 右上剑护手
	# 血条
	draw_rect(Rect2(-13, -22, 26, 5), Color.RED)
	draw_rect(Rect2(-13, -22, 26.0 * hp / max_hp, 5), Color.GREEN)

func set_hex_pos(hex: Vector2i):
	hex_pos = hex
	position = _hex_to_pixel(hex)

func move_to(hex: Vector2i):
	hex_pos = hex
	var tween = create_tween()
	tween.tween_property(self, "position", _hex_to_pixel(hex), 0.25)

func _hex_to_pixel(hex: Vector2i) -> Vector2:
	var x = HEX_SIZE * (3.0 / 2.0 * hex.x)
	var y = HEX_SIZE * (sqrt(3) / 2.0 * hex.x + sqrt(3) * hex.y)
	return Vector2(x, y)

func take_damage(amount: int) -> bool:
	hp -= amount
	queue_redraw()
	return hp <= 0
