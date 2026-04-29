extends Node2D

const MAX_ROLLBACK = 10

var num_players = 2
var current_frame: int = -1
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
	var players: Array[player_state]

	func _init() -> void:
		players = []
		for i in range(SynchronizationHandler.num_players):
			players.append(player_state.new())

class state_buffer:
	var game_states: Array[frame_state]
	var barriers: Array[Barrier]
	var pop_offset: int = 0

	func new_frame() -> void:
		var new_frame_state = frame_state.new()
		game_states.append(new_frame_state)
		if game_states.size() > MAX_ROLLBACK:
			game_states.pop_front()
			barriers.pop_front()
			pop_offset += 1

	func get_current_barrier(frame: int) -> Barrier:
		return barriers[frame - pop_offset]
	
	func update_player_state(frame: int, player: int, state: player_state) -> void:
		var frame_state = game_states[frame - pop_offset]
		frame_state.players[player] = state
	
	func get_player_state(frame: int, player: int) -> player_state:
		# print("Getting state for frame ", frame, " player ", player)
		# print(game_states)
		# # print(game_states[0])
		# print(game_states[0].players)
		var frame_state = game_states[frame - pop_offset]
		return frame_state.players[player]

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
		# print(local_sense)
		# print("Player ", player_id, " reached barrier with sense ", s)
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

func _enter_tree() -> void:
	save_states = state_buffer.new()
	new_frame_barrier = Barrier.new(num_players+1)

	print("New game started with ", num_players, " players")


func _process(_delta: float) -> void:
	current_frame += 1
	save_states.new_frame()
	#Get local input
	var local_input = get_local_input()
	var local_player_state = player_state.new()
	local_player_state.input = local_input
	save_states.update_player_state(current_frame, 0, local_player_state)
	#Get remote input
	#Figure out conflicts
	save_states.barriers.append(Barrier.new(num_players)) # Should add barriers with the right number of players to correct frames
	#Start threads at correct frame

	new_frame_barrier.cycle(num_players) 


func get_local_input() -> Array[String]:
	var input: Array[String] = []
	if Input.is_action_pressed("ui_left"):
		input.append("ui_left")
	elif Input.is_action_pressed("ui_right"):
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