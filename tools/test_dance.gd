extends Node

## 回復ダンス（interact 長押し）のシーンハーネス検証。
## 実行: godot --path . --headless res://tools/test_dance.tscn

const STAGE: String = "res://levels/test_stage.tscn"
const HEAL_SETUP_DAMAGE: float = 60.0
const HEAL_MEASURE_FRAMES: int = 60
const HEAL_TOLERANCE: float = 0.25
const STOP_OBSERVE_FRAMES: int = 30
const POSE_SETTLE_FRAMES: int = 30
const POSE_SAMPLE_FRAMES: int = 12
const POSE_MIN_ANGLE_DEG: float = 0.05
const DANCE_MAX_HORIZONTAL_DISTANCE: float = 0.005
const HIT_DAMAGE: float = 20.0
const HIT_KNOCKBACK: float = 5.0
const HIT_OBSERVE_FRAMES: int = 8
const HIT_MIN_HORIZONTAL_DISTANCE: float = 0.01
const STATE_WAIT_FRAMES: int = 60
const HURT_LOCK_WAIT_FRAMES: int = 30
const STOP_TEST_DAMAGE: float = 5.0
const DANCE_ANIMATION: StringName = &"player/dance"

var _pass: int = 0
var _fail: int = 0

var _stage: Node3D = null
var _player: Node3D = null
var _model: Node3D = null
var _melee: Node = null
var _health: Health = null
var _hurtbox: Hurtbox = null
var _skeleton: Skeleton3D = null
var _playback: AnimationNodeStateMachinePlayback = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 回復ダンス 検証開始 ===")
	RunState.reset()
	GameDirector.reset()
	GameDirector.notify_prologue_finished()
	if not await _setup():
		_fatal("テスト舞台またはプレイヤーの初期化に失敗")
		return

	# 回復速度を測れるように HP を先に減らす。Health への直接ダメージなので
	# 被弾ロックは発生せず、ダンス開始条件だけを独立して検証できる。
	_health.take_hit(HEAL_SETUP_DAMAGE)
	_press_key(KEY_E)
	var entered_dance: bool = await _wait_for_state(&"dance")
	_assert("(1) interact を押すと dance ステートに入る",
		entered_dance and bool(_player.call("is_dancing")))

	var move_start: Vector3 = _player.global_position
	var heal_start: float = _health.current_hp()
	await _wait_frames(HEAL_MEASURE_FRAMES)
	var elapsed: float = float(HEAL_MEASURE_FRAMES) / float(Engine.physics_ticks_per_second)
	var healed: float = _health.current_hp() - heal_start
	var expected_heal: float = float(_player.get("dance_heal_per_second")) * elapsed
	var heal_error: float = absf(healed - expected_heal)
	print("[heal] elapsed=%.3fs actual=%.3f expected=%.3f error=%.3f" %
		[elapsed, healed, expected_heal, heal_error])
	_assert("(2) 長押し中の回復速度が dance_heal_per_second と一致する",
		heal_error <= HEAL_TOLERANCE)

	var horizontal_distance: float = _horizontal_distance(move_start, _player.global_position)
	print("[stationary] elapsed=%.3fs horizontal_distance=%.6fm threshold=%.6fm" %
		[elapsed, horizontal_distance, DANCE_MAX_HORIZONTAL_DISTANCE])
	_assert("(10) ダンス中に水平移動しない",
		horizontal_distance <= DANCE_MAX_HORIZONTAL_DISTANCE)

	await _wait_frames(POSE_SETTLE_FRAMES)
	var bone_index: int = _animated_bone_index()
	var pose_changed: bool = false
	var pose_angle_deg: float = 0.0
	var bone_name: String = "(none)"
	if bone_index >= 0:
		bone_name = _skeleton.get_bone_name(bone_index)
		var pose_before: Quaternion = _skeleton.get_bone_pose_rotation(bone_index)
		await _wait_frames(POSE_SAMPLE_FRAMES)
		var pose_after: Quaternion = _skeleton.get_bone_pose_rotation(bone_index)
		pose_angle_deg = rad_to_deg(pose_before.angle_to(pose_after))
		pose_changed = pose_angle_deg >= POSE_MIN_ANGLE_DEG
	print("[retarget] bone=%s sample_frames=%d angle_delta=%.4fdeg threshold=%.4fdeg" %
		[bone_name, POSE_SAMPLE_FRAMES, pose_angle_deg, POSE_MIN_ANGLE_DEG])
	_assert("(11) dance 再生中に VRM ボーンの姿勢が変化する", pose_changed)

	# 上限より大きな通常回復を通してもクランプされることを、ダンス継続中に確認する。
	_health.heal(_health.max_hp)
	await _wait_frames(2)
	print("[cap] hp=%.3f max_hp=%.3f" % [_health.current_hp(), _health.max_hp])
	_assert("(3) max_hp を超えて回復しない", _health.current_hp() <= _health.max_hp
		and is_equal_approx(_health.current_hp(), _health.max_hp))

	_release_key(KEY_E)
	var released_to_locomotion: bool = await _wait_for_state(&"locomotion")
	_health.take_hit(STOP_TEST_DAMAGE)
	var hp_after_release: float = _health.current_hp()
	await _wait_frames(STOP_OBSERVE_FRAMES)
	var stopped_heal: float = _health.current_hp() - hp_after_release
	print("[release] observe=%.3fs healed_after_release=%.3f state=%s" %
		[float(STOP_OBSERVE_FRAMES) / float(Engine.physics_ticks_per_second), stopped_heal,
		String(_playback.get_current_node())])
	_assert("(4) interact を離すと locomotion に戻り回復が止まる",
		released_to_locomotion and is_zero_approx(stopped_heal))

	_press_key(KEY_E)
	await _wait_for_state(&"dance")
	_press_key(KEY_W)
	var move_canceled: bool = await _wait_for_state(&"locomotion")
	_release_key(KEY_W)
	_release_key(KEY_E)
	_assert("(5) 移動入力でダンスがキャンセルされる", move_canceled)

	_press_key(KEY_E)
	await _wait_for_state(&"dance")
	_tap_key(KEY_J)
	var attack_canceled: bool = await _wait_for_state(&"locomotion")
	_release_key(KEY_E)
	_assert("(6) 攻撃入力でダンスがキャンセルされる", attack_canceled
		and not bool(_melee.call("is_attacking")))

	_press_key(KEY_E)
	await _wait_for_state(&"dance")
	_tap_key(KEY_SPACE)
	var dodge_canceled: bool = await _wait_for_state(&"locomotion")
	_release_key(KEY_E)
	_assert("(7) 回避入力でダンスがキャンセルされる", dodge_canceled)

	await _wait_frames(2)
	_press_key(KEY_E)
	await _wait_for_state(&"dance")
	var hp_before_hit: float = _health.current_hp()
	var hit_start: Vector3 = _player.global_position
	var hit_accepted: bool = _deliver_hit()
	var hp_immediately_after_hit: float = _health.current_hp()
	await _wait_frames(HIT_OBSERVE_FRAMES)
	var hp_after_hit_observe: float = _health.current_hp()
	var knockback_distance: float = _horizontal_distance(hit_start, _player.global_position)
	var damage_taken: float = hp_before_hit - hp_immediately_after_hit
	var post_hit_heal: float = hp_after_hit_observe - hp_immediately_after_hit
	print("[hit] damage=%.3f hp_after=%.3f post_hit_heal=%.3f knockback_distance=%.6fm" %
		[damage_taken, hp_immediately_after_hit, post_hit_heal, knockback_distance])
	_assert("(8) 被弾で停止し、HP が減り、ノックバックし、回復と同時進行しない",
		hit_accepted and not bool(_player.call("is_dancing"))
		and is_equal_approx(damage_taken, HIT_DAMAGE) and is_zero_approx(post_hit_heal)
		and knockback_distance >= HIT_MIN_HORIZONTAL_DISTANCE)
	_release_key(KEY_E)

	# 被弾ロックが切れてからダウンさせ、ダウン中の新規開始を試す。
	await _wait_frames(HURT_LOCK_WAIT_FRAMES)
	_health.take_hit(_health.current_hp())
	await get_tree().physics_frame
	_press_key(KEY_E)
	await _wait_frames(2)
	var down_start_blocked: bool = bool(_player.call("is_downed")) \
		and not bool(_player.call("is_dancing"))
	_release_key(KEY_E)
	_assert("(9) ダウン中はダンスを始められない", down_start_blocked)

	_finish()


