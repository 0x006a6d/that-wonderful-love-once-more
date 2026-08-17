extends "res://tools/test_lock_on_fixture.gd"

## HUD の HP 通知、人数、画面上ロックオン表示、エンディング時の非表示を検証する。
## 実行: godot --path . --headless res://tools/test_hud.tscn

const HUD_SCENE: PackedScene = preload("res://ui/hud.tscn")
const ENDING_CARD_SCENE: PackedScene = preload("res://ui/ending_card.tscn")
const TEST_MAX_HP: float = 100.0
const HIT_DAMAGE: float = 28.0
const HEAL_AMOUNT: float = 8.0
const ROBBER_TOTAL: int = 3
const CIVILIAN_TOTAL: int = 4
const LIVE_TARGET_POSITION: Vector3 = Vector3(0.0, 0.0, -6.0)
const FINISH_TARGET_POSITION: Vector3 = Vector3(0.0, 0.0, -0.5)
const MARKER_WAIT_FRAMES: int = 2
const BEHIND_CAMERA_DISTANCE: float = 2.0

var _hp_signal_values: Array[Vector2] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	print("=== HUD 検証開始 ===")
	await _test_health_signal()
	await _new_world()
	var player := _spawn_player()
	var hud := _spawn_hud()
	await _wait_frames(SETTLE_FRAMES)
	await _test_hp_display(player, hud)
	await _test_population(hud)
	await _test_lock_marker(player, hud)
	_test_ending_hides_hud(hud)
	get_tree().paused = false
	await _clear_world()
	_finish()


func _test_health_signal() -> void:
	var health := Health.new()
	health.name = "SignalHealth"
	health.max_hp = TEST_MAX_HP
	add_child(health)
	health.hp_changed.connect(_on_test_hp_changed)

	var take_start := _hp_signal_values.size()
	health.take_hit(HIT_DAMAGE)
	var take_value := _last_hp_signal()
	print("[hp_changed take_hit] current=%.3f maximum=%.3f" %
		[take_value.x, take_value.y])
	var take_ok: bool = _hp_signal_values.size() == take_start + 1 \
		and is_equal_approx(take_value.x, TEST_MAX_HP - HIT_DAMAGE) \
		and is_equal_approx(take_value.y, TEST_MAX_HP)

	var heal_start := _hp_signal_values.size()
	health.heal(HEAL_AMOUNT)
	var heal_value := _last_hp_signal()
	print("[hp_changed heal] current=%.3f maximum=%.3f" %
		[heal_value.x, heal_value.y])
	var heal_ok: bool = _hp_signal_values.size() == heal_start + 1 \
		and is_equal_approx(heal_value.x, TEST_MAX_HP - HIT_DAMAGE + HEAL_AMOUNT) \
		and is_equal_approx(heal_value.y, TEST_MAX_HP)

	health.take_hit(health.current_hp())
	var revive_start := _hp_signal_values.size()
	health.revive()
	var revive_value := _last_hp_signal()
	print("[hp_changed revive] current=%.3f maximum=%.3f" %
		[revive_value.x, revive_value.y])
	var revive_ok: bool = _hp_signal_values.size() == revive_start + 1 \
		and is_equal_approx(revive_value.x, TEST_MAX_HP) \
		and is_equal_approx(revive_value.y, TEST_MAX_HP)

	_assert("(1) hp_changed が take_hit / heal / revive の実測値を通知する",
		take_ok and heal_ok and revive_ok)
	health.queue_free()
	await get_tree().process_frame


func _spawn_hud() -> CanvasLayer:
	var hud := HUD_SCENE.instantiate() as CanvasLayer
	hud.set("health_path", NodePath("../Actors/Player/Health"))
	hud.set("camera_path", NodePath("../Actors/Player/SpringArm3D/Camera3D"))
	hud.set("lock_on_path", NodePath("../Actors/Player/LockOnDetector"))
	add_child(hud)
	return hud


