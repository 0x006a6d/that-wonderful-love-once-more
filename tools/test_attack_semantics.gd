extends Node

## 攻撃入力セマンティクスの検証 (シーンハーネス)。
## 実行: godot --path . --headless res://tools/test_attack_semantics.tscn
##
## 4 ケースを実イベント (Input.parse_input_event, キー J) で駆動し、
## hitbox 有効化回数 (monitoring の立ち上がりエッジ) と melee_2 到達を数える。
##   (1) 単発押下       → melee_1 のみ、有効化 1 回、locomotion 復帰
##   (2) 窓内で再押下   → melee_2 連鎖、有効化 2 回
##   (3) 開始直後に再押下 → 連鎖しない、有効化 1 回
##   (4) 押しっぱなし   → 1 発のみ
## あわせて attack() の呼び出し回数も記録し、二重カウントの層を特定する。

const PLAYER := "res://actors/player/player.tscn"

var _pass: int = 0
var _fail: int = 0

var _player: Node3D = null
var _melee: Node = null
var _hitbox: Area3D = null

var _frames: int = 0
var _phase: int = 0
var _phase_start: int = 0
var _acts: int = 0
var _melee2_seen: bool = false
var _attack_calls: int = 0
var _prev_monitoring: bool = false
var _case_step: int = 0


func _ready() -> void:
	print("=== 攻撃入力セマンティクス 検証開始 ===")
	_player = (load(PLAYER) as PackedScene).instantiate() as Node3D
	add_child(_player)
	_melee = _player.get_node("PlayerMelee")
	_hitbox = _player.get_node("Model/MeleeHitbox") as Area3D
	# attack() の呼び出し回数を数える (combo_started は開始のみなので別カウント)。
	_melee.connect("combo_started", func() -> void: _attack_calls += 1)


func _press() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	Input.parse_input_event(ev)


func _release() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = false
	Input.parse_input_event(ev)


func _reset_counters() -> void:
	_acts = 0
	_melee2_seen = false
	_case_step = 0
	_phase_start = _frames


func _physics_process(_delta: float) -> void:
	_frames += 1

	# 計測: hitbox 有効化エッジと melee_2 到達。
	if _hitbox != null:
		if _hitbox.monitoring and not _prev_monitoring:
			_acts += 1
		_prev_monitoring = _hitbox.monitoring
	if _melee != null and str(_melee.get("_state")) == "melee_2":
		_melee2_seen = true

	if _frames < 20:
		return

	var local := _frames - _phase_start
	match _phase:
		0:
			_reset_counters()
			_phase = 1
		1:
			_run_case_1(local)
		2:
			_run_case_2(local)
		3:
			_run_case_3(local)
		4:
			_run_case_4(local)
		5:
			_finish()


## (1) 単発押下 → melee_1 のみ・有効化 1 回・locomotion 復帰。
func _run_case_1(local: int) -> void:
	if _case_step == 0:
		_press()
		_case_step = 1
	elif _case_step == 1 and local == 2:
		_release()
		_case_step = 2
	elif _case_step == 2 and local >= 90:
		var back := str(_melee.get("_state")) == "locomotion"
		_assert("(1) 単発: hitbox 有効化 1 回 (実測 %d)" % _acts, _acts == 1)
		_assert("(1) 単発: melee_2 に行かない (到達=%s)" % str(_melee2_seen), not _melee2_seen)
		_assert("(1) 単発: locomotion 復帰", back)
		_reset_counters()
		_phase = 2


## (2) melee_1 の窓内 (開始 14f 後 ≈ 50%) で再押下 → melee_2 連鎖・有効化 2 回。
func _run_case_2(local: int) -> void:
	if _case_step == 0:
		_press()
		_case_step = 1
	elif _case_step == 1 and local == 2:
		_release()
		_case_step = 2
	elif _case_step == 2 and local == 14:
		_press()
		_case_step = 3
	elif _case_step == 3 and local == 16:
		_release()
		_case_step = 4
	elif _case_step == 4 and local >= 120:
		_assert("(2) 窓内再押下: melee_2 へ連鎖 (到達=%s)" % str(_melee2_seen), _melee2_seen)
		_assert("(2) 窓内再押下: hitbox 有効化 2 回 (実測 %d)" % _acts, _acts == 2)
		_reset_counters()
		_phase = 3


## (3) 開始直後 (2f 後 ≈ 7%) の再押下 → 連鎖しない・有効化 1 回。
func _run_case_3(local: int) -> void:
	if _case_step == 0:
		_press()
		_case_step = 1
	elif _case_step == 1 and local == 2:
		_release()
		_press()
		_case_step = 2
	elif _case_step == 2 and local == 4:
		_release()
		_case_step = 3
	elif _case_step == 3 and local >= 120:
		_assert("(3) 開始直後の再押下: 連鎖しない (到達=%s)" % str(_melee2_seen), not _melee2_seen)
		_assert("(3) 開始直後の再押下: hitbox 有効化 1 回 (実測 %d)" % _acts, _acts == 1)
		_reset_counters()
		_phase = 4


## (4) 押しっぱなし (80f 押下維持) → 1 発のみ。
func _run_case_4(local: int) -> void:
	if _case_step == 0:
		_press()
		_case_step = 1
	elif _case_step == 1 and local == 80:
		_release()
		_case_step = 2
	elif _case_step == 2 and local >= 120:
		_assert("(4) 押しっぱなし: melee_2 に行かない (到達=%s)" % str(_melee2_seen), not _melee2_seen)
		_assert("(4) 押しっぱなし: hitbox 有効化 1 回 (実測 %d)" % _acts, _acts == 1)
		_phase = 5


func _finish() -> void:
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