func _setup() -> bool:
	var packed: PackedScene = load(STAGE) as PackedScene
	if packed == null:
		return false
	_stage = packed.instantiate() as Node3D
	add_child(_stage)
	_player = _stage.get_node_or_null(^"Player") as Node3D
	if _player == null:
		return false
	# AI の偶発攻撃を排除し、回復ダンスだけを観測する。
	var robber: Node = _stage.get_node_or_null(^"Robber1")
	if robber != null:
		robber.set_process(false)
		robber.set_physics_process(false)
	_model = _player.get_node_or_null(^"Model") as Node3D
	_melee = _player.get_node_or_null(^"PlayerMelee")
	_health = _player.get_node_or_null(^"Health") as Health
	_hurtbox = _player.get_node_or_null(^"Hurtbox") as Hurtbox
	if _model == null or _melee == null or _health == null or _hurtbox == null:
		return false
	_skeleton = _find_skeleton(_model)
	var tree: AnimationTree = _melee.get_node_or_null(^"AnimationTree") as AnimationTree
	if _skeleton == null or tree == null:
		return false
	var animation_player: AnimationPlayer = _find_animation_player(_model)
	if animation_player == null or not animation_player.has_animation(DANCE_ANIMATION):
		return false
	var dance_animation: Animation = animation_player.get_animation(DANCE_ANIMATION)
	print("[clip] name=%s length=%.3fs tracks=%d" % [
		DANCE_ANIMATION, dance_animation.length, dance_animation.get_track_count()
	])
	_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	await _wait_frames(5)
	return _playback != null


