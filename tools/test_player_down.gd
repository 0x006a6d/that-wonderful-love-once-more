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
##
## 反撃はしない。プレイヤーはノックバックされた分だけ元の位置へ戻し、
## 殴られ続ける状況を維持する。

const STAGE := "res://levels/test_stage.tscn"
const MAX_FRAMES := 2600
## 入力が通ったかを見る観測窓（フレーム）。
const INPUT_WINDOW := 20

var _pass: int = 0
var _fail: int = 0

var _stage: Node3D = null
var _player: Node3D = null
var _model: Node3D = null
var _health: Health = null
var _melee: Node = null
var _robber: Node3D = null

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
	_configured_down = float(_player.get("down_duration"))
	_configured_stand = float(_player.get("stand_up_time"))
	_player.connect("player_recovered", _on_recovered)


func _on_recovered() -> void:
	if _recover_frame >= 0:
		return
	_recover_frame = _frames
	_hp_on_recover = _health.current_hp()
	_tilt_on_recover = absf(rad_to_deg(_model.rotation.x))
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


func _fatal(msg: String) -> void:
	print("[FATAL] %s" % msg)
	get_tree().quit(1)
