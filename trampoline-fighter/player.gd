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

var velocity: Vector2 = Vector2.ZERO
var movement_direction_x: int = 0

var jump_buffered: bool = false
var jumps: int = 1
var fast_fall_buffered: bool = false
var dodge_buffered: bool = false

var attack_buffered: bool = false
var hit_players: Array[Player] = []

var current_state_frame_counter: int = 0
var state: State = State.MOVING:
	set(value):
		if value == state:
			return
		current_state_frame_counter = 0
		state = value

var other_players: Array[Player]

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
		
func state_to_int(state: State) -> int:
	match state:
		State.MOVING: return 0
		State.ATTACKING: return 1
		State.DODGING: return 2
		State.ATTACK_LAG: return 3
		State.DODGE_LAG: return 4
		State.HIT_STUN: return 5
		_: return 0

@onready var trampoline = get_tree().get_first_node_in_group("trampoline")
@export var local_player: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for player in get_tree().get_nodes_in_group("player"):
		if player != self and player is Player:
			other_players.append(player)

	var thread = Thread.new()
	thread.start(main_loop.bind())


func main_loop() -> void:
	while true:
		# INCORRECT PARAMETERS
		_simulate_tick(1, 1)
		await get_tree().process_frame

# func _physics_process(_delta: float) -> void:
	# _simulate_tick()

# Called once a frame. I think we shouldn't use delta because we don't need consistent 
# movement wrt time, just consistent for frames. 
func _simulate_tick(frame: int, player_number: int) -> SynchronizationHandler.player_state:
	# Get appropriate player's state
	var player_curr_frame = SynchronizationHandler.game_states.get_player_state(frame, player_number)
	var player_new_frame = player_curr_frame.duplicate()
	
	# Simple state machine
	var player_state = int_to_state(player_curr_frame.state)
	var next_state: State
	if player_state != State.MOVING and player_new_frame.current_state_frame_counter < STATE_FRAMES[state]:
		player_new_frame.current_state_frame_counter += 1
	else:
		if player_state == State.ATTACKING:
			next_state = State.ATTACK_LAG
		elif player_state == State.DODGING:
			next_state = State.DODGE_LAG
		elif player_state in [State.ATTACK_LAG, State.DODGE_LAG, State.HIT_STUN]:
			next_state = State.MOVING

	handle_input(player_curr_frame.input)
	
	if dodge_buffered and next_state == State.MOVING:
		next_state = State.DODGING
		player_new_frame.vel.x = movement_direction_x * DODGE_SPEED
		dodge_buffered = false
	elif next_state not in [State.HIT_STUN]: # Don't change velocity if dodging, just keep momentum
		player_new_frame.vel.x = move_toward(player_new_frame.vel.x, movement_direction_x * MAX_SPEED, ACCELERATION)

	if attack_buffered and next_state == State.MOVING:
		hit_players.clear()
		next_state = State.ATTACKING
		attack_buffered = false

	if jump_buffered and jumps > 0:
		jumps -= 1
		player_new_frame.vel.y = JUMP_SPEED

	if fast_fall_buffered and player_new_frame.vel.y > JUMP_SPEED * 0.9:
		player_new_frame.vel.y = MAX_FALL_SPEED

	if player_new_frame.vel.y < MAX_FALL_SPEED:
		player_new_frame.vel += GRAVITY

	# Attack collision. Barrier so all characters have calculated movement
	# FIX TO MAKE IT SO I ONLY ADD PEOPLE I HIT TO MY LIST
	for player in SynchronizationHandler.num_players:
		var other_player_frame = SynchronizationHandler.game_states.get_player_state(frame, player)
		if int_to_state(other_player_frame.state) == State.ATTACKING and int_to_state(other_player_frame.state) != State.DODGING and not other_player_frame.hit_players.has(self ):
			if player_new_frame.pos.distance_to(other_player_frame.pos) < ATTACK_RANGE:
				player_new_frame.vel = (player_new_frame.pos - other_player_frame.pos).normalized() * KNOCKBACK_SPEED # Knockback
				other_player_frame.hit_players.append(self ) # Add to hit players so they can't be hit again until they leave the attack range
				next_state = State.HIT_STUN


	# Trampoline collision. Another barrier		

	# Check if your head hits the bottom of the trampoline
	var bounced = false
	if player_new_frame.pos.y > trampoline.position.y + 128 + 26:
		player_new_frame.pos.y = trampoline.position.y + 128 + 26
		player_new_frame.vel.y = - player_new_frame.vel.y
	# Check if your feet hit the trampoline
	elif player_new_frame.pos.y > trampoline.position.y - 26:
		if player_new_frame.vel.y > 0:
			var extra_y = player_new_frame.vel.y - (trampoline.position.y - 26 - player_new_frame.pos.y)
			player_new_frame.pos.y = trampoline.position.y - 26 - extra_y
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

func handle_input(input: String) -> void:
	movement_direction_x = 0
	if input == "ui_left":
		movement_direction_x = -1
	elif input == "ui_right":
		movement_direction_x = 1

	if input == "ui_up": # Jump
		jump_buffered = true
	if input == "ui_down": # Fast fall
		fast_fall_buffered = true
	
	if input == "attack":
		attack_buffered = true
	if input == "dodge":
		dodge_buffered = true
