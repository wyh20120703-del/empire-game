extends Node2D

var hex_map: HexMap
var game_manager: GameManager
var camera: Camera2D
var ui_layer: CanvasLayer
var resource_label: Label
var info_label: Label
var selected_label: Label
var general_button: Button
var general_stance_button: Button
var minister_button: Button
var convert_button: Button
var relocate_button: Button
var ally_button: Button
var alliance_label: Label

# 地块弹出菜单
var context_panel: ColorRect
var ctx_title: Label
var ctx_army_btn: Button
var ctx_garrison_btn: Button
var ctx_farm_btn: Button
var ctx_mine_btn: Button
var selected_hex: Vector2i = Vector2i(-999, -999)

var dragging: bool = false
var _left_holding: bool = false
var _drag_build_last_hex: Vector2i = Vector2i(-999, -999)
# 长按建造模式：0=自动(军队/部署地) 1=农田 2=矿洞
var _drag_mode: int = 0
var _drag_mode_btn: Button
var relocate_mode: bool = false
var ally_mode: bool = false
var missile_mode: bool = false
var missile_count: int = 0
var _pwd_buffer: String = ""
var missile_btn: Button

# 联机
var net_mgr: Node
var _client_selected_hex: Vector2i = Vector2i(-999, -999)
var _lobby_panel: ColorRect
var _lobby_status: Label
var _ip_input: LineEdit
var _waiting_room_layer: CanvasLayer = null
var _player_list_label: Label = null
var _start_btn: Button = null
var _nation_count_label: Label = null
var _host_nation_count: int = 7
var _connected_peers: Array = []

func _ready():
	_setup_camera()
	_setup_hex_map()
	_setup_game_manager()
	_setup_ui()
	_setup_legend()
	_setup_context_panel()
	_setup_network()
	_setup_lobby()

func _setup_camera():
	camera = Camera2D.new()
	camera.zoom = Vector2(0.52, 0.52)
	camera.position = Vector2(0, 0)  # 地图以原点为中心
	add_child(camera)
	camera.make_current()

func _setup_hex_map():
	hex_map = HexMap.new()
	add_child(hex_map)

func _setup_game_manager():
	game_manager = GameManager.new()
	add_child(game_manager)
	game_manager.hex_map = hex_map
	game_manager.nation_resource_updated.connect(_on_resource_updated)
	game_manager.nation_defeated.connect(_on_nation_defeated)
	game_manager.game_over.connect(_on_game_over)
	game_manager.alliance_request_received.connect(_on_alliance_request_received)
	game_manager.alliance_changed.connect(_on_alliance_changed)
	game_manager.restart_agreed.connect(_on_restart_agreed)
	game_manager.game_reset.connect(_on_game_reset)
	# initialize() 由 _on_lobby_singleplayer 或 start_game_for_all 调用

func _setup_ui():
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	# ── 左上：资源面板 ──
	var top_bg = ColorRect.new()
	top_bg.color = Color(0, 0, 0, 0.75)
	top_bg.size = Vector2(320, 178)
	top_bg.position = Vector2(8, 8)
	ui_layer.add_child(top_bg)

	resource_label = Label.new()
	resource_label.position = Vector2(13, 12)
	resource_label.size = Vector2(308, 168)
	resource_label.add_theme_font_size_override("font_size", 24)
	resource_label.modulate = Color.WHITE
	ui_layer.add_child(resource_label)

	# ── 左中：结盟 + 消息 ──
	var mid_bg = ColorRect.new()
	mid_bg.color = Color(0, 0, 0, 0.68)
	mid_bg.size = Vector2(320, 188)
	mid_bg.position = Vector2(8, 192)
	ui_layer.add_child(mid_bg)

	ally_button = Button.new()
	ally_button.text = "结盟 [L]  Y接受 N拒绝"
	ally_button.position = Vector2(8, 196)
	ally_button.size = Vector2(320, 44)
	ally_button.add_theme_font_size_override("font_size", 22)
	ally_button.pressed.connect(_on_ally_pressed)
	ui_layer.add_child(ally_button)

	selected_label = Label.new()
	selected_label.position = Vector2(13, 246)
	selected_label.size = Vector2(310, 52)
	selected_label.add_theme_font_size_override("font_size", 24)
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_label.modulate = Color.CYAN
	ui_layer.add_child(selected_label)

	info_label = Label.new()
	info_label.position = Vector2(13, 304)
	info_label.size = Vector2(310, 36)
	info_label.add_theme_font_size_override("font_size", 20)
	info_label.modulate = Color(1, 1, 0.5)
	info_label.text = "右键拖动 | 滚轮缩放 | 左键拖动批量建造"
	ui_layer.add_child(info_label)

	alliance_label = Label.new()
	alliance_label.position = Vector2(13, 344)
	alliance_label.size = Vector2(310, 32)
	alliance_label.add_theme_font_size_override("font_size", 20)
	alliance_label.modulate = Color(0.8, 1.0, 0.8)
	ui_layer.add_child(alliance_label)

	# ── 左下：操作按钮（单列） ──
	var bot_bg = ColorRect.new()
	bot_bg.color = Color(0, 0, 0, 0.75)
	bot_bg.size = Vector2(320, 390)
	bot_bg.position = Vector2(8, 386)
	ui_layer.add_child(bot_bg)

	var W = 320
	var y = 390; var SH = 40; var FS = 22; var GAP = 2

	general_button = Button.new()
	general_button.text = "将军 [J]  (120金)  自动派兵"
	general_button.position = Vector2(8, y); general_button.size = Vector2(W, SH)
	general_button.add_theme_font_size_override("font_size", FS)
	general_button.pressed.connect(_on_general_pressed); ui_layer.add_child(general_button)
	y += SH + GAP

	general_stance_button = Button.new()
	general_stance_button.text = "将军模式：进攻 [P]"
	general_stance_button.position = Vector2(8, y); general_stance_button.size = Vector2(W, SH)
	general_stance_button.add_theme_font_size_override("font_size", FS)
	general_stance_button.modulate = Color(1.0, 0.6, 0.6)
	general_stance_button.pressed.connect(_on_general_stance_pressed); ui_layer.add_child(general_stance_button)
	y += SH + GAP

	minister_button = Button.new()
	minister_button.text = "文臣 [M]  (100金)  产量+35%"
	minister_button.position = Vector2(8, y); minister_button.size = Vector2(W, SH)
	minister_button.add_theme_font_size_override("font_size", FS)
	minister_button.pressed.connect(_on_minister_pressed); ui_layer.add_child(minister_button)
	y += SH + GAP

	convert_button = Button.new()
	convert_button.text = "粮→产 [T]  (20粮=10产)"
	convert_button.position = Vector2(8, y); convert_button.size = Vector2(W, SH)
	convert_button.add_theme_font_size_override("font_size", FS)
	convert_button.pressed.connect(_on_convert_pressed); ui_layer.add_child(convert_button)
	y += SH + GAP

	relocate_button = Button.new()
	relocate_button.text = "迁都 [C]  (150金)"
	relocate_button.position = Vector2(8, y); relocate_button.size = Vector2(W, SH)
	relocate_button.add_theme_font_size_override("font_size", FS)
	relocate_button.pressed.connect(_on_relocate_pressed); ui_layer.add_child(relocate_button)
	y += SH + GAP

	ally_button = Button.new()
	ally_button.text = "结盟 [L]  Y接受 N拒绝"
	ally_button.position = Vector2(8, y); ally_button.size = Vector2(W, SH)
	ally_button.add_theme_font_size_override("font_size", FS)
	ally_button.pressed.connect(_on_ally_pressed); ui_layer.add_child(ally_button)
	y += SH + GAP

	var leave_ally_btn = Button.new()
	leave_ally_btn.text = "退出联盟 [X]"
	leave_ally_btn.position = Vector2(8, y); leave_ally_btn.size = Vector2(W, SH)
	leave_ally_btn.add_theme_font_size_override("font_size", FS)
	leave_ally_btn.pressed.connect(_on_leave_alliance_pressed); ui_layer.add_child(leave_ally_btn)
	y += SH + GAP

	_drag_mode_btn = Button.new()
	_drag_mode_btn.text = "长按模式：自动 [Z]"
	_drag_mode_btn.position = Vector2(8, y); _drag_mode_btn.size = Vector2(W, SH)
	_drag_mode_btn.add_theme_font_size_override("font_size", FS)
	_drag_mode_btn.pressed.connect(_on_drag_mode_pressed); ui_layer.add_child(_drag_mode_btn)
	y += SH + GAP

	missile_btn = Button.new()
	missile_btn.text = "▶ 导弹 [Q]  x0"
	missile_btn.position = Vector2(8, y); missile_btn.size = Vector2(W, SH)
	missile_btn.add_theme_font_size_override("font_size", FS)
	missile_btn.modulate = Color(1.0, 0.45, 0.0)
	missile_btn.visible = false
	missile_btn.pressed.connect(_on_missile_pressed)
	ui_layer.add_child(missile_btn)

	_update_resource_display()

