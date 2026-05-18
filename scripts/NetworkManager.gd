extends Node

signal connected_to_host()
signal connection_failed(reason: String)
signal peer_joined(id: int)
signal peer_left(id: int)

const PORT := 7777
const MAX_PLAYERS := 6

func host_game() -> bool:
	var peer = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS) != OK:
		connection_failed.emit("端口 %d 被占用，请关闭其他程序后重试" % PORT)
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return true

func join_game(ip: String) -> bool:
	var peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		connection_failed.emit("无法连接，请确认IP地址")
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): connected_to_host.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit("连接失败，请确认IP地址正确"))
	return true

func get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"

func _on_peer_connected(id: int):
	peer_joined.emit(id)

func _on_peer_disconnected(id: int):
	peer_left.emit(id)
