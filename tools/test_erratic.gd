extends Node

## 不安定型と共有ヒットスキャン銃のヘッドレス検証。

const ERRATIC_SCENE: PackedScene = preload("res://actors/npc/roles/erratic.tscn")
const CIVILIAN_SCENE: PackedScene = preload("res://actors/npc/civilian.tscn")
const ROBBER_SCENE: PackedScene = preload("res://actors/npc/robber.tscn")
const SHOOT_INTERVAL: float = 0.10
const SHOOT_TELEGRAPH: float = 0.05
const SETTLE_FRAMES: int = 6
const WAIT_MARGIN: float = 0.25
const NEAR_POSITION: Vector3 = Vector3(0.0, 0.0, -3.0)
const FAR_POSITION: Vector3 = Vector3(0.0, 0.0, -6.0)
const WALL_SIZE: Vector3 = Vector3(3.0, 3.0, 0.4)
const MELEE_TARGET_POSITION: Vector3 = Vector3(0.0, 0.0, -0.7)
const PATROL_POINT_COUNT: int = 5
const PATROL_SAMPLE_COUNT: int = 10
const PATROL_TEST_SEEDS: Array[int] = [1103, 2207, 3301]

var _pass: int = 0
var _fail: int = 0
var _actors: Node3D = null
var _shot_bodies: Array[Node3D] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 不安定型 検証開始 ===")
	await _test_scene_defaults()
	await _test_prologue_does_not_shoot()
	await _test_interval_nearest_and_failure()
	await _test_occlusion()
	await _test_downed_robber_stops()
	await _test_melee_filter_but_shot_passes()
	await _test_robber_does_not_block_civilian_shot()
	await _test_random_patrol_order()
	await _clear_world()
	_finish()


func _test_scene_defaults() -> void:
	await _new_world()
	var erratic := ERRATIC_SCENE.instantiate() as Erratic
	erratic.set_physics_process(false)
	_actors.add_child(erratic)
	var gun := erratic.get_node("MuzzlePoint/HitscanGun") as HitscanGun
	print("[erratic defaults] shoot_civilian_interval=%.1f sec / ignore_groups=%s" %
		[erratic.shoot_civilian_interval, str(gun.ignore_groups)])
	_assert("0. シーン既定値は射撃間隔15秒・仲間の犯人を除外",
		is_equal_approx(erratic.shoot_civilian_interval, 15.0)
		and gun.ignore_groups.has(&"robber"))


func _test_prologue_does_not_shoot() -> void:
	await _new_world()
	var civilian := _spawn_civilian(NEAR_POSITION)
	var erratic := _spawn_erratic(Vector3.ZERO)
	var health := civilian.get_node("Health") as Health
	var wait_frames := _seconds_to_frames(SHOOT_INTERVAL + SHOOT_TELEGRAPH + WAIT_MARGIN)
	await _wait_frames(wait_frames)
	var measured := float(wait_frames) / float(Engine.physics_ticks_per_second)
	print("[prologue] measured=%.3f sec / interval=%.3f sec / shots=%d / HP=%.1f" %
		[measured, erratic.shoot_civilian_interval, _shot_bodies.size(), health.current_hp()])
	_assert("1. Act.PROLOGUE では客を撃たない",
		GameDirector.current_act == GameTypes.Act.PROLOGUE
		and measured > erratic.shoot_civilian_interval
		and _shot_bodies.is_empty() and is_equal_approx(health.current_hp(), health.max_hp))