func _test_hp_display(player: Node3D, hud: CanvasLayer) -> void:
	var health := player.get_node(^"Health") as Health
	var hp_bar_path: NodePath = hud.get("hp_bar_path")
	var bar := hud.get_node(hp_bar_path) as ProgressBar
	# 期待値は max_hp から導く。バランス調整で最大HPが変わっても壊れないようにする。
	var maximum: float = health.max_hp
	health.take_hit(HIT_DAMAGE)
	var hit_text := String(hud.call("hp_display_text"))
	var hit_value := float(hud.call("hp_bar_value"))
	var hit_pixels: float = bar.size.x * hit_value / bar.max_value
	print("[HUD HP hit] text='%s' value=%.3f max=%.3f width=%.3f filled=%.3f" %
		[hit_text, hit_value, bar.max_value, bar.size.x, hit_pixels])
	var hit_expected: float = maximum - HIT_DAMAGE
	_assert("(2a) 被弾後に HP 数値とバー長が追随する",
		hit_text == "SELF HP   %d / %d" % [roundi(hit_expected), roundi(maximum)]
		and is_equal_approx(hit_value, hit_expected)
		and is_equal_approx(hit_pixels, bar.size.x * hit_expected / maximum))

	health.heal(HEAL_AMOUNT)
	var heal_text := String(hud.call("hp_display_text"))
	var heal_value := float(hud.call("hp_bar_value"))
	var heal_pixels: float = bar.size.x * heal_value / bar.max_value
	print("[HUD HP heal] text='%s' value=%.3f max=%.3f width=%.3f filled=%.3f" %
		[heal_text, heal_value, bar.max_value, bar.size.x, heal_pixels])
	var heal_expected: float = minf(hit_expected + HEAL_AMOUNT, maximum)
	_assert("(2b) 回復後に HP 数値とバー長が増える",
		heal_text == "SELF HP   %d / %d" % [roundi(heal_expected), roundi(maximum)]
		and is_equal_approx(heal_value, heal_expected)
		and heal_pixels > hit_pixels
		and is_equal_approx(heal_pixels, bar.size.x * heal_expected / maximum))