func _setup_legend():
	var entries = [
		["草地（正常）",        TerrainType.get_color(TerrainType.Type.PLAINS)],
		["沙漠（部署地½血）",  TerrainType.get_color(TerrainType.Type.DESERT)],
		["山脉（不可行走）",   TerrainType.get_color(TerrainType.Type.MOUNTAIN)],
		["水路（不可行走）",   TerrainType.get_color(TerrainType.Type.WATER)],
	]

	var FONT_SZ = 22
	var ROW_H = 34
	var SQ = 22
	var PAD = 8
	var panel_w = SQ + PAD * 3 + 240
	var panel_h = entries.size() * ROW_H + PAD * 2 + 34
	var panel_x = 336
	var panel_y = 8

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.size = Vector2(panel_w, panel_h)
	bg.position = Vector2(panel_x, panel_y)
	ui_layer.add_child(bg)

	var title = Label.new()
	title.text = "地形图示"
	title.position = Vector2(panel_x + PAD, panel_y + PAD)
	title.add_theme_font_size_override("font_size", FONT_SZ)
	title.modulate = Color.YELLOW
	ui_layer.add_child(title)

	for i in range(entries.size()):
		var row_y = panel_y + PAD + 38 + i * ROW_H

		var sq = ColorRect.new()
		sq.color = entries[i][1]
		sq.size = Vector2(SQ, SQ)
		sq.position = Vector2(panel_x + PAD, row_y + (ROW_H - SQ) / 2.0)
		ui_layer.add_child(sq)

		var border = ColorRect.new()
		border.color = Color.BLACK
		border.size = Vector2(SQ + 2, SQ + 2)
		border.position = Vector2(panel_x + PAD - 1, row_y + (ROW_H - SQ) / 2.0 - 1)
		border.z_index = -1
		ui_layer.add_child(border)

		var lbl = Label.new()
		lbl.text = entries[i][0]
		lbl.position = Vector2(panel_x + PAD * 2 + SQ, row_y + (ROW_H - FONT_SZ) / 2.0)
		lbl.add_theme_font_size_override("font_size", FONT_SZ)
		lbl.modulate = Color.WHITE
		ui_layer.add_child(lbl)

func _input(event: InputEvent):
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left_holding = true
				var world_pos = get_global_mouse_position()
				_drag_build_last_hex = hex_map.pixel_to_hex(world_pos)
				_on_left_click()
			else:
				_left_holding = false
				_drag_build_last_hex = Vector2i(-999, -999)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			dragging = mb.pressed
			if mb.pressed:
				_left_holding = false
				relocate_mode = false
				ally_mode = false
				missile_mode = false
				missile_btn.text = "▶ 导弹 [Q]  x%d" % missile_count
				ally_button.text = "结盟 [L]  Y接受 N拒绝"
				relocate_button.text = "迁都 [C]  (150金)"
				_hide_context()
				selected_label.text = ""
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.3, 0.3), Vector2(2.5, 2.5))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom * 0.9).clamp(Vector2(0.3, 0.3), Vector2(2.5, 2.5))
	elif event is InputEventMouseMotion:
		var motion = event as InputEventMouseMotion
		if dragging:
			camera.position -= motion.relative / camera.zoom
		elif _left_holding and not missile_mode and not ally_mode and not relocate_mode \
				and game_manager.selected_army == null \
				and _client_selected_hex == Vector2i(-999, -999):
			var world_pos = get_global_mouse_position()
			var hex = hex_map.pixel_to_hex(world_pos)
			_drag_build(hex)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			_pwd_buffer += str(event.keycode - KEY_0)
			if _pwd_buffer.length() > 4:
				_pwd_buffer = _pwd_buffer.substr(_pwd_buffer.length() - 4)
			if _pwd_buffer == "0703":
				_unlock_missile()
				_pwd_buffer = ""
		match event.keycode:
			KEY_B: _ctx_action("army")
			KEY_G: _ctx_action("garrison")
			KEY_E: _ctx_action("farm")
			KEY_R: _ctx_action("mine")
			KEY_D: _ctx_action("demolish")
			KEY_J: _on_general_pressed()
			KEY_P: _on_general_stance_pressed()
			KEY_M: _on_minister_pressed()
			KEY_T: _on_convert_pressed()
			KEY_C: _on_relocate_pressed()
			KEY_L: _on_ally_pressed()
			KEY_Y: _on_accept_alliance()
			KEY_N: _on_decline_alliance()
			KEY_X: _on_leave_alliance_pressed()
			KEY_Q: _on_missile_pressed()
			KEY_Z: _on_drag_mode_pressed()

