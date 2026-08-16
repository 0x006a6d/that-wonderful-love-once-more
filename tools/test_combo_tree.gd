extends Node

## コンボ木を実際の PlayerMelee.attack() / kick() と AnimationTree 再生で検証する。
## 実行: godot --path . --headless res://tools/test_combo_tree.tscn

const PLAYER: PackedScene = preload("res://actors/player/player.tscn")
const ComboTree := preload("res://actors/player/combo_tree.gd")

const P: StringName = ComboTree.INPUT_PUNCH
const K: StringName = ComboTree.INPUT_KICK
const JAB: StringName = ComboTree.TECHNIQUE_JAB
const STRAIGHT: StringName = ComboTree.TECHNIQUE_STRAIGHT
const HOOK: StringName = ComboTree.TECHNIQUE_HOOK
const KNEE: StringName = ComboTree.TECHNIQUE_KNEE
const MIDDLE: StringName = ComboTree.TECHNIQUE_MIDDLE
const HIGH: StringName = ComboTree.TECHNIQUE_HIGH

const WINDOW_RATIO: float = 0.60
const LATE_RATIO_MARGIN: float = 0.02
const MAX_WAIT_FRAMES: int = 240

var _pass: int = 0
var _fail: int = 0
var _player: Node3D = null
var _melee: Node = null
var _playback: AnimationNodeStateMachinePlayback = null
var _played: Array[StringName] = []
var _expected_stage_count: int = 0
var _premature_finish: bool = false
var _stage_order_ok: bool = true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== コンボ木 検証開始 ===")
	var route4_result: Dictionary = {}

	await _assert_sequence("punch3", [P, P, P], [JAB, STRAIGHT, HOOK])
	await _assert_sequence("kick3", [K, K, K], [KNEE, MIDDLE, HIGH])
	await _assert_sequence("route1", [P, K, P, P], [JAB, KNEE, JAB, STRAIGHT])
	await _assert_sequence("route2", [P, K, K, P], [JAB, KNEE, MIDDLE, HOOK])
	await _assert_sequence("route3", [P, P, K, P, K], [JAB, STRAIGHT, KNEE, HOOK, HIGH])
	route4_result = await _assert_sequence("route4", [K, P, P, P, K, P, K],
		[KNEE, HOOK, STRAIGHT, JAB, KNEE, HOOK, HIGH])

	await _assert_sequence("outside_pppp", [P, P, P, P], [JAB, STRAIGHT, HOOK])
	await _assert_sequence("outside_pkpk", [P, K, P, K], [JAB, KNEE, JAB])

	var stopped_ok: bool = true
	stopped_ok = await _check_stopped("stop_punch3", [P, P], [JAB, STRAIGHT]) and stopped_ok
	stopped_ok = await _check_stopped("stop_kick3", [K, K], [KNEE, MIDDLE]) and stopped_ok
	stopped_ok = await _check_stopped("stop_route1", [P, K, P], [JAB, KNEE, JAB]) and stopped_ok
	stopped_ok = await _check_stopped("stop_route2", [P, K, K], [JAB, KNEE, MIDDLE]) and stopped_ok
	stopped_ok = await _check_stopped("stop_route3", [P, P, K, P],
		[JAB, STRAIGHT, KNEE, HOOK]) and stopped_ok
	stopped_ok = await _check_stopped("stop_route4", [K, P, P, P, K, P],
		[KNEE, HOOK, STRAIGHT, JAB, KNEE, HOOK]) and stopped_ok
	_assert("(8) 全ルートの途中で入力を止めると、その段で待機へ戻る", stopped_ok)

	var late_ok := await _test_late_input()
	_assert("(9) 受付窓を過ぎた入力では次段が出ない", late_ok)
	_assert("(10) 7段ルートは途中で待機に落ちず段番号も連続する",
		bool(route4_result.get("no_early_finish", false))
		and bool(route4_result.get("stage_order_ok", false)))

	print("=== 結果: PASS=%d FAIL=%d ===" % [_pass, _fail])
	print("ALL PASS" if _fail == 0 else "HAS FAILURE")
	get_tree().quit(0 if _fail == 0 else 1)


func _assert_sequence(label: String, inputs: Array[StringName],
		expected: Array[StringName]) -> Dictionary:
	var result := await _run_sequence(label, inputs, expected)
	_assert("[%s] 入力列どおりの技が再生され待機へ戻る" % label,
		bool(result.get("matches", false)) and bool(result.get("idle", false)))
	return result


