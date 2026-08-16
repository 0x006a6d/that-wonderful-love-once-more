extends Node

## プレイヤーのダウンと自力復帰の検証（シーンハーネス版）。
##   godot --path . --headless res://tools/test_player_down.tscn
##
## 経緯: 犯人に殴られ続けると操作不能になる、という実機報告があった。原因は
## HP0 でのダウン（復帰処理が無く、シーン再読込まで戻らない）。仕様を
## 「数秒で自力復帰。失うのは時間だけ」と決めたため、その挙動を固定する。
##
## 検証項目:
##   (1) 犯人の攻撃を受け続けると HP0 でダウンする
##   (2) ダウン中は attack アクション（キー J）が通らない
##   (3) down_duration + stand_up_time 後に自力で立ち上がる
##   (4) 立ち上がり時に HP が全快し、傾けたモデルが元へ戻る
##   (5) 復帰後は attack アクションが再び通る
##   (6) down ステートで非ループクリップが再生され、VRM ボーンが動く
##   (7) 倒れ込みが down_fall_time で終わる
##   (8) 同じクリップの逆再生が stand_up_time で終わり、端点が逆順になる
##
## 反撃はしない。プレイヤーはノックバックされた分だけ元の位置へ戻し、
## 殴られ続ける状況を維持する。

const STAGE := "res://levels/test_stage.tscn"
const MAX_FRAMES := 2600
## 入力が通ったかを見る観測窓（フレーム）。
const INPUT_WINDOW := 20
const DOWN_ANIMATION: StringName = &"player/down"
const POSE_MIN_ANGLE_DEG: float = 1.0
const ENDPOINT_TOLERANCE_DEG: float = 8.0
const DURATION_TOLERANCE: float = 0.08

var _pass: int = 0
var _fail: int = 0

var _stage: Node3D = null
var _player: Node3D = null
var _model: Node3D = null
var _health: Health = null
var _melee: Node = null
var _robber: Node3D = null
var _skeleton: Skeleton3D = null
var _playback: AnimationNodeStateMachinePlayback = null
var _down_animation: Animation = null
var _animated_bone: int = -1

var _hold: Vector3 = Vector3.ZERO
var _frames: int = 0
var _last_hp: float = -1.0
var _hits: int = 0
var _down_frame: int = -1
var _recover_frame: int = -1
var _hit_frames: Array[int] = []

var _attack_while_down: bool = false
var _attack_after_recover: bool = false
var _hp_on_recover: float = -1.0
var _tilt_on_recover: float = 999.0
var _down_test_frame: int = -1
var _recover_test_frame: int = -1
## 秒数に 0 を設定した場合でも復帰するか（インスペクタで踏める永久ロックの検出）。
var _zero_test_frame: int = -1
var _zero_recovered: bool = false
## 設定値は開始時に控える（後半で 0 に書き換えるため、評価時に読むとずれる）。
var _configured_down: float = 0.0
var _configured_stand: float = 0.0
var _configured_fall: float = 0.0

var _down_state_entered: bool = false
var _down_position_advanced: bool = false
var _down_last_position: float = -1.0
var _fall_end_frame: int = -1
var _fall_max_angle_deg: float = 0.0
var _fall_start_pose: Quaternion = Quaternion.IDENTITY
var _fall_end_pose: Quaternion = Quaternion.IDENTITY
var _stand_start_frame: int = -1
var _stand_max_angle_deg: float = 0.0
var _stand_start_pose: Quaternion = Quaternion.IDENTITY
var _stand_end_pose: Quaternion = Quaternion.IDENTITY
var _stand_uses_backward_clip: bool = false