func _on_left_click():
	var world_pos = get_global_mouse_position()
	var hex = hex_map.pixel_to_hex(world_pos)

	# 导弹瞄准模式
	if missile_mode:
		if _is_client():
			_send_net_action("missile", {"hex": hex})
			selected_label.text = "导弹已发射！"
		else:
			missile_count -= 1
			game_manager.launch_missile(game_manager.PLAYER_ID, hex)
			selected_label.text = "导弹命中！范围内敌军已全部消灭！"
			_update_resource_display()
		missile_mode = false
		if missile_count > 0:
			missile_btn.text = "▶ 导弹 [Q]  x%d" % missile_count
		else:
			missile_btn.text = "▶ 导弹 [Q]  x0"
			if not _is_client():
				missile_btn.visible = false
		return

	# 结盟模式
	if ally_mode:
		var tile_owner = game_manager.hex_map.get_tile_owner(hex)
		if tile_owner < 0:
			selected_label.text = "该格无人占领，请点击敌国领土"
		elif tile_owner == game_manager.PLAYER_ID:
			selected_label.text = "不能与自己结盟"
		elif game_manager.are_allied(game_manager.PLAYER_ID, tile_owner):
			selected_label.text = "已与该国结盟"
		else:
			if _is_client():
				_send_net_action("ally", {"target_id": tile_owner})
				var n = game_manager.get_nation(tile_owner)
				selected_label.text = "已发送：向 %s 请求结盟" % n.nation_name
			else:
				var al_size = game_manager.get_alliance_of(game_manager.PLAYER_ID).size() + game_manager.get_alliance_of(tile_owner).size()
				if al_size > 3:
					selected_label.text = "结盟后联盟超过3国上限"
				else:
					game_manager.send_alliance_request(game_manager.PLAYER_ID, tile_owner)
					var n = game_manager.get_nation(tile_owner)
					selected_label.text = "已向 %s 发送结盟申请" % n.nation_name
		ally_mode = false
		ally_button.text = "结盟 [L]  Y接受 N拒绝"
		return

	# 迁都模式
	if relocate_mode:
		if _is_client():
			_send_net_action("relocate", {"hex": hex})
			selected_label.text = "已发送：迁都申请"
		else:
			var n = game_manager.get_player_nation()
			if game_manager.hex_map.get_tile_owner(hex) != game_manager.PLAYER_ID:
				selected_label.text = "该格不是己方领土"
			elif game_manager.hex_map.get_terrain(hex) != TerrainType.Type.PLAINS:
				selected_label.text = "只能迁到草地"
			elif hex == n.capital_pos:
				selected_label.text = "已是当前首都位置"
			elif game_manager.try_relocate_capital(game_manager.PLAYER_ID, hex):
				selected_label.text = "迁都成功！"
				_update_resource_display()
			else:
				selected_label.text = "迁都失败"
		relocate_mode = false
		relocate_button.text = "迁都 [C]  (150金)"
		return

	# 客户端军队移动
	if _is_client():
		if _client_selected_hex != Vector2i(-999, -999):
			_send_net_action("move_army", {"from": _client_selected_hex, "to": hex})
			_client_selected_hex = Vector2i(-999, -999)
			game_manager.selected_army = null
			selected_label.text = ""
			_hide_context()
			return
		var army = game_manager.select_army_at(hex)
		if army != null:
			_client_selected_hex = hex
			var n = game_manager.get_nation(army.nation_id)
			selected_label.text = "已选中 %s 军队  HP: %d（点击目标格移动）" % [n.nation_name, army.hp]
			_show_context(hex)
			return
		if hex_map.get_tile_owner(hex) == game_manager.PLAYER_ID:
			_show_context(hex)
			return
		_client_selected_hex = Vector2i(-999, -999)
		_hide_context()
		selected_label.text = ""
		return

	# 移动已选中军队（单机/主机）
	if game_manager.selected_army != null:
		var moved = game_manager.try_move_army(game_manager.selected_army, hex)
		if moved:
			game_manager.selected_army = null
			selected_label.text = ""
			_hide_context()
			_update_resource_display()
			return

	# 选中己方军队 → 显示上下文菜单
	var army = game_manager.select_army_at(hex)
	if army != null:
		var n = game_manager.get_nation(army.nation_id)
		selected_label.text = "已选中 %s 军队  HP: %d" % [n.nation_name, army.hp]
		_show_context(hex)
		return

	# 点击己方地块 → 显示上下文菜单
	if hex_map.get_tile_owner(hex) == game_manager.PLAYER_ID:
		_show_context(hex)
		return

	# 点击空地/敌方 → 取消选中
	game_manager.selected_army = null
	_hide_context()
	selected_label.text = ""

func _on_general_pressed():
	if _is_client():
		_send_net_action("hire_general")
		selected_label.text = "已发送：雇佣将军"
		return
	var n = game_manager.get_player_nation()
	if n == null: return
	if n.generals >= Nation.MAX_GENERALS:
		selected_label.text = "将军已达上限（%d/%d）" % [n.generals, Nation.MAX_GENERALS]
		return
	if n.gold < Nation.GENERAL_COST:
		selected_label.text = "黄金不足（需%d，当前%d）" % [Nation.GENERAL_COST, int(n.gold)]
		return
	game_manager.try_hire_general(game_manager.PLAYER_ID)
	selected_label.text = "已雇佣将军！现有 %d/%d 名" % [n.generals, Nation.MAX_GENERALS]
	_update_resource_display()

func _on_general_stance_pressed():
	if _is_client():
		_send_net_action("toggle_stance")
		selected_label.text = "已发送：切换将军模式"
		return
	var n = game_manager.get_player_nation()
	if n == null: return
	if n.generals == 0:
		selected_label.text = "还没有将军，无法切换模式"
		return
	if n.general_stance == "attack":
		n.general_stance = "defend"
		general_stance_button.text = "将军模式：防守 [P]"
		general_stance_button.modulate = Color(0.6, 0.8, 1.0)
		selected_label.text = "将军切换为防守模式：守护边界"
	else:
		n.general_stance = "attack"
		general_stance_button.text = "将军模式：进攻 [P]"
		general_stance_button.modulate = Color(1.0, 0.6, 0.6)
		selected_label.text = "将军切换为进攻模式：主动攻击"

func _on_minister_pressed():
	if _is_client():
		_send_net_action("hire_minister")
		selected_label.text = "已发送：雇佣文臣"
		return
	var n = game_manager.get_player_nation()
	if n == null: return
	if n.ministers >= Nation.MAX_MINISTERS:
		selected_label.text = "文臣已达上限（%d/%d）" % [n.ministers, Nation.MAX_MINISTERS]
		return
	if n.gold < Nation.MINISTER_COST:
		selected_label.text = "黄金不足（需%d，当前%d）" % [Nation.MINISTER_COST, int(n.gold)]
		return
	game_manager.try_hire_minister(game_manager.PLAYER_ID)
	selected_label.text = "已雇佣文臣！现有 %d/%d 名，产量+%d%%" % [n.ministers, Nation.MAX_MINISTERS, n.ministers * 35]
	_update_resource_display()

func _unlock_missile():
	missile_count += 1
	missile_btn.visible = true
	missile_btn.text = "▶ 导弹 [Q]  x%d" % missile_count
	selected_label.text = "彩蛋解锁！获得导弹 ×1，按 [Q] 激活瞄准"
	info_label.modulate = Color(1.0, 0.5, 0.0)

func _on_missile_pressed():
	if missile_count <= 0:
		selected_label.text = "没有导弹可用"
		return
	if missile_mode:
		missile_mode = false
		missile_btn.text = "▶ 导弹 [Q]  x%d" % missile_count
		selected_label.text = "导弹瞄准已取消"
		return
	missile_mode = true
	relocate_mode = false
	ally_mode = false
	missile_btn.text = "瞄准中... [Q取消]"
	selected_label.text = "导弹瞄准中，点击目标格  [右键/Q 取消]"

func _on_leave_alliance_pressed():
	if _is_client():
		_send_net_action("leave_alliance")
		selected_label.text = "已发送：退出联盟"
		return
	var al = game_manager.get_alliance_of(game_manager.PLAYER_ID)
	if al.is_empty():
		selected_label.text = "当前不在任何联盟中"
		return
	var names = []
	for id in al:
		if id != game_manager.PLAYER_ID:
			var n = game_manager.get_nation(id)
			if n: names.append(n.nation_name)
	game_manager.leave_alliance(game_manager.PLAYER_ID)
	selected_label.text = "已退出联盟（原盟友：%s）" % "、".join(names)
	_update_alliance_display()

func _on_ally_pressed():
	var n = game_manager.get_player_nation()
	if n == null or n.is_defeated: return
	ally_mode = true
	relocate_mode = false
	selected_label.text = "请点击目标国的领土选择结盟对象 [右键取消]"
	ally_button.text = "等待选择结盟目标..."

