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

const DEFAULT_SIGNAL_URL := "ws://127.0.0.1:8915"
const ICE_SERVERS := [{ "urls": ["stun:stun.l.google.com:19302"] }]
const PLAYER_SCENE := preload("res://player.tscn")

var signal_url := DEFAULT_SIGNAL_URL

var ws := WebSocketMultiplayerPeer.new()
var rtc_peer := WebRTCMultiplayerPeer.new()
var lb := Leaderboard.new()

var peers := {} # peer_id -> WebRTCPeerConnection
var spawned := {} # peer_id -> Node2D
var names := {} # peer_id -> display name


var confirmed_leaderboard := {} # peer_id -> score
var temp_leaderboard := {}
var pending_peers := []



var my_id := 0
var player_name := "Player"
var current_frame: int = 0

@onready var players_parent: Node2D = get_node("../Players")


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_rtc_peer_connected)
	multiplayer.peer_disconnected.connect(_on_rtc_peer_disconnected)


func _on_rtc_peer_connected(peer_id: int) -> void:
	print("rtc peer connected ", peer_id)

	# DEBUG: bypass sync handler while testing RPC protocol
	#if peers.size() == SynchronizationHandler.num_players - 1:
	#	SynchronizationHandler.start_game()

func _on_rtc_peer_disconnected(peer_id: int) -> void:
	print("rtc peer disconnected ", peer_id)
	peers.erase(peer_id)
	despawn_player(peer_id)
	
func _process(_delta: float) -> void:
	ws.poll()
	while ws.get_available_packet_count() > 0:
		var packet := ws.get_packet()
		if packet == null:
			continue
		var data = JSON.parse_string(packet.get_string_from_utf8())
		handle_message(data)

	if my_id != 0:
		current_frame += 1
		var local_input := _read_local_input()
		submit_input.rpc(current_frame, local_input)

		_handle_debug_input()


func _handle_debug_input() -> void:
	if Input.is_action_just_pressed("debug_attest_attack"):
		var victim := _pick_other_peer()
		if victim != 0:
			print("[debug] %s attests I attacked %s at frame 0" % [name_of(my_id), name_of(victim)])
			receive_vote.rpc(0, my_id, victim)

	if Input.is_action_just_pressed("debug_attest_victim"):
		var attacker := _pick_other_peer()
		if attacker != 0:
			print("[debug] %s attests I was hit by %s at frame 0" % [name_of(my_id), name_of(attacker)])
			receive_vote.rpc(0, attacker, my_id)

	if Input.is_action_just_pressed("debug_dump_leaderboard"):
		print("[debug] my lb.confirmed = ", _named_dict(lb.confirmed))
		print("[debug] my lb.pending = ", lb.pending)
		request_all_leaderboards()
		await get_tree().create_timer(0.5).timeout
		print("[debug] merged confirmed_leaderboard = ", _named_dict(confirmed_leaderboard))


func _pick_other_peer() -> int:
	for pid in peers.keys():
		return pid
	return 0


func name_of(pid: int) -> String:
	return "%s(%d)" % [names.get(pid, "Player"), pid]


func _named_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for pid in d:
		out[name_of(int(pid))] = d[pid]
	return out

func _read_local_input() -> Array[String]:
	var input: Array[String] = []
	if Input.is_action_pressed("ui_left"):
		input.append("ui_left")
	elif Input.is_action_pressed("ui_right"):
		input.append("ui_right")
	if Input.is_action_pressed("ui_up"):
		input.append("ui_up")
	if Input.is_action_pressed("ui_down"):
		input.append("ui_down")
	if Input.is_action_just_pressed("attack"):
		input.append("attack")
	if Input.is_action_just_pressed("dodge"):
		input.append("dodge")
	return input



@rpc("any_peer", "call_remote", "reliable")
func receive_vote(frame, attacker_peer, victim_peer):
	if my_id == attacker_peer or my_id == victim_peer:
		return

	var key = [frame, attacker_peer, victim_peer]
	if !lb.pending.has(key):
		lb.pending[key] = [false, false]
	
	var sender := multiplayer.get_remote_sender_id()
	if sender == attacker_peer:
		lb.pending[key][0] = true
	elif sender == victim_peer:
		lb.pending[key][1] = true
	else:
		return

	if lb.pending[key][0] and lb.pending[key][1]:
		lb.confirmed[attacker_peer] = lb.confirmed.get(attacker_peer, 0) + 1
		lb.pending.erase(key)
	
func request_all_leaderboards():
	temp_leaderboard = {}
	for peer_id in lb.confirmed:
		temp_leaderboard[peer_id] = [lb.confirmed[peer_id]]

	pending_peers = multiplayer.get_peers()
	rpc("share_leaderboard")


