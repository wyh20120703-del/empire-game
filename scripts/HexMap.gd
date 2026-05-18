class_name HexMap
extends Node2D

const HEX_SIZE = 55.0
const MAP_RADIUS = 11
var terrain_data: Dictionary = {}
var owner_data: Dictionary = {}
var capital_data: Dictionary = {}
var nation_colors: Dictionary = {}
var farm_data: Dictionary = {}
var mine_data: Dictionary = {}

func generate_map():
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.09

	for q in range(-MAP_RADIUS, MAP_RADIUS + 1):
		var r_min = max(-MAP_RADIUS, -q - MAP_RADIUS)
		var r_max = min(MAP_RADIUS, -q + MAP_RADIUS)
		for r in range(r_min, r_max + 1):
			var hex = Vector2i(q, r)
			var v = noise.get_noise_2d(q, r)
			var t: TerrainType.Type
			if   v < -0.40: t = TerrainType.Type.WATER    # 约 30%
			elif v < -0.20: t = TerrainType.Type.DESERT   # 约 10%
			elif v <  0.40: t = TerrainType.Type.PLAINS   # 约 30%
			else:            t = TerrainType.Type.MOUNTAIN  # 约 30%
			terrain_data[hex] = t
			owner_data[hex] = -1

func hex_to_pixel(hex: Vector2i) -> Vector2:
	var x = HEX_SIZE * (3.0 / 2.0 * hex.x)
	var y = HEX_SIZE * (sqrt(3) / 2.0 * hex.x + sqrt(3) * hex.y)
	return Vector2(x, y)

func pixel_to_hex(pixel: Vector2) -> Vector2i:
	var ax = pixel.x / HEX_SIZE
	var ay = pixel.y / HEX_SIZE
	var q = 2.0 / 3.0 * ax
	var r = -1.0 / 3.0 * ax + sqrt(3) / 3.0 * ay
	return _hex_round(q, r)

func _hex_round(q: float, r: float) -> Vector2i:
	var s = -q - r
	var rq = round(q); var rr = round(r); var rs = round(s)
	if abs(rq - q) > abs(rr - r) and abs(rq - q) > abs(rs - s):
		rq = -rr - rs
	elif abs(rr - r) > abs(rs - s):
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))

func _get_hex_vertices(center: Vector2) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in range(6):
		var a = PI / 3.0 * i
		pts.append(center + Vector2(HEX_SIZE * 0.94 * cos(a), HEX_SIZE * 0.94 * sin(a)))
	return pts

const _DIRS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

func _draw():
	# 第一遍：地形填充，混入国家颜色
	for hex in terrain_data:
		var center = hex_to_pixel(hex)
		var verts = _get_hex_vertices(center)
		var base_color = TerrainType.get_color(terrain_data[hex])
		var owner = owner_data.get(hex, -1)
		var final_color = base_color
		if owner >= 0 and owner in nation_colors:
			final_color = base_color.lerp(nation_colors[owner], 0.48)
		draw_polygon(verts, PackedColorArray([final_color]))
		draw_polyline(PackedVector2Array(Array(verts) + [verts[0]]), Color(0, 0, 0, 0.2), 1.0)

	# 第二遍：国家外围加粗彩色边界线
	for hex in owner_data:
		var owner = owner_data[hex]
		if owner < 0:
			continue
		var border_color = nation_colors.get(owner, Color.WHITE)
		var center = hex_to_pixel(hex)
		var verts = _get_hex_vertices(center)
		for i in range(6):
			var neighbor = hex + _DIRS[i]
			var neighbor_owner = owner_data.get(neighbor, -1)
			if neighbor_owner != owner:
				var v1 = verts[(i - 1 + 6) % 6]
				var v2 = verts[i]
				draw_line(v1, v2, Color.BLACK, 10.0)
				draw_line(v1, v2, border_color, 6.0)

	# 第三遍：首都画五角星
	for hex in capital_data:
		var center = hex_to_pixel(hex)
		var nid = capital_data[hex]
		var col = nation_colors.get(nid, Color.WHITE)
		_draw_star(center, 15.0, col)

	# 第四遍：农田
	for hex in farm_data:
		_draw_farm(hex_to_pixel(hex))

	# 第五遍：黄金矿洞
	for hex in mine_data:
		_draw_mine(hex_to_pixel(hex))