func _on_accept_alliance():
	var req = game_manager.get_pending_request_for_player()
	if req.is_empty():
		selected_label.text = "当前没有待处理的结盟申请！"
		return
	if _is_client():
		_send_net_action("accept_alliance", {"from_id": req.from_id})
		selected_label.text = "已发送：接受结盟"
		return
	game_manager.accept_alliance_request(req.from_id, req.to_id)
	var n = game_manager.get_nation(req.from_id)
	selected_label.text = "已接受 %s 的结盟申请！" % n.nation_name
	_update_alliance_display()

func _on_decline_alliance():
	var req = game_manager.get_pending_request_for_player()
	if req.is_empty():
		selected_label.text = "当前没有待处理的结盟申请！"
		return
	if _is_client():
		_send_net_action("decline_alliance", {"from_id": req.from_id})
		selected_label.text = "已拒绝结盟申请"
		return
	game_manager.decline_alliance_request(req.from_id, req.to_id)
	var n = game_manager.get_nation(req.from_id)
	selected_label.text = "已拒绝 %s 的结盟申请。" % n.nation_name

func _on_alliance_request_received(from_id: int):
	var n = game_manager.get_nation(from_id)
	selected_label.text = "%s 请求与你结盟！按 Y 接受 / N 拒绝" % n.nation_name

func _on_alliance_changed():
	_update_alliance_display()

func _update_alliance_display():
	if alliance_label == null:
		return
	if game_manager.alliances.is_empty():
		alliance_label.text = ""
		return
	var parts = []
	for al in game_manager.alliances:
		var names = []
		for id in al:
			var n = game_manager.get_nation(id)
			if n:
				names.append(n.nation_name)
		parts.append("[" + " + ".join(names) + "]")
	alliance_label.text = "联盟：" + "  ".join(parts)

func _on_relocate_pressed():
	var n = game_manager.get_player_nation()
	if n == null: return
	if not _is_client() and n.gold < 150:
		selected_label.text = "黄金不足（需150，当前%d）" % int(n.gold)
		return
	relocate_mode = true
	selected_label.text = "请点击己方草地作为新首都位置"
	relocate_button.text = "等待选择新首都... [右键取消]"

func _on_convert_pressed():
	if _is_client():
		_send_net_action("convert_food")
		selected_label.text = "已发送：粮→产"
		return
	var n = game_manager.get_player_nation()
	if n == null: return
	if n.food < 20:
		selected_label.text = "粮食不足（需20，当前%d）" % int(n.food)
		return
	game_manager.convert_food_to_production(game_manager.PLAYER_ID)
	selected_label.text = "转换成功：-20粮食 +10产量"
	_update_resource_display()

func _drag_build(hex: Vector2i):
	if hex == _drag_build_last_hex:
		return
	if not game_manager.game_active:
		return
	_drag_build_last_hex = hex
	if hex_map.get_tile_owner(hex) != game_manager.PLAYER_ID:
		return
	var n = game_manager.get_player_nation()
	if n == null or n.is_defeated:
		return
	match _drag_mode:
		0: # 自动：军队/部署地
			if game_manager.can_deploy_at(game_manager.PLAYER_ID, hex):
				if _is_client():
					_send_net_action("build_army", {"hex": hex})
				elif game_manager.try_build_army(game_manager.PLAYER_ID, hex) != null:
					_update_resource_display()
			elif game_manager.can_build_garrison_at(game_manager.PLAYER_ID, hex):
				if _is_client():
					_send_net_action("build_garrison", {"hex": hex})
				elif game_manager.try_build_garrison(game_manager.PLAYER_ID, hex) != null:
					_update_resource_display()
		1: # 农田
			if game_manager.can_build_farm_at(game_manager.PLAYER_ID, hex):
				if _is_client():
					_send_net_action("build_farm", {"hex": hex})
				elif game_manager.try_build_farm(game_manager.PLAYER_ID, hex):
					_update_resource_display()
		2: # 矿洞
			if game_manager.can_build_mine_at(game_manager.PLAYER_ID, hex):
				if _is_client():
					_send_net_action("build_mine", {"hex": hex})
				elif game_manager.try_build_mine(game_manager.PLAYER_ID, hex):
					_update_resource_display()

func _on_drag_mode_pressed():
	_drag_mode = (_drag_mode + 1) % 3
	var labels = ["自动", "农田", "矿洞"]
	_drag_mode_btn.text = "长按模式：%s [Z]" % labels[_drag_mode]

func _on_resource_updated(nation_id: int):
	if nation_id == game_manager.PLAYER_ID:
		_update_resource_display()

func _update_resource_display():
	var n = game_manager.get_player_nation()
	if n == null:
		return
	# 同步将军模式按钮文字（联机时由状态同步驱动）
	if general_stance_button != null:
		if n.general_stance == "defend":
			general_stance_button.text = "将军模式：防守 [P]"
			general_stance_button.modulate = Color(0.6, 0.8, 1.0)
		else:
			general_stance_button.text = "将军模式：进攻 [P]"
			general_stance_button.modulate = Color(1.0, 0.6, 0.6)
	var minister_pct = int(n.ministers * 35)
	var farm_cnt = 0; var mine_cnt = 0
	for hex in game_manager.hex_map.farm_data:
		if game_manager.hex_map.farm_data[hex] == game_manager.PLAYER_ID: farm_cnt += 1
	for hex in game_manager.hex_map.mine_data:
		if game_manager.hex_map.mine_data[hex] == game_manager.PLAYER_ID: mine_cnt += 1
	resource_label.text = "【%s】\n粮:%d 产:%d 金:%d\n人:%d 军:%d 农:%d 矿:%d\n将%d/%d 臣%d/%d +%d%%" % [
		n.nation_name, n.food, n.production, n.gold,
		n.population, n.armies.size(), farm_cnt, mine_cnt,
		n.generals, Nation.MAX_GENERALS,
		n.ministers, Nation.MAX_MINISTERS, minister_pct
	]

func _on_nation_defeated(nation_id: int):
	var n = game_manager.get_nation(nation_id)
	if n:
		if nation_id == game_manager.PLAYER_ID:
			info_label.text = "你的国家被消灭了！"
			info_label.modulate = Color.RED
		else:
			info_label.text = "%s 已被消灭！" % n.nation_name
			info_label.modulate = Color.ORANGE

func _on_game_over(winner_name: String):
	var vp = get_viewport_rect().size
	var over_layer = CanvasLayer.new()
	over_layer.layer = 20
	add_child(over_layer)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 1.0)
	bg.size = vp
	over_layer.add_child(bg)

	var win_label = Label.new()
	win_label.text = "游戏结束\n%s 一统天下！" % winner_name
	win_label.size = Vector2(vp.x, vp.y * 0.6)
	win_label.position = Vector2(0, vp.y * 0.12)
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 80)
	win_label.modulate = Color(1.0, 0.85, 0.0)
	over_layer.add_child(win_label)

	var continue_btn = _make_white_border_button("继续（3秒后可点击）")
	continue_btn.size = Vector2(360, 64)
	continue_btn.position = Vector2(vp.x * 0.5 - 180, vp.y * 0.78)
	continue_btn.add_theme_font_size_override("font_size", 28)
	continue_btn.disabled = true
	over_layer.add_child(continue_btn)

	continue_btn.pressed.connect(func():
		over_layer.queue_free()
		_show_battle_stats()
	)
	for i in range(3, 0, -1):
		continue_btn.text = "继续（%d秒后可点击）" % i
		await get_tree().create_timer(1.0).timeout
	continue_btn.text = "继续"
	continue_btn.disabled = false

