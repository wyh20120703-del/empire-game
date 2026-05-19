class_name GameManager
extends Node

signal nation_resource_updated(nation_id: int)
signal nation_defeated(nation_id: int)
signal game_over(winner_name: String)
signal alliance_request_received(from_id: int)
signal alliance_changed()

var PLAYER_ID: int = 0
const RESOURCE_TICK = 3.0
const AI_TICK = 5.0
const REINFORCE_TICK = 4.0
const GENERAL_TICK = 6.0

var hex_map: HexMap
var nations: Array[Nation] = []
var armies: Array = []
var garrisons: Array = []
var resource_timer: float = 0.0
var ai_timer: float = 0.0
var reinforce_timer: float = 0.0
var general_timer: float = 0.0
var game_active: bool = false
var selected_army = null
var _army_prev_pos: Dictionary = {}
var alliances: Array = []          # [[id,id,...], ...]
var pending_requests: Array = []   # [{from_id, to_id}, ...]

var camps: Array = []

var net_mode: bool = false
var is_net_authority: bool = true
var _net_timer: float = 0.0
const _NET_INTERVAL := 1.0
var _territory_dirty: bool = false

var _peer_to_nation: Dictionary = {}
var _player_nation_ids: Array = []
var nation_count: int = 7
signal game_started

var _nation_names = ["秦国", "楚国", "赵国", "魏国", "燕国", "韩国", "齐国"]
var _nation_colors = [
	Color(0.9, 0.2, 0.2),
	Color(0.2, 0.5, 0.9),
	Color(0.2, 0.8, 0.3),
	Color(0.9, 0.8, 0.1),
	Color(0.75, 0.3, 0.9),
	Color(0.9, 0.52, 0.1),
	Color(0.1, 0.85, 0.85),
]

func initialize(map: HexMap, count: int = 7):
	hex_map = map
	hex_map.generate_map()
	_spawn_nations(count)
	game_active = true

func _spawn_nations(count: int):
	var positions = hex_map.get_spread_positions(count)
	for i in range(min(count, positions.size())):
		var n = Nation.new()
		n.id = i
		n.nation_name = _nation_names[i]
		n.color = _nation_colors[i]
		n.capital_pos = positions[i]
		n.population = 200
		match i:
			0: n.food = 200; n.production = 120; n.gold = 50
			1: n.food = 150; n.production = 200; n.gold = 30
			2: n.food = 180; n.production = 100; n.gold = 120
			3: n.food = 220; n.production = 150; n.gold = 40
			4: n.food = 160; n.production = 130; n.gold = 80
			5: n.food = 140; n.production = 180; n.gold = 60
			6: n.food = 190; n.production = 110; n.gold = 100
		hex_map.nation_colors[i] = _nation_colors[i]
		hex_map.mark_capital(positions[i], i)
		_claim_bfs(positions[i], i, 7)
		# 首都要塞：2000 血，不可绕过
		var cap_g = _create_garrison(i, positions[i])
		cap_g.is_capital = true
		cap_g.hp = 2100
		cap_g.max_hp = 2100
		cap_g.attack = 120
		# 初始军队集中营（在首都旁）
		var camp_pos = _find_adjacent_camp_pos(positions[i])
		if camp_pos != Vector2i(-999, -999):
			_create_camp(i, camp_pos)
			n.camps_built += 1
		nations.append(n)

# ── 军队集中营 ─────────────────────────────────────────

func _create_camp(nation_id: int, hex: Vector2i) -> MilitaryCamp:
	var c = MilitaryCamp.new()
	c.nation_id = nation_id
	c.nation_color = _nation_colors[nation_id]
	c.set_hex_pos(hex)
	hex_map.add_child(c)
	camps.append(c)
	return c

func _get_camp_at(hex: Vector2i):
	for c in camps:
		if is_instance_valid(c) and c.hex_pos == hex:
			return c
	return null

func _get_camps_of(nation_id: int) -> Array:
	var result = []
	for c in camps:
		if is_instance_valid(c) and c.nation_id == nation_id:
			result.append(c)
	return result

func _get_nearest_camp(nation_id: int, target_hex: Vector2i):
	var nearest = null
	var min_dist = 999999
	for c in _get_camps_of(nation_id):
		var d = hex_map.hex_distance(c.hex_pos, target_hex)
		if d < min_dist:
			min_dist = d
			nearest = c
	return nearest

func _find_adjacent_camp_pos(capital_pos: Vector2i) -> Vector2i:
	for nb in hex_map.get_neighbors(capital_pos):
		if hex_map.is_passable(nb) and _get_garrison_at(nb) == null and _get_camp_at(nb) == null:
			return nb
	return Vector2i(-999, -999)

func has_camp_at(hex: Vector2i) -> bool:
	return _get_camp_at(hex) != null

func can_build_camp_at(nation_id: int, hex: Vector2i) -> bool:
	var n = _get_nation(nation_id)
	if n == null or n.camps_built >= Nation.MAX_CAMPS: return false
	if hex_map.get_tile_owner(hex) != nation_id: return false
	var t = hex_map.get_terrain(hex)
	if t != TerrainType.Type.PLAINS and t != TerrainType.Type.DESERT: return false
	if _get_garrison_at(hex) != null: return false
	if _get_camp_at(hex) != null: return false
	if hex in hex_map.farm_data or hex in hex_map.mine_data: return false
	return true

func try_build_camp(nation_id: int, hex: Vector2i):
	var n = _get_nation(nation_id)
	if n == null or not can_build_camp_at(nation_id, hex): return null
	if n.production < Nation.CAMP_COST_PROD: return null
	n.production -= Nation.CAMP_COST_PROD
	n.camps_built += 1
	nation_resource_updated.emit(nation_id)
	return _create_camp(nation_id, hex)

func try_demolish_camp(nation_id: int, hex: Vector2i) -> bool:
	var c = _get_camp_at(hex)
	if c == null or c.nation_id != nation_id: return false
	var n = _get_nation(nation_id)
	if n:
		n.production += 30.0
		n.camps_built -= 1
	camps.erase(c)
	c.queue_free()
	nation_resource_updated.emit(nation_id)
	return true

func _resolve_army_vs_camp(army, camp, camp_hex: Vector2i):
	var camp_dead = camp.take_damage(army.attack)
	var army_dead = army.take_damage(camp.attack)
	if camp_dead:
		var owner = camp.nation_id
		camps.erase(camp)
		camp.queue_free()
		var n = _get_nation(owner)
		if n: n.camps_built -= 1
		if not army_dead:
			army.move_to(camp_hex)
			_claim_tile(camp_hex, army.nation_id)
	if army_dead:
		_remove_army(army)

func _claim_bfs(start: Vector2i, nation_id: int, count: int):
	var claimed = 0
	var plains_q: Array[Vector2i] = []
	var other_q: Array[Vector2i] = []
	var visited = {start: true}
	_claim_tile(start, nation_id)
	claimed += 1
	for nb in hex_map.get_neighbors(start):
		visited[nb] = true
		if hex_map.is_passable(nb):
			if hex_map.get_terrain(nb) == TerrainType.Type.PLAINS:
				plains_q.append(nb)
			else:
				other_q.append(nb)
	while claimed < count:
		var current: Vector2i
		if _count_plains(nation_id) < 3 and plains_q.size() > 0:
			current = plains_q.pop_front()
		elif plains_q.size() > 0:
			current = plains_q.pop_front()
		elif other_q.size() > 0:
			current = other_q.pop_front()
		else:
			break
		_claim_tile(current, nation_id)
		claimed += 1
		for nb in hex_map.get_neighbors(current):
			if nb in visited:
				continue
			visited[nb] = true
			if hex_map.is_passable(nb):
				if hex_map.get_terrain(nb) == TerrainType.Type.PLAINS:
					plains_q.append(nb)
				else:
					other_q.append(nb)