func _draw_farm(center: Vector2):
	var s = 8.0
	var g = 1.5
	draw_rect(Rect2(center.x - s - g, center.y - s - g, s, s), Color(0.15, 0.7, 0.1))
	draw_rect(Rect2(center.x + g,     center.y - s - g, s, s), Color(0.15, 0.7, 0.1))
	draw_rect(Rect2(center.x - s - g, center.y + g,     s, s), Color(0.15, 0.7, 0.1))
	draw_rect(Rect2(center.x + g,     center.y + g,     s, s), Color(0.15, 0.7, 0.1))
	draw_line(Vector2(center.x - s - g, center.y), Vector2(center.x + s + g, center.y), Color.BLACK, 1.0)
	draw_line(Vector2(center.x, center.y - s - g), Vector2(center.x, center.y + s + g), Color.BLACK, 1.0)

func _draw_mine(center: Vector2):
	var s = 11.0
	var pts = PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(s * 0.7, 0),
		center + Vector2(0, s),
		center + Vector2(-s * 0.7, 0)
	])
	draw_polygon(pts, PackedColorArray([Color(1.0, 0.82, 0.0, 0.92)]))
	draw_polyline(PackedVector2Array(Array(pts) + [pts[0]]), Color.BLACK, 1.5)
	draw_circle(center, 2.5, Color.BLACK)

func transfer_buildings(from_id: int, to_id: int):
	for hex in farm_data:
		if farm_data[hex] == from_id:
			farm_data[hex] = to_id
	for hex in mine_data:
		if mine_data[hex] == from_id:
			mine_data[hex] = to_id
	queue_redraw()

func _draw_star(center: Vector2, outer_r: float, color: Color):
	var pts = PackedVector2Array()
	for i in range(10):
		var angle = -PI / 2.0 + i * (PI / 5.0)
		var r = outer_r if i % 2 == 0 else outer_r * 0.42
		pts.append(center + Vector2(cos(angle) * r, sin(angle) * r))
	# 黑色描边
	var outline = PackedVector2Array()
	for p in pts:
		outline.append(p + Vector2(0, 1))
	draw_polygon(pts, PackedColorArray([Color.BLACK]))
	# 缩小一点画国家颜色
	var inner_pts = PackedVector2Array()
	for i in range(10):
		var angle = -PI / 2.0 + i * (PI / 5.0)
		var r = (outer_r - 1.5) if i % 2 == 0 else (outer_r * 0.42 - 1.0)
		inner_pts.append(center + Vector2(cos(angle) * r, sin(angle) * r))
	draw_polygon(inner_pts, PackedColorArray([color]))

func get_neighbors(hex: Vector2i) -> Array[Vector2i]:
	var dirs = [Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1),
				Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,1)]
	var result: Array[Vector2i] = []
	for d in dirs:
		var nb = hex + d
		if terrain_data.has(nb):
			result.append(nb)
	return result

func is_passable(hex: Vector2i) -> bool:
	if not terrain_data.has(hex):
		return false
	return TerrainType.get_move_cost(terrain_data[hex]) < 999

func claim_territory(hex: Vector2i, nation_id: int):
	if terrain_data.has(hex) and TerrainType.get_move_cost(terrain_data[hex]) < 999:
		owner_data[hex] = nation_id
		queue_redraw()

func mark_capital(hex: Vector2i, nation_id: int):
	capital_data[hex] = nation_id
	queue_redraw()

func remove_capital(hex: Vector2i):
	capital_data.erase(hex)
	queue_redraw()

func is_capital(hex: Vector2i) -> bool:
	return capital_data.has(hex)

func get_capital_owner(hex: Vector2i) -> int:
	return capital_data.get(hex, -1)

func get_tile_owner(hex: Vector2i) -> int:
	return owner_data.get(hex, -1)

func get_terrain(hex: Vector2i) -> TerrainType.Type:
	return terrain_data.get(hex, TerrainType.Type.PLAINS)

func transfer_all_tiles(from_id: int, to_id: int):
	for hex in owner_data:
		if owner_data[hex] == from_id:
			owner_data[hex] = to_id
	queue_redraw()

func get_nation_tiles(nation_id: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for hex in owner_data:
		if owner_data[hex] == nation_id:
			tiles.append(hex)
	return tiles

func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var d = b - a
	return (abs(d.x) + abs(d.y) + abs(d.x + d.y)) / 2

func get_spread_positions(count: int) -> Array[Vector2i]:
	var land: Array[Vector2i] = []
	for hex in terrain_data:
		if terrain_data[hex] == TerrainType.Type.PLAINS:
			land.append(hex)
	# 从大到小尝试最小间距，确保能放下所有国家
	for min_dist in [8, 6, 5, 4, 3]:
		var candidates = land.duplicate()
		candidates.shuffle()
		var positions: Array[Vector2i] = []
		for tile in candidates:
			var ok = true
			for p in positions:
				if hex_distance(tile, p) < min_dist:
					ok = false; break
			if ok:
				positions.append(tile)
				if positions.size() >= count:
					return positions
	# 保底：随机取草地
	land.shuffle()
	return land.slice(0, count)
