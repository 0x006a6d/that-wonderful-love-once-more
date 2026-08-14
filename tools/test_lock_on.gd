extends "res://tools/test_lock_on_fixture.gd"

## ロックオン、客への近接例外、カメラ追従をヘッドレス検証する。
## godot --path . --headless res://tools/test_lock_on.tscn

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== ロックオン 検証開始 ===")
	await _test_no_candidate()
	await _test_layer_target("範囲内の犯人をロックオンできる", ROBBER_LAYER, &"robber")
	await _test_layer_target("範囲内の客をロックオンできる", CIVILIAN_LAYER, &"civilian")
	await _test_angle_selection()
	await _test_wall_filter()
	await _test_toggle_release()
	await _test_downed_release()
	await _test_range_release()
	await _test_short_occlusion()
	await _test_civilian_filter_and_exemption()
	await _test_other_civilian_filtered()
	await _test_three_hit_down()
	await _test_camera_follow()
	await _clear_world()
	_finish()


func _test_no_candidate() -> void:
	await _new_world()
	var player := _spawn_player()
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	_assert("候補が居なければロックオンできない", _lock_on(player).current_target() == null)


func _test_layer_target(label: String, layer: int, group: StringName) -> void:
	await _new_world()
	var player := _spawn_player()
	var target := _spawn_target("Candidate", layer, group, Vector3(0.0, 0.0, -6.0))
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	_assert(label, _lock_on(player).current_target() == target)


func _test_angle_selection() -> void:
	await _new_world()
	var player := _spawn_player()
	var centered := _spawn_target("Centered", ROBBER_LAYER, &"robber", Vector3(0.0, 0.0, -6.0))
	var offset := _spawn_target("Offset", CIVILIAN_LAYER, &"civilian", Vector3(2.5, 0.0, -6.0))
	await _wait_frames(SETTLE_FRAMES)
	var camera := player.get_node("SpringArm3D/Camera3D") as Camera3D
	var centered_angle := _camera_angle_deg(camera, centered)
	var offset_angle := _camera_angle_deg(camera, offset)
	print("[angle] Centered=%.3f deg / Offset=%.3f deg" % [centered_angle, offset_angle])
	await _toggle_lock_on()
	_assert("候補2体ではカメラ前方との角度が小さいほうを選ぶ",
		centered_angle < offset_angle and _lock_on(player).current_target() == centered)


func _test_wall_filter() -> void:
	await _new_world()
	var player := _spawn_player()
	var target := _spawn_target("Occluded", ROBBER_LAYER, &"robber", Vector3(0.0, 0.0, -6.0))
	await _wait_frames(SETTLE_FRAMES)
	_spawn_wall_between(player, target)
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	_assert("壁で遮蔽された対象はロックオンできない", _lock_on(player).current_target() == null)


func _test_toggle_release() -> void:
	await _new_world()
	var player := _spawn_player()
	var target := _spawn_target("Toggle", ROBBER_LAYER, &"robber", Vector3(0.0, 0.0, -5.0))
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	var acquired: bool = _lock_on(player).current_target() == target
	await _toggle_lock_on()
	_assert("lock_on の再押下で解除できる", acquired and _lock_on(player).current_target() == null)


func _test_downed_release() -> void:
	await _new_world()
	var player := _spawn_player()
	var target := _spawn_target("Downed", ROBBER_LAYER, &"robber", Vector3(0.0, 0.0, -5.0))
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	var health := target.get_node("Health") as Health
	health.take_hit(health.max_hp)
	await get_tree().physics_frame
	_assert("対象がダウンすると自動解除される", health.is_downed()
		and _lock_on(player).current_target() == null)


func _test_range_release() -> void:
	await _new_world()
	var player := _spawn_player()
	var target := _spawn_target("Far", ROBBER_LAYER, &"robber", Vector3(0.0, 0.0, -5.0))
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	var detector := _lock_on(player)
	target.global_position = Vector3(0.0, 0.0, -(detector.lock_on_release_range + 1.0))
	await _wait_frames(2)
	print("[range] target=%.3f m / release=%.3f m" %
		[player.global_position.distance_to(target.global_position), detector.lock_on_release_range])
	_assert("対象が lock_on_release_range の外へ出ると自動解除される",
		detector.current_target() == null)


