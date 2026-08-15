extends "res://tools/gunner_test_harness.gd"

## 銃持ちの COVER 選定・移動・射撃を検証するヘッドレスシーン。

const CIVILIAN_SCENE: PackedScene = preload("res://actors/npc/civilian.tscn")
const ROBBER_SCENE: PackedScene = preload("res://actors/npc/robber.tscn")
const PLAYER_POSITION: Vector3 = Vector3(0.0, 0.0, -8.0)
const ALT_PLAYER_POSITION: Vector3 = Vector3(6.0, 0.0, -8.0)
const CLEAR_NEAR: Vector3 = Vector3(-2.0, 0.0, 0.0)
const CLEAR_FAR: Vector3 = Vector3(-5.0, 0.0, 1.0)
const BLOCKED_POSITION: Vector3 = Vector3(3.0, 0.0, 0.0)
const TOO_CLOSE_POSITION: Vector3 = Vector3(0.0, 0.0, -3.0)
const WALL_POSITION: Vector3 = Vector3(1.5, 1.2, -4.0)
const WALL_SIZE: Vector3 = Vector3(0.8, 3.0, 0.8)
const LONG_REEVALUATE: float = 10.0
const STRAY_CIVILIAN_HEIGHT: float = 0.85


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 銃持ち 検証開始 ===")
	await _test_fallback_without_cover()
	await _test_cover_selection()
	await _test_blocked_only_fallback()
	await _test_shooting_and_damage()
	await _test_robber_does_not_block_shot()
	await _test_reevaluation()
	await _test_melee_stops_shooting()
	await _test_prologue_and_downed()
	await _test_civilian_stray_fire()
	await _clear_world()
	print("=== 結果: PASS=%d FAIL=%d ===" % [_pass, _fail])
	print("ALL PASS" if _fail == 0 else "FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _test_fallback_without_cover() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	var player := _spawn_player(PLAYER_POSITION)
	var gunner := _spawn_gunner(Vector3.ZERO)
	var start_distance := _flat_distance(gunner.global_position, player.global_position)
	var chase_elapsed := await _wait_for_state(gunner, Robber.State.CHASE, STATE_TIMEOUT)
	await _wait_seconds(0.35)
	var end_distance := _flat_distance(gunner.global_position, player.global_position)
	print("[fallback] CHASE=%.3f sec / distance %.3f -> %.3f m" %
		[chase_elapsed, start_distance, end_distance])
	_assert("1. 遮蔽地点が無ければ CHASE へフォールバックして接近する",
		gunner.current_state() == Robber.State.CHASE and end_distance < start_distance)


func _test_cover_selection() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	var player := _spawn_player(PLAYER_POSITION)
	var near := _add_cover(&"CoverNear", CLEAR_NEAR)
	var far := _add_cover(&"CoverFar", CLEAR_FAR)
	var blocked := _add_cover(&"CoverBlocked", BLOCKED_POSITION)
	var too_close := _add_cover(&"CoverTooClose", TOO_CLOSE_POSITION)
	_add_wall(WALL_POSITION, WALL_SIZE)
	var gunner := _spawn_gunner(Vector3.ZERO)
	var entered: Array[int] = []
	gunner.state_entered.connect(func(state: int) -> void: entered.append(state))
	var cover_elapsed := await _wait_for_state(gunner, Gunner.COVER, STATE_TIMEOUT)
	var selected := gunner.selected_cover()
	var gun := gunner.get_node("MuzzlePoint/HitscanGun") as HitscanGun
	var blocked_clear := gun.has_clear_shot_from(
		blocked.global_position + Vector3.UP * gunner.cover_muzzle_height,
		player, player.global_position + Vector3.UP * gunner.player_aim_height)
	var selected_clear: bool = selected != null and gun.has_clear_shot_from(
		selected.global_position + Vector3.UP * gunner.cover_muzzle_height,
		player, player.global_position + Vector3.UP * gunner.player_aim_height)
	var selected_player_distance := _flat_distance(selected.global_position, player.global_position)
	var near_distance := _flat_distance(gunner.global_position, near.global_position)
	var far_distance := _flat_distance(gunner.global_position, far.global_position)
	var close_player_distance := _flat_distance(too_close.global_position, player.global_position)
	print("[cover] state=%.3f sec / selected=%s / clear=%s / blocked_clear=%s" %
		[cover_elapsed, selected.name, str(selected_clear), str(blocked_clear)])
	print("[cover distance] selected-player=%.3f m / minimum=%.3f m / rejected=%.3f m" %
		[selected_player_distance, gunner.min_cover_distance, close_player_distance])
	print("[candidate distance] near=%.3f m / far=%.3f m" % [near_distance, far_distance])
	_assert("2. プレイヤー視認後は CHASE を経ず COVER に入る",
		gunner.current_state() == Gunner.COVER and not entered.has(Robber.State.CHASE))
	_assert("3. マーカー地点から射線が通る候補だけを選ぶ",
		selected_clear and not blocked_clear and selected != blocked)
	_assert("4. 選択地点はプレイヤーから min_cover_distance 以上離れている",
		selected_player_distance >= gunner.min_cover_distance
		and close_player_distance < gunner.min_cover_distance and selected != too_close)
	_assert("5. 条件を満たす候補のうち自分に最も近い地点を選ぶ",
		near_distance < far_distance and selected == near)


func _test_blocked_only_fallback() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	_spawn_player(PLAYER_POSITION)
	_add_cover(&"CoverBlockedOnly", BLOCKED_POSITION)
	_add_wall(WALL_POSITION, WALL_SIZE)
	var gunner := _spawn_gunner(Vector3.ZERO)
	await _wait_for_state(gunner, Robber.State.CHASE, STATE_TIMEOUT)
	print("[blocked only] state=%d / selected=%s" %
		[gunner.current_state(), str(gunner.selected_cover())])
	_assert("3b. 射線が通らない地点しか無い場合は選ばない",
		gunner.current_state() == Robber.State.CHASE and gunner.selected_cover() == null)


func _test_shooting_and_damage() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	var player := _spawn_player(PLAYER_POSITION)
	_add_cover(&"CoverAtGunner", Vector3.ZERO)
	var gunner := _spawn_gunner(Vector3.ZERO)
	var health := player.get_node("Health") as Health
	await _wait_for_shots(1, STATE_TIMEOUT)
	var hp_after_one := health.current_hp()
	await _wait_for_shots(2, STATE_TIMEOUT)
	var measured_interval := float(_shot_frames[1] - _shot_frames[0]) \
		/ float(Engine.physics_ticks_per_second)
	var frame_duration := 1.0 / float(Engine.physics_ticks_per_second)
	print("[shoot] interval=%.3f sec / configured=%.3f sec / HP after one=%.1f" %
		[measured_interval, gunner.shoot_interval, hp_after_one])
	_assert("6. 遮蔽地点に着くと shoot_interval ごとにプレイヤーを撃つ",
		_shots.size() >= 2 and measured_interval >= gunner.shoot_interval
		and measured_interval <= gunner.shoot_interval + frame_duration * 2.0
		and health.current_hp() < health.max_hp)
	_assert("11. damage=20 の一発ではプレイヤーはダウンしない",
		is_equal_approx(hp_after_one, 80.0) and not health.is_downed())


func _test_robber_does_not_block_shot() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	var player := _spawn_player(PLAYER_POSITION)
	var gunner := _spawn_gunner(Vector3.ZERO)
	gunner.set_physics_process(false)
	var ally := ROBBER_SCENE.instantiate() as Robber
	ally.position = Vector3(0.0, 0.0, -4.0)
	_actors.add_child(ally)
	ally.set_physics_process(false)
	for _frame: int in range(6):
		await get_tree().physics_frame
	var gun := gunner.get_node("MuzzlePoint/HitscanGun") as HitscanGun
	var ally_health := ally.get_node("Health") as Health
	var player_health := player.get_node("Health") as Health
	var aim := player.global_position + Vector3.UP * gunner.player_aim_height
	var clear_through_ally := gun.has_clear_shot(player, aim)
	var hit_body := gun.fire_at(aim)
	await get_tree().physics_frame
	print(("[ally transparency] clear=%s hit=%s ally HP=%.1f player HP=%.1f " +
		"ignore=%s") % [str(clear_through_ally), str(hit_body),
		ally_health.current_hp(), player_health.current_hp(), str(gun.ignore_groups)])
	_assert("6a. プレイヤーとの直線上にいる仲間の犯人は銃撃で HP が減らない",
		is_equal_approx(ally_health.current_hp(), ally_health.max_hp)
		and gun.ignore_groups.has(&"robber"))
	_assert("6b. 仲間越しでも射線ありと判定し、背後のプレイヤーへ命中する",
		clear_through_ally and hit_body == player
		and is_equal_approx(player_health.current_hp(), 80.0))


func _test_reevaluation() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	var player := _spawn_player(PLAYER_POSITION)
	var first := _add_cover(&"CoverFirst", Vector3.ZERO)
	var alternate := _add_cover(&"CoverAlternate", Vector3(-4.0, 0.0, 0.0))
	_add_wall(Vector3(3.0, 1.2, -4.0), WALL_SIZE)
	var gunner := _spawn_gunner(Vector3.ZERO)
	await _wait_for_state(gunner, Gunner.COVER, STATE_TIMEOUT)
	var initially_first := gunner.selected_cover() == first
	player.global_position = ALT_PLAYER_POSITION
	var elapsed := await _wait_for_selected_cover(
		gunner, alternate, gunner.cover_reevaluate_interval + WAIT_MARGIN)
	var moved_after_switch := _flat_distance(gunner.global_position, first.global_position)
	print("[reevaluate] selected %s -> %s / elapsed=%.3f sec / limit=%.3f sec / moved=%.3f m" %
		[first.name, gunner.selected_cover().name, elapsed, gunner.cover_reevaluate_interval,
		moved_after_switch])
	_assert("7. プレイヤー移動で射線が切れると再評価間隔以内に別地点へ移る",
		initially_first and gunner.selected_cover() == alternate
		and elapsed <= gunner.cover_reevaluate_interval + WAIT_MARGIN
		and moved_after_switch > 0.0)


func _test_melee_stops_shooting() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	var player := _spawn_player(PLAYER_POSITION)
	_add_cover(&"CoverAtGunner", Vector3.ZERO)
	var gunner := _spawn_gunner(Vector3.ZERO)
	await _wait_for_state(gunner, Gunner.COVER, STATE_TIMEOUT)
	player.global_position = Vector3(0.0, 0.0, -1.0)
	var attack_elapsed := await _wait_for_state(gunner, Robber.State.ATTACK, STATE_TIMEOUT)
	await _wait_seconds(gunner.shoot_interval + gunner.shoot_telegraph_duration + WAIT_MARGIN)
	print("[melee] ATTACK=%.3f sec / shots=%d" % [attack_elapsed, _shots.size()])
	_assert("8. attack_range 内では ATTACK に入り銃を撃たない",
		attack_elapsed < STATE_TIMEOUT and _shots.is_empty())


func _test_prologue_and_downed() -> void:
	await _new_world(GameTypes.Act.PROLOGUE)
	var prologue_player := _spawn_player(PLAYER_POSITION)
	_add_cover(&"CoverAtGunner", Vector3.ZERO)
	var prologue_gunner := _spawn_gunner(Vector3.ZERO)
	await _wait_seconds(0.8)
	var prologue_hp := (prologue_player.get_node("Health") as Health).current_hp()
	print("[prologue] state=%d / shots=%d / HP=%.1f" %
		[prologue_gunner.current_state(), _shots.size(), prologue_hp])
	_assert("9. Act.PROLOGUE では撃たない", _shots.is_empty() and is_equal_approx(prologue_hp, 100.0))

	await _new_world(GameTypes.Act.INFILTRATION)
	var down_player := _spawn_player(PLAYER_POSITION)
	_add_cover(&"CoverAtGunner", Vector3.ZERO)
	var down_gunner := _spawn_gunner(Vector3.ZERO)
	var robber_health := down_gunner.get_node("Health") as Health
	await _wait_for_state(down_gunner, Gunner.COVER, STATE_TIMEOUT)
	robber_health.take_hit(robber_health.max_hp)
	await _wait_seconds(0.8)
	var down_player_hp := (down_player.get_node("Health") as Health).current_hp()
	print("[downed] state=%d / shots=%d / player HP=%.1f" %
		[down_gunner.current_state(), _shots.size(), down_player_hp])
	_assert("10. 犯人が DOWNED になったら以後撃たない",
		down_gunner.current_state() == Robber.State.DOWNED and _shots.is_empty()
		and is_equal_approx(down_player_hp, 100.0))


func _test_civilian_stray_fire() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	_spawn_player(PLAYER_POSITION)
	_add_cover(&"CoverAtGunner", Vector3.ZERO)
	var gunner := _spawn_gunner(Vector3.ZERO)
	gunner.cover_reevaluate_interval = LONG_REEVALUATE
	await _wait_until_telegraph(gunner, STATE_TIMEOUT)
	var civilian := CIVILIAN_SCENE.instantiate() as Civilian
	civilian.position = Vector3(0.0, STRAY_CIVILIAN_HEIGHT, -4.0)
	_actors.add_child(civilian)
	# 射線上へ入った瞬間を再現する検証なので、重力で高さが変わらないよう固定する。
	civilian.set_physics_process(false)
	var civilian_health := civilian.get_node("Health") as Health
	await _wait_for_civilian_kill(STATE_TIMEOUT)
	var civilian_hits: int = _shots.count(civilian)
	print("[stray] hits=%d / civilian HP=%.1f / killed=%d / damage=%.1f" %
		[civilian_hits, civilian_health.current_hp(), RunState.civilians_killed,
		(gunner.get_node("MuzzlePoint/HitscanGun") as HitscanGun).damage])
	_assert("12. 流れ弾を5発受けた客は civilians_killed に入る",
		civilian_hits == 5 and civilian_health.is_downed() and RunState.civilians_killed == 1)
