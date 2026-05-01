extends Node

enum Message {
	id,
	join,
	lobby,
	userConnected,
	offer,
	answer,
	candidate,
}

const PORT := 8915

var ws := WebSocketMultiplayerPeer.new()
var lobby := Lobby.new()


func _ready() -> void:
	ws.peer_connected.connect(_on_peer_connected)
	ws.peer_disconnected.connect(_on_peer_disconnected)

	if "--server" in OS.get_cmdline_args():
		start_server()


func _process(_delta: float) -> void:
	ws.poll()
	while ws.get_available_packet_count() > 0:
		var packet := ws.get_packet()
		if packet == null:
			continue
			
		var data = JSON.parse_string(packet.get_string_from_utf8())
		handle_message(data)


func handle_message(data: Dictionary) -> void:
	match int(data["message"]):
		Message.lobby:
			print("joining lobby: ", data["id"], " as ", data.get("name", "Player"))
			join_lobby(int(data["id"]), str(data.get("name", "Player")))

		Message.offer, Message.answer, Message.candidate:
			send_to(int(data["peer"]), data)


func join_lobby(user_id: int, p_name: String) -> void:
	lobby.addPlayer(user_id, p_name)

	# tell every existing peer about the new one and the new one about each existing peer
	for p in lobby.players:
		send_to(p, { "message": Message.userConnected, "id": user_id, "name": p_name })
		send_to(user_id, { "message": Message.userConnected, "id": p, "name": lobby.players[p].get("name", "Player") })
		send_to(p, {
			"message": Message.lobby,
			"players": JSON.stringify(lobby.players),
		})

	send_to(user_id, {
		"id": user_id,
		"message": Message.userConnected,
		"player": lobby.players[user_id],
		"name": p_name,
	})


func send_to(user_id: int, data: Dictionary) -> void:
	var peer := ws.get_peer(user_id)
	if peer == null:
		push_warning("no peer with id %d" % user_id)
		return
	peer.put_packet(JSON.stringify(data).to_utf8_buffer())


func _on_peer_connected(id: int) -> void:
	print("peer connected: ", id)
	send_to(id, { "id": id, "message": Message.id })


func _on_peer_disconnected(_id: int) -> void:
	pass


func start_server() -> void:
	ws.create_server(PORT)
	print("server started on port ", PORT)
	print("clients on this LAN should connect with --host=<one of>:")
	for addr in IP.get_local_addresses():
		if addr.begins_with("127.") or addr.contains(":"):
			continue
		print("  ", addr)
