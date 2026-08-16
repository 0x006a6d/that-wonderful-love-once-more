extends "res://tools/test_lock_on_fixture.gd"

## ダウンした犯人への追い打ちに必要な3関門と、客を対象外にする規則を検証する。
## godot --path . --headless res://tools/test_finish.tscn

const ROBBER_SCENE: PackedScene = preload("res://actors/npc/robber.tscn")
const CLOSE_TARGET_POSITION: Vector3 = Vector3(0.0, 0.05, -0.5)
const ACCIDENT_LIVE_POSITION: Vector3 = Vector3(0.55, 0.05, -0.7)
const FAR_RANGE_MARGIN: float = 1.0
const COMBO_WAIT_FRAMES: int = 240
const INPUT_QUEUE_FRAMES: int = 5

var _combo_landed: int = 0
var _civilian_finished: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== ダウン追い打ち 検証開始 ===")
	await _test_accidental_finish_regression()
	await _test_finish_gates_and_double_record()
	await _test_finish_range()
	await _test_combo_auto_release()
	await _test_civilian_excluded()
	await _test_no_finish_keeps_nonlethal()
	await _clear_world()
	_finish()


func _test_accidental_finish_regression() -> void:
	await _new_world()
	_combo_landed = 0
	var player := _spawn_test_player()
	# 実機事故と同じく、遺体を正面至近、生存犯人を近接が届くやや横へ置く。
	player.set("lunge_speeds", Vector3.ZERO)
	var downed_robber := _spawn_robber(CLOSE_TARGET_POSITION)
	var live_robber := _spawn_robber(ACCIDENT_LIVE_POSITION)
	await _wait_frames(SETTLE_FRAMES)
	var downed_health := downed_robber.get_node(^"Health") as Health
	var live_health := live_robber.get_node(^"Health") as Health
	downed_health.take_hit(downed_health.max_hp)
	await _wait_frames(2)
	var camera := player.get_node(^"SpringArm3D/Camera3D") as Camera3D
	var downed_angle := _camera_angle_deg(camera, downed_robber)
	var live_angle := _camera_angle_deg(camera, live_robber)
	var downed_distance := player.global_position.distance_to(downed_robber.global_position)
	var live_distance := player.global_position.distance_to(live_robber.global_position)
	print(("[accident candidates] downed angle=%.3f deg distance=%.3f m / " \
		+ "live angle=%.3f deg distance=%.3f m") %
		[downed_angle, downed_distance, live_angle, live_distance])
	# 初段で生存側が倒れ、残り段が正面の遺体にも重なる事故条件を作る。
	live_health.take_hit(live_health.max_hp - 1.0)
	await _toggle_lock_on()
	var detector := _lock_on(player)
	var selected_live: bool = detector.current_target() == live_robber
	var killed_by_player_before := RunState.robbers_killed_by_player
	var hitbox := player.get_node(^"Model/MeleeHitbox") as Hitbox
	var melee := player.get_node(^"PlayerMelee")
	hitbox.hit_landed.connect(func(_target: Node3D) -> void: _combo_landed += 1)
	melee.call("attack")
	await _wait_frames(INPUT_QUEUE_FRAMES)
	melee.call("attack")
	await _wait_frames(INPUT_QUEUE_FRAMES)
	melee.call("attack")
	for _frame: int in range(COMBO_WAIT_FRAMES):
		await get_tree().physics_frame
		if str(melee.get("_state")) == "locomotion" and live_health.is_downed():
			break
	print("[accident combo] selected_live=%s landed=%d killed_by_player=%d -> %d" %
		[str(selected_live), _combo_landed, killed_by_player_before,
		RunState.robbers_killed_by_player])
	_assert("正面至近の遺体がいても生存犯人へロックしコンボで追い打ち事故を起こさない",
		downed_angle < live_angle and downed_distance < live_distance
		and selected_live and live_health.is_downed() and _combo_landed >= 3
		and RunState.robbers_killed_by_player == killed_by_player_before)


func _test_finish_gates_and_double_record() -> void:
	await _new_world()
	var player := _spawn_test_player()
	var robber := _spawn_robber(CLOSE_TARGET_POSITION)
	await _wait_frames(SETTLE_FRAMES)
	var detector := _lock_on(player)
	var health := robber.get_node(^"Health") as Health
	var hitbox := player.get_node(^"Model/MeleeHitbox") as Hitbox

	# 生存中のロックはダウン通知で解除され、同じコンボへ攻撃意図を残さない。
	await _toggle_lock_on()
	health.take_hit(health.max_hp)
	await _wait_frames(2)
	var released_on_down: bool = detector.current_target() == null
	await _strike(hitbox, MELEE_DAMAGE)
	print("[unlocked finish] released=%s killed=%d" %
		[str(released_on_down), RunState.robbers_killed])
	_assert("ダウン犯人へロックオンなしで攻撃しても robbers_killed は増えない",
		released_on_down and RunState.robbers_killed == 0)

	await _toggle_lock_on()
	var distance := player.global_position.distance_to(robber.global_position)
	var marker_material := detector.get("_marker_material") as StandardMaterial3D
	var finish_marker: bool = marker_material != null \
		and marker_material.albedo_color.is_equal_approx(detector.marker_finish_color)
	print("[near finish lock] distance=%.3f m / finish_lock_range=%.3f m / marker=%s" %
		[distance, detector.finish_lock_range, str(finish_marker)])
	_assert("finish_lock_range 以内ならダウン犯人を狙い直せる",
		distance <= detector.finish_lock_range and detector.current_target() == robber)
	_assert("追い打ち対象は生存対象と異なる marker_finish_color で示される", finish_marker)

	await _strike(hitbox, MELEE_DAMAGE)
	print("[finish hit] count=1 killed=%d" % RunState.robbers_killed)
	_assert("ロックオンして1回叩いても robbers_killed は増えない",
		RunState.robbers_killed == 0)
	await _strike(hitbox, MELEE_DAMAGE)
	print("[finish hit] count=2 killed=%d" % RunState.robbers_killed)
	_assert("既定 finish_hits の2回目で robbers_killed が1増える",
		health.finish_hits == 2 and RunState.robbers_killed == 1)
	await _strike(hitbox, MELEE_DAMAGE)
	print("[finish hit] count=3 killed=%d" % RunState.robbers_killed)
	_assert("成立後にさらに叩いても robbers_killed を二重記録しない",
		RunState.robbers_killed == 1)


