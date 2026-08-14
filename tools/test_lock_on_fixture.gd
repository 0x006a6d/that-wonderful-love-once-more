extends Node

## test_lock_on.gd のシーン生成・入力・物理待機を担うフィクスチャ。

const PLAYER_SCENE: PackedScene = preload("res://actors/player/player.tscn")
const CIVILIAN_SCENE: PackedScene = preload("res://actors/npc/civilian.tscn")
const CIVILIAN_SCRIPT: Script = preload("res://actors/npc/civilian.gd")
const ROBBER_LAYER: int = 1 << 2
const CIVILIAN_LAYER: int = 1 << 3
const SETTLE_FRAMES: int = 6
const CAMERA_FOLLOW_FRAMES: int = 30
const MELEE_DAMAGE: float = 25.0

var _pass: int = 0
var _fail: int = 0
var _actors: Node3D = null


func _new_world() -> void:
	await _clear_world()
	RunState.reset()
	GameDirector.reset()
	_actors = Node3D.new()
	_actors.name = "Actors"
	add_child(_actors)
	_add_ground()


func _clear_world() -> void:
	if _actors != null and is_instance_valid(_actors):
		_actors.queue_free()
		await get_tree().process_frame
	_actors = null


func _spawn_player() -> Node3D:
	var player := PLAYER_SCENE.instantiate() as Node3D
	_actors.add_child(player)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	return player


func _spawn_target(target_name: String, layer: int, group: StringName,
		position: Vector3) -> Node3D:
	var body := CharacterBody3D.new()
	body.name = target_name
	body.collision_layer = layer
	body.collision_mask = 1
	body.add_to_group(group)
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.6
	shape_node.position.y = 0.8
	shape_node.shape = shape
	body.add_child(shape_node)
	var health := Health.new()
	health.name = "Health"
	body.add_child(health)
	body.position = position
	_actors.add_child(body)
	return body


func _spawn_civilian(position: Vector3) -> Node3D:
	var civilian := CIVILIAN_SCENE.instantiate() as Node3D
	civilian.position = position
	_actors.add_child(civilian)
	civilian.set_physics_process(false)
	return civilian


func _add_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.2, 40.0)
	collision.position.y = -0.1
	collision.shape = box
	ground.add_child(collision)
	_actors.add_child(ground)


func _spawn_wall_between(player: Node3D, target: Node3D) -> void:
	var camera := player.get_node("SpringArm3D/Camera3D") as Camera3D
	var aim := target.global_position + Vector3.UP * _lock_on(player).target_aim_height
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.5)
	collision.shape = box
	wall.add_child(collision)
	_actors.add_child(wall)
	wall.global_position = (camera.global_position + aim) * 0.5


func _prepare_melee_facing(player: Node3D) -> void:
	var model := player.get_node("Model") as Node3D
	model.rotation.y = PI


func _strike(hitbox: Hitbox, damage: float) -> void:
	hitbox.configure(damage, 0.0, false)
	hitbox.activate()
	await _wait_frames(SETTLE_FRAMES)
	hitbox.deactivate()
	await get_tree().physics_frame


func _toggle_lock_on() -> void:
	var press := InputEventAction.new()
	press.action = &"lock_on"
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventAction.new()
	release.action = &"lock_on"
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().physics_frame


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await get_tree().physics_frame


func _lock_on(player: Node3D) -> LockOn:
	return player.get_node("LockOnDetector") as LockOn


func _camera_angle_deg(camera: Camera3D, target: Node3D) -> float:
	var forward := -camera.global_transform.basis.z
	var to_target := target.global_position + Vector3.UP * 0.8 - camera.global_position
	return rad_to_deg(forward.angle_to(to_target))


func _assert(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[PASS] %s" % label)
	else:
		_fail += 1
		print("[FAIL] %s" % label)


func _finish() -> void:
	print("=== 結果: PASS=%d FAIL=%d ===" % [_pass, _fail])
	print("ALL PASS" if _fail == 0 else "FAILED")
	get_tree().quit(0 if _fail == 0 else 1)
