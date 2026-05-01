extends Node2D

class_name Player

const MAX_FALL_SPEED: float = 35.0
const GRAVITY: Vector2 = 1 * Vector2.DOWN
const MAX_SPEED: float = 17
const ACCELERATION: float = 2.0
const JUMP_SPEED: float = -30.0
const MIN_JUMP_SPEED: float = -8
const ATTACK_RANGE: float = 128.0
const DODGE_SPEED: float = 50.0
const KNOCKBACK_SPEED: float = 40.0

var thread = Thread.new()

var velocity: Vector2 = Vector2.ZERO
var movement_direction_x: int = 0

var jump_buffered: bool = false
var jumps: int = 1
var fast_fall_buffered: bool = false
var dodge_buffered: bool = false

var attack_buffered: bool = false
var hit_players: Array[bool] = []

var current_state_frame_counter: int = 0
var state: State = State.MOVING:
	set(value):
		if value == state:
			return
		current_state_frame_counter = 0
		state = value

enum State {
	MOVING,
	ATTACKING,
	DODGING,
	ATTACK_LAG,
	DODGE_LAG,
	HIT_STUN,
}
const STATE_FRAMES = {
	State.MOVING: 0,
	State.ATTACKING: 10,
	State.DODGING: 10,
	State.ATTACK_LAG: 10,
	State.DODGE_LAG: 10,
	State.HIT_STUN: 10,
}

func int_to_state(state_id: int) -> State:
	match state_id:
		0: return State.MOVING
		1: return State.ATTACKING
		2: return State.DODGING
		3: return State.ATTACK_LAG
		4: return State.DODGE_LAG
		5: return State.HIT_STUN
		_: return State.MOVING
		
func state_to_int(s: State) -> int:
	match s:
		State.MOVING: return 0
		State.ATTACKING: return 1
		State.DODGING: return 2
		State.ATTACK_LAG: return 3
		State.DODGE_LAG: return 4
		State.HIT_STUN: return 5
		_: return 0

@onready var trampoline = get_tree().get_first_node_in_group("trampoline")
@onready var trampoline_top = trampoline.position.y - 26
@onready var starting_position = position

@export var local_player: bool = false
@export var player_number: int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("Player ", player_number, " ready")
	for i in range(SynchronizationHandler.num_players):
		hit_players.append(false)

	SynchronizationHandler.update_positions.connect(_on_update_positions)

	thread.start(main_loop.bind())

	SynchronizationHandler.ready_players += 1

func _exit_tree():
	thread.wait_to_finish()

func main_loop() -> void:
	print("Player ", player_number, " starting main loop")

	SynchronizationHandler.new_frame_barrier.cycle(player_number) # Wait for all players to be ready for new frame

	var first_frame = SynchronizationHandler.player_state.new()
	first_frame.pos = starting_position

	SynchronizationHandler.save_states.update_player_state(0, player_number, first_frame)

	while true:
		SynchronizationHandler.new_frame_barrier.cycle(player_number) # Wait for all players to be ready for new frame
		# SynchronizationHandler.locks[player_number].lock() # Wait for main thread to signal start of new frame

		var rollback_frame = SynchronizationHandler.rollback_start_frames[player_number]

		while rollback_frame <= SynchronizationHandler.current_frame:
			# print("Player ", player_number, " simulating frame ", rollback_frame, " current frame ", SynchronizationHandler.current_frame)
			# print(1, " ", SynchronizationHandler.current_frame, " ", rollback_frame)

			var new_frame = _simulate_tick(rollback_frame)
			# var new_frame = _simulate_tick(SynchronizationHandler.current_frame)

			# print(2, " ", SynchronizationHandler.current_frame, " ", rollback_frame)

			SynchronizationHandler.save_states.update_player_state(rollback_frame+1, player_number, new_frame)
			# SynchronizationHandler.save_states.update_player_state(SynchronizationHandler.current_frame, player_number, new_frame)

			# print(3, " ", SynchronizationHandler.current_frame, " ", rollback_frame)
			rollback_frame += 1

		# SynchronizationHandler.locks[player_number].unlock()
		SynchronizationHandler.new_frame_barrier.cycle(player_number) 


# func _physics_process(_delta: float) -> void:
	# _simulate_tick()

