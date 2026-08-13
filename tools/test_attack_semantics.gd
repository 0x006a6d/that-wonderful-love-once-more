extends Node

## 攻撃入力セマンティクスの検証 (シーンハーネス、パンチ/キック 各3段仕様)。
## 実行: godot --path . --headless res://tools/test_attack_semantics.tscn
##
## 実イベント (Input.parse_input_event、パンチ=J / キック=K) で駆動し、
## hitbox 有効化回数 (monitoring の立ち上がりエッジ) と各段到達を数える。
##   (1) 単発押下         → melee_1 のみ、有効化 1 回、locomotion 復帰
##   (2) 窓内で再押下     → melee_2 まで、有効化 2 回、melee_3 に行かない
##   (3) 開始直後に再押下 → 連鎖しない、有効化 1 回
##   (4) 押しっぱなし     → 1 発のみ
##   (5) 3回押し+4回目    → melee_3 まで連鎖、有効化ちょうど 3 回 (4回目は無視)
##   (6) キック単発       → kick_1 のみ、有効化 1 回、locomotion 復帰
##   (7) キック3連+4回目  → kick_3 まで連鎖、有効化ちょうど 3 回
##   (8) 相互排他         → パンチ中のキック入力・キック中のパンチ入力は無視
## 窓内押下はタイミング固定ではなく再生割合 (ratio 0.5-0.7) を監視して送る。

const PLAYER := "res://actors/player/player.tscn"

var _pass: int = 0
var _fail: int = 0

var _player: Node3D = null
var _melee: Node = null
var _hitbox: Area3D = null
var _playback: AnimationNodeStateMachinePlayback = null

## 全体のハードタイムアウト（物理フレーム）。コンボが連鎖しない回帰が入っても
## _physics_process が無限に回らないようにする（ヘッドレス/CI のハング防止）。
const MAX_FRAMES := 4000

var _frames: int = 0
var _phase: int = 0
var _phase_start: int = 0
var _acts: int = 0
var _melee2_seen: bool = false
var _melee3_seen: bool = false
var _kick_any_seen: bool = false
var _kick2_seen: bool = false
var _kick3_seen: bool = false
var _melee_any_seen: bool = false
var _prev_monitoring: bool = false
var _case_step: int = 0


func _ready() -> void:
	print("=== 攻撃入力セマンティクス 検証開始 (3段仕様) ===")
	_player = (load(PLAYER) as PackedScene).instantiate() as Node3D
	add_child(_player)
	_melee = _player.get_node("PlayerMelee")
	_hitbox = _player.get_node("Model/MeleeHitbox") as Area3D


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


func _tap() -> void:
	_press()
	# release は次フレームでなくても直後で良い (押下エッジのみが意味を持つ)。
	_release.call_deferred()


func _tap_kick() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_K
	ev.pressed = true
	Input.parse_input_event(ev)
	var rel := InputEventKey.new()
	rel.physical_keycode = KEY_K
	rel.pressed = false
	Input.parse_input_event.call_deferred(rel)


## 指定ステートが現在再生中ならその再生割合、でなければ -1。
func _ratio(state_name: String) -> float:
	if _playback == null:
		var tree := _melee.get_node_or_null("AnimationTree") as AnimationTree
		if tree == null:
			return -1.0
		_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if str(_playback.get_current_node()) != state_name:
		return -1.0
	var length := _playback.get_current_length()
	if length <= 0.0:
		return -1.0
	return _playback.get_current_play_position() / length