func _test_interval_nearest_and_failure() -> void:
	await _new_world()
	var near := _spawn_civilian(NEAR_POSITION)
	var far := _spawn_civilian(FAR_POSITION)
	var erratic := _spawn_erratic(Vector3.ZERO)
	var near_health := near.get_node("Health") as Health
	var far_health := far.get_node("Health") as Health
	var near_distance := erratic.global_position.distance_to(near.global_position)
	var far_distance := erratic.global_position.distance_to(far.global_position)
	print("[distance] near=%.3f m / far=%.3f m" % [near_distance, far_distance])

	GameDirector.advance_to(GameTypes.Act.INFILTRATION)
	var elapsed := await _wait_until_shot(SHOOT_INTERVAL + SHOOT_TELEGRAPH + WAIT_MARGIN)
	print("[infiltration] first shot=%.3f sec / interval=%.3f sec / telegraph=%.3f sec" %
		[elapsed, erratic.shoot_civilian_interval, erratic.shoot_telegraph_duration])
	_assert("2. INFILTRATION 以降は shoot_civilian_interval 経過後に撃つ",
		_shot_bodies.size() == 1 and elapsed >= erratic.shoot_civilian_interval)
	_assert("3. stagger_threshold=2 の客も銃撃1発でダウンする",
		near_health.stagger_threshold == 2 and near_health.is_downed())
	print("[RunState] downed=%d killed=%d records=%d" %
		[RunState.civilians_downed, RunState.civilians_killed, RunState.downed.size()])
	_assert("4. 銃撃ダウンで RunState.civilians_killed が増える",
		RunState.civilians_killed == 1)
	_assert("5. 銃撃による死者があると Ending.FAILURE になる",
		RunState.resolve_ending() == GameTypes.Ending.FAILURE)
	_assert("6. 客が2人なら距離の近いほうを撃つ",
		near_distance < far_distance and near_health.is_downed() and not far_health.is_downed()
		and _shot_bodies[0] == near)

	await _wait_frames(SETTLE_FRAMES)
	var gun := erratic.get_node("MuzzlePoint/HitscanGun") as HitscanGun
	gun.fire_at(near.global_position + Vector3.UP * erratic.civilian_aim_height)
	await get_tree().physics_frame
	print("[double record] downed=%d killed=%d records=%d" %
		[RunState.civilians_downed, RunState.civilians_killed, RunState.downed.size()])
	_assert("9. 撃たれた客は downed/killed を各1回だけ記録する",
		RunState.civilians_downed == 1 and RunState.civilians_killed == 1
		and RunState.downed.size() == 1)

	var ignore_groups := (erratic.get_node("MeleeHitbox") as Hitbox).ignore_groups
	print("[ignore_groups] %s / shot hit civilian=%s" %
		[str(ignore_groups), str(_shot_bodies[0] == near)])
	_assert("10. 銃撃は Hitbox.ignore_groups の civilian 除外に影響されない",
		ignore_groups.has(&"civilian") and near_health.is_downed())


func _test_occlusion() -> void:
	await _new_world()
	var control := _spawn_civilian(NEAR_POSITION)
	_spawn_erratic(Vector3.ZERO)
	GameDirector.advance_to(GameTypes.Act.INFILTRATION)
	var control_elapsed := await _wait_until_shot(
		SHOOT_INTERVAL + SHOOT_TELEGRAPH + WAIT_MARGIN)
	var control_downed := (control.get_node("Health") as Health).is_downed()
	print("[occlusion control] elapsed=%.3f sec / shots=%d / downed=%s" %
		[control_elapsed, _shot_bodies.size(), str(control_downed)])

	await _new_world()
	var blocked := _spawn_civilian(NEAR_POSITION)
	var blocked_erratic := _spawn_erratic(Vector3.ZERO)
	_spawn_wall_between(blocked_erratic, blocked)
	await _wait_frames(SETTLE_FRAMES)
	GameDirector.advance_to(GameTypes.Act.INFILTRATION)
	var wait_seconds := SHOOT_INTERVAL + SHOOT_TELEGRAPH + WAIT_MARGIN
	var wait_frames := _seconds_to_frames(wait_seconds)
	await _wait_frames(wait_frames)
	var blocked_health := blocked.get_node("Health") as Health
	var blocked_measured := float(wait_frames) / float(Engine.physics_ticks_per_second)
	print("[occluded] measured=%.3f sec / shots=%d / HP=%.1f" %
		[blocked_measured, _shot_bodies.size(), blocked_health.current_hp()])
	_assert("7. 壁なしでは撃たれ、同一配置を壁で遮ると狙われず撃たれない",
		control_downed and blocked_measured > blocked_erratic.shoot_civilian_interval
		and _shot_bodies.is_empty()
		and is_equal_approx(blocked_health.current_hp(), blocked_health.max_hp))


