class_name TerrainType

enum Type { PLAINS, MOUNTAIN, WATER, DESERT }

static func get_resource_bonus(t: Type) -> Dictionary:
	match t:
		Type.PLAINS:   return {"food": 2, "prod": 1, "gold": 1}
		Type.MOUNTAIN: return {"food": 0, "prod": 0, "gold": 0}
		Type.WATER:    return {"food": 0, "prod": 0, "gold": 0}
		Type.DESERT:   return {"food": 0, "prod": 0, "gold": 1}
	return {"food": 0, "prod": 0, "gold": 0}

static func get_move_cost(t: Type) -> int:
	match t:
		Type.MOUNTAIN: return 999
		Type.WATER:    return 999
		_:             return 1

static func get_terrain_name(t: Type) -> String:
	match t:
		Type.PLAINS:   return "草地"
		Type.MOUNTAIN: return "山脉"
		Type.WATER:    return "水路"
		Type.DESERT:   return "沙漠"
	return "未知"

static func get_color(t: Type) -> Color:
	match t:
		Type.PLAINS:   return Color(0.56, 0.74, 0.35)
		Type.MOUNTAIN: return Color(0.55, 0.38, 0.18)
		Type.WATER:    return Color(0.2,  0.42, 0.85)
		Type.DESERT:   return Color(0.87, 0.76, 0.42)
	return Color.WHITE