func _setup_context_panel():
	context_panel = ColorRect.new()
	context_panel.color = Color(0.05, 0.05, 0.1, 0.92)
	context_panel.visible = false
	context_panel.size = Vector2(310, 10)
	ui_layer.add_child(context_panel)

	ctx_title = Label.new()
	ctx_title.position = Vector2(8, 6)
	ctx_title.size = Vector2(294, 26)
	ctx_title.add_theme_font_size_override("font_size", 20)
	ctx_title.modulate = Color.YELLOW
	context_panel.add_child(ctx_title)

	var btn_fs = 20
	var btn_h = 40
	ctx_army_btn     = _make_ctx_btn(btn_h, btn_fs, _on_ctx_army)
	ctx_garrison_btn = _make_ctx_btn(btn_h, btn_fs, _on_ctx_garrison)
	ctx_farm_btn     = _make_ctx_btn(btn_h, btn_fs, _on_ctx_farm)
	ctx_mine_btn     = _make_ctx_btn(btn_h, btn_fs, _on_ctx_mine)
	for btn in [ctx_army_btn, ctx_garrison_btn, ctx_farm_btn, ctx_mine_btn]:
		context_panel.add_child(btn)

func _make_ctx_btn(h: int, fs: int, cb: Callable) -> Button:
	var btn = Button.new()
	btn.size = Vector2(302, h)
	btn.add_theme_font_size_override("font_size", fs)
	btn.pressed.connect(cb)
	btn.visible = false
	return btn

func _show_context(hex: Vector2i):
	selected_hex = hex
	var hm = game_manager.hex_map
	var n = game_manager.get_player_nation()
	var terrain = hm.get_terrain(hex)
	var is_land = terrain == TerrainType.Type.PLAINS or terrain == TerrainType.Type.DESERT
	var has_army = game_manager.has_army_at(hex)
	var has_g = game_manager.has_garrison_at(hex)
	var has_farm = hex in hm.farm_data
	var has_mine = hex in hm.mine_data

	# 标题
	var what = []
	if has_army:  what.append("军队")
	if has_g:     what.append("部署地")
	if has_farm:  what.append("农田")
	if has_mine:  what.append("矿洞")
	ctx_title.text = "【%s】%s" % [TerrainType.get_terrain_name(terrain), " ".join(what)]

	# 军队按钮
	if has_army:
		ctx_army_btn.text = "解散军队 [D]  →+20产+10粮"
		ctx_army_btn.visible = true
	elif is_land and not has_g and n:
		ctx_army_btn.text = "建造军队 [B]  (20产+10粮)"
		ctx_army_btn.visible = true
	else:
		ctx_army_btn.visible = false

	# 部署地按钮
	var g = game_manager._get_garrison_at(hex)
	if has_g and g and not g.is_capital:
		ctx_garrison_btn.text = "拆除部署地 [D]  →+30产"
		ctx_garrison_btn.visible = true
	elif not has_g and is_land and not has_army and not has_farm and not has_mine and n:
		ctx_garrison_btn.text = "建造部署地 [G]  (30产)"
		ctx_garrison_btn.visible = true
	else:
		ctx_garrison_btn.visible = false

	# 农田按钮
	if has_farm:
		ctx_farm_btn.text = "拆除农田 [D]  →+10人口"
		ctx_farm_btn.visible = true
	elif is_land and not has_g and not has_mine and n:
		ctx_farm_btn.text = "建造农田 [E]  (10人口)"
		ctx_farm_btn.visible = true
	else:
		ctx_farm_btn.visible = false

	# 矿洞按钮
	if has_mine:
		ctx_mine_btn.text = "拆除矿洞 [D]  →+10人口"
		ctx_mine_btn.visible = true
	elif is_land and not has_g and not has_farm and n:
		ctx_mine_btn.text = "建造矿洞 [R]  (10人口)"
		ctx_mine_btn.visible = true
	else:
		ctx_mine_btn.visible = false

	# 布局按钮位置
	var btns = [ctx_army_btn, ctx_garrison_btn, ctx_farm_btn, ctx_mine_btn]
	var cy = 36
	for btn in btns:
		if btn.visible:
			btn.position = Vector2(4, cy)
			cy += 42
	context_panel.size = Vector2(310, cy + 4)

	# 定位面板（跟随格子，夹在屏幕内）
	var world_pos = hex_map.hex_to_pixel(hex)
	var vp = get_viewport_rect().size
	var sp = (world_pos - camera.position) * camera.zoom + vp * 0.5
	var px = clamp(sp.x + 50, 4, vp.x - 314)
	var py = clamp(sp.y - context_panel.size.y * 0.5, 4, vp.y - context_panel.size.y - 4)
	context_panel.position = Vector2(px, py)
	context_panel.visible = true

func _hide_context():
	selected_hex = Vector2i(-999, -999)
	context_panel.visible = false
	game_manager.selected_army = null

func _on_ctx_army():
	if selected_hex == Vector2i(-999, -999): return
	if _is_client():
		if game_manager.has_army_at(selected_hex):
			_send_net_action("disband_army", {"hex": selected_hex})
			selected_label.text = "已发送：解散军队"
		else:
			_send_net_action("build_army", {"hex": selected_hex})
			selected_label.text = "已发送：建造军队"
		return
	if game_manager.has_army_at(selected_hex):
		if game_manager.try_disband_army(game_manager.PLAYER_ID, selected_hex):
			selected_label.text = "军队已解散，返还20产+10粮"
	else:
		var n = game_manager.get_player_nation()
		if n and n.production < Nation.ARMY_COST_PROD:
			selected_label.text = "产量不足（需20，当前%d）" % int(n.production)
			return
		if n and n.food < Nation.ARMY_COST_FOOD:
			selected_label.text = "粮食不足（需10，当前%d）" % int(n.food)
			return
		if game_manager.try_build_army(game_manager.PLAYER_ID, selected_hex) != null:
			selected_label.text = "军队已部署！"
		else:
			selected_label.text = "无法部署军队"
	_update_resource_display()
	_show_context(selected_hex)

func _on_ctx_garrison():
	if selected_hex == Vector2i(-999, -999): return
	if _is_client():
		if game_manager.has_garrison_at(selected_hex):
			_send_net_action("demolish_garrison", {"hex": selected_hex})
			selected_label.text = "已发送：拆除部署地"
		else:
			_send_net_action("build_garrison", {"hex": selected_hex})
			selected_label.text = "已发送：建造部署地"
		return
	if game_manager.has_garrison_at(selected_hex):
		if game_manager.try_demolish_garrison(game_manager.PLAYER_ID, selected_hex):
			selected_label.text = "部署地已拆除，返还30产"
	else:
		var n = game_manager.get_player_nation()
		if n and n.production < 30:
			selected_label.text = "产量不足（需30，当前%d）" % int(n.production)
			return
		if game_manager.try_build_garrison(game_manager.PLAYER_ID, selected_hex) != null:
			selected_label.text = "部署地已建立！"
		else:
			selected_label.text = "无法建造部署地"
	_update_resource_display()
	_show_context(selected_hex)