func _count_plains(nation_id: int) -> int:
	var count = 0
	for hex in hex_map.get_nation_tiles(nation_id):
		if hex_map.get_terrain(hex) == TerrainType.Type.PLAINS:
			count += 1
	return count

func _process(delta: float):
	if not game_active:
		return
	for a in armies:
		if not is_instance_valid(a): continue
		if a.move_cooldown > 0.0:
			a.move_cooldown -= delta
		if a.stamina < a.max_stamina:
			a.stamina_regen_timer += delta
			if a.stamina_regen_timer >= 2.0:
				a.stamina_regen_timer = 0.0
				a.stamina += 1
	if not is_net_authority:
		return
	resource_timer += delta
	if resource_timer >= RESOURCE_TICK:
		resource_timer = 0.0
		_update_resources()
	ai_timer += delta
	if ai_timer >= AI_TICK:
		ai_timer = 0.0
		_run_ai()
	reinforce_timer += delta
	if reinforce_timer >= REINFORCE_TICK:
		reinforce_timer = 0.0
		_auto_reinforce()
	general_timer += delta
	if general_timer >= GENERAL_TICK:
		general_timer = 0.0
		_run_generals()
	if net_mode:
		_net_timer += delta
		if _net_timer >= _NET_INTERVAL:
			_net_timer = 0.0
			_broadcast_state()

func _update_resources():
	for n in nations:
		if n.is_defeated:
			continue
		var farm_food = 0.0
		var farm_prod = 0.0
		var mine_gold = 0.0
		var mine_food_cost = 0.0
		for hex in hex_map.farm_data:
			if hex_map.farm_data[hex] == n.id:
				var terrain_mult = 0.5 if hex_map.get_terrain(hex) == TerrainType.Type.DESERT else 1.0
				farm_food += 10.0 * terrain_mult
				farm_prod += 10.0 * terrain_mult
		for hex in hex_map.mine_data:
			if hex_map.mine_data[hex] == n.id:
				var terrain_mult = 1.5 if hex_map.get_terrain(hex) == TerrainType.Type.DESERT else 1.0
				mine_gold += 20.0 * terrain_mult
				mine_food_cost += 10.0
		var army_count = 0
		var garrison_count = 0
		for a in armies:
			if a.nation_id == n.id:
				army_count += 1
		for g in garrisons:
			if g.nation_id == n.id and not g.is_capital:
				garrison_count += 1
		var upkeep_food = army_count * 3.0 + garrison_count * 2.0
		var upkeep_prod = army_count * 3.0 + garrison_count * 2.0
		var mult = n.minister_multiplier()
		n.food       += farm_food * mult
		n.production += farm_prod * mult
		n.gold       += mine_gold * mult
		n.food       -= mine_food_cost + upkeep_food
		n.production -= upkeep_prod
		n.food       = max(0, n.food)
		n.production = max(0, n.production)
		nation_resource_updated.emit(n.id)

func _claim_tile(hex: Vector2i, nation_id: int):
	var old_owner = hex_map.get_tile_owner(hex)
	hex_map.claim_territory(hex, nation_id)
	if old_owner != nation_id:
		_territory_dirty = true
		var n = _get_nation(nation_id)
		if n:
			n.population += 10
		if hex in hex_map.farm_data and hex_map.farm_data[hex] == old_owner:
			hex_map.farm_data[hex] = nation_id
		if hex in hex_map.mine_data and hex_map.mine_data[hex] == old_owner:
			hex_map.mine_data[hex] = nation_id

# ── 部署地（Garrison）系统 ──────────────────────────────

func try_build_garrison(nation_id: int, hex: Vector2i):
	var n = _get_nation(nation_id)
	if n == null or n.production < 30:
		return null
	if not can_build_garrison_at(nation_id, hex):
		return null
	n.production -= 30
	n.garrisons_built += 1
	return _create_garrison(nation_id, hex)

func can_relocate_capital_to(nation_id: int, hex: Vector2i) -> bool:
	var n = _get_nation(nation_id)
	if n == null or n.gold < 150:
		return false
	return hex_map.get_tile_owner(hex) == nation_id and \
		   hex_map.get_terrain(hex) == TerrainType.Type.PLAINS and \
		   hex != n.capital_pos

func try_relocate_capital(nation_id: int, new_hex: Vector2i) -> bool:
	var n = _get_nation(nation_id)
	if n == null or not can_relocate_capital_to(nation_id, new_hex):
		return false
	n.gold -= 150
	# 旧首都要塞降级为普通部署地
	var old_g = _get_garrison_at(n.capital_pos)
	if old_g != null:
		old_g.is_capital = false
		old_g.max_hp = 1200
		old_g.hp = min(old_g.hp, old_g.max_hp)
		old_g.attack = 80
		old_g.queue_redraw()
	hex_map.remove_capital(n.capital_pos)
	# 新首都
	n.capital_pos = new_hex
	hex_map.mark_capital(new_hex, nation_id)
	var new_g = _get_garrison_at(new_hex)
	if new_g != null:
		new_g.is_capital = true
		new_g.max_hp = 2100
		new_g.hp = min(new_g.hp + 500, new_g.max_hp)
		new_g.attack = 120
		new_g.queue_redraw()
	else:
		var cap_g = _create_garrison(nation_id, new_hex)
		cap_g.is_capital = true
		cap_g.hp = 2100
		cap_g.max_hp = 2100
		cap_g.attack = 120
	_territory_dirty = true
	nation_resource_updated.emit(nation_id)
	return true

func can_build_garrison_at(nation_id: int, hex: Vector2i) -> bool:
	if hex_map.get_tile_owner(hex) != nation_id:
		return false
	var t = hex_map.get_terrain(hex)
	if t != TerrainType.Type.PLAINS and t != TerrainType.Type.DESERT:
		return false
	if _get_garrison_at(hex) != null or _get_camp_at(hex) != null:
		return false
	if hex in hex_map.farm_data or hex in hex_map.mine_data:
		return false
	return true

func can_build_farm_at(nation_id: int, hex: Vector2i) -> bool:
	if hex_map.get_tile_owner(hex) != nation_id: return false
	var t = hex_map.get_terrain(hex)
	if t != TerrainType.Type.PLAINS and t != TerrainType.Type.DESERT: return false
	if _get_garrison_at(hex) != null or _get_camp_at(hex) != null: return false
	if hex in hex_map.farm_data or hex in hex_map.mine_data: return false
	return true

func can_build_mine_at(nation_id: int, hex: Vector2i) -> bool:
	if hex_map.get_tile_owner(hex) != nation_id: return false
	var t = hex_map.get_terrain(hex)
	if t != TerrainType.Type.PLAINS and t != TerrainType.Type.DESERT: return false
	if _get_garrison_at(hex) != null or _get_camp_at(hex) != null: return false
	if hex in hex_map.farm_data or hex in hex_map.mine_data: return false
	return true

func try_build_farm(nation_id: int, hex: Vector2i) -> bool:
	var n = _get_nation(nation_id)
	if n == null or n.population < 10: return false
	if not can_build_farm_at(nation_id, hex): return false
	n.population -= 10
	n.farms_built += 1
	hex_map.farm_data[hex] = nation_id
	hex_map.queue_redraw()
	_territory_dirty = true
	nation_resource_updated.emit(nation_id)
	return true

