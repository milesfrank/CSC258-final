extends Node2D

@onready var join_button: Button = $UI/JoinButton
@onready var client = $Client
@onready var server = $Server


func _ready() -> void:
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--host="):
			var host := arg.substr(7)
			client.signal_url = "ws://%s:%d" % [host, server.PORT]

	if "--server" in args:
		join_button.hide()


func _on_join_pressed() -> void:
	join_button.hide()
	client.connect_to_signal_server()