func _on_ctx_farm():
	if selected_hex == Vector2i(-999, -999): return
	if _is_client():
		if hex_map.farm_data.get(selected_hex, -1) == game_manager.PLAYER_ID:
			_send_net_action("demolish_farm", {"hex": selected_hex})
			selected_label.text = "已发送：拆除农田"
		else:
			_send_net_action("build_farm", {"hex": selected_hex})
			selected_label.text = "已发送：建造农田"
		return
	if hex_map.farm_data.get(selected_hex, -1) == game_manager.PLAYER_ID:
		if game_manager.try_demolish_farm(game_manager.PLAYER_ID, selected_hex):
			selected_label.text = "农田已拆除，返还10人口"
	else:
		var n = game_manager.get_player_nation()
		if n and n.population < 10:
			selected_label.text = "人口不足（需10，当前%d）" % n.population
			return
		if game_manager.try_build_farm(game_manager.PLAYER_ID, selected_hex):
			selected_label.text = "农田已建造！"
		else:
			selected_label.text = "无法建造农田"
	_update_resource_display()
	_show_context(selected_hex)

func _on_ctx_mine():
	if selected_hex == Vector2i(-999, -999): return
	if _is_client():
		if hex_map.mine_data.get(selected_hex, -1) == game_manager.PLAYER_ID:
			_send_net_action("demolish_mine", {"hex": selected_hex})
			selected_label.text = "已发送：拆除矿洞"
		else:
			_send_net_action("build_mine", {"hex": selected_hex})
			selected_label.text = "已发送：建造矿洞"
		return
	if hex_map.mine_data.get(selected_hex, -1) == game_manager.PLAYER_ID:
		if game_manager.try_demolish_mine(game_manager.PLAYER_ID, selected_hex):
			selected_label.text = "矿洞已拆除，返还10人口"
	else:
		var n = game_manager.get_player_nation()
		if n and n.population < 10:
			selected_label.text = "人口不足（需10，当前%d）" % n.population
			return
		if game_manager.try_build_mine(game_manager.PLAYER_ID, selected_hex):
			selected_label.text = "矿洞已建造！"
		else:
			selected_label.text = "无法建造矿洞"
	_update_resource_display()
	_show_context(selected_hex)

func _ctx_action(action: String):
	if selected_hex == Vector2i(-999, -999):
		selected_label.text = "请先点击己方格子"
		return
	match action:
		"army":     _on_ctx_army()
		"garrison": _on_ctx_garrison()
		"farm":     _on_ctx_farm()
		"mine":     _on_ctx_mine()
		"demolish":
			if _is_client():
				_send_net_action("disband_army", {"hex": selected_hex})
				selected_label.text = "已发送：拆除操作"
				return
			if game_manager.try_disband_army(game_manager.PLAYER_ID, selected_hex):
				selected_label.text = "军队已解散，返还20产+10粮"
			elif game_manager.try_demolish_garrison(game_manager.PLAYER_ID, selected_hex):
				selected_label.text = "部署地已拆除，返还30产"
			elif game_manager.try_demolish_farm(game_manager.PLAYER_ID, selected_hex):
				selected_label.text = "农田已拆除，返还10人口"
			elif game_manager.try_demolish_mine(game_manager.PLAYER_ID, selected_hex):
				selected_label.text = "矿洞已拆除，返还10人口"
			else:
				selected_label.text = "该格没有可拆除的内容"
			_update_resource_display()
			_show_context(selected_hex)

# ── 联机系统 ─────────────────────────────────────────────

func _is_client() -> bool:
	return game_manager.net_mode and not game_manager.is_net_authority

func _send_net_action(action: String, params: Dictionary = {}):
	game_manager.rpc_id(1, "_net_action", action, params)

func _setup_network():
	net_mgr = load("res://scripts/NetworkManager.gd").new()
	net_mgr.name = "NetworkManager"
	add_child(net_mgr)
	net_mgr.connected_to_host.connect(_on_net_connected_to_host)
	net_mgr.connection_failed.connect(_on_net_connection_failed)
	net_mgr.peer_joined.connect(_on_peer_joined)
	net_mgr.peer_left.connect(_on_peer_left)
	game_manager.game_started.connect(_on_game_started)

func _setup_lobby():
	var vp = get_viewport().get_visible_rect().size
	var layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_lobby_panel = ColorRect.new()
	_lobby_panel.color = Color(0, 0, 0, 0.92)
	_lobby_panel.size = vp
	_lobby_panel.position = Vector2.ZERO
	layer.add_child(_lobby_panel)

	var title = Label.new()
	title.text = "帝国天下"
	title.add_theme_font_size_override("font_size", 72)
	title.modulate = Color(1.0, 0.85, 0.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vp.x, 100)
	title.position = Vector2(0, vp.y * 0.15)
	_lobby_panel.add_child(title)

	var cx = vp.x * 0.5
	var btn_w = 380.0
	var btn_h = 60.0
	var btn_fs = 28

	var sp_btn = _make_lobby_btn("单机游戏", Vector2(cx - btn_w * 0.5, vp.y * 0.4), Vector2(btn_w, btn_h), btn_fs)
	sp_btn.pressed.connect(_on_lobby_singleplayer)
	_lobby_panel.add_child(sp_btn)

	var host_btn = _make_lobby_btn("创建房间（主机）", Vector2(cx - btn_w * 0.5, vp.y * 0.4 + btn_h + 16), Vector2(btn_w, btn_h), btn_fs)
	host_btn.pressed.connect(_on_lobby_host)
	_lobby_panel.add_child(host_btn)

	var join_row_y = vp.y * 0.4 + (btn_h + 16) * 2
	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "输入主机IP（如 192.168.1.5）"
	_ip_input.size = Vector2(btn_w - 130, btn_h)
	_ip_input.position = Vector2(cx - btn_w * 0.5, join_row_y)
	_ip_input.add_theme_font_size_override("font_size", 22)
	_lobby_panel.add_child(_ip_input)

	var join_btn = _make_lobby_btn("加入", Vector2(cx + btn_w * 0.5 - 120, join_row_y), Vector2(120, btn_h), btn_fs)
	join_btn.pressed.connect(_on_lobby_join)
	_lobby_panel.add_child(join_btn)

	_lobby_status = Label.new()
	_lobby_status.size = Vector2(vp.x, 50)
	_lobby_status.position = Vector2(0, join_row_y + btn_h + 20)
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_status.add_theme_font_size_override("font_size", 24)
	_lobby_status.modulate = Color(0.7, 1.0, 0.7)
	_lobby_panel.add_child(_lobby_status)

	var exit_btn = _make_lobby_btn("退出游戏", Vector2(cx - btn_w * 0.5, vp.y * 0.88), Vector2(btn_w, btn_h - 10), btn_fs - 4)
	exit_btn.pressed.connect(_show_exit_confirm)
	_lobby_panel.add_child(exit_btn)

func _make_lobby_btn(txt: String, pos: Vector2, sz: Vector2, fs: int) -> Button:
	var btn = Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = sz
	btn.add_theme_font_size_override("font_size", fs)
	return btn

func _on_lobby_singleplayer():
	_lobby_panel.visible = false
	game_manager.net_mode = false
	game_manager.is_net_authority = true
	game_manager.PLAYER_ID = 0
	game_manager._player_nation_ids = [0]
	game_manager.nation_count = 7
	game_manager.initialize(hex_map, 7)
	_update_resource_display()

func _on_lobby_host():
	_lobby_status.text = "正在启动服务器..."
	if net_mgr.host_game():
		game_manager.net_mode = true
		game_manager.is_net_authority = true
		game_manager.PLAYER_ID = 0
		_connected_peers.clear()
		_host_nation_count = 7
		var local_ip = net_mgr.get_local_ip()
		_show_host_waiting_room(local_ip)

func _on_lobby_join():
	var ip = _ip_input.text.strip_edges()
	if ip.is_empty():
		_lobby_status.text = "请先输入主机IP地址"
		return
	_lobby_status.text = "正在连接 %s ..." % ip
	net_mgr.join_game(ip)

