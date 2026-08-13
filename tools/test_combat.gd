extends Node

## 近接戦闘のヘッドレス検証（シーンハーネス版）。
## autoload（RunState / HitStop / GameTypes）を正しく解決させるため、
## --script ではなくシーンとして起動する:
##   godot --path . --headless res://tools/test_combat.tscn
##
## 検証項目:
##   (1) ダミーの Health が減る（Hitbox→Hurtbox が通る）
##   (2) ノックバックでダミーの位置が動く
##   (3) コンボが melee_2 まで連鎖する
##   (4) ダミーがダウンし RunState に robber ダウンが記録される

const STAGE := "res://levels/test_stage.tscn"
const MAX_FRAMES := 240

var _pass: int = 0
var _fail: int = 0

var _stage: Node = null
var _player: Node3D = null
var _melee: Node = null
var _dummy: Node3D = null
var _dummy_health: Node = null

var _dummy_start_pos: Vector3 = Vector3.ZERO
var _dummy_start_hp: float = 0.0
var _reached_melee_2: bool = false
var _frames: int = 0
var _phase: int = 0


func _ready() -> void:
	print("=== 近接戦闘 検証開始 ===")
	RunState.reset()
	var packed := load(STAGE) as PackedScene
	if packed == null:
		_fatal("test_stage load 失敗")
		return
	_stage = packed.instantiate()
	add_child(_stage)
	_player = _stage.get_node_or_null("Player") as Node3D
	_dummy = _stage.get_node_or_null("Dummy1") as Node3D
	if _player == null or _dummy == null:
		_fatal("Player / Dummy1 が見つからない")
		return
	_melee = _player.get_node_or_null("PlayerMelee")
	_dummy_health = _dummy.get_node_or_null("Health")
	if _melee == null or _dummy_health == null:
		_fatal("PlayerMelee / Health が見つからない")
		return


func _physics_process(_delta: float) -> void:
	_frames += 1

	if _phase == 0:
		if _frames < 10:
			return
		_dummy_start_pos = _dummy.global_position
		_dummy_start_hp = float(_dummy_health.call("current_hp"))
		print("[init] dummy hp=%.1f pos=%s" % [_dummy_start_hp, str(_dummy_start_pos)])
		_melee.call("attack")
		_phase = 1
		return

	if _phase == 1:
		if _frames == 20:
			_melee.call("attack")  # 2 段目をバッファ入力
		if str(_melee.get("_state")) == "melee_2":
			_reached_melee_2 = true
		if _frames >= MAX_FRAMES:
			_evaluate()


func _evaluate() -> void:
	var hp := float(_dummy_health.call("current_hp"))
	var moved := _dummy.global_position.distance_to(_dummy_start_pos)
	var downed: bool = bool(_dummy_health.call("is_downed"))

	print("[result] dummy hp %.1f -> %.1f  moved=%.3f m  downed=%s  reached_melee_2=%s" %
		[_dummy_start_hp, hp, moved, str(downed), str(_reached_melee_2)])
	print("[result] RunState.robbers_downed=%d  downed_records=%d" %
		[RunState.robbers_downed, RunState.downed.size()])

	_assert("ダミーの HP が減った（判定が通った）", hp < _dummy_start_hp)
	_assert("ノックバックでダミーが動いた", moved > 0.05)
	_assert("コンボが 2 段目まで連鎖した", _reached_melee_2)
	_assert("ダミーがダウンした", downed)
	_assert("RunState に robber ダウンが記録された", RunState.robbers_downed >= 1)

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