func try_build_mine(nation_id: int, hex: Vector2i) -> bool:
	var n = _get_nation(nation_id)
	if n == null or n.population < 10: return false
	if not can_build_mine_at(nation_id, hex): return false
	n.population -= 10
	n.mines_built += 1
	hex_map.mine_data[hex] = nation_id
	hex_map.queue_redraw()
	_territory_dirty = true
	nation_resource_updated.emit(nation_id)
	return true

func _create_garrison(nation_id: int, hex: Vector2i):
	var g = Garrison.new()
	g.nation_id = nation_id
	g.nation_color = _nation_colors[nation_id]
	if hex_map.get_terrain(hex) == TerrainType.Type.DESERT:
		g.hp = 600
		g.max_hp = 600
	g.set_hex_pos(hex)
	hex_map.add_child(g)
	garrisons.append(g)
	return g

func _get_garrison_at(hex: Vector2i):
	for g in garrisons:
		if g.hex_pos == hex:
			return g
	return null

func _get_army_at(hex: Vector2i):
	for a in armies:
		if a.hex_pos == hex:
			return a
	return null

func has_garrison_at(hex: Vector2i) -> bool:
	return _get_garrison_at(hex) != null

func has_army_at(hex: Vector2i) -> bool:
	return _get_army_at(hex) != null

# 自动补充：周围友军或友方部署地补血到血量低的部署地
func _auto_reinforce():
	for g in garrisons.duplicate():
		if not is_instance_valid(g):
			continue
		if g.hp >= g.max_hp:
			continue
		for nb in hex_map.get_neighbors(g.hex_pos):
			if g.hp >= g.max_hp:
				break
			# 友军补充
			for army in armies.duplicate():
				if not is_instance_valid(army):
					continue
				if army.hex_pos == nb and army.nation_id == g.nation_id:
					var transfer = min(army.hp, g.max_hp - g.hp)
					g.receive_hp(transfer)
					army.hp -= transfer
					if army.hp <= 0:
						_remove_army(army)
					else:
						army.queue_redraw()
					break
			# 友方部署地互相补充
			var neighbor_g = _get_garrison_at(nb)
			if neighbor_g != null and is_instance_valid(neighbor_g) and \
			   neighbor_g.nation_id == g.nation_id and neighbor_g.hp > 0:
				var transfer = min(neighbor_g.hp, g.max_hp - g.hp)
				g.receive_hp(transfer)
				neighbor_g.hp -= transfer
				if neighbor_g.hp <= 0:
					garrisons.erase(neighbor_g)
					neighbor_g.queue_free()
				else:
					neighbor_g.queue_redraw()

# ── 军队 ──────────────────────────────────────────────

func try_build_army(nation_id: int, deploy_hex: Vector2i = Vector2i(-999, -999)):
	var n = _get_nation(nation_id)
	if n == null or not n.can_build_army():
		return null
	# 确定目标格（用于找最近集中营）
	var target = n.capital_pos
	if deploy_hex != Vector2i(-999, -999):
		var deploy_t = hex_map.get_terrain(deploy_hex)
		if hex_map.get_tile_owner(deploy_hex) == nation_id and \
		   (deploy_t == TerrainType.Type.PLAINS or deploy_t == TerrainType.Type.DESERT):
			target = deploy_hex
	# 从最近的军队集中营出发
	var nearest_camp = _get_nearest_camp(nation_id, target)
	if nearest_camp == null:
		return null
	var spawn_hex = nearest_camp.hex_pos
	# 集中营被占则找旁边空格
	if _get_army_at(spawn_hex) != null:
		var found = false
		for nb in hex_map.get_neighbors(spawn_hex):
			if hex_map.is_passable(nb) and hex_map.get_tile_owner(nb) == nation_id and _get_army_at(nb) == null:
				spawn_hex = nb
				found = true
				break
		if not found:
			return null
	n.spend_for_army()
	n.armies_built += 1
	return _create_army(nation_id, spawn_hex)

func convert_food_to_production(nation_id: int) -> bool:
	var n = _get_nation(nation_id)
	if n == null or n.food < 20:
		return false
	n.food -= 20
	n.production += 10
	nation_resource_updated.emit(nation_id)
	return true

func auto_build_armies(nation_id: int) -> int:
	var n = _get_nation(nation_id)
	if n == null:
		return 0
	var count = 0
	for tile in hex_map.get_nation_tiles(nation_id):
		if not n.can_build_army():
			break
		if can_deploy_at(nation_id, tile):
			if try_build_army(nation_id, tile) != null:
				count += 1
	return count

func auto_build_garrisons(nation_id: int) -> int:
	var count = 0
	for tile in hex_map.get_nation_tiles(nation_id):
		var n = _get_nation(nation_id)
		if n == null or n.production < 30:
			break
		if can_build_garrison_at(nation_id, tile):
			if try_build_garrison(nation_id, tile) != null:
				count += 1
	return count

func can_deploy_at(nation_id: int, hex: Vector2i) -> bool:
	var n = _get_nation(nation_id)
	if n != null and hex == n.capital_pos:
		return false
	var t = hex_map.get_terrain(hex)
	return hex_map.get_tile_owner(hex) == nation_id and \
		   (t == TerrainType.Type.PLAINS or t == TerrainType.Type.DESERT) and \
		   _get_army_at(hex) == null

func _create_army(nation_id: int, hex: Vector2i):
	var army = Army.new()
	army.nation_id = nation_id
	army.nation_color = _nation_colors[nation_id]
	army.set_hex_pos(hex)
	hex_map.add_child(army)
	armies.append(army)
	var n = _get_nation(nation_id)
	if n:
		n.armies.append(army)
	return army

func try_move_army(army, target_hex: Vector2i) -> bool:
	if army.move_cooldown > 0.0:
		return false
	if army.stamina <= 0:
		return false
	if not hex_map.is_passable(target_hex):
		return false
	if not target_hex in hex_map.get_neighbors(army.hex_pos):
		return false

	var target_owner = hex_map.get_tile_owner(target_hex)

	# 目标格已有己方或盟友军队：禁止移入
	var existing_army = _get_army_at(target_hex)
	if existing_army != null and (existing_army.nation_id == army.nation_id or are_allied(army.nation_id, existing_army.nation_id)):
		return false

	# 敌方部署地：就地攻击；盟友/己方部署地直接通过
	var enemy_garrison = _get_garrison_at(target_hex)
	if enemy_garrison != null and enemy_garrison.nation_id != army.nation_id and not are_allied(army.nation_id, enemy_garrison.nation_id):
		_resolve_army_vs_garrison(army, enemy_garrison, target_hex)
		hex_map.queue_redraw()
		return true

	# 敌方集中营：就地攻击；盟友/己方集中营直接通过
	var camp_at = _get_camp_at(target_hex)
	if camp_at != null and camp_at.nation_id != army.nation_id and not are_allied(army.nation_id, camp_at.nation_id):
		_resolve_army_vs_camp(army, camp_at, target_hex)
		hex_map.queue_redraw()
		return true

	# 无阻碍：正常移动
	army.move_to(target_hex)
	army.move_cooldown = 0.5
	army.stamina -= 1
	army.stamina_regen_timer = 0.0

	# 盟友领土：经过但不占领
	if target_owner >= 0 and target_owner != army.nation_id and are_allied(army.nation_id, target_owner):
		hex_map.queue_redraw()
		return true

	_claim_tile(target_hex, army.nation_id)
	_resolve_combat(target_hex, army)
	hex_map.queue_redraw()
	return true