func _on_net_connected_to_host():
	game_manager.net_mode = true
	game_manager.is_net_authority = false
	_show_client_waiting_room()

func _on_net_connection_failed(reason: String):
	_lobby_status.modulate = Color(1.0, 0.4, 0.4)
	_lobby_status.text = "错误：%s" % reason

func _on_peer_joined(id: int):
	if not game_manager.is_net_authority:
		return
	_connected_peers.append(id)
	_update_player_list_display()
	if _start_btn != null:
		_start_btn.disabled = false
		_start_btn.text = "开始游戏（%d人已加入）" % (_connected_peers.size() + 1)

func _on_peer_left(id: int):
	if not game_manager.is_net_authority:
		return
	_connected_peers.erase(id)
	_update_player_list_display()
	if _connected_peers.is_empty() and _start_btn != null:
		_start_btn.disabled = true
		_start_btn.text = "开始游戏（至少需要2人）"

func _show_host_waiting_room(local_ip: String):
	_lobby_panel.visible = false
	var vp = get_viewport_rect().size

	_waiting_room_layer = CanvasLayer.new()
	_waiting_room_layer.layer = 10
	add_child(_waiting_room_layer)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.size = vp
	_waiting_room_layer.add_child(bg)

	var title = Label.new()
	title.text = "等待玩家加入"
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = Color(1.0, 0.85, 0.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vp.x, 80)
	title.position = Vector2(0, 36)
	_waiting_room_layer.add_child(title)

	var ip_lbl = Label.new()
	ip_lbl.text = "你的IP地址：%s" % local_ip
	ip_lbl.add_theme_font_size_override("font_size", 30)
	ip_lbl.modulate = Color(0.5, 1.0, 0.5)
	ip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_lbl.size = Vector2(vp.x, 50)
	ip_lbl.position = Vector2(0, 128)
	_waiting_room_layer.add_child(ip_lbl)

	# 国家数量选择
	var nc_lbl = Label.new()
	nc_lbl.text = "国家数量："
	nc_lbl.add_theme_font_size_override("font_size", 28)
	nc_lbl.modulate = Color.WHITE
	nc_lbl.position = Vector2(vp.x * 0.5 - 210, 196)
	_waiting_room_layer.add_child(nc_lbl)

	var minus_btn = _make_white_border_button("−")
	minus_btn.size = Vector2(50, 50)
	minus_btn.position = Vector2(vp.x * 0.5 - 10, 192)
	minus_btn.add_theme_font_size_override("font_size", 30)
	minus_btn.pressed.connect(_on_nation_count_minus)
	_waiting_room_layer.add_child(minus_btn)

	_nation_count_label = Label.new()
	_nation_count_label.text = str(_host_nation_count)
	_nation_count_label.add_theme_font_size_override("font_size", 38)
	_nation_count_label.modulate = Color(1.0, 0.85, 0.0)
	_nation_count_label.position = Vector2(vp.x * 0.5 + 46, 196)
	_nation_count_label.size = Vector2(50, 50)
	_nation_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_room_layer.add_child(_nation_count_label)

	var plus_btn = _make_white_border_button("+")
	plus_btn.size = Vector2(50, 50)
	plus_btn.position = Vector2(vp.x * 0.5 + 100, 192)
	plus_btn.add_theme_font_size_override("font_size", 30)
	plus_btn.pressed.connect(_on_nation_count_plus)
	_waiting_room_layer.add_child(plus_btn)

	# 玩家列表
	_player_list_label = Label.new()
	_player_list_label.add_theme_font_size_override("font_size", 24)
	_player_list_label.modulate = Color(0.8, 0.9, 1.0)
	_player_list_label.position = Vector2(vp.x * 0.5 - 220, 264)
	_player_list_label.size = Vector2(440, 320)
	_waiting_room_layer.add_child(_player_list_label)
	_update_player_list_display()

	# 开始按钮
	_start_btn = _make_white_border_button("开始游戏（至少需要2人）")
	_start_btn.size = Vector2(420, 60)
	_start_btn.position = Vector2(vp.x * 0.5 - 210, vp.y * 0.82)
	_start_btn.add_theme_font_size_override("font_size", 26)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_host_start_game)
	_waiting_room_layer.add_child(_start_btn)

	# 返回按钮
	var back_btn = _make_white_border_button("返回主界面")
	back_btn.size = Vector2(220, 50)
	back_btn.position = Vector2(vp.x * 0.5 - 110, vp.y * 0.91)
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.pressed.connect(_on_back_from_waiting_room)
	_waiting_room_layer.add_child(back_btn)

func _show_client_waiting_room():
	_lobby_panel.visible = false
	var vp = get_viewport_rect().size

	_waiting_room_layer = CanvasLayer.new()
	_waiting_room_layer.layer = 10
	add_child(_waiting_room_layer)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.size = vp
	_waiting_room_layer.add_child(bg)

	var title = Label.new()
	title.text = "已连接！"
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = Color(0.5, 1.0, 0.5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vp.x, 80)
	title.position = Vector2(0, vp.y * 0.32)
	_waiting_room_layer.add_child(title)

	_player_list_label = Label.new()
	_player_list_label.text = "等待房主开始游戏..."
	_player_list_label.add_theme_font_size_override("font_size", 28)
	_player_list_label.modulate = Color(0.8, 0.9, 1.0)
	_player_list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_list_label.position = Vector2(0, vp.y * 0.48)
	_player_list_label.size = Vector2(vp.x, 80)
	_waiting_room_layer.add_child(_player_list_label)

func _update_player_list_display():
	if _player_list_label == null:
		return
	var nation_names = ["秦国", "楚国", "赵国", "魏国", "燕国", "韩国", "齐国"]
	var text = "玩家列表：\n"
	text += "• 房主（%s）\n" % nation_names[0]
	for i in range(_connected_peers.size()):
		var n_idx = i + 1
		if n_idx < nation_names.size():
			text += "• 玩家%d（%s）\n" % [i + 1, nation_names[n_idx]]
	var total = _connected_peers.size() + 1
	var ai_count = max(0, _host_nation_count - total)
	if ai_count > 0:
		text += "• AI × %d\n" % ai_count
	_player_list_label.text = text

func _on_nation_count_minus():
	var min_count = max(2, _connected_peers.size() + 1)
	if _host_nation_count > min_count:
		_host_nation_count -= 1
		if _nation_count_label:
			_nation_count_label.text = str(_host_nation_count)
		_update_player_list_display()

func _on_nation_count_plus():
	if _host_nation_count < 7:
		_host_nation_count += 1
		if _nation_count_label:
			_nation_count_label.text = str(_host_nation_count)
		_update_player_list_display()

func _on_host_start_game():
	if _start_btn:
		_start_btn.disabled = true
		_start_btn.text = "游戏开始中..."
	await game_manager.start_game_for_all(_host_nation_count)

func _on_game_started():
	if _waiting_room_layer != null:
		_waiting_room_layer.queue_free()
		_waiting_room_layer = null
	_player_list_label = null
	_start_btn = null
	_nation_count_label = null
	_lobby_panel.visible = false
	if game_manager.is_net_authority:
		_update_resource_display()
		_update_alliance_display()
	else:
		game_manager.hex_map = hex_map
		game_manager.nation_resource_updated.connect(_on_client_first_state, CONNECT_ONE_SHOT)

func _on_client_first_state(_nation_id: int):
	_update_resource_display()
	_update_alliance_display()