func _test_downed_robber_stops() -> void:
	await _new_world()
	var civilian := _spawn_civilian(NEAR_POSITION)
	var erratic := _spawn_erratic(Vector3.ZERO)
	var robber_health := erratic.get_node("Health") as Health
	await _wait_frames(SETTLE_FRAMES)
	robber_health.take_hit(robber_health.max_hp)
	await _wait_frames(SETTLE_FRAMES)
	GameDirector.advance_to(GameTypes.Act.INFILTRATION)
	var wait_frames := _seconds_to_frames(SHOOT_INTERVAL + SHOOT_TELEGRAPH + WAIT_MARGIN)
	await _wait_frames(wait_frames)
	var civilian_health := civilian.get_node("Health") as Health
	print("[robber downed] state=%d / measured=%.3f sec / shots=%d / civilian HP=%.1f" %
		[erratic.current_state(), float(wait_frames) / float(Engine.physics_ticks_per_second),
		_shot_bodies.size(), civilian_health.current_hp()])
	_assert("8. 犯人自身が DOWNED になったら以後撃たない",
		robber_health.is_downed() and erratic.current_state() == Robber.State.DOWNED
		and _shot_bodies.is_empty()
		and is_equal_approx(civilian_health.current_hp(), civilian_health.max_hp))


func _test_melee_filter_but_shot_passes() -> void:
	await _new_world()
	var civilian := _spawn_civilian(MELEE_TARGET_POSITION)
	var erratic := _spawn_erratic(Vector3.ZERO)
	await _wait_frames(SETTLE_FRAMES)
	var health := civilian.get_node("Health") as Health
	var hp_before := health.current_hp()
	erratic.attack_damage = health.max_hp
	erratic.call("_open_hitbox")
	await _wait_frames(SETTLE_FRAMES)
	erratic.call("_close_hitbox")
	var hp_after_melee := health.current_hp()

	var gun := erratic.get_node("MuzzlePoint/HitscanGun") as HitscanGun
	gun.fire_at(civilian.global_position + Vector3.UP * erratic.civilian_aim_height)
	await get_tree().physics_frame
	print("[melee vs shot] HP %.1f -> melee %.1f -> shot %.1f" %
		[hp_before, hp_after_melee, health.current_hp()])
	_assert("11. 犯人の近接は客を除外し、同じ客へ銃撃だけが通る",
		is_equal_approx(hp_before, hp_after_melee) and health.is_downed())


func _test_robber_does_not_block_civilian_shot() -> void:
	await _new_world()
	var civilian := _spawn_civilian(FAR_POSITION)
	var erratic := _spawn_erratic(Vector3.ZERO)
	var ally := ROBBER_SCENE.instantiate() as Robber
	ally.position = NEAR_POSITION
	_actors.add_child(ally)
	ally.set_physics_process(false)
	await _wait_frames(SETTLE_FRAMES)
	var gun := erratic.get_node("MuzzlePoint/HitscanGun") as HitscanGun
	var ally_health := ally.get_node("Health") as Health
	var civilian_health := civilian.get_node("Health") as Health
	var aim := civilian.global_position + Vector3.UP * erratic.civilian_aim_height
	var clear_through_ally := gun.has_clear_shot(civilian, aim)
	var hit_body := gun.fire_at(aim)
	await get_tree().physics_frame
	print(("[ally before civilian] clear=%s hit=%s ally HP=%.1f civilian HP=%.1f " +
		"killed=%d") % [str(clear_through_ally), str(hit_body),
		ally_health.current_hp(), civilian_health.current_hp(), RunState.civilians_killed])
	_assert("11b. 客との直線上の仲間は被弾せず、射線を止めずに客へ命中する",
		clear_through_ally and hit_body == civilian
		and is_equal_approx(ally_health.current_hp(), ally_health.max_hp)
		and civilian_health.is_downed() and RunState.civilians_killed == 1)