func _reset_counters() -> void:
	_acts = 0
	_melee2_seen = false
	_melee3_seen = false
	_kick_any_seen = false
	_kick2_seen = false
	_kick3_seen = false
	_melee_any_seen = false
	_case_step = 0
	_phase_start = _frames


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames > MAX_FRAMES:
		_assert("全ケースが MAX_FRAMES 内に完了した (phase=%d)" % _phase, false)
		_finish()
		return

	if _hitbox != null:
		if _hitbox.monitoring and not _prev_monitoring:
			_acts += 1
		_prev_monitoring = _hitbox.monitoring
	var st := str(_melee.get("_state")) if _melee != null else ""
	if st == "melee_2":
		_melee2_seen = true
	elif st == "melee_3":
		_melee3_seen = true
	if st.begins_with("melee_"):
		_melee_any_seen = true
	elif st.begins_with("kick_"):
		_kick_any_seen = true
		if st == "kick_2":
			_kick2_seen = true
		elif st == "kick_3":
			_kick3_seen = true

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
			_run_case_5(local)
		6:
			_run_case_6(local)
		7:
			_run_case_7(local)
		8:
			_run_case_8(local)
		9:
			_finish()


## (1) 単発押下 → melee_1 のみ・有効化 1 回・locomotion 復帰。
func _run_case_1(local: int) -> void:
	if _case_step == 0:
		_tap()
		_case_step = 1
	elif _case_step == 1 and local >= 110:
		var back := str(_melee.get("_state")) == "locomotion"
		_assert("(1) 単発: hitbox 有効化 1 回 (実測 %d)" % _acts, _acts == 1)
		_assert("(1) 単発: melee_2/3 に行かない (2=%s 3=%s)" % [str(_melee2_seen), str(_melee3_seen)],
			not _melee2_seen and not _melee3_seen)
		_assert("(1) 単発: locomotion 復帰", back)
		_reset_counters()
		_phase = 2


## (2) melee_1 の窓内 (ratio 0.5-0.7) で再押下 → melee_2 まで・有効化 2 回。
func _run_case_2(local: int) -> void:
	if _case_step == 0:
		_tap()
		_case_step = 1
	elif _case_step == 1:
		var r := _ratio("melee_1")
		if r >= 0.5 and r <= 0.7:
			_tap()
			_case_step = 2
	elif _case_step == 2 and local >= 160:
		_assert("(2) 窓内再押下: melee_2 へ連鎖 (到達=%s)" % str(_melee2_seen), _melee2_seen)
		_assert("(2) 窓内再押下: melee_3 に行かない (到達=%s)" % str(_melee3_seen), not _melee3_seen)
		_assert("(2) 窓内再押下: hitbox 有効化 2 回 (実測 %d)" % _acts, _acts == 2)
		_reset_counters()
		_phase = 3


## (3) 開始直後 (2f 後 ≈ ratio 0.05) の再押下 → 連鎖しない・有効化 1 回。
func _run_case_3(local: int) -> void:
	if _case_step == 0:
		_tap()
		_case_step = 1
	elif _case_step == 1 and local == 2:
		_tap()
		_case_step = 2
	elif _case_step == 2 and local >= 120:
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
		_assert("(4) 押しっぱなし: 連鎖しない (2=%s 3=%s)" % [str(_melee2_seen), str(_melee3_seen)],
			not _melee2_seen and not _melee3_seen)
		_assert("(4) 押しっぱなし: hitbox 有効化 1 回 (実測 %d)" % _acts, _acts == 1)
		_reset_counters()
		_phase = 5


## (5) 各段の窓内で計3回押し + melee_3 中に4回目 → 3段到達・有効化ちょうど3回。
func _run_case_5(local: int) -> void:
	if _case_step == 0:
		_tap()
		_case_step = 1
	elif _case_step == 1:
		var r1 := _ratio("melee_1")
		if r1 >= 0.5 and r1 <= 0.7:
			_tap()
			_case_step = 2
	elif _case_step == 2:
		var r2 := _ratio("melee_2")
		if r2 >= 0.5 and r2 <= 0.7:
			_tap()
			_case_step = 3
	elif _case_step == 3:
		if _ratio("melee_3") >= 0.0:
			_tap()  # 4回目 (melee_3 中) は無視されるはず
			_case_step = 4
	elif _case_step == 4 and local >= 260:
		var back := str(_melee.get("_state")) == "locomotion"
		_assert("(5) 3連鎖: melee_3 まで到達 (到達=%s)" % str(_melee3_seen), _melee3_seen)
		_assert("(5) 3連鎖: hitbox 有効化ちょうど 3 回 (実測 %d)" % _acts, _acts == 3)
		_assert("(5) 3連鎖: 4回目の押下で追加攻撃が出ず locomotion 復帰", back)
		_reset_counters()
		_phase = 6