func _resolve_army_vs_garrison(army, garrison, garrison_hex: Vector2i):
	var defender_id = garrison.nation_id
	var attacker_dmg_mult = 1.0

	var friendly_count = 0
	var enemy_count = 0
	for nb in hex_map.get_neighbors(garrison_hex):
		var hf = false; var he = false
		for a in armies:
			if a.hex_pos == nb:
				if a.nation_id == defender_id: hf = true
				elif a.nation_id == army.nation_id: he = true
		if hf: friendly_count += 1
		if he: enemy_count += 1

	if friendly_count > enemy_count:
		attacker_dmg_mult = 1.0 / 2.0
	elif friendly_count == enemy_count:
		attacker_dmg_mult = 1.0 / 1.5
	else:
		attacker_dmg_mult = 1.0 / 0.75

	var garrison_dead = garrison.take_damage(int(army.attack * attacker_dmg_mult))
	var army_dead = army.take_damage(garrison.attack)

	if garrison_dead:
		var was_capital = garrison.is_capital
		var defeated_nation = garrison.nation_id
		garrisons.erase(garrison)
		garrison.queue_free()
		if was_capital:
			hex_map.remove_capital(garrison_hex)
			_defeat_nation(defeated_nation, army.nation_id)
		# 部署地被消灭后，军队才移入
		if not army_dead:
			army.move_to(garrison_hex)
			_claim_tile(garrison_hex, army.nation_id)

	if army_dead:
		_remove_army(army)

func _resolve_combat(hex: Vector2i, attacker):
	var enemies = []
	for other in armies:
		if other != attacker and other.hex_pos == hex and other.nation_id != attacker.nation_id \
				and not are_allied(attacker.nation_id, other.nation_id):
			enemies.append(other)
	if enemies.size() == 0:
		return

	for enemy in enemies:
		if not is_instance_valid(attacker): break
		var a_hp = attacker.hp
		var e_hp = enemy.hp
		if a_hp > e_hp:
			attacker.hp = a_hp - e_hp
			attacker.queue_redraw()
			_remove_army(enemy)
		elif e_hp > a_hp:
			enemy.hp = e_hp - a_hp
			enemy.queue_redraw()
			_remove_army(attacker)
		else:
			_remove_army(enemy)
			_remove_army(attacker)

func _remove_army(army):
	if not army in armies:
		return
	armies.erase(army)
	var n = _get_nation(army.nation_id)
	if n:
		n.armies.erase(army)
	if selected_army == army:
		selected_army = null
	_army_prev_pos.erase(army.get_instance_id())
	army.queue_free()

func try_disband_army(nation_id: int, hex: Vector2i) -> bool:
	var army = _get_army_at(hex)
	if army == null or army.nation_id != nation_id:
		return false
	var n = _get_nation(nation_id)
	if n:
		n.production += Nation.ARMY_COST_PROD
		n.food += Nation.ARMY_COST_FOOD
	_remove_army(army)
	nation_resource_updated.emit(nation_id)
	return true

func try_demolish_garrison(nation_id: int, hex: Vector2i) -> bool:
	var g = _get_garrison_at(hex)
	if g == null or g.nation_id != nation_id:
		return false
	if g.is_capital:
		return false
	var n = _get_nation(nation_id)
	if n:
		n.production += 30.0
	garrisons.erase(g)
	g.queue_free()
	nation_resource_updated.emit(nation_id)
	return true

func try_demolish_farm(nation_id: int, hex: Vector2i) -> bool:
	if not hex in hex_map.farm_data or hex_map.farm_data[hex] != nation_id:
		return false
	var n = _get_nation(nation_id)
	if n:
		n.population += 10
	hex_map.farm_data.erase(hex)
	hex_map.queue_redraw()
	nation_resource_updated.emit(nation_id)
	return true

func try_demolish_mine(nation_id: int, hex: Vector2i) -> bool:
	if not hex in hex_map.mine_data or hex_map.mine_data[hex] != nation_id:
		return false
	var n = _get_nation(nation_id)
	if n:
		n.population += 10
	hex_map.mine_data.erase(hex)
	hex_map.queue_redraw()
	nation_resource_updated.emit(nation_id)
	return true

func _defeat_nation(nation_id: int, conqueror_id: int):
	var n = _get_nation(nation_id)
	if n == null or n.is_defeated:
		return
	n.is_defeated = true
	_remove_from_alliances(nation_id)
	hex_map.remove_capital(n.capital_pos)
	var conquered_tiles = hex_map.get_nation_tiles(nation_id)
	hex_map.transfer_all_tiles(nation_id, conqueror_id)
	hex_map.transfer_buildings(nation_id, conqueror_id)
	_territory_dirty = true
	var n_conq = _get_nation(conqueror_id)
	if n_conq:
		n_conq.population += conquered_tiles.size() * 10
		n_conq.nations_eliminated += 1
	var to_remove_a = armies.filter(func(a): return a.nation_id == nation_id)
	for a in to_remove_a:
		_remove_army(a)
	var to_remove_g = garrisons.filter(func(g): return g.nation_id == nation_id)
	for g in to_remove_g:
		garrisons.erase(g)
		g.queue_free()
	var to_remove_c = camps.filter(func(c): return c.nation_id == nation_id)
	for c in to_remove_c:
		camps.erase(c)
		c.queue_free()
	nation_defeated.emit(nation_id)
	var alive = nations.filter(func(na): return not na.is_defeated)
	if alive.size() == 1:
		game_active = false
		game_over.emit(alive[0].nation_name)

# ── 结盟系统 ──────────────────────────────────────────
func get_alliance_of(nation_id: int) -> Array:
	for a in alliances:
		if nation_id in a:
			return a
	return []

func are_allied(a: int, b: int) -> bool:
	if a == b:
		return false
	var al = get_alliance_of(a)
	return b in al

func can_request_alliance(from_id: int, to_id: int) -> bool:
	if from_id == to_id:
		return false
	if are_allied(from_id, to_id):
		return false
	var n_from = _get_nation(from_id)
	var n_to   = _get_nation(to_id)
	if n_from == null or n_to == null or n_from.is_defeated or n_to.is_defeated:
		return false
	for req in pending_requests:
		if (req.from_id == from_id and req.to_id == to_id) or \
		   (req.from_id == to_id   and req.to_id == from_id):
			return false
	var al_from = get_alliance_of(from_id)
	var al_to   = get_alliance_of(to_id)
	var merged_size = al_from.size() + al_to.size()
	if from_id not in al_from: merged_size += 1
	if to_id   not in al_to:   merged_size += 1
	return merged_size <= 3

func send_alliance_request(from_id: int, to_id: int) -> bool:
	if not can_request_alliance(from_id, to_id):
		return false
	pending_requests.append({from_id = from_id, to_id = to_id})
	if to_id == PLAYER_ID:
		alliance_request_received.emit(from_id)
	elif net_mode and is_net_authority and to_id in _player_nation_ids and to_id != PLAYER_ID:
		var target_peer = _get_peer_for_nation(to_id)
		if target_peer > 0:
			rpc_id(target_peer, "_net_notify_alliance", from_id)
	else:
		_ai_handle_alliance_request(from_id, to_id)
	return true

func _ai_handle_alliance_request(from_id: int, to_id: int):
	# AI 自动接受（如尚未满联盟）
	accept_alliance_request(from_id, to_id)

func accept_alliance_request(from_id: int, to_id: int):
	for i in range(pending_requests.size() - 1, -1, -1):
		var req = pending_requests[i]
		if (req.from_id == from_id and req.to_id == to_id) or \
		   (req.from_id == to_id   and req.to_id == from_id):
			pending_requests.remove_at(i)
			break
	var al_a = get_alliance_of(from_id)
	var al_b = get_alliance_of(to_id)
	if al_a.size() > 0 and al_b.size() > 0 and al_a != al_b:
		for n in al_b:
			if n not in al_a:
				al_a.append(n)
		alliances.erase(al_b)
	elif al_a.size() > 0:
		if to_id not in al_a:
			al_a.append(to_id)
	elif al_b.size() > 0:
		if from_id not in al_b:
			al_b.append(from_id)
	else:
		alliances.append([from_id, to_id])
	alliance_changed.emit()

