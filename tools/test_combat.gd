extends Node

## 近接戦闘のヘッドレス検証（シーンハーネス版）。
## autoload（RunState / HitStop / GameTypes）を正しく解決させるため、
## --script ではなくシーンとして起動する:
##   godot --path . --headless res://tools/test_combat.tscn
##
## 検証項目:
##   (1) 被弾でダミーの Health が減り staggered が発火する（Hitbox→Hurtbox が通る）
##   (2) ノックバックでダミーの位置が動く
##   (3) コンボが melee_2 まで連鎖する
##   (4) 連打で HP が尽きるとダウンする（1発ではダウンしない）
##   (5) RunState に robber ダウンが記録される
##
## ノックバックでダミーが射程外へ押し出されるため、攻撃の合間に
## プレイヤーをダミーの手前 1m へ寄せ直す（歩き寄りの代替）。

const STAGE := "res://levels/test_stage.tscn"
const MAX_FRAMES := 1200

var _pass: int = 0
var _fail: int = 0

var _stage: Node = null
var _player: Node3D = null
var _melee: Node = null
var _dummy: Node3D = null
var _dummy_health: Node = null

var _dummy_start_pos: Vector3 = Vector3.ZERO
var _dummy_start_hp: float = 0.0
var _hp_after_first_hit: float = -1.0
var _downed_after_first_hit: bool = false
var _staggered_count: int = 0
var _max_moved: float = 0.0
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
	_dummy_health.connect("staggered", _on_staggered)


func _on_staggered() -> void:
	_staggered_count += 1
	if _hp_after_first_hit < 0.0:
		_hp_after_first_hit = float(_dummy_health.call("current_hp"))
		_downed_after_first_hit = bool(_dummy_health.call("is_downed"))


func _physics_process(_delta: float) -> void:
	_frames += 1

	if _phase == 0:
		if _frames < 10:
			return
		_dummy_start_pos = _dummy.global_position
		_dummy_start_hp = float(_dummy_health.call("current_hp"))
		print("[init] dummy hp=%.1f pos=%s" % [_dummy_start_hp, str(_dummy_start_pos)])
		_phase = 1
		return

	if _phase == 1:
		_max_moved = maxf(_max_moved, _dummy.global_position.distance_to(_dummy_start_pos))
		var state := str(_melee.get("_state"))
		if state == "melee_2":
			_reached_melee_2 = true

		var downed: bool = bool(_dummy_health.call("is_downed"))
		if downed:
			_evaluate()
			return
		if _frames >= MAX_FRAMES:
			print("[timeout] frames=%d" % _frames)
			_evaluate()
			return

		# 攻撃の合間に射程へ寄せ直し、連打を続ける。
		if state == "locomotion":
			var pos := _dummy.global_position
			pos.z -= 1.0
			pos.y = _player.global_position.y
			_player.global_position = pos
			_melee.call("attack")
		elif state == "melee_1":
			_melee.call("attack")  # 2 段目をバッファ入力


func _evaluate() -> void:
	var hp := float(_dummy_health.call("current_hp"))
	var downed: bool = bool(_dummy_health.call("is_downed"))

	print("[result] dummy hp %.1f -> %.1f  staggered=%d 回  max_moved=%.3f m" %
		[_dummy_start_hp, hp, _staggered_count, _max_moved])
	print("[result] 初撃後 hp=%.1f downed=%s / 最終 downed=%s reached_melee_2=%s frames=%d" %
		[_hp_after_first_hit, str(_downed_after_first_hit), str(downed), str(_reached_melee_2), _frames])
	print("[result] RunState.robbers_downed=%d  downed_records=%d" %
		[RunState.robbers_downed, RunState.downed.size()])

	_assert("被弾で HP が減り staggered が発火した",
		_hp_after_first_hit >= 0.0 and _hp_after_first_hit < _dummy_start_hp and _staggered_count >= 1)
	_assert("1発ではダウンしない（初撃後は非ダウン）", not _downed_after_first_hit)
	_assert("ノックバックでダミーが動いた", _max_moved > 0.05)
	_assert("コンボが 2 段目まで連鎖した", _reached_melee_2)
	_assert("連打で HP が尽きてダウンした", downed and hp <= 0.0)
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