func _test_finish_range() -> void:
	await _new_world()
	var player := _spawn_test_player()
	var detector := _lock_on(player)
	var far_distance := detector.finish_lock_range + FAR_RANGE_MARGIN
	var robber := _spawn_robber(Vector3(0.0, 0.05, -far_distance))
	await _wait_frames(SETTLE_FRAMES)
	var health := robber.get_node(^"Health") as Health
	health.take_hit(health.max_hp)
	await _wait_frames(2)
	await _toggle_lock_on()
	var measured := player.global_position.distance_to(robber.global_position)
	print("[far finish lock] distance=%.3f m / finish_lock_range=%.3f m" %
		[measured, detector.finish_lock_range])
	_assert("finish_lock_range より遠いダウン犯人はロックオンできない",
		measured > detector.finish_lock_range and detector.current_target() == null)


func _test_combo_auto_release() -> void:
	await _new_world()
	_combo_landed = 0
	var player := _spawn_test_player()
	# 段ごとの踏み込みを止め、3段とも同じ相手への重なりを実測する。
	player.set("lunge_speeds", Vector3.ZERO)
	var robber := _spawn_robber(CLOSE_TARGET_POSITION)
	await _wait_frames(SETTLE_FRAMES)
	var detector := _lock_on(player)
	var health := robber.get_node(^"Health") as Health
	var hitbox := player.get_node(^"Model/MeleeHitbox") as Hitbox
	var melee := player.get_node(^"PlayerMelee")
	hitbox.hit_landed.connect(func(_target: Node3D) -> void: _combo_landed += 1)
	await _toggle_lock_on()
	# 初段で確実にダウンし、残り2段がダウン後に重なるHPへ調整する。
	health.take_hit(health.max_hp - 1.0)
	melee.call("attack")
	await _wait_frames(INPUT_QUEUE_FRAMES)
	melee.call("attack")
	await _wait_frames(INPUT_QUEUE_FRAMES)
	melee.call("attack")
	for _frame: int in range(COMBO_WAIT_FRAMES):
		await get_tree().physics_frame
		if str(melee.get("_state")) == "locomotion" and health.is_downed():
			break
	print("[combo down] landed=%d target_released=%s killed=%d" %
		[_combo_landed, str(detector.current_target() == null), RunState.robbers_killed])
	_assert("コンボ途中のダウン後に残り段が当たっても追い打ちにならない",
		health.is_downed() and _combo_landed >= 3
		and detector.current_target() == null and RunState.robbers_killed == 0)


func _test_civilian_excluded() -> void:
	await _new_world()
	_civilian_finished = 0
	var player := _spawn_test_player()
	var civilian := _spawn_civilian(CLOSE_TARGET_POSITION)
	await _wait_frames(SETTLE_FRAMES)
	var detector := _lock_on(player)
	var health := civilian.get_node(^"Health") as Health
	health.finished.connect(func(_attacker: Node3D) -> void: _civilian_finished += 1)
	for _hit: int in range(health.stagger_threshold):
		health.take_hit(health.max_hp)
	await _wait_frames(2)
	await _toggle_lock_on()
	var hitbox := player.get_node(^"Model/MeleeHitbox") as Hitbox
	# 万一 exempt_body が外から指定されても、客のダウン時 Hurtbox は検出不能のまま。
	hitbox.exempt_body = civilian
	await _strike(hitbox, MELEE_DAMAGE)
	print("[civilian finish] selected=%s finished=%d civilians_killed=%d" %
		[str(detector.current_target() == civilian), _civilian_finished, RunState.civilians_killed])
	_assert("ダウンした客はロックオン候補にも追い打ち対象にもならない",
		detector.current_target() == null and _civilian_finished == 0
		and RunState.civilians_killed == 0)


func _test_no_finish_keeps_nonlethal() -> void:
	await _new_world()
	var robber := _spawn_robber(CLOSE_TARGET_POSITION)
	await _wait_frames(SETTLE_FRAMES)
	var health := robber.get_node(^"Health") as Health
	health.take_hit(health.max_hp)
	await _wait_frames(SETTLE_FRAMES)
	print("[no finish] downed=%s robbers_killed=%d" %
		[str(health.is_downed()), RunState.robbers_killed])
	_assert("犯人をダウンさせても追い打ちしなければ robbers_killed は0のまま",
		health.is_downed() and RunState.robbers_killed == 0)


func _spawn_test_player() -> Node3D:
	var player := _spawn_player()
	player.set_physics_process(false)
	_prepare_melee_facing(player)
	return player


func _spawn_robber(position: Vector3) -> Node3D:
	var robber := ROBBER_SCENE.instantiate() as Node3D
	robber.position = position
	robber.set("fall_duration", 0.0)
	_actors.add_child(robber)
	robber.set_physics_process(false)
	return robber