func _test_population(hud: CanvasLayer) -> void:
	RunState.robbers_total = ROBBER_TOTAL
	RunState.civilians_total = CIVILIAN_TOTAL
	await get_tree().process_frame
	await get_tree().process_frame
	var robber_before := String(hud.call("robber_display_text"))
	var robber := Node3D.new()
	robber.name = "HudCountRobber"
	_actors.add_child(robber)
	RunState.record_down(robber, GameTypes.Faction.ROBBER, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var robber_after := String(hud.call("robber_display_text"))
	print("[HUD robber] before='%s' after='%s' downed=%d total=%d" %
		[robber_before, robber_after, RunState.robbers_downed, RunState.robbers_total])
	_assert("(3) 犯人を倒すと残りが減り、制圧数 / 総数も更新される",
		robber_before.contains("残り 3 / 3") and robber_before.contains("制圧 0 / 3")
		and robber_after.contains("残り 2 / 3") and robber_after.contains("制圧 1 / 3"))

	var civilian_before := String(hud.call("civilian_display_text"))
	var civilian := Node3D.new()
	civilian.name = "HudCountCivilian"
	_actors.add_child(civilian)
	RunState.record_down(civilian, GameTypes.Faction.CIVILIAN, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var civilian_after := String(hud.call("civilian_display_text"))
	print("[HUD civilian] before='%s' after='%s' downed=%d total=%d" %
		[civilian_before, civilian_after, RunState.civilians_downed,
		RunState.civilians_total])
	_assert("(4) 客がダウンすると生存人数が減る",
		civilian_before.contains("4 / 4") and civilian_after.contains("3 / 4"))


func _test_lock_marker(player: Node3D, hud: CanvasLayer) -> void:
	var robber := _spawn_target("HudLiveRobber", ROBBER_LAYER, &"robber",
		LIVE_TARGET_POSITION)
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	await _wait_frames(MARKER_WAIT_FRAMES)
	var marker_path: NodePath = hud.get("marker_path")
	var marker := hud.get_node(marker_path) as Label
	var robber_visible := bool(hud.call("marker_is_visible"))
	var robber_kind := int(hud.call("displayed_marker_kind"))
	var robber_text := String(hud.call("displayed_marker_text"))
	var robber_color: Color = hud.call("displayed_marker_color")
	var hud_marker_size: Vector2 = hud.get("marker_size")
	print("[HUD marker live robber] visible=%s kind=%d position=%s text='%s' color=%s" %
		[str(robber_visible), robber_kind, marker.position, robber_text, robber_color])
	_assert("(5) ロックオンすると対象位置に画面上マーカーが出る",
		robber_visible and robber_kind == LockOn.TargetKind.LIVE_ROBBER
		and marker.position.x >= -hud_marker_size.x
		and marker.position.y >= -hud_marker_size.y)

	await _toggle_lock_on()
	await get_tree().process_frame
	print("[HUD marker release] visible=%s kind=%d" %
		[str(bool(hud.call("marker_is_visible"))),
		int(hud.call("displayed_marker_kind"))])
	_assert("(7) ロックオンを外すと画面上マーカーが消える",
		not bool(hud.call("marker_is_visible"))
		and int(hud.call("displayed_marker_kind")) == LockOn.TargetKind.NONE)
	robber.queue_free()
	await get_tree().process_frame

	var civilian := _spawn_target("HudLiveCivilian", CIVILIAN_LAYER, &"civilian",
		LIVE_TARGET_POSITION)
	await _wait_frames(SETTLE_FRAMES)
	await _toggle_lock_on()
	await _wait_frames(MARKER_WAIT_FRAMES)
	var civilian_kind := int(hud.call("displayed_marker_kind"))
	var civilian_text := String(hud.call("displayed_marker_text"))
	var civilian_color: Color = hud.call("displayed_marker_color")
	print("[HUD marker civilian] visible=%s kind=%d text='%s' color=%s" %
		[str(bool(hud.call("marker_is_visible"))), civilian_kind,
		civilian_text, civilian_color])
	await _toggle_lock_on()
	civilian.queue_free()
	await get_tree().process_frame

	var downed_robber := _spawn_lock_test_robber(FINISH_TARGET_POSITION)
	await _wait_frames(SETTLE_FRAMES)
	var downed_health := downed_robber.get_node(^"Health") as Health
	downed_health.take_hit(downed_health.max_hp)
	await _wait_frames(MARKER_WAIT_FRAMES)
	await _toggle_lock_on()
	await _wait_frames(MARKER_WAIT_FRAMES)
	var finish_kind := int(hud.call("displayed_marker_kind"))
	var finish_text := String(hud.call("displayed_marker_text"))
	var finish_color: Color = hud.call("displayed_marker_color")
	print("[HUD marker downed robber] visible=%s kind=%d text='%s' color=%s" %
		[str(bool(hud.call("marker_is_visible"))), finish_kind,
		finish_text, finish_color])
	_assert("(6) 生存犯人 / 生存客 / ダウン犯人で警告を含む見た目が変わる",
		robber_kind == LockOn.TargetKind.LIVE_ROBBER
		and civilian_kind == LockOn.TargetKind.LIVE_CIVILIAN
		and finish_kind == LockOn.TargetKind.DOWNED_ROBBER
		and robber_text != civilian_text and robber_text != finish_text
		and civilian_text.contains("CIVILIAN")
		and not robber_color.is_equal_approx(civilian_color)
		and not robber_color.is_equal_approx(finish_color)
		and not civilian_color.is_equal_approx(finish_color))

	var camera := player.get_node(^"SpringArm3D/Camera3D") as Camera3D
	var camera_rig := player.get_node(^"SpringArm3D") as Node3D
	camera_rig.set_physics_process(false)
	var behind_position := camera.global_position \
		+ camera.global_transform.basis.z.normalized() * BEHIND_CAMERA_DISTANCE
	var marker_world_height := float(hud.get("marker_world_height"))
	downed_robber.global_position = behind_position - Vector3.UP * marker_world_height
	hud.call("_update_marker")
	var marker_world_position := downed_robber.global_position \
		+ Vector3.UP * marker_world_height
	var is_behind := camera.is_position_behind(marker_world_position)
	print("[HUD marker behind] world=%s behind=%s visible=%s" %
		[marker_world_position, str(is_behind),
		str(bool(hud.call("marker_is_visible")))])
	_assert("(8) 対象がカメラ背後にあるときマーカーを隠す",
		is_behind and not bool(hud.call("marker_is_visible")))
	await _toggle_lock_on()


func _test_ending_hides_hud(hud: CanvasLayer) -> void:
	var ending_card := ENDING_CARD_SCENE.instantiate() as EndingCard
	add_child(ending_card)
	GameDirector.advance_to(GameTypes.Act.EPILOGUE)
	print("[HUD ending] card_visible=%s hud_visible=%s paused=%s" %
		[str(ending_card.is_displayed()), str(hud.visible), str(get_tree().paused)])
	_assert("(9) エンディングカードが出ると HUD が隠れる",
		ending_card.is_displayed() and not hud.visible and get_tree().paused)
	get_tree().paused = false
	ending_card.queue_free()


func _on_test_hp_changed(current: float, maximum: float) -> void:
	_hp_signal_values.append(Vector2(current, maximum))


func _last_hp_signal() -> Vector2:
	return _hp_signal_values.back() if not _hp_signal_values.is_empty() else Vector2.ZERO
