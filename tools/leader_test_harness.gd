extends Node
class_name LeaderTestHarness

## test_leader.gd のワールド生成・攻撃角度の計測・待機を担当する基盤。

const LEADER_SCENE: PackedScene = preload("res://actors/npc/roles/leader.tscn")
const LEADER_SCRIPT: Script = preload("res://actors/npc/roles/leader.gd")
const CIVILIAN_SCENE: PackedScene = preload("res://actors/npc/civilian.tscn")
const PLAYER_SCENE: PackedScene = preload("res://actors/player/player.tscn")
const STATE_TIMEOUT: float = 2.0
const SHIELD_TIMEOUT: float = 3.0
const WAIT_MARGIN: float = 0.20
const ATTACK_DISTANCE: float = 1.0
const ATTACK_DAMAGE: float = 10.0
const HIT_SETTLE_FRAMES: int = 6
const GROUND_SIZE: Vector3 = Vector3(30.0, 0.2, 30.0)
const SHIELD_STATIONARY_DURATION: float = 0.5
const SHIELD_STATIONARY_MAX_DISTANCE: float = 0.01
const ORBIT_ARC_DEG: float = 90.0

enum AttackSide { FRONT, SIDE, BACK }

var _pass: int = 0
var _fail: int = 0
var _actors: Node3D = null


func _new_world(act: int) -> void:
	await _clear_world()
	RunState.reset()
	GameDirector.reset()
	if act != GameTypes.Act.PROLOGUE:
		GameDirector.advance_to(act)
	_actors = Node3D.new()
	add_child(_actors)
	_add_ground()


func _clear_world() -> void:
	if _actors != null and is_instance_valid(_actors):
		_actors.queue_free()
		await get_tree().process_frame
	_actors = null
	Engine.time_scale = 1.0


func _spawn_player(position: Vector3) -> Node3D:
	var player := PLAYER_SCENE.instantiate() as Node3D
	player.position = position
	_actors.add_child(player)
	player.set_physics_process(false)
	var camera_shake := player.get_node_or_null("SpringArm3D/Camera3D/CameraShake")
	if camera_shake != null:
		camera_shake.set("duration", 0.01)
	player.set("hit_stop_duration", 0.01)
	return player


func _spawn_leader(position: Vector3) -> Robber:
	var leader := LEADER_SCENE.instantiate() as Robber
	leader.position = position
	_actors.add_child(leader)
	return leader


func _spawn_civilian(position: Vector3) -> Civilian:
	var civilian := CIVILIAN_SCENE.instantiate() as Civilian
	civilian.position = position
	_actors.add_child(civilian)
	return civilian


func _add_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = GROUND_SIZE
	shape_node.shape = box
	ground.add_child(shape_node)
	_actors.add_child(ground)
	ground.position = Vector3(0.0, -0.1, 0.0)


func _wait_for_state(leader: Robber, state: int, timeout: float) -> float:
	for index: int in range(_seconds_to_frames(timeout)):
		await get_tree().physics_frame
		if leader.current_state() == state:
			return float(index + 1) / float(Engine.physics_ticks_per_second)
	return timeout


func _wait_for_shield(leader: Robber, timeout: float) -> float:
	return await _wait_for_state(leader, int(LEADER_SCRIPT.SHIELD), timeout)


func _wait_while_shielded(leader: Robber, seconds: float) -> bool:
	for _index: int in range(_seconds_to_frames(seconds)):
		await get_tree().physics_frame
		if leader.current_state() == int(LEADER_SCRIPT.SHIELD):
			return false
	return true


func _wait_for_regrab(leader: Robber, timeout: float) -> float:
	for index: int in range(_seconds_to_frames(timeout)):
		await get_tree().physics_frame
		if leader.current_state() == int(LEADER_SCRIPT.SHIELD):
			return float(index + 1) / float(Engine.physics_ticks_per_second)
	return timeout


func _perform_player_hit(player: Node3D, leader: Robber, side: int) -> Dictionary:
	var forward := -leader.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var attack_direction := forward
	match side:
		AttackSide.SIDE:
			attack_direction = leader.global_transform.basis.x.normalized()
		AttackSide.BACK:
			attack_direction = -forward
	player.global_position = leader.global_position + attack_direction * ATTACK_DISTANCE
	return await _perform_player_hit_at_current_position(player, leader)


func _perform_player_hit_at_current_position(player: Node3D, leader: Robber) -> Dictionary:
	var forward := -leader.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var hitbox := player.get_node("Model/MeleeHitbox") as Hitbox
	var hurt_shape := leader.get_node("Hurtbox/CollisionShape3D") as CollisionShape3D
	hitbox.global_position = hurt_shape.global_position
	var health := leader.get_node("Health") as Health
	var hp_before := health.current_hp()
	var landed_count: Array[int] = [0]
	var on_landed := func(_target: Node3D) -> void: landed_count[0] += 1
	hitbox.hit_landed.connect(on_landed)
	hitbox.configure(ATTACK_DAMAGE, 0.0, false)
	hitbox.activate()
	for _index: int in range(HIT_SETTLE_FRAMES):
		await get_tree().physics_frame
	hitbox.deactivate()
	if hitbox.hit_landed.is_connected(on_landed):
		hitbox.hit_landed.disconnect(on_landed)

	var to_attacker := player.global_position - leader.global_position
	to_attacker.y = 0.0
	var measured_distance := to_attacker.length()
	var measured_angle := rad_to_deg(forward.angle_to(to_attacker.normalized()))
	var camera_shake := player.get_node("SpringArm3D/Camera3D/CameraShake")
	var result: Dictionary = {
		"hp_before": hp_before,
		"hp_after": health.current_hp(),
		"landed": landed_count[0],
		"distance": measured_distance,
		"angle": measured_angle,
		"time_scale": Engine.time_scale,
		"camera_shaking": camera_shake.is_processing(),
	}
	await get_tree().create_timer(0.04, true, false, true).timeout
	return result


func _seconds_to_frames(seconds: float) -> int:
	return ceili(seconds * float(Engine.physics_ticks_per_second))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	var offset := a - b
	return Vector2(offset.x, offset.z).length()


func _assert(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[PASS] %s" % label)
	else:
		_fail += 1
		print("[FAIL] %s" % label)