func _ready() -> void:
	print("=== プレイヤーのダウン/復帰 検証開始 ===")
	RunState.reset()
	GameDirector.reset()
	GameDirector.notify_prologue_finished()

	var packed := load(STAGE) as PackedScene
	if packed == null:
		_fatal("test_stage load 失敗")
		return
	_stage = packed.instantiate() as Node3D
	add_child(_stage)
	_player = _stage.get_node_or_null("Player") as Node3D
	_robber = _stage.get_node_or_null("Robber1") as Node3D
	if _player == null or _robber == null:
		_fatal("Player / Robber1 が見つからない")
		return
	_model = _player.get_node_or_null("Model") as Node3D
	_health = _player.get_node_or_null("Health") as Health
	_melee = _player.get_node_or_null("PlayerMelee")
	if _model == null or _health == null or _melee == null:
		_fatal("Model / Health / PlayerMelee が見つからない")
		return
	_skeleton = _find_skeleton(_model)
	var animation_player: AnimationPlayer = _find_animation_player(_model)
	var tree: AnimationTree = _melee.get_node_or_null(^"AnimationTree") as AnimationTree
	if _skeleton == null or animation_player == null or tree == null \
			or not animation_player.has_animation(DOWN_ANIMATION):
		_fatal("down クリップまたは AnimationTree の初期化に失敗")
		return
	_down_animation = animation_player.get_animation(DOWN_ANIMATION)
	_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_animated_bone = _animated_bone_index()
	if _playback == null or _animated_bone < 0:
		_fatal("down 再生位置または検証対象ボーンを取得できない")
		return
	print("[clip] name=%s length=%.3fs tracks=%d loop_mode=%d" % [
		DOWN_ANIMATION, _down_animation.length, _down_animation.get_track_count(),
		_down_animation.loop_mode
	])
	_stand_uses_backward_clip = _inspect_stand_up_node(tree)
	_configured_down = float(_player.get("down_duration"))
	_configured_stand = float(_player.get("stand_up_time"))
	_configured_fall = float(_player.get("down_fall_time"))
	_player.connect("player_recovered", _on_recovered)


func _on_recovered() -> void:
	if _recover_frame >= 0:
		return
	_recover_frame = _frames
	_hp_on_recover = _health.current_hp()
	_tilt_on_recover = absf(rad_to_deg(_model.rotation.x))
	_stand_end_pose = _skeleton.get_bone_pose_rotation(_animated_bone)
	print("[recover] frame=%d (%.2fs)  hp=%.1f  傾き=%.2f度" %
		[_frames, _frames / 60.0, _hp_on_recover, _tilt_on_recover])
	_press_attack()
	_recover_test_frame = _frames


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames == 4:
		# 犯人の正面 2m に立たせ、そこから動かさない（反撃しない）。
		var forward := -_robber.global_transform.basis.z
		_hold = _robber.global_position + forward * 2.0
		_hold.y = 0.2
		_last_hp = _health.current_hp()
	if _frames < 4:
		return

	_player.global_position = _hold

	var hp := _health.current_hp()
	if hp < _last_hp:
		_hits += 1
		_hit_frames.append(_frames)
		print("[hit %d] frame=%d (%.2fs) hp %.1f -> %.1f" %
			[_hits, _frames, _frames / 60.0, _last_hp, hp])
	_last_hp = hp

	# ダウンの瞬間: 攻撃入力が通らないことを確認する。
	if _player.call("is_downed") and _down_frame < 0:
		_down_frame = _frames
		print("[down] frame=%d (%.2fs)  hits=%d" % [_frames, _frames / 60.0, _hits])
		_press_attack()
		_down_test_frame = _frames

	if _down_frame > 0 and _recover_frame < 0:
		_sample_down_animation()

	if _down_test_frame > 0 and _frames <= _down_test_frame + INPUT_WINDOW:
		if bool(_melee.call("is_attacking")):
			_attack_while_down = true

	if _recover_test_frame > 0 and _zero_test_frame < 0:
		if bool(_melee.call("is_attacking")):
			_attack_after_recover = true
		if _frames > _recover_test_frame + INPUT_WINDOW:
			# 秒数を 0 に設定した状態でもう一度倒す。以前はここで
			# どのタイマー分岐にも入らず、倒れたまま戻らなくなっていた。
			_player.set("down_duration", 0.0)
			_player.set("stand_up_time", 0.0)
			_health.take_hit(_health.max_hp)
			_zero_test_frame = _frames
			print("[zero] down_duration=0 / stand_up_time=0 で再ダウンさせた frame=%d" % _frames)
		return

	if _zero_test_frame > 0:
		if not bool(_player.call("is_downed")):
			_zero_recovered = true
			_evaluate()
			return
		if _frames > _zero_test_frame + 60:
			print("[zero] 60 フレーム経っても復帰しない")
			_evaluate()
			return
		return

	if _frames >= MAX_FRAMES:
		print("[timeout] frames=%d downed=%s" % [_frames, str(_player.call("is_downed"))])
		_evaluate()