func decline_alliance_request(from_id: int, to_id: int):
	for i in range(pending_requests.size() - 1, -1, -1):
		var req = pending_requests[i]
		if (req.from_id == from_id and req.to_id == to_id) or \
		   (req.from_id == to_id   and req.to_id == from_id):
			pending_requests.remove_at(i)
			return

func get_pending_request_for_player() -> Dictionary:
	for req in pending_requests:
		if req.to_id == PLAYER_ID:
			return req
	return {}

func leave_alliance(nation_id: int) -> bool:
	var al = get_alliance_of(nation_id)
	if al.is_empty():
		return false
	_remove_from_alliances(nation_id)
	return true

func _remove_from_alliances(nation_id: int):
	for al in alliances.duplicate():
		if nation_id in al:
			al.erase(nation_id)
			if al.size() <= 1:
				alliances.erase(al)
	alliance_changed.emit()

func try_hire_general(nation_id: int) -> bool:
	var n = _get_nation(nation_id)
	if n == null or not n.can_hire_general():
		return false
	n.gold -= Nation.GENERAL_COST
	n.generals += 1
	nation_resource_updated.emit(nation_id)
	return true

func try_hire_minister(nation_id: int) -> bool:
	var n = _get_nation(nation_id)
	if n == null or not n.can_hire_minister():
		return false
	n.gold -= Nation.MINISTER_COST
	n.ministers += 1
	nation_resource_updated.emit(nation_id)
	return true

func _run_generals():
	for pid in _player_nation_ids:
		var n = _get_nation(pid)
		if n == null or n.is_defeated or n.generals == 0:
			continue
		for i in range(n.generals):
			_general_action(n)

func _general_action(n: Nation):
	if n.general_stance == "defend":
		_general_defend(n)
	else:
		_general_attack(n)

func _get_border_tiles(n: Nation) -> Array[Vector2i]:
	var border: Array[Vector2i] = []
	for tile in hex_map.get_nation_tiles(n.id):
		for nb in hex_map.get_neighbors(tile):
			if hex_map.get_tile_owner(nb) != n.id:
				border.append(tile)
				break
	return border

func _general_defend(n: Nation):
	var border = _get_border_tiles(n)
	# 在边界建部署地
	if n.production >= 30:
		for tile in border:
			if can_build_garrison_at(n.id, tile):
				try_build_garrison(n.id, tile)
				return
	# 在边界建军队
	if n.can_build_army():
		for tile in border:
			if can_deploy_at(n.id, tile):
				try_build_army(n.id, tile)
				return
	# 把内陆军队移向边界
	for army in n.armies.duplicate():
		if not is_instance_valid(army): continue
		var on_border = false
		for nb in hex_map.get_neighbors(army.hex_pos):
			if hex_map.get_tile_owner(nb) != n.id:
				on_border = true; break
		if on_border: continue
		var nearest = Vector2i(-1, -1)
		var min_d = 999999
		for btile in border:
			var d = hex_map.hex_distance(army.hex_pos, btile)
			if d < min_d:
				min_d = d; nearest = btile
		if nearest == Vector2i(-1, -1): continue
		var best_nb = Vector2i(-1, -1)
		var best_dist = 999999
		for nb in hex_map.get_neighbors(army.hex_pos):
			if not hex_map.is_passable(nb): continue
			if hex_map.get_tile_owner(nb) != n.id: continue
			if _get_army_at(nb) != null: continue
			var d = hex_map.hex_distance(nb, nearest)
			if d < best_dist:
				best_dist = d; best_nb = nb
		if best_nb != Vector2i(-1, -1):
			try_move_army(army, best_nb)
			return

func _general_attack(n: Nation):
	# 在紧邻敌方的己方格建部署地
	if n.production >= 30:
		var tiles = hex_map.get_nation_tiles(n.id)
		for tile in tiles:
			if can_build_garrison_at(n.id, tile):
				var near_enemy = false
				for nb in hex_map.get_neighbors(tile):
					if hex_map.get_tile_owner(nb) != n.id and hex_map.get_tile_owner(nb) >= 0:
						near_enemy = true; break
				if near_enemy:
					try_build_garrison(n.id, tile)
					return
	# 建军队
	if n.can_build_army():
		var deploy = _find_general_deploy(n)
		if deploy != Vector2i(-999, -999):
			try_build_army(n.id, deploy)
			return
	# 移动军队攻击
	for army in n.armies.duplicate():
		if not is_instance_valid(army): continue
		var aid = army.get_instance_id()
		var is_stuck = _army_prev_pos.get(aid, Vector2i(-999, -999)) == army.hex_pos
		_army_prev_pos[aid] = army.hex_pos
		if is_stuck:
			var expand_nb = _find_expand_move(army.hex_pos, n.id)
			if expand_nb != Vector2i(-1, -1):
				try_move_army(army, expand_nb)
				return
		var attacked = false
		for nb in hex_map.get_neighbors(army.hex_pos):
			var g = _get_garrison_at(nb)
			if g != null and g.nation_id != n.id and not are_allied(n.id, g.nation_id):
				try_move_army(army, nb)
				attacked = true; break
		if attacked: return
		var target = _find_nearest_enemy_capital(n.id, army.hex_pos)
		if target == Vector2i(-1, -1): continue
		var best_nb = Vector2i(-1, -1)
		var best_dist = 999999
		for nb in hex_map.get_neighbors(army.hex_pos):
			if not hex_map.is_passable(nb): continue
			if _get_army_at(nb) != null and _get_army_at(nb).nation_id == n.id: continue
			var dist = hex_map.hex_distance(nb, target)
			if dist < best_dist:
				best_dist = dist; best_nb = nb
		if best_nb != Vector2i(-1, -1):
			try_move_army(army, best_nb)
			return
		else:
			var expand_nb = _find_expand_move(army.hex_pos, n.id)
			if expand_nb != Vector2i(-1, -1):
				try_move_army(army, expand_nb)
				return

func _find_general_deploy(n: Nation) -> Vector2i:
	var tiles = hex_map.get_nation_tiles(n.id)
	for tile in tiles:
		if can_deploy_at(n.id, tile):
			return tile
	return Vector2i(-999, -999)

