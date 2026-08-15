extends "res://tools/leader_test_harness.gd"

## リーダーの客確保・方向防御・解除条件を検証するヘッドレスシーン。

const PLAYER_POSITION: Vector3 = Vector3(0.0, 0.0, -8.0)
const CIVILIAN_POSITION: Vector3 = Vector3(0.0, 0.0, -2.0)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== リーダー 検証開始 ===")
	await _test_fallback_without_civilian()
	await _test_shield_stationary_and_orbit()
	await _test_shield_combat_and_cooldown()
	await _test_downed_releases_civilian()
	await _test_prologue_does_not_grab()
	await _clear_world()
	print("=== 結果: PASS=%d FAIL=%d ===" % [_pass, _fail])
	print("ALL PASS" if _fail == 0 else "FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _test_fallback_without_civilian() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	_spawn_player(PLAYER_POSITION)
	var leader := _spawn_leader(Vector3.ZERO)
	var chase_elapsed := await _wait_for_state(leader, Robber.State.CHASE, STATE_TIMEOUT)
	print("[fallback] CHASE=%.3f sec / state=%d" % [chase_elapsed, leader.current_state()])
	_assert("1. 掴める客が居なければ CHASE へフォールバックする",
		leader.current_state() == Robber.State.CHASE)


func _test_shield_stationary_and_orbit() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	var player := _spawn_player(PLAYER_POSITION)
	_spawn_civilian(CIVILIAN_POSITION)
	var leader := _spawn_leader(Vector3.ZERO)
	await _wait_for_shield(leader, SHIELD_TIMEOUT)

	var stationary_start := leader.global_position
	for _index: int in range(_seconds_to_frames(SHIELD_STATIONARY_DURATION)):
		await get_tree().physics_frame
	var stationary_distance := _flat_distance(stationary_start, leader.global_position)
	print("[shield stationary] duration=%.3f sec / horizontal distance=%.5f m / threshold=%.5f m" %
		[SHIELD_STATIONARY_DURATION, stationary_distance, SHIELD_STATIONARY_MAX_DISTANCE])
	_assert("14. SHIELD 中は一定時間経っても水平移動しない",
		leader.current_state() == int(LEADER_SCRIPT.SHIELD)
		and stationary_distance <= SHIELD_STATIONARY_MAX_DISTANCE)

	var orbit_radius := ATTACK_DISTANCE
	var start_forward := -leader.global_transform.basis.z
	start_forward.y = 0.0
	start_forward = start_forward.normalized()
	player.global_position = leader.global_position + start_forward * orbit_radius
	await get_tree().physics_frame
	# 実機と同じ move_speed で近接間合いの円周を進み、盾の追従が間に合うかを測る。
	var move_speed: float = float(player.get("move_speed"))
	var physics_delta := 1.0 / float(Engine.physics_ticks_per_second)
	var target_arc := deg_to_rad(ORBIT_ARC_DEG)
	var traveled_arc := 0.0
	var orbit_frames := 0
	while traveled_arc < target_arc:
		traveled_arc = minf(
			traveled_arc + move_speed * physics_delta / orbit_radius, target_arc)
		var orbit_direction := start_forward.rotated(Vector3.UP, traveled_arc)
		player.global_position = leader.global_position + orbit_direction * orbit_radius
		await get_tree().physics_frame
		orbit_frames += 1

	var shield_forward := -leader.global_transform.basis.z
	shield_forward.y = 0.0
	shield_forward = shield_forward.normalized()
	var toward_player := player.global_position - leader.global_position
	toward_player.y = 0.0
	var measured_angle := rad_to_deg(shield_forward.angle_to(toward_player.normalized()))
	var measured_duration := float(orbit_frames) * physics_delta
	var orbit_hit := await _perform_player_hit_at_current_position(player, leader)
	print(("[shield orbit] move_speed=%.3f m/s / radius=%.3f m / arc=%.2f deg / " +
		"duration=%.3f sec / shield_face_speed=%.3f / relative angle=%.2f deg / " +
		"shield half arc=%.2f deg / HP %.1f -> %.1f") %
		[move_speed, orbit_radius, rad_to_deg(traveled_arc), measured_duration,
		float(leader.get("shield_face_speed")), measured_angle,
		float(leader.get("shield_arc_deg")) * 0.5,
		float(orbit_hit.hp_before), float(orbit_hit.hp_after)])
	_assert("15. move_speed で近接間合いを回り込むと盾の角度から外れて攻撃が通る",
		int(leader.get("shield_break_hits")) > 1
		and measured_angle > float(leader.get("shield_arc_deg")) * 0.5
		and float(orbit_hit.hp_after) < float(orbit_hit.hp_before)
		and leader.current_state() == int(LEADER_SCRIPT.SHIELD))


func _test_shield_combat_and_cooldown() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	var player := _spawn_player(PLAYER_POSITION)
	var civilian := _spawn_civilian(CIVILIAN_POSITION)
	var leader := _spawn_leader(Vector3.ZERO)
	var shield_elapsed := await _wait_for_shield(leader, SHIELD_TIMEOUT)
	var held := leader.call("shielded_civilian") as Civilian
	print("[grab] SHIELD=%.3f sec / held=%s" %
		[shield_elapsed, str(held == civilian)])
	_assert("2. 客が居れば視認後に接近して掴み SHIELD に入る",
		leader.current_state() == int(LEADER_SCRIPT.SHIELD) and held == civilian)

	await get_tree().physics_frame
	var held_distance := _flat_distance(leader.global_position, civilian.global_position)
	var forward := -leader.global_transform.basis.z.normalized()
	var toward_civilian := (civilian.global_position - leader.global_position).normalized()
	var forward_dot := forward.dot(toward_civilian)
	print("[shield offset] measured=%.3f m / configured=%.3f m / forward dot=%.4f" %
		[held_distance, float(leader.get("shield_offset")), forward_dot])
	_assert("3. SHIELD 中は客が SHIELDED になり正面 shield_offset に保たれる",
		civilian.current_state() == Civilian.CivilianState.SHIELDED
		and is_equal_approx(held_distance, float(leader.get("shield_offset")))
		and forward_dot > 0.99)

	GameDirector.advance_to(GameTypes.Act.INFILTRATION)
	await get_tree().physics_frame
	print("[act change] act=%d / civilian state=%d" %
		[GameDirector.current_act, civilian.current_state()])
	_assert("4. SHIELDED 中は INFILTRATION になっても PRONE へ遷移しない",
		civilian.current_state() == Civilian.CivilianState.SHIELDED)

	# 攻撃時だけ移動を止め、同じ距離・ダメージで角度だけを変えて比較する。
	leader.set_physics_process(false)
	civilian.set_physics_process(false)
	var front := await _perform_player_hit(player, leader, AttackSide.FRONT)
	print("[front] angle=%.2f deg / distance=%.3f m / damage=%.1f / HP %.1f -> %.1f" %
		[front.angle, front.distance, ATTACK_DAMAGE, front.hp_before, front.hp_after])
	_assert("5. 正面からの近接は盾で防がれ HP が減らない",
		is_equal_approx(float(front.hp_after), float(front.hp_before)))
	_assert("13. 防がれた攻撃は hit_landed が出ずヒットストップ・シェイクも起きない",
		int(front.landed) == 0 and is_equal_approx(float(front.time_scale), 1.0)
		and not bool(front.camera_shaking))

	var side := await _perform_player_hit(player, leader, AttackSide.SIDE)
	print("[side] angle=%.2f deg / distance=%.3f m / damage=%.1f / HP %.1f -> %.1f" %
		[side.angle, side.distance, ATTACK_DAMAGE, side.hp_before, side.hp_after])
	_assert("6. 同じ距離・ダメージでも側面からの近接は通る",
		float(side.hp_after) < float(side.hp_before)
		and is_equal_approx(float(side.distance), float(front.distance)))

	var back := await _perform_player_hit(player, leader, AttackSide.BACK)
	print("[back] angle=%.2f deg / distance=%.3f m / damage=%.1f / HP %.1f -> %.1f" %
		[back.angle, back.distance, ATTACK_DAMAGE, back.hp_before, back.hp_after])
	_assert("7. 背面からの近接も通る", float(back.hp_after) < float(back.hp_before))

	var breaking := await _perform_player_hit(player, leader, AttackSide.SIDE)
	print("[break] accepted hits=%d / state=%d / civilian state=%d" %
		[int(leader.get("shield_break_hits")), leader.current_state(), civilian.current_state()])
	_assert("8. 側面・背面から shield_break_hits 回当てると客を解放して幕の姿勢へ戻す",
		float(breaking.hp_after) < float(breaking.hp_before)
		and leader.current_state() == Robber.State.CHASE
		and civilian.current_state() == Civilian.CivilianState.PRONE)

	var released_front := await _perform_player_hit(player, leader, AttackSide.FRONT)
	print("[released front] angle=%.2f deg / HP %.1f -> %.1f / landed=%d" %
		[released_front.angle, released_front.hp_before, released_front.hp_after,
		int(released_front.landed)])
	_assert("9. 解除後は CHASE へ移り正面からの近接も通る",
		leader.current_state() == Robber.State.STAGGERED
		and float(released_front.hp_after) < float(released_front.hp_before)
		and int(released_front.landed) == 1)

	leader.set_physics_process(true)
	civilian.set_physics_process(true)
	var regrab_cooldown: float = float(leader.get("regrab_cooldown"))
	var protected_duration := maxf(regrab_cooldown - WAIT_MARGIN, 0.0)
	var stayed_released := await _wait_while_shielded(leader, protected_duration)
	var regrab_elapsed := await _wait_for_regrab(
		leader, regrab_cooldown + SHIELD_TIMEOUT)
	var total_elapsed := protected_duration + regrab_elapsed
	print("[regrab] released for %.3f sec / configured cooldown=%.3f sec" %
		[total_elapsed, regrab_cooldown])
	_assert("10. 解除直後は regrab_cooldown の間掴み直さない",
		stayed_released and total_elapsed >= regrab_cooldown
		and leader.current_state() == int(LEADER_SCRIPT.SHIELD))


func _test_downed_releases_civilian() -> void:
	await _new_world(GameTypes.Act.INFILTRATION)
	_spawn_player(PLAYER_POSITION)
	var civilian := _spawn_civilian(CIVILIAN_POSITION)
	var leader := _spawn_leader(Vector3.ZERO)
	await _wait_for_shield(leader, SHIELD_TIMEOUT)
	var health := leader.get_node("Health") as Health
	health.take_hit(health.max_hp)
	await get_tree().physics_frame
	print("[downed] leader state=%d / civilian state=%d / held=%s" %
		[leader.current_state(), civilian.current_state(),
		str(leader.call("shielded_civilian"))])
	_assert("11. リーダーがダウンすると客が解放され掴まれたまま残らない",
		leader.current_state() == Robber.State.DOWNED
		and civilian.current_state() != Civilian.CivilianState.SHIELDED
		and leader.call("shielded_civilian") == null)


func _test_prologue_does_not_grab() -> void:
	await _new_world(GameTypes.Act.PROLOGUE)
	_spawn_player(PLAYER_POSITION)
	var civilian := _spawn_civilian(CIVILIAN_POSITION)
	var leader := _spawn_leader(Vector3.ZERO)
	await get_tree().create_timer(1.0).timeout
	print("[prologue] leader state=%d / civilian state=%d / held=%s" %
		[leader.current_state(), civilian.current_state(),
		str(leader.call("shielded_civilian"))])
	_assert("12. Act.PROLOGUE では客を掴まない",
		leader.current_state() != int(LEADER_SCRIPT.SHIELD)
		and civilian.current_state() != Civilian.CivilianState.SHIELDED
		and leader.call("shielded_civilian") == null)