## attack アクションを入力イベントとして流す（入力マップ経由の経路を通す）。
func _press_attack() -> void:
	var press := InputEventKey.new()
	press.physical_keycode = KEY_J
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_J
	release.pressed = false
	Input.parse_input_event(release)


func _evaluate() -> void:
	var intervals := PackedStringArray()
	for i in range(1, _hit_frames.size()):
		intervals.append("%.2f" % ((_hit_frames[i] - _hit_frames[i - 1]) / 60.0))
	print("[result] 被弾=%d 回  被弾間隔(秒)=[%s]" % [_hits, ", ".join(intervals)])
	var down_to_recover := -1.0
	if _down_frame > 0 and _recover_frame > 0:
		down_to_recover = (_recover_frame - _down_frame) / 60.0
	print("[result] ダウン fr=%d 復帰 fr=%d  倒れていた時間=%.2f 秒（設定値 %.2f + %.2f）" %
		[_down_frame, _recover_frame, down_to_recover, _configured_down, _configured_stand])
	var fall_elapsed: float = -1.0
	if _fall_end_frame > 0:
		fall_elapsed = float(_fall_end_frame - _down_frame) / float(Engine.physics_ticks_per_second)
	var stand_elapsed: float = -1.0
	if _stand_start_frame > 0 and _recover_frame > 0:
		stand_elapsed = float(_recover_frame - _stand_start_frame) \
			/ float(Engine.physics_ticks_per_second)
	var fallen_to_stand_start_deg: float = rad_to_deg(_fall_end_pose.angle_to(_stand_start_pose))
	var standing_end_to_start_deg: float = rad_to_deg(_stand_end_pose.angle_to(_fall_start_pose))
	print("[retarget] bone=%s max_angle_delta=%.3fdeg" % [
		_skeleton.get_bone_name(_animated_bone), _fall_max_angle_deg
	])
	print("[fall] actual=%.3fs expected=%.3fs end_frame=%d" % [
		fall_elapsed, _configured_fall, _fall_end_frame
	])
	print(("[stand_up] actual=%.3fs expected=%.3fs play_mode=BACKWARD pose_delta=%.3fdeg " \
			+ "fallen_endpoint_error=%.3fdeg standing_endpoint_error=%.3fdeg") % [
		stand_elapsed, _configured_stand, _stand_max_angle_deg,
		fallen_to_stand_start_deg, standing_end_to_start_deg
	])

	_assert("殴られ続けると HP0 でダウンする", _down_frame > 0)
	_assert("ダウン中は attack 入力が通らない", not _attack_while_down)
	_assert("自力で立ち上がる（復帰シグナルが出る）", _recover_frame > 0)
	var expected := _configured_down + _configured_stand
	_assert("倒れていた時間が設定値どおり（±0.2秒）",
		down_to_recover > 0.0 and absf(down_to_recover - expected) <= 0.2)
	_assert("復帰時に HP が全快している", is_equal_approx(_hp_on_recover, _health.max_hp))
	_assert("復帰時にモデルの傾きが戻っている", _tilt_on_recover < 1.0)
	_assert("復帰後は attack 入力が通る", _attack_after_recover)
	_assert("down_duration / stand_up_time が 0 でも復帰する", _zero_recovered)
	_assert("down ステートに入り非ループクリップが再生される",
		_down_state_entered and _down_position_advanced
		and _down_animation.loop_mode == Animation.LOOP_NONE)
	_assert("down 再生中に VRM ボーンの姿勢が変化する",
		_fall_max_angle_deg >= POSE_MIN_ANGLE_DEG)
	_assert("倒れ込みが down_fall_time で終わる（±%.2f秒）" % DURATION_TOLERANCE,
		fall_elapsed > 0.0 and absf(fall_elapsed - _configured_fall) <= DURATION_TOLERANCE)
	_assert("立ち上がりが同じクリップの逆再生で stand_up_time に終わる",
		_stand_uses_backward_clip and _stand_max_angle_deg >= POSE_MIN_ANGLE_DEG
		and stand_elapsed > 0.0
		and absf(stand_elapsed - _configured_stand) <= DURATION_TOLERANCE
		and fallen_to_stand_start_deg <= ENDPOINT_TOLERANCE_DEG
		and standing_end_to_start_deg <= ENDPOINT_TOLERANCE_DEG)

	print("=== 結果: PASS=%d FAIL=%d ===" % [_pass, _fail])
	print("ALL PASS" if _fail == 0 else "HAS FAILURE")
	get_tree().quit(0 if _fail == 0 else 1)