func _run_ai():
	# AI 结盟逻辑：处于劣势时向邻近国发送结盟申请
	for n in nations:
		if n.is_defeated or n.id in _player_nation_ids:
			continue
		if get_alliance_of(n.id).size() == 0 and randf() < 0.15:
			var my_tiles = hex_map.get_nation_tiles(n.id).size()
			for other in nations:
				if other.is_defeated or other.id == n.id:
					continue
				var other_tiles = hex_map.get_nation_tiles(other.id).size()
				if my_tiles <= other_tiles and can_request_alliance(n.id, other.id):
					send_alliance_request(n.id, other.id)
					break
	for n in nations:
		if n.is_defeated or n.id in _player_nation_ids:
			continue
		# 优先建造军队集中营（没有时第一件事）
		if _get_camps_of(n.id).is_empty() and n.production >= Nation.CAMP_COST_PROD:
			for tile in hex_map.get_nation_tiles(n.id):
				if can_build_camp_at(n.id, tile):
					try_build_camp(n.id, tile)
					break
		# 建造农田（人口≥20时优先建）
		if n.population >= 20:
			var farm_cnt = 0
			for hx in hex_map.farm_data:
				if hex_map.farm_data[hx] == n.id: farm_cnt += 1
			if farm_cnt < 6:
				for tile in hex_map.get_nation_tiles(n.id):
					if can_build_farm_at(n.id, tile):
						try_build_farm(n.id, tile)
						break
		# 建造矿洞（有余粮时建）
		if n.population >= 20 and n.food > 100:
			var mine_cnt = 0
			for hx in hex_map.mine_data:
				if hex_map.mine_data[hx] == n.id: mine_cnt += 1
			if mine_cnt < 3:
				for tile in hex_map.get_nation_tiles(n.id):
					if can_build_mine_at(n.id, tile):
						try_build_mine(n.id, tile)
						break
		# 首都防御：周围2格有敌军时，优先在首都周围建部署地和军队
		var capital_under_threat = false
		if n.production >= 30:
			var threat_hexes = []
			for nb1 in hex_map.get_neighbors(n.capital_pos):
				threat_hexes.append(nb1)
				for nb2 in hex_map.get_neighbors(nb1):
					if not nb2 in threat_hexes:
						threat_hexes.append(nb2)
			for th in threat_hexes:
				var enemy_there = false
				for a in armies:
					if is_instance_valid(a) and a.hex_pos == th and a.nation_id != n.id and not are_allied(n.id, a.nation_id):
						enemy_there = true; break
				if enemy_there:
					capital_under_threat = true; break
			if capital_under_threat:
				for nb in hex_map.get_neighbors(n.capital_pos):
					if hex_map.get_tile_owner(nb) != n.id:
						continue
					var terrain = hex_map.get_terrain(nb)
					if terrain == TerrainType.Type.WATER or terrain == TerrainType.Type.MOUNTAIN:
						continue
					# 拆除农田
					if nb in hex_map.farm_data and hex_map.farm_data[nb] == n.id:
						hex_map.farm_data.erase(nb)
						n.population += 10
						_territory_dirty = true
					# 拆除矿洞
					if nb in hex_map.mine_data and hex_map.mine_data[nb] == n.id:
						hex_map.mine_data.erase(nb)
						n.population += 10
						_territory_dirty = true
					# 拆除普通部署地（非首都）后重建，或直接建
					var existing_g = _get_garrison_at(nb)
					if existing_g != null and existing_g.is_capital:
						continue
					if existing_g == null and can_build_garrison_at(n.id, nb):
						try_build_garrison(n.id, nb)
				if n.can_build_army():
					try_build_army(n.id)
		# 尝试建造部署地（在前线空草地）
		if not capital_under_threat and n.production >= 30:
			var tiles = hex_map.get_nation_tiles(n.id)
			for tile in tiles:
				if can_build_garrison_at(n.id, tile):
					var near_enemy = false
					for nb in hex_map.get_neighbors(tile):
						var owner = hex_map.get_tile_owner(nb)
						if owner >= 0 and owner != n.id:
							near_enemy = true; break
					if near_enemy:
						try_build_garrison(n.id, tile)
						break
		# 尝试建造军队
		if n.can_build_army():
			try_build_army(n.id)
		# 移动每支军队：优先攻击相邻敌方部署地，否则向最近敌方首都前进
		for army in n.armies.duplicate():
			if not is_instance_valid(army):
				continue
			var aid = army.get_instance_id()
			var is_stuck = _army_prev_pos.get(aid, Vector2i(-999, -999)) == army.hex_pos
			_army_prev_pos[aid] = army.hex_pos
			# 卡住时向无主地扩张
			if is_stuck:
				var expand_nb = _find_expand_move(army.hex_pos, n.id)
				if expand_nb != Vector2i(-1, -1):
					try_move_army(army, expand_nb)
					continue
			# 优先攻击相邻敌方部署地
			var attacked = false
			for nb in hex_map.get_neighbors(army.hex_pos):
				var g = _get_garrison_at(nb)
				if g != null and g.nation_id != n.id and not are_allied(n.id, g.nation_id):
					try_move_army(army, nb)
					attacked = true
					break
			if attacked:
				continue
			var target = _find_nearest_enemy_capital(n.id, army.hex_pos)
			if target == Vector2i(-1, -1):
				continue
			var best_nb = Vector2i(-1, -1)
			var best_dist = 999999
			for nb in hex_map.get_neighbors(army.hex_pos):
				if not hex_map.is_passable(nb):
					continue
				var a_at = _get_army_at(nb)
				if a_at != null and a_at.nation_id == n.id:
					continue
				var dist = hex_map.hex_distance(nb, target)
				if dist < best_dist:
					best_dist = dist
					best_nb = nb
			if best_nb != Vector2i(-1, -1):
				try_move_army(army, best_nb)
			else:
				var expand_nb = _find_expand_move(army.hex_pos, n.id)
				if expand_nb != Vector2i(-1, -1):
					try_move_army(army, expand_nb)

func _find_expand_move(from_hex: Vector2i, nation_id: int) -> Vector2i:
	var best_target = Vector2i(-1, -1)
	var best_dist = 999999
	for hex in hex_map.terrain_data:
		if hex_map.get_tile_owner(hex) == -1 and hex_map.is_passable(hex):
			var d = hex_map.hex_distance(from_hex, hex)
			if d < best_dist:
				best_dist = d
				best_target = hex
	if best_target == Vector2i(-1, -1):
		return Vector2i(-1, -1)
	var best_nb = Vector2i(-1, -1)
	best_dist = 999999
	for nb in hex_map.get_neighbors(from_hex):
		if not hex_map.is_passable(nb): continue
		var a_at = _get_army_at(nb)
		if a_at != null and a_at.nation_id == nation_id: continue
		var g = _get_garrison_at(nb)
		if g != null and g.nation_id != nation_id: continue
		var d = hex_map.hex_distance(nb, best_target)
		if d < best_dist:
			best_dist = d
			best_nb = nb
	return best_nb

func _find_nearest_enemy_capital(nation_id: int, from_hex: Vector2i) -> Vector2i:
	var best = Vector2i(-1, -1)
	var best_dist = 999999
	for n in nations:
		if n.id == nation_id or n.is_defeated or are_allied(nation_id, n.id):
			continue
		var d = hex_map.hex_distance(from_hex, n.capital_pos)
		if d < best_dist:
			best_dist = d
			best = n.capital_pos
	return best

func launch_missile(nation_id: int, target_hex: Vector2i):
	var affected: Array[Vector2i] = []
	for hex in hex_map.terrain_data:
		if hex_map.hex_distance(hex, target_hex) <= 2:
			affected.append(hex)
	# 击中首都 → 消灭该国（继承其所有领土）
	for g in garrisons.duplicate():
		if not is_instance_valid(g): continue
		if g.is_capital and g.nation_id != nation_id:
			if hex_map.hex_distance(g.hex_pos, target_hex) <= 2:
				_defeat_nation(g.nation_id, nation_id)
	# 消灭范围内残余敌军
	for a in armies.duplicate():
		if not is_instance_valid(a): continue
		if a.nation_id != nation_id and hex_map.hex_distance(a.hex_pos, target_hex) <= 2:
			_remove_army(a)
	# 消灭范围内残余敌方部署地
	for g in garrisons.duplicate():
		if not is_instance_valid(g): continue
		if g.nation_id != nation_id and hex_map.hex_distance(g.hex_pos, target_hex) <= 2:
			garrisons.erase(g)
			g.queue_free()
	# 占领范围内可通行地块并建立己方部署地
	for hex in affected:
		var t = hex_map.get_terrain(hex)
		if t == TerrainType.Type.PLAINS or t == TerrainType.Type.DESERT:
			_claim_tile(hex, nation_id)
			if _get_garrison_at(hex) == null and _get_army_at(hex) == null:
				_create_garrison(nation_id, hex)
	hex_map.queue_redraw()
	nation_resource_updated.emit(nation_id)