# Called once a frame. I think we shouldn't use delta because we don't need consistent 
# movement wrt time, just consistent for frames. 
func _simulate_tick(frame: int) -> SynchronizationHandler.player_state:
	# print("Simulating tick for player ", player_number, " frame ", frame, " current frame ", SynchronizationHandler.current_frame)
	# Get appropriate player's state
	var player_curr_frame = SynchronizationHandler.save_states.get_player_state(frame, player_number)
	var player_new_frame = SynchronizationHandler.player_state.new()
	player_new_frame.copy_from(player_curr_frame) # Start with current frame's state and modify for new frame
	
	# Simple state machine
	var player_state = int_to_state(player_new_frame.state)
	current_state_frame_counter = player_new_frame.current_state_frame_counter

	var next_state: State
	if player_state != State.MOVING and current_state_frame_counter < STATE_FRAMES[state]:
		current_state_frame_counter += 1
	else:
		if player_state == State.ATTACKING:
			next_state = State.ATTACK_LAG
		elif player_state == State.DODGING:
			next_state = State.DODGE_LAG
		elif player_state in [State.ATTACK_LAG, State.DODGE_LAG, State.HIT_STUN]:
			next_state = State.MOVING

	# print(player_curr_frame.input)
	handle_input(player_new_frame.input)
	
	if dodge_buffered and next_state == State.MOVING:
		next_state = State.DODGING
		player_new_frame.vel.x = movement_direction_x * DODGE_SPEED
		dodge_buffered = false
	elif next_state not in [State.HIT_STUN]: # Don't change velocity if dodging, just keep momentum
		player_new_frame.vel.x = move_toward(player_new_frame.vel.x, movement_direction_x * MAX_SPEED, ACCELERATION)

	if attack_buffered and next_state == State.MOVING:
		for i in range(SynchronizationHandler.num_players):
			player_new_frame.hit_players[i] = false # Reset hit players for new attack
		next_state = State.ATTACKING
		attack_buffered = false

	if jump_buffered and jumps > 0:
		jumps -= 1
		player_new_frame.vel.y = JUMP_SPEED

	if fast_fall_buffered and player_new_frame.vel.y > JUMP_SPEED * 0.9:
		player_new_frame.vel.y = MAX_FALL_SPEED

	if player_new_frame.vel.y < MAX_FALL_SPEED:
		player_new_frame.vel += GRAVITY

	player_new_frame.current_state_frame_counter = current_state_frame_counter

	SynchronizationHandler.save_states.get_current_barrier(frame).cycle(player_number) 

	# Attack collision. Barrier so all characters have calculated movement
	for player in range(SynchronizationHandler.num_players):
		if player == player_number:
			continue
		var other_player_frame = SynchronizationHandler.save_states.get_player_state(frame, player)
		if int_to_state(other_player_frame.state) == State.ATTACKING and int_to_state(other_player_frame.state) != State.DODGING and not other_player_frame.hit_players[player_number]:
			if player_new_frame.pos.distance_to(other_player_frame.pos) < ATTACK_RANGE:
				player_new_frame.vel = (player_new_frame.pos - other_player_frame.pos).normalized() * KNOCKBACK_SPEED # Knockback
				other_player_frame.hit_players[player_number] = true # Add to hit players so they can't be hit again until they leave the attack range
				next_state = State.HIT_STUN


	SynchronizationHandler.save_states.get_current_barrier(frame).cycle(player_number) 


	# Trampoline collision. Another barrier		

	# Check if your head hits the bottom of the trampoline
	var bounced = false
	if player_new_frame.pos.y > trampoline_top + 128 + 52:
		player_new_frame.pos.y = trampoline_top + 128 + 52
		player_new_frame.vel.y = - player_new_frame.vel.y
	# Check if your feet hit the trampoline
	elif player_new_frame.pos.y > trampoline_top:
		if player_new_frame.vel.y > 0:
			var extra_y = player_new_frame.vel.y - (trampoline_top - player_new_frame.pos.y)
			player_new_frame.pos.y = trampoline_top - extra_y
			player_new_frame.vel.y = min(-player_new_frame.vel.y * 0.9, MIN_JUMP_SPEED)
			jumps = 1 # Reset jumps on trampoline
		player_new_frame.pos.x += player_new_frame.vel.x
		bounced = true

	if not bounced:
		player_new_frame.pos += player_new_frame.vel

	fast_fall_buffered = false
	jump_buffered = false
	
	# Do enum conversion for state
	player_new_frame.state = state_to_int(next_state)
	return player_new_frame

func handle_input(inputs: Array[String]) -> void:
	movement_direction_x = 0
	for input in inputs:
		# print(input)
		match input:
			"ui_left":
				movement_direction_x -= 1
			"ui_right":
				movement_direction_x += 1
			"ui_up": # Jump
				jump_buffered = true
			"ui_down": # Fast fall
				fast_fall_buffered = true
			"attack":
				attack_buffered = true
			"dodge":
				dodge_buffered = true


func _on_update_positions(frame: int) -> void:
	# print(3.5, " ", SynchronizationHandler.current_frame, " ", frame)
	var new_frame_state = SynchronizationHandler.save_states.get_player_state(frame, player_number)
	# print("Updating position for player ", player_number, " to ", new_frame_state.pos)
	position = new_frame_state.pos
