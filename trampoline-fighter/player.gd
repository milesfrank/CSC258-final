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

@onready var trampoline = get_tree().get_first_node_in_group("trampoline")
@export var local_player: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for player in get_tree().get_nodes_in_group("player"):
		if player != self and player is Player:
			other_players.append(player)

	var thread = Thread.new()
	thread.start(main_loop.bind())

<<<<<<< HEAD
func _physics_process(_delta: float) -> void:
	# INCORRECRT PARAMETER
	_simulate_tick(_delta, 1)
=======

func main_loop() -> void:
	while true:
		_simulate_tick()
		await get_tree().process_frame

# func _physics_process(_delta: float) -> void:
	# _simulate_tick()
>>>>>>> 51542271bc35f62e4ead6bce506cab05045954d9


# Called once a frame. I think we shouldn't use delta because we don't need consistent 
# movement wrt time, just consistent for frames. 
func _simulate_tick(frame: int, player_number: int) -> void:
	# Get appropriate player's state
	var player = SynchronizationHandler.state_buffer.get_player_state(frame, player_number)
	
	# Simple state machine
	if state != State.MOVING and current_state_frame_counter < STATE_FRAMES[state]:
		current_state_frame_counter += 1
	else:
		if state == State.ATTACKING:
			state = State.ATTACK_LAG
		elif state == State.DODGING:
			state = State.DODGE_LAG
		elif state in [State.ATTACK_LAG, State.DODGE_LAG, State.HIT_STUN]:
			state = State.MOVING
	
	# Calculate movement
	handle_input()

	if dodge_buffered and state == State.MOVING:
		state = State.DODGING
		velocity.x = movement_direction_x * DODGE_SPEED
		dodge_buffered = false
	elif state not in [State.HIT_STUN]: # Don't change velocity if dodging, just keep momentum
		velocity.x = move_toward(velocity.x, movement_direction_x * MAX_SPEED, ACCELERATION)

	if attack_buffered and state == State.MOVING:
		hit_players.clear()
		state = State.ATTACKING
		attack_buffered = false

	if jump_buffered and jumps > 0:
		jumps -= 1
		velocity.y = JUMP_SPEED

	if fast_fall_buffered and velocity.y > JUMP_SPEED * 0.9:
		velocity.y = MAX_FALL_SPEED

	if velocity.y < MAX_FALL_SPEED:
		velocity += GRAVITY

	# Attack collision. Barrier so all characters have calculated movement
	for player in other_players:
		if player.state == State.ATTACKING and state != State.DODGING and not player.hit_players.has(self ):
			if position.distance_to(player.position) < ATTACK_RANGE:
				velocity = (position - player.position).normalized() * KNOCKBACK_SPEED # Knockback
				player.hit_players.append(self ) # Add to hit players so they can't be hit again until they leave the attack range
				state = State.HIT_STUN


	# Trampoline collision. Another barrier		

	# Check if your head hits the bottom of the trampoline
	var bounced = false
	if position.y > trampoline.position.y + 128 + 26:
		global_position.y = trampoline.position.y + 128 + 26
		velocity.y = - velocity.y
	# Check if your feet hit the trampoline
	elif position.y > trampoline.position.y - 26:
		if velocity.y > 0:
			var extra_y = velocity.y - (trampoline.position.y - 26 - position.y)
			position.y = trampoline.position.y - 26 - extra_y
			velocity.y = min(-velocity.y * 0.9, MIN_JUMP_SPEED)
			jumps = 1 # Reset jumps on trampoline
		position.x += velocity.x
		bounced = true

	if not bounced:
		position += velocity

	fast_fall_buffered = false
	jump_buffered = false


func handle_input() -> void:
	if local_player:
		movement_direction_x = 0
		if Input.is_action_pressed("ui_left"):
			movement_direction_x = -1
		elif Input.is_action_pressed("ui_right"):
			movement_direction_x = 1

		if Input.is_action_pressed("ui_up"): # Jump
			jump_buffered = true
		if Input.is_action_pressed("ui_down"): # Fast fall
			fast_fall_buffered = true
		
		if Input.is_action_just_pressed("attack"):
			attack_buffered = true
		if Input.is_action_just_pressed("dodge"):
			dodge_buffered = true