func _get_nation(id: int) -> Nation:
	for n in nations:
		if n.id == id:
			return n
	return null

func select_army_at(hex: Vector2i):
	for army in armies:
		if army.hex_pos == hex and army.nation_id == PLAYER_ID:
			selected_army = army
			return army
	selected_army = null
	return null

func get_nation(id: int) -> Nation:
	return _get_nation(id)

func get_player_nation() -> Nation:
	return _get_nation(PLAYER_ID)

# ── 联机网络 ──────────────────────────────────────────

func _toggle_stance(nation_id: int):
	var n = _get_nation(nation_id)
	if n == null: return
	n.general_stance = "defend" if n.general_stance == "attack" else "attack"

@rpc("any_peer", "call_remote", "reliable")
func _net_action(action: String, params: Dictionary):
	if not is_net_authority:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var pid = _peer_to_nation.get(sender_id, -1)
	if pid < 0:
		return
	match action:
		"hire_general":      try_hire_general(pid)
		"hire_minister":     try_hire_minister(pid)
		"toggle_stance":     _toggle_stance(pid)
		"convert_food":      convert_food_to_production(pid)
		"leave_alliance":    leave_alliance(pid)
		"accept_alliance":   accept_alliance_request(params.get("from_id", -1), pid)
		"decline_alliance":  decline_alliance_request(params.get("from_id", -1), pid)
		"ally":              send_alliance_request(pid, params.get("target_id", -1))
		"missile":           launch_missile(pid, params.get("hex", Vector2i(-999,-999)))
		"relocate":          try_relocate_capital(pid, params.get("hex", Vector2i(-999,-999)))
		"build_army":        try_build_army(pid, params.get("hex", Vector2i(-999,-999)))
		"build_garrison":    try_build_garrison(pid, params.get("hex", Vector2i(-999,-999)))
		"build_farm":        try_build_farm(pid, params.get("hex", Vector2i(-999,-999)))
		"build_mine":        try_build_mine(pid, params.get("hex", Vector2i(-999,-999)))
		"build_camp":        try_build_camp(pid, params.get("hex", Vector2i(-999,-999)))
		"disband_army":      try_disband_army(pid, params.get("hex", Vector2i(-999,-999)))
		"demolish_garrison": try_demolish_garrison(pid, params.get("hex", Vector2i(-999,-999)))
		"demolish_farm":     try_demolish_farm(pid, params.get("hex", Vector2i(-999,-999)))
		"demolish_mine":     try_demolish_mine(pid, params.get("hex", Vector2i(-999,-999)))
		"demolish_camp":     try_demolish_camp(pid, params.get("hex", Vector2i(-999,-999)))
		"move_army":
			var from_hex = params.get("from", Vector2i(-999,-999))
			var to_hex   = params.get("to",   Vector2i(-999,-999))
			var army = _get_army_at(from_hex)
			if army != null and army.nation_id == pid:
				try_move_army(army, to_hex)

@rpc("authority", "call_remote", "reliable")
func _net_notify_alliance(from_id: int):
	alliance_request_received.emit(from_id)

@rpc("authority", "call_remote", "reliable")
func _net_receive_init(state: Dictionary):
	hex_map.terrain_data.clear()
	hex_map.owner_data.clear()
	for k in state.get("terrain", {}):
		var parts = k.split("_")
		var hex = Vector2i(int(parts[0]), int(parts[1]))
		hex_map.terrain_data[hex] = state.terrain[k]
		hex_map.owner_data[hex] = -1
	var cols = state.get("nation_colors", [])
	for i in range(cols.size()):
		var c = cols[i]
		hex_map.nation_colors[i] = Color(c[0], c[1], c[2], c[3])
	# 客户端重连/重开时重建国家对象
	if nations.is_empty():
		for nd in state.get("nations", []):
			var n = Nation.new()
			n.id = nd.id
			n.nation_name = _nation_names[nd.id]
			n.color = _nation_colors[nd.id]
			n.capital_pos = Vector2i(nd.get("cx", 0), nd.get("cy", 0))
			nations.append(n)
	_apply_state(state)
	nation_resource_updated.emit(PLAYER_ID)

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_receive_state(state: Dictionary):
	_apply_state(state)
	nation_resource_updated.emit(PLAYER_ID)

func _broadcast_init():
	var state = _build_state()
	state["terrain"] = {}
	for hex in hex_map.terrain_data:
		state["terrain"]["%d_%d" % [hex.x, hex.y]] = hex_map.terrain_data[hex]
	var cols = []
	for i in range(nations.size()):
		var c = _nation_colors[i]
		cols.append([c.r, c.g, c.b, c.a])
	state["nation_colors"] = cols
	rpc("_net_receive_init", state)

func _broadcast_state():
	rpc("_net_receive_state", _build_state())

func _build_state() -> Dictionary:
	var nd_arr = []
	for n in nations:
		nd_arr.append({
			"id": n.id, "food": n.food, "prod": n.production,
			"gold": n.gold, "pop": n.population,
			"gen": n.generals, "min": n.ministers,
			"stance": n.general_stance, "dead": n.is_defeated,
			"cx": n.capital_pos.x, "cy": n.capital_pos.y,
			"ab": n.armies_built, "fb": n.farms_built,
			"mb": n.mines_built, "gb": n.garrisons_built,
			"cb": n.camps_built, "ke": n.nations_eliminated
		})
	var army_arr = []
	for a in armies:
		if is_instance_valid(a):
			army_arr.append({"nid": a.nation_id, "x": a.hex_pos.x, "y": a.hex_pos.y, "hp": a.hp})
	var gar_arr = []
	for g in garrisons:
		if is_instance_valid(g):
			gar_arr.append({
				"nid": g.nation_id, "x": g.hex_pos.x, "y": g.hex_pos.y,
				"hp": g.hp, "mhp": g.max_hp, "cap": g.is_capital
			})
	var camp_arr = []
	for c in camps:
		if is_instance_valid(c):
			camp_arr.append({"nid": c.nation_id, "x": c.hex_pos.x, "y": c.hex_pos.y, "hp": c.hp})
	var own = {}
	for hex in hex_map.owner_data:
		own["%d_%d" % [hex.x, hex.y]] = hex_map.owner_data[hex]
	var farms = {}
	for hex in hex_map.farm_data:
		farms["%d_%d" % [hex.x, hex.y]] = hex_map.farm_data[hex]
	var mines = {}
	for hex in hex_map.mine_data:
		mines["%d_%d" % [hex.x, hex.y]] = hex_map.mine_data[hex]
	var caps = {}
	for hex in hex_map.capital_data:
		caps["%d_%d" % [hex.x, hex.y]] = hex_map.capital_data[hex]
	var result = {
		"nations": nd_arr, "armies": army_arr, "garrisons": gar_arr,
		"mil_camps": camp_arr, "alliances": alliances.duplicate(true), "active": game_active
	}
	if _territory_dirty:
		result["owner"] = own
		result["farms"] = farms
		result["mines"] = mines
		result["caps"] = caps
		_territory_dirty = false
	return result