## (6) キック単発 → kick_1 のみ・有効化 1 回・locomotion 復帰。
func _run_case_6(local: int) -> void:
	if _case_step == 0:
		_tap_kick()
		_case_step = 1
	elif _case_step == 1 and local >= 120:
		var back := str(_melee.get("_state")) == "locomotion"
		_assert("(6) キック単発: hitbox 有効化 1 回 (実測 %d)" % _acts, _acts == 1)
		_assert("(6) キック単発: kick_2/3 に行かない (2=%s 3=%s)" % [str(_kick2_seen), str(_kick3_seen)],
			not _kick2_seen and not _kick3_seen)
		_assert("(6) キック単発: パンチ系ステートに入らない", not _melee_any_seen)
		_assert("(6) キック単発: locomotion 復帰", back)
		_reset_counters()
		_phase = 7


## (7) キック3連 (デバウンス超え間隔で3回) + kick_3 中に4回目 → 3段・有効化3回。
func _run_case_7(local: int) -> void:
	if _case_step == 0:
		_tap_kick()
		_case_step = 1
	elif _case_step == 1 and local == 8:
		_tap_kick()
		_case_step = 2
	elif _case_step == 2 and local == 16:
		_tap_kick()
		_case_step = 3
	elif _case_step == 3:
		if _ratio("kick_3") >= 0.0:
			_tap_kick()  # 4回目 (kick_3 中) は無視されるはず
			_case_step = 4
	elif _case_step == 4 and local >= 300:
		var back := str(_melee.get("_state")) == "locomotion"
		_assert("(7) キック3連鎖: kick_3 まで到達 (到達=%s)" % str(_kick3_seen), _kick3_seen)
		_assert("(7) キック3連鎖: hitbox 有効化ちょうど 3 回 (実測 %d)" % _acts, _acts == 3)
		_assert("(7) キック3連鎖: 4回目は無視され locomotion 復帰", back)
		_reset_counters()
		_phase = 8


## (8) 相互排他: パンチ中のキック入力は無視、キック中のパンチ入力は無視。
func _run_case_8(local: int) -> void:
	if _case_step == 0:
		_tap()  # パンチ開始
		_case_step = 1
	elif _case_step == 1:
		var r := _ratio("melee_1")
		if r >= 0.3 and r <= 0.7:
			_tap_kick()  # パンチ中のキック → 無視されるはず
			_case_step = 2
	elif _case_step == 2 and local >= 120:
		_assert("(8a) パンチ中のキック入力: キック系に入らない (kick=%s)" % str(_kick_any_seen),
			not _kick_any_seen)
		_assert("(8a) パンチ中のキック入力: 有効化 1 回のみ (実測 %d)" % _acts, _acts == 1)
		# 後半: キック中のパンチ入力。
		_reset_counters()
		_tap_kick()
		_case_step = 3
	elif _case_step == 3:
		var r2 := _ratio("kick_1")
		if r2 >= 0.3 and r2 <= 0.7:
			_tap()  # キック中のパンチ → 無視されるはず
			_case_step = 4
	elif _case_step == 4 and local >= 260:
		var back := str(_melee.get("_state")) == "locomotion"
		_assert("(8b) キック中のパンチ入力: パンチ系に入らない (melee=%s)" % str(_melee_any_seen),
			not _melee_any_seen)
		_assert("(8b) キック中のパンチ入力: 有効化 1 回のみ (実測 %d)" % _acts, _acts == 1)
		_assert("(8b) locomotion 復帰", back)
		_phase = 9


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