func _on_game_reset():
	if _stats_layer:
		_stats_layer.queue_free()
		_stats_layer = null
	_restart_agreed_ids.clear()
	_agree_labels.clear()
	game_manager.nation_resource_updated.connect(_on_client_first_state, CONNECT_ONE_SHOT)

func _on_back_from_waiting_room():
	if _waiting_room_layer != null:
		_waiting_room_layer.queue_free()
		_waiting_room_layer = null
	_player_list_label = null
	_start_btn = null
	_nation_count_label = null
	_connected_peers.clear()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	_lobby_panel.visible = true
	_lobby_status.text = ""
	_lobby_status.modulate = Color(0.7, 1.0, 0.7)

# ── 白色边框按钮 ──────────────────────────────────────

func _make_white_border_button(txt: String) -> Button:
	var btn = Button.new()
	btn.text = txt
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s = StyleBoxFlat.new()
		s.bg_color = Color(0.15, 0.15, 0.15, 0.9) if state != "disabled" else Color(0.05, 0.05, 0.05, 0.5)
		s.border_color = Color.WHITE if state != "disabled" else Color(0.4, 0.4, 0.4)
		s.set_border_width_all(2)
		s.content_margin_left = 12; s.content_margin_right = 12
		s.content_margin_top = 6;  s.content_margin_bottom = 6
		if state == "hover":
			s.bg_color = Color(0.28, 0.28, 0.28, 0.95)
		btn.add_theme_stylebox_override(state, s)
	return btn

# ── 战果统计界面 ──────────────────────────────────────

var _restart_agreed_ids: Array = []
var _agree_labels: Dictionary = {}
var _stats_layer: CanvasLayer = null

func _show_battle_stats():
	var vp = get_viewport_rect().size
	_stats_layer = CanvasLayer.new()
	_stats_layer.layer = 20
	add_child(_stats_layer)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 1.0)
	bg.size = vp
	_stats_layer.add_child(bg)

	var title = Label.new()
	title.text = "战果统计"
	title.size = Vector2(vp.x, 70)
	title.position = Vector2(0, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = Color(1.0, 0.85, 0.0)
	_stats_layer.add_child(title)

	var sorted_nations = game_manager.nations.duplicate()
	sorted_nations.sort_custom(func(a, b):
		if not a.is_defeated and b.is_defeated: return true
		if a.is_defeated and not b.is_defeated: return false
		return a.nations_eliminated > b.nations_eliminated
	)

	var row_h = 88
	var sy = 95
	for n in sorted_nations:
		var bar = ColorRect.new()
		bar.color = n.color
		bar.size = Vector2(8, 72)
		bar.position = Vector2(36, sy)
		_stats_layer.add_child(bar)

		var status = "★ 胜利" if not n.is_defeated else "已消灭"
		var lbl = Label.new()
		lbl.text = "%s  %s\n消灭：%d 国   军队：%d   农田：%d   矿洞：%d   部署地：%d" % [
			n.nation_name, status,
			n.nations_eliminated, n.armies_built,
			n.farms_built, n.mines_built, n.garrisons_built
		]
		lbl.position = Vector2(56, sy)
		lbl.size = Vector2(vp.x - 72, row_h - 10)
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.modulate = n.color if not n.is_defeated else Color(0.65, 0.65, 0.65)
		_stats_layer.add_child(lbl)
		sy += row_h

	# 按钮行
	var btn_y = vp.y - 130
	var cx = vp.x * 0.5

	var replay_btn = _make_white_border_button("再来一盘")
	replay_btn.size = Vector2(200, 56)
	replay_btn.position = Vector2(cx - 220, btn_y)
	replay_btn.add_theme_font_size_override("font_size", 26)
	replay_btn.pressed.connect(_on_replay_pressed)
	_stats_layer.add_child(replay_btn)

	var menu_btn = _make_white_border_button("返回主界面")
	menu_btn.size = Vector2(200, 56)
	menu_btn.position = Vector2(cx + 20, btn_y)
	menu_btn.add_theme_font_size_override("font_size", 26)
	menu_btn.pressed.connect(_on_return_to_lobby)
	_stats_layer.add_child(menu_btn)

	# 联机同意状态标签
	if game_manager.net_mode:
		var label_y = btn_y + 68
		for n in game_manager.nations:
			if n.id in game_manager._player_nation_ids:
				var al = Label.new()
				al.text = "%s：等待中" % n.nation_name
				al.position = Vector2(cx - 180, label_y)
				al.size = Vector2(360, 28)
				al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				al.add_theme_font_size_override("font_size", 20)
				al.modulate = Color(0.7, 0.7, 0.7)
				_stats_layer.add_child(al)
				_agree_labels[n.id] = al
				label_y += 30
		game_manager.restart_agreed.connect(_on_restart_agreed)

func _on_replay_pressed():
	_restart_agreed_ids.clear()
	if game_manager.net_mode:
		game_manager.agree_restart()
	else:
		_do_restart()

func _on_restart_agreed(nation_id: int):
	if nation_id not in _restart_agreed_ids:
		_restart_agreed_ids.append(nation_id)
	if nation_id in _agree_labels:
		var n = game_manager.get_nation(nation_id)
		_agree_labels[nation_id].text = "%s：已同意" % n.nation_name
		_agree_labels[nation_id].modulate = Color(0.4, 1.0, 0.4)
	# 主机判断所有玩家是否都同意
	var need = game_manager._player_nation_ids.size()
	if game_manager.is_net_authority and _restart_agreed_ids.size() >= need:
		_do_restart()

func _do_restart():
	if _stats_layer:
		_stats_layer.queue_free()
		_stats_layer = null
	_restart_agreed_ids.clear()
	_agree_labels.clear()
	game_manager.reset_game()
	# reset_game handles _net_do_restart + _broadcast_init internally for net mode
	_update_resource_display()
	_update_alliance_display()

func _on_return_to_lobby():
	if _stats_layer:
		_stats_layer.queue_free()
		_stats_layer = null
	_restart_agreed_ids.clear()
	_agree_labels.clear()
	_connected_peers.clear()
	if game_manager.net_mode:
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer = null
		game_manager.net_mode = false
		game_manager._player_nation_ids.clear()
		game_manager._peer_to_nation.clear()
	_lobby_panel.visible = true
	_lobby_status.text = ""
	_lobby_status.modulate = Color(0.7, 1.0, 0.7)

# ── 退出游戏确认 ──────────────────────────────────────

func _show_exit_confirm():
	var vp = get_viewport_rect().size
	var layer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.88)
	bg.size = vp
	layer.add_child(bg)

	var lbl = Label.new()
	lbl.text = "确定要退出游戏吗？"
	lbl.size = Vector2(vp.x, 120)
	lbl.position = Vector2(0, vp.y * 0.35)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.modulate = Color.WHITE
	layer.add_child(lbl)

	var cx = vp.x * 0.5
	var by = vp.y * 0.55

	var yes_btn = _make_white_border_button("确认退出吗，退出是给")
	yes_btn.size = Vector2(180, 56)
	yes_btn.position = Vector2(cx - 200, by)
	yes_btn.add_theme_font_size_override("font_size", 26)
	yes_btn.pressed.connect(func(): get_tree().quit())
	layer.add_child(yes_btn)

	var no_btn = _make_white_border_button("取消")
	no_btn.size = Vector2(180, 56)
	no_btn.position = Vector2(cx + 20, by)
	no_btn.add_theme_font_size_override("font_size", 26)
	no_btn.pressed.connect(func(): layer.queue_free())
	layer.add_child(no_btn)