func _apply_state(state: Dictionary):
	# 更新各国数据
	for nd in state.get("nations", []):
		var n = _get_nation(nd.id)
		if n == null: continue
		var was_dead = n.is_defeated
		n.food = nd.food; n.production = nd.prod
		n.gold = nd.gold; n.population = nd.pop
		n.generals = nd.gen; n.ministers = nd.min
		n.general_stance = nd.stance; n.is_defeated = nd.dead
		n.capital_pos = Vector2i(nd.cx, nd.cy)
		n.armies_built = nd.get("ab", 0); n.farms_built = nd.get("fb", 0)
		n.mines_built = nd.get("mb", 0); n.garrisons_built = nd.get("gb", 0)
		n.camps_built = nd.get("cb", 0); n.nations_eliminated = nd.get("ke", 0)
		if not was_dead and n.is_defeated:
			nation_defeated.emit(n.id)

	# 差量更新军队（避免全部重建导致闪烁）
	var army_set: Dictionary = {}
	for ad in state.get("armies", []):
		army_set["%d_%d" % [ad.x, ad.y]] = ad
	for a in armies.duplicate():
		if not is_instance_valid(a): continue
		var k = "%d_%d" % [a.hex_pos.x, a.hex_pos.y]
		if not k in army_set or army_set[k].nid != a.nation_id:
			_remove_army(a)
	for k in army_set:
		var ad = army_set[k]
		var hex = Vector2i(ad.x, ad.y)
		var existing = _get_army_at(hex)
		if existing != null and existing.nation_id == ad.nid:
			existing.hp = ad.hp
			existing.queue_redraw()
		else:
			if existing != null:
				_remove_army(existing)
			var a = _create_army(ad.nid, hex)
			a.hp = ad.hp
			a.queue_redraw()

	# 差量更新部署地
	var gar_set: Dictionary = {}
	for gd in state.get("garrisons", []):
		gar_set["%d_%d" % [gd.x, gd.y]] = gd
	for g in garrisons.duplicate():
		if not is_instance_valid(g): continue
		var k = "%d_%d" % [g.hex_pos.x, g.hex_pos.y]
		if not k in gar_set:
			garrisons.erase(g)
			g.queue_free()
	for k in gar_set:
		var gd = gar_set[k]
		var hex = Vector2i(gd.x, gd.y)
		var existing = _get_garrison_at(hex)
		if existing != null:
			existing.hp = gd.hp; existing.max_hp = gd.mhp; existing.is_capital = gd.cap
			existing.queue_redraw()
		else:
			var g = _create_garrison(gd.nid, hex)
			g.hp = gd.hp; g.max_hp = gd.mhp; g.is_capital = gd.cap
			g.queue_redraw()

	# 差量更新军队集中营
	var camp_set: Dictionary = {}
	for cd in state.get("mil_camps", []):
		camp_set["%d_%d" % [cd.x, cd.y]] = cd
	for c in camps.duplicate():
		if not is_instance_valid(c): continue
		var k = "%d_%d" % [c.hex_pos.x, c.hex_pos.y]
		if not k in camp_set:
			camps.erase(c)
			c.queue_free()
	for k in camp_set:
		var cd = camp_set[k]
		var hex = Vector2i(cd.x, cd.y)
		var existing = _get_camp_at(hex)
		if existing != null:
			existing.hp = cd.hp
			existing.queue_redraw()
		else:
			var c = _create_camp(cd.nid, hex)
			c.hp = cd.hp
			c.queue_redraw()

	# 应用领土、农田、矿洞、首都
	for k in state.get("owner", {}):
		var parts = k.split("_")
		hex_map.owner_data[Vector2i(int(parts[0]), int(parts[1]))] = state.owner[k]
	hex_map.farm_data.clear()
	for k in state.get("farms", {}):
		var parts = k.split("_")
		hex_map.farm_data[Vector2i(int(parts[0]), int(parts[1]))] = state.farms[k]
	hex_map.mine_data.clear()
	for k in state.get("mines", {}):
		var parts = k.split("_")
		hex_map.mine_data[Vector2i(int(parts[0]), int(parts[1]))] = state.mines[k]
	hex_map.capital_data.clear()
	for k in state.get("caps", {}):
		var parts = k.split("_")
		hex_map.capital_data[Vector2i(int(parts[0]), int(parts[1]))] = state.caps[k]

	alliances = state.get("alliances", [])
	var was_active = game_active
	game_active = state.get("active", true)
	if was_active and not game_active:
		var alive = nations.filter(func(na): return not na.is_defeated)
		if alive.size() == 1:
			game_over.emit(alive[0].nation_name)

	alliance_changed.emit()
	hex_map.queue_redraw()

func net_send_alliance_notify(from_id: int):
	if net_mode and is_net_authority:
		rpc("_net_notify_alliance", from_id)

func _get_peer_for_nation(nation_id: int) -> int:
	for peer_id in _peer_to_nation:
		if _peer_to_nation[peer_id] == nation_id:
			return peer_id
	return -1

# ── 多人大厅开局 ──────────────────────────────────────

func start_game_for_all(count: int):
	nation_count = count
	var peer_nation_map: Dictionary = {}
	var next_nation = 1
	for peer_id in multiplayer.get_peers():
		peer_nation_map[peer_id] = next_nation
		next_nation += 1
	_peer_to_nation = peer_nation_map
	_player_nation_ids.clear()
	_player_nation_ids.append(0)
	for n_id in peer_nation_map.values():
		_player_nation_ids.append(n_id)
	PLAYER_ID = 0
	rpc("_net_start_game", count, peer_nation_map)
	initialize(hex_map, count)
	await get_tree().process_frame
	_broadcast_init()
	game_started.emit()

@rpc("authority", "call_remote", "reliable")
func _net_start_game(count: int, peer_nation_map: Dictionary):
	var my_peer_id = multiplayer.get_unique_id()
	PLAYER_ID = peer_nation_map.get(my_peer_id, 1)
	_peer_to_nation = peer_nation_map
	_player_nation_ids.clear()
	_player_nation_ids.append(0)
	for n_id in peer_nation_map.values():
		_player_nation_ids.append(n_id)
	nation_count = count
	game_started.emit()

# ── 重开游戏 ──────────────────────────────────────────

signal restart_agreed(nation_id: int)

@rpc("any_peer", "call_remote", "reliable")
func _net_agree_restart(nation_id: int):
	restart_agreed.emit(nation_id)

signal game_reset

@rpc("authority", "call_remote", "reliable")
func _net_do_restart():
	for a in armies.duplicate():
		_remove_army(a)
	for g in garrisons.duplicate():
		garrisons.erase(g)
		g.queue_free()
	for c in camps.duplicate():
		camps.erase(c)
		c.queue_free()
	nations.clear()
	alliances.clear()
	pending_requests.clear()
	game_active = false
	game_reset.emit()
	nation_resource_updated.emit(PLAYER_ID)

func agree_restart():
	if net_mode:
		restart_agreed.emit(PLAYER_ID)
		rpc_id(1, "_net_agree_restart", PLAYER_ID)
	else:
		reset_game()

func reset_game():
	for a in armies.duplicate():
		_remove_army(a)
	for g in garrisons.duplicate():
		garrisons.erase(g)
		g.queue_free()
	for c in camps.duplicate():
		camps.erase(c)
		c.queue_free()
	hex_map.owner_data.clear()
	hex_map.capital_data.clear()
	hex_map.farm_data.clear()
	hex_map.mine_data.clear()
	hex_map.terrain_data.clear()
	hex_map.nation_colors.clear()
	nations.clear()
	alliances.clear()
	pending_requests.clear()
	resource_timer = 0.0; ai_timer = 0.0
	reinforce_timer = 0.0; general_timer = 0.0
	_net_timer = 0.0
	game_active = false
	initialize(hex_map, nation_count)
	if net_mode and is_net_authority:
		rpc("_net_do_restart")
		await get_tree().process_frame
		_broadcast_init()
