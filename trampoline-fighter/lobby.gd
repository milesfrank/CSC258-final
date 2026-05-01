extends Node2D

@onready var join_button: Button = $UI/JoinButton
@onready var name_edit: LineEdit = $UI/NameEdit
@onready var leaderboard_label: Label = $UI/LeaderboardLabel
@onready var client = $Client
@onready var server = $Server

var _t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--host="):
			var host := arg.substr(7)
			client.signal_url = "ws://%s:%d" % [host, server.PORT]

	if "--server" in args:
		join_button.hide()
		name_edit.hide()


func _on_join_pressed() -> void:
	var entered := name_edit.text.strip_edges()
	if entered.is_empty():
		entered = "Player"
	client.player_name = entered
	join_button.hide()
	name_edit.hide()
	client.connect_to_signal_server()


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0 or client.my_id == 0:
		return
	_t = 0.0
	client.request_all_leaderboards()
	await get_tree().create_timer(0.4).timeout
	var rows : Array = client.names.keys()
	rows.sort_custom(func(a, b): return client.confirmed_leaderboard.get(a, 0) > client.confirmed_leaderboard.get(b, 0))
	var text := "Leaderboard:"
	for pid in rows:
		text += "\n  %s: %d" % [client.names[pid], client.confirmed_leaderboard.get(pid, 0)]
	leaderboard_label.text = text