func _deliver_hit() -> bool:
	var attacker := Node3D.new()
	attacker.name = "DanceTestAttacker"
	_stage.add_child(attacker)
	attacker.global_position = _player.global_position + Vector3(0.0, 0.0, -1.0)
	var hitbox := Hitbox.new()
	hitbox.name = "Hitbox"
	hitbox.source_body_path = ^".."
	attacker.add_child(hitbox)
	hitbox.configure(HIT_DAMAGE, HIT_KNOCKBACK, false)
	var accepted: bool = _hurtbox.receive_hit(hitbox)
	return accepted


func _animated_bone_index() -> int:
	var candidates: Array[StringName] = [&"LeftUpperArm", &"RightUpperArm", &"Chest", &"Spine"]
	for bone_name: StringName in candidates:
		var index: int = _skeleton.find_bone(bone_name)
		if index >= 0:
			return index
	return -1


func _wait_for_state(state: StringName) -> bool:
	for _frame: int in range(STATE_WAIT_FRAMES):
		if _playback != null and StringName(_playback.get_current_node()) == state:
			return true
		await get_tree().physics_frame
	return false


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await get_tree().physics_frame


func _press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)


func _release_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = false
	Input.parse_input_event(event)


func _tap_key(keycode: Key) -> void:
	_press_key(keycode)
	_release_key(keycode)


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _assert(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[PASS] %s" % label)
	else:
		_fail += 1
		print("[FAIL] %s" % label)


func _finish() -> void:
	print("=== 結果: PASS=%d FAIL=%d ===" % [_pass, _fail])
	print("ALL PASS" if _fail == 0 else "HAS FAILURE")
	get_tree().quit(0 if _fail == 0 else 1)


func _fatal(message: String) -> void:
	print("[FATAL] %s" % message)
	get_tree().quit(1)
