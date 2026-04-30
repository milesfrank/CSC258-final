extends Node2D

const MAX_ROLLBACK = 10

var num_players = 3
var current_frame: int = 0
var save_states: state_buffer
var new_frame_barrier: Barrier
var start_flag: bool = false

class player_state:
	var input: Array[String]
	var pos: Vector2
	var vel: Vector2
	var state: int
	var hit_players: Array[bool]
	var current_state_frame_counter: int

	func _init() -> void:
		input = []
		pos = Vector2.ZERO
		vel = Vector2.ZERO
		state = 0
		hit_players = []
		current_state_frame_counter = 0

	func copy_from(other: player_state) -> void:
		input = other.input.duplicate()
		pos = other.pos
		vel = other.vel
		state = other.state
		hit_players = other.hit_players.duplicate()
		current_state_frame_counter = other.current_state_frame_counter

class frame_state:
	var players: Array[player_state] = []

	func _init() -> void:
		for i in range(SynchronizationHandler.num_players):
			players.append(player_state.new())

class state_buffer:
	var game_states: Array[frame_state] = []
	var barriers: Array[Barrier] = []

	func _init() -> void:
		for i in range(MAX_ROLLBACK):
			game_states.append(frame_state.new())
			barriers.append(Barrier.new(SynchronizationHandler.num_players))

	func get_current_barrier(frame: int) -> Barrier:
		return barriers[frame % MAX_ROLLBACK]
	
	func update_player_state(frame: int, player: int, state: player_state) -> void:
		var frame_state = game_states[frame % MAX_ROLLBACK]
		frame_state.players[player] = state
	
	func get_player_state(frame: int, player: int) -> player_state:
		var frame_state = game_states[frame % MAX_ROLLBACK]
		return frame_state.players[player]

	func set_input(frame: int, player: int, input: Array[String]) -> void:
		var frame_state = game_states[frame % MAX_ROLLBACK]
		frame_state.players[player].input = input


func _enter_tree() -> void:
	save_states = state_buffer.new()
	new_frame_barrier = Barrier.new(num_players+1)

	print("New game started with ", num_players, " players")


signal update_positions(frame: int)

func _process(_delta: float) -> void:
	var local_input = get_local_input()
	save_states.set_input(current_frame, 0, local_input)
	
	#Start threads at correct frame

	new_frame_barrier.cycle(num_players) # Tell threads to start next frame after main thread has done setup

	new_frame_barrier.cycle(num_players) # Wait for threads to finish simulating next frame before updating positions

	update_positions.emit(current_frame)

	current_frame += 1


func get_local_input() -> Array[String]:
	var input: Array[String] = []
	if Input.is_action_pressed("ui_left"):
		input.append("ui_left")
	if Input.is_action_pressed("ui_right"):
		input.append("ui_right")

	if Input.is_action_pressed("ui_up"): # Jump
		input.append("ui_up")
	if Input.is_action_pressed("ui_down"): # Fast fall
		input.append("ui_down")
	
	if Input.is_action_just_pressed("attack"):
		input.append("attack")
	if Input.is_action_just_pressed("dodge"):
		input.append("dodge")

	return input



class Barrier:
	var count: int = 0
	var n: int
	var sense: bool = true
	var local_sense: Array[bool]
	var lock: Mutex = Mutex.new()

	func _init(_n: int) -> void:
		self.n = _n
		local_sense = []
		for i in range(max(SynchronizationHandler.num_players, _n)):
			local_sense.append(true)

	func cycle(player_id: int) -> void:
		var s = not local_sense[player_id]
		local_sense[player_id] = s
		if fai() == n:
			count = 0
			sense = s
		else:
			# var delay = 1
			while sense != s:
				# if main_thread:
				# print(delay)
				# OS.delay_msec(delay) # Sleep to prevent busy waiting
				# delay = min(delay * 2, 100) # Exponential backoff with max delay
				pass

	func fai() -> int:
		lock.lock()
		count += 1
		lock.unlock()
		return count