func _test_random_patrol_order() -> void:
	await _new_world()
	var sequences: Array[Array] = []
	for seed_value: int in PATROL_TEST_SEEDS:
		var erratic := ERRATIC_SCENE.instantiate() as Erratic
		erratic.set_physics_process(false)
		for point_index: int in range(PATROL_POINT_COUNT):
			erratic.patrol_points.append(NodePath("PatrolPoint%d" % point_index))
		_actors.add_child(erratic)
		var rng := erratic.get("_rng") as RandomNumberGenerator
		rng.seed = seed_value
		var sequence: Array[int] = []
		var current_index := 0
		for _sample: int in range(PATROL_SAMPLE_COUNT):
			current_index = int(erratic.call("_next_patrol_index", current_index))
			sequence.append(current_index)
		sequences.append(sequence)
	print("[patrol sequences] seed=%d %s / seed=%d %s / seed=%d %s" %
		[PATROL_TEST_SEEDS[0], str(sequences[0]), PATROL_TEST_SEEDS[1], str(sequences[1]),
		PATROL_TEST_SEEDS[2], str(sequences[2])])
	_assert("12. 複数生成した PATROL の巡回順は固定でない",
		sequences[0] != sequences[1] and sequences[0] != sequences[2]
		and sequences[1] != sequences[2])


func _new_world() -> void:
	await _clear_world()
	RunState.reset()
	GameDirector.reset()
	_shot_bodies.clear()
	_actors = Node3D.new()
	_actors.name = "Actors"
	add_child(_actors)
	_add_ground()


func _clear_world() -> void:
	if _actors != null and is_instance_valid(_actors):
		_actors.queue_free()
		await get_tree().process_frame
	_actors = null


func _spawn_erratic(position: Vector3) -> Erratic:
	var erratic := ERRATIC_SCENE.instantiate() as Erratic
	erratic.shoot_civilian_interval = SHOOT_INTERVAL
	erratic.shoot_telegraph_duration = SHOOT_TELEGRAPH
	erratic.position = position
	_actors.add_child(erratic)
	var gun := erratic.get_node("MuzzlePoint/HitscanGun") as HitscanGun
	gun.shot_fired.connect(_on_shot_fired)
	return erratic


func _spawn_civilian(position: Vector3) -> Civilian:
	var civilian := CIVILIAN_SCENE.instantiate() as Civilian
	civilian.position = position
	_actors.add_child(civilian)
	return civilian


func _spawn_wall_between(erratic: Erratic, civilian: Civilian) -> void:
	var muzzle := erratic.get_node("MuzzlePoint/HitscanGun") as Node3D
	var aim := civilian.global_position + Vector3.UP * erratic.civilian_aim_height
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = WALL_SIZE
	collision.shape = box
	wall.add_child(collision)
	_actors.add_child(wall)
	wall.global_position = (muzzle.global_position + aim) * 0.5


func _add_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.2, 20.0)
	collision.position.y = -0.1
	collision.shape = box
	ground.add_child(collision)
	_actors.add_child(ground)


func _on_shot_fired(_from: Vector3, _to: Vector3, hit_body: Node3D) -> void:
	_shot_bodies.append(hit_body)


func _wait_until_shot(timeout_seconds: float) -> float:
	var max_frames := _seconds_to_frames(timeout_seconds)
	for frame_index: int in range(max_frames):
		await get_tree().physics_frame
		if not _shot_bodies.is_empty():
			return float(frame_index + 1) / float(Engine.physics_ticks_per_second)
	return float(max_frames) / float(Engine.physics_ticks_per_second)


func _seconds_to_frames(seconds: float) -> int:
	return ceili(seconds * float(Engine.physics_ticks_per_second))


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await get_tree().physics_frame


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
