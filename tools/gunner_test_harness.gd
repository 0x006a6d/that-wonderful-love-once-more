extends Node
class_name GunnerTestHarness

## test_gunner.gd のワールド生成・待機・計測だけを担当するテスト基盤。

const GUNNER_SCENE: PackedScene = preload("res://actors/npc/roles/gunner.tscn")
const PLAYER_SCENE: PackedScene = preload("res://actors/player/player.tscn")
const STATE_TIMEOUT: float = 1.5
const WAIT_MARGIN: float = 0.25
const FAST_SHOOT_INTERVAL: float = 0.10
const FAST_TELEGRAPH: float = 0.05

var _pass: int = 0
var _fail: int = 0
var _actors: Node3D = null
var _shots: Array[Node3D] = []
var _shot_frames: Array[int] = []
var _physics_frames: int = 0


func _physics_process(_delta: float) -> void:
	_physics_frames += 1


func _new_world(act: int) -> void:
	await _clear_world()
	RunState.reset()
	GameDirector.reset()
	if act != GameTypes.Act.PROLOGUE:
		GameDirector.advance_to(act)
	_shots.clear()
	_shot_frames.clear()
	_actors = Node3D.new()
	add_child(_actors)
	_add_ground()


func _clear_world() -> void:
	if _actors != null and is_instance_valid(_actors):
		_actors.queue_free()
		await get_tree().process_frame
	_actors = null


func _spawn_player(position: Vector3) -> Node3D:
	var player := PLAYER_SCENE.instantiate() as Node3D
	player.position = position
	_actors.add_child(player)
	player.set_physics_process(false)
	return player


func _spawn_gunner(position: Vector3) -> Gunner:
	var gunner := GUNNER_SCENE.instantiate() as Gunner
	gunner.position = position
	gunner.shoot_interval = FAST_SHOOT_INTERVAL
	gunner.shoot_telegraph_duration = FAST_TELEGRAPH
	_actors.add_child(gunner)
	var gun := gunner.get_node("MuzzlePoint/HitscanGun") as HitscanGun
	gun.shot_fired.connect(_on_shot_fired)
	return gunner


func _add_cover(marker_name: StringName, position: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = position
	marker.add_to_group(&"cover")
	_actors.add_child(marker)
	return marker


func _add_wall(position: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	wall.add_child(collision)
	_actors.add_child(wall)
	wall.global_position = position


func _add_ground() -> void:
	_add_wall(Vector3(0.0, -0.1, 0.0), Vector3(30.0, 0.2, 30.0))


func _on_shot_fired(_from: Vector3, _to: Vector3, hit_body: Node3D) -> void:
	_shots.append(hit_body)
	_shot_frames.append(_physics_frames)


func _wait_for_state(gunner: Gunner, state: int, timeout: float) -> float:
	for index: int in range(_seconds_to_frames(timeout)):
		await get_tree().physics_frame
		if gunner.current_state() == state:
			return float(index + 1) / float(Engine.physics_ticks_per_second)
	return timeout


func _wait_for_shots(count: int, timeout: float) -> void:
	for _index: int in range(_seconds_to_frames(timeout)):
		await get_tree().physics_frame
		if _shots.size() >= count:
			return


func _wait_for_selected_cover(gunner: Gunner, cover: Marker3D, timeout: float) -> float:
	for index: int in range(_seconds_to_frames(timeout)):
		await get_tree().physics_frame
		if gunner.selected_cover() == cover:
			return float(index + 1) / float(Engine.physics_ticks_per_second)
	return timeout


func _wait_until_telegraph(gunner: Gunner, timeout: float) -> void:
	for _index: int in range(_seconds_to_frames(timeout)):
		await get_tree().physics_frame
		if bool(gunner.get("_telegraph_active")):
			return


func _wait_for_civilian_kill(timeout: float) -> void:
	for _index: int in range(_seconds_to_frames(timeout)):
		await get_tree().physics_frame
		if RunState.civilians_killed > 0:
			return


func _wait_seconds(seconds: float) -> void:
	for _index: int in range(_seconds_to_frames(seconds)):
		await get_tree().physics_frame


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