func _check_stopped(label: String, inputs: Array[StringName],
		expected: Array[StringName]) -> bool:
	var result := await _run_sequence(label, inputs, expected)
	return bool(result.get("matches", false)) and bool(result.get("idle", false))


func _run_sequence(label: String, inputs: Array[StringName],
		expected: Array[StringName]) -> Dictionary:
	await _spawn_player(expected.size())
	_send_input(inputs[0])
	var drove_all_inputs: bool = true
	for input_index: int in range(1, inputs.size()):
		if not await _wait_for_stage_window(input_index):
			drove_all_inputs = false
			break
		_send_input(inputs[input_index])
	var returned_idle := await _wait_for_idle()
	var actual: Array[StringName] = _played.duplicate()
	print("[%s] %s" % [label, _format_sequence(actual)])
	var result: Dictionary = {
		"matches": drove_all_inputs and actual == expected,
		"idle": returned_idle,
		"no_early_finish": not _premature_finish,
		"stage_order_ok": _stage_order_ok,
	}
	await _remove_player()
	return result


func _test_late_input() -> bool:
	await _spawn_player(1)
	_melee.call("attack")
	if not await _wait_for_played_count(1):
		await _remove_player()
		return false
	# PlayerMelee の終端判定だけを止め、AnimationTree を受付終了割合より先へ進める。
	_melee.set_physics_process(false)
	var out_ratio := float(_melee.get("jab_out_ratio"))
	var reached_late := await _wait_for_ratio(out_ratio + LATE_RATIO_MARGIN)
	_melee.call("attack")
	_melee.set_physics_process(true)
	var returned_idle := await _wait_for_idle()
	var actual: Array[StringName] = _played.duplicate()
	print("[late_input] %s" % _format_sequence(actual))
	var ok := reached_late and returned_idle and actual == [JAB]
	await _remove_player()
	return ok


func _spawn_player(expected_stage_count: int) -> void:
	_player = PLAYER.instantiate() as Node3D
	add_child(_player)
	_melee = _player.get_node(^"PlayerMelee")
	_playback = (_melee.get_node(^"AnimationTree") as AnimationTree) \
		.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_played.clear()
	_expected_stage_count = expected_stage_count
	_premature_finish = false
	_stage_order_ok = true
	_melee.connect("stage_started", _on_stage_started)
	_melee.connect("combo_finished", _on_combo_finished)
	await get_tree().physics_frame


func _remove_player() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	await get_tree().process_frame
	_player = null
	_melee = null
	_playback = null


func _send_input(input_kind: StringName) -> void:
	if input_kind == P:
		_melee.call("attack")
	else:
		_melee.call("kick")


func _wait_for_stage_window(completed_inputs: int) -> bool:
	if not await _wait_for_played_count(completed_inputs):
		return false
	return await _wait_for_ratio(WINDOW_RATIO)


func _wait_for_played_count(count: int) -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		if _played.size() >= count:
			return true
		if not bool(_melee.call("is_attacking")):
			return false
		await get_tree().physics_frame
	return false


func _wait_for_ratio(target_ratio: float) -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		if _current_ratio() >= target_ratio:
			return true
		if not bool(_melee.call("is_attacking")):
			return false
		await get_tree().physics_frame
	return false


func _wait_for_idle() -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		if not bool(_melee.call("is_attacking")):
			return true
		await get_tree().physics_frame
	return false


func _current_ratio() -> float:
	if _playback == null:
		return -1.0
	var length := _playback.get_current_length()
	if length <= 0.0:
		return -1.0
	return _playback.get_current_play_position() / length


func _on_stage_started(technique: StringName, stage: int) -> void:
	_stage_order_ok = _stage_order_ok and stage == _played.size() + 1
	_played.append(technique)


func _on_combo_finished() -> void:
	if _played.size() < _expected_stage_count:
		_premature_finish = true


func _format_sequence(sequence: Array[StringName]) -> String:
	var names := PackedStringArray()
	for technique in sequence:
		names.append(String(technique))
	return " -> ".join(names)


func _assert(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[PASS] %s" % label)
	else:
		_fail += 1
		print("[FAIL] %s" % label)
