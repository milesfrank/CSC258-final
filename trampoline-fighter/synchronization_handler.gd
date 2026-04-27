extends Node2D

const MAX_ROLLBACK = 10

var num_players

class player_state:
	var input: String
	var pos: Vector2
	var vel: Vector2
	var state: int
	var hit_players: Array
	var current_state_frame_counter: int

class frame_state:
	var players: Array[player_state]

class state_buffer:
	var game_states: Array[frame_state]
	
	func update_player_state(frame: int, player: int, state: player_state) -> void:
		var frame_state = game_states[frame]
		frame_state.players[player] = player_state
	
	func get_player_state(frame: int, player: int) -> player_state:
		var frame_state = game_states[frame]
		return frame_state.players[player]

func _ready() -> void:
	var game_states = state_buffer.new()
# Called every frame. 'delta' is the elapsed time since the previous frame.

# FIX LATER


func _process(_delta: float) -> void:
	#Get local input
	#Get remote input
	#Figure out conflicts
	#Start threads at correct frame

	pass