@rpc("any_peer", "call_remote", "reliable")
func receive_leaderboard(data):
	var sender = multiplayer.get_remote_sender_id()
	var parsed = JSON.parse_string(data.get_string_from_utf8())

	for peer_id in parsed:
		var pid_int := int(peer_id)
		if not temp_leaderboard.has(pid_int):
			temp_leaderboard[pid_int] = []
		temp_leaderboard[pid_int].append(parsed[peer_id])
	
	pending_peers.erase(sender)
	if pending_peers.is_empty():
		finalize_leaderboard()

func finalize_leaderboard():
	confirmed_leaderboard = {}
	for peer_id in temp_leaderboard:
		var scores : Array = temp_leaderboard[peer_id]
		var total = scores.reduce(func(a, b): return a + b)
		confirmed_leaderboard[peer_id] = total
	
	

@rpc("any_peer", "call_remote", "reliable")
func share_leaderboard():
	var caller := multiplayer.get_remote_sender_id()
	rpc_id(caller, "receive_leaderboard", JSON.stringify(lb.confirmed).to_utf8_buffer())


@rpc("any_peer", "call_remote", "reliable")
func submit_input(frame: int, inputs: Array[String]) -> void:
	if inputs.is_empty():
		return
	var sender := multiplayer.get_remote_sender_id()
	#print("[recv] f=%d from=%d input=%s" % [frame, sender, inputs])
	# DEBUG: bypass sync handler while testing RPC protocol
	#SynchronizationHandler.remote_input.append([frame, sender, inputs])


func connect_to_signal_server() -> void:
	print("connecting to signaling server: ", signal_url)
	ws.create_client(signal_url)


func handle_message(data: Dictionary) -> void:
	match int(data["message"]):
		Message.id:
			my_id = int(data["id"])
			names[my_id] = player_name
			print("my id: ", my_id, " (", player_name, ")")
			DisplayServer.window_set_title("%s (Peer %d)" % [player_name, my_id])
			rtc_peer.create_mesh(my_id)
			multiplayer.multiplayer_peer = rtc_peer
			spawn_player(my_id)
			send_message({ "id": my_id, "name": player_name, "message": Message.lobby })

		Message.userConnected:
			var pid := int(data["id"])
			var pname := str(data.get("name", "Player"))
			names[pid] = pname
			if pid == my_id:
				return
			create_peer(pid)
			spawn_player(pid)

		Message.lobby:
			pass

		Message.offer:
			var from := int(data["orgPeer"])
			if peers.has(from):
				peers[from].set_remote_description("offer", data["data"])

		Message.answer:
			var from := int(data["orgPeer"])
			if peers.has(from):
				peers[from].set_remote_description("answer", data["data"])

		Message.candidate:
			var from := int(data["orgPeer"])
			if peers.has(from):
				peers[from].add_ice_candidate(data["mid"], int(data["index"]), data["sdp"])



func create_peer(peer_id: int) -> void:
	if peer_id == my_id or peers.has(peer_id):
		return

	var pc := WebRTCPeerConnection.new()
	pc.initialize({ "iceServers": ICE_SERVERS })
	pc.session_description_created.connect(_on_session_description_created.bind(peer_id))
	pc.ice_candidate_created.connect(_on_ice_candidate_created.bind(peer_id))

	peers[peer_id] = pc
	rtc_peer.add_peer(pc, peer_id)

	if peer_id < my_id:
		pc.create_offer()


func _on_session_description_created(type: String, sdp: String, peer_id: int) -> void:
	if not peers.has(peer_id):
		return
	peers[peer_id].set_local_description(type, sdp)
	send_message({
		"peer": peer_id,
		"orgPeer": my_id,
		"message": Message.offer if type == "offer" else Message.answer,
		"data": sdp,
	})


func _on_ice_candidate_created(mid: String, index: int, sdp: String, peer_id: int) -> void:
	send_message({
		"peer": peer_id,
		"orgPeer": my_id,
		"message": Message.candidate,
		"mid": mid,
		"index": index,
		"sdp": sdp,
	})

func spawn_player(peer_id: int) -> void:
	if spawned.has(peer_id):
		return
	var node := PLAYER_SCENE.instantiate()
	node.player_number = spawned.size()
	node.name = "Peer_%d" % peer_id
	node.position = spawn_position_for(peer_id)
	players_parent.add_child(node)
	spawned[peer_id] = node


func despawn_player(peer_id: int) -> void:
	if not spawned.has(peer_id):
		return
	spawned[peer_id].queue_free()
	spawned.erase(peer_id)


func spawn_position_for(peer_id: int) -> Vector2:
	var slot := peer_id % 5
	return Vector2(-400.0 + slot * 200.0, 400.0)

func send_message(message: Dictionary) -> void:
	ws.put_packet(JSON.stringify(message).to_utf8_buffer())