func _test_short_occlusion() -> void:
	await _new_world()
	var player := _spawn_player()
	var target := _spawn_target("Grace", ROBBER_LAYER, &"robber", Vector3(0.0, 0.0, -6.0))
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	var detector := _lock_on(player)
	_spawn_wall_between(player, target)
	var wait_frames := maxi(1, floori(detector.lose_target_grace * 0.5 *
		Engine.physics_ticks_per_second))
	await _wait_frames(wait_frames)
	var measured := float(wait_frames) / float(Engine.physics_ticks_per_second)
	print("[occlusion] measured=%.3f sec / grace=%.3f sec" %
		[measured, detector.lose_target_grace])
	_assert("遮蔽が lose_target_grace 未満なら解除されない",
		measured < detector.lose_target_grace and detector.current_target() == target)


func _test_civilian_filter_and_exemption() -> void:
	await _new_world()
	var player := _spawn_player()
	var civilian := _spawn_civilian(Vector3(0.0, 0.0, -0.5))
	_prepare_melee_facing(player)
	await _wait_frames(SETTLE_FRAMES)
	var health := civilian.get_node("Health") as Health
	var hitbox := player.get_node("Model/MeleeHitbox") as Hitbox
	var hp_before := health.current_hp()
	await _strike(hitbox, MELEE_DAMAGE)
	var hp_without_lock := health.current_hp()
	print("[melee unlocked] civilian HP %.1f -> %.1f" % [hp_before, hp_without_lock])
	_assert("ロックオンしていないとき客に近接が当たらない",
		is_equal_approx(hp_before, hp_without_lock))
	await _toggle_lock_on()
	await _strike(hitbox, MELEE_DAMAGE)
	var hp_with_lock := health.current_hp()
	print("[melee locked] civilian HP %.1f -> %.1f / exempt=%s" %
		[hp_without_lock, hp_with_lock, str(hitbox.exempt_body == civilian)])
	_assert("同じ配置で客をロックオンすると近接が当たる",
		_lock_on(player).current_target() == civilian and hp_with_lock < hp_without_lock)


func _test_other_civilian_filtered() -> void:
	await _new_world()
	var player := _spawn_player()
	var civilian_a := _spawn_civilian(Vector3(0.0, 0.0, -0.5))
	var civilian_b := _spawn_civilian(Vector3(0.25, 0.0, -0.5))
	_prepare_melee_facing(player)
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	var health_b := civilian_b.get_node("Health") as Health
	var hp_b_before := health_b.current_hp()
	await _strike(player.get_node("Model/MeleeHitbox") as Hitbox, MELEE_DAMAGE)
	print("[other civilian] B HP %.1f -> %.1f" % [hp_b_before, health_b.current_hp()])
	_assert("客Aをロックオン中は客Bに当たらない",
		_lock_on(player).current_target() == civilian_a
		and is_equal_approx(hp_b_before, health_b.current_hp()))


func _test_three_hit_down() -> void:
	await _new_world()
	var player := _spawn_player()
	var civilian := _spawn_civilian(Vector3(0.0, 0.0, -0.5))
	_prepare_melee_facing(player)
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	var health := civilian.get_node("Health") as Health
	var hitbox := player.get_node("Model/MeleeHitbox") as Hitbox
	for hit_index: int in range(3):
		await _strike(hitbox, health.max_hp)
		print("[three hits] hit=%d HP=%.1f downed=%s" %
			[hit_index + 1, health.current_hp(), str(health.is_downed())])
	_assert("ロックオンした客は3回目で DOWNED になり RunState が増える",
		health.is_downed()
		and int(civilian.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.DOWNED
		and RunState.civilians_downed == 1)


func _test_camera_follow() -> void:
	await _new_world()
	var player := _spawn_player()
	_spawn_target("CameraTarget", ROBBER_LAYER, &"robber", Vector3(4.0, 0.0, -6.0))
	await _wait_frames(SETTLE_FRAMES)
	var rig := player.get_node("SpringArm3D") as Node3D
	var before := rig.rotation.y
	await _toggle_lock_on()
	var target := _lock_on(player).current_target()
	var flat := target.global_position - player.global_position
	var theoretical := atan2(-flat.x, -flat.z)
	await _wait_frames(CAMERA_FOLLOW_FRAMES)
	var after := rig.rotation.y
	var before_error := absf(wrapf(before - theoretical, -PI, PI))
	var after_error := absf(wrapf(after - theoretical, -PI, PI))
	print("[camera yaw] before=%.3f deg / after=%.3f deg / theoretical=%.3f deg" %
		[rad_to_deg(before), rad_to_deg(after), rad_to_deg(theoretical)])
	_assert("カメラのヨーがロックオン対象方向へ向く", after_error < before_error)