func _assert(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("[PASS] %s" % label)
	else:
		_fail += 1
		print("[FAIL] %s" % label)


func _sample_down_animation() -> void:
	var state: StringName = StringName(_playback.get_current_node())
	var position: float = _playback.get_current_play_position()
	var pose: Quaternion = _skeleton.get_bone_pose_rotation(_animated_bone)
	if state == &"down":
		if not _down_state_entered:
			_down_state_entered = true
			_fall_start_pose = pose
		if _down_last_position >= 0.0 and position > _down_last_position + 0.0001:
			_down_position_advanced = true
		_down_last_position = position
		_fall_max_angle_deg = maxf(_fall_max_angle_deg,
			rad_to_deg(_fall_start_pose.angle_to(pose)))
		var frame_margin: float = _down_animation.length \
			/ maxf(_configured_fall * float(Engine.physics_ticks_per_second), 1.0) * 1.25
		if _fall_end_frame < 0 and position >= _down_animation.length - frame_margin:
			_fall_end_frame = _frames
			_fall_end_pose = pose
	elif state == &"stand_up":
		if _stand_start_frame < 0:
			_stand_start_frame = _frames
			_stand_start_pose = pose
		_stand_max_angle_deg = maxf(_stand_max_angle_deg,
			rad_to_deg(_stand_start_pose.angle_to(pose)))


func _inspect_stand_up_node(tree: AnimationTree) -> bool:
	var state_machine: AnimationNodeStateMachine = tree.tree_root as AnimationNodeStateMachine
	if state_machine == null:
		return false
	var stand_tree: AnimationNodeBlendTree = state_machine.get_node(&"stand_up") as AnimationNodeBlendTree
	if stand_tree == null:
		return false
	var clip: AnimationNodeAnimation = stand_tree.get_node(&"clip") as AnimationNodeAnimation
	return clip != null and clip.animation == DOWN_ANIMATION \
		and clip.play_mode == AnimationNodeAnimation.PLAY_MODE_BACKWARD


func _animated_bone_index() -> int:
	var candidates: Array[StringName] = [&"Chest", &"Spine", &"LeftUpperArm", &"RightUpperArm"]
	for bone_name: StringName in candidates:
		var index: int = _skeleton.find_bone(bone_name)
		if index >= 0:
			return index
	return -1


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


func _fatal(msg: String) -> void:
	print("[FATAL] %s" % msg)
	get_tree().quit(1)
