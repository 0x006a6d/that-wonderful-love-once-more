extends Node

## 犯人1体との1対1の殴り合いを計測する。
##   godot --path . --headless res://tools/measure_duel.tscn
##
## 「コンボは気持ちいいのに戦いがつまらない」の原因を数字で押さえるためのツール。
## プレイヤーは間合いを保ってコンボを回し続けるだけ。回復もしない。
## ここで犯人がほとんど行動できていないなら、それは戦いではなく作業になっている。
##
## 出す数字:
##   - 決着までの秒数と、犯人が STAGGERED（のけぞり）で固まっていた時間の割合
##   - 犯人が攻撃を出せた回数（ATTACK 進入）と、実際に当てられた回数
##   - プレイヤーが受けた総ダメージ

const STAGE: String = "res://levels/test_stage.tscn"
const MAX_FRAMES: int = 3600
const SETUP_FRAMES: int = 30
## プレイヤーを置く間合い（m）。犯人の attack_range 1.7 の内側。
const ENGAGE_DISTANCE: float = 1.2

var _stage: Node3D = null
var _player: Node3D = null
var _player_health: Health = null
var _melee: Node = null
var _robber: Node3D = null
var _robber_health: Health = null
## プレイヤーの向きは Model ノードが持つ（+Z が前方。近接判定もこの下）。
## 位置をテレポートで作るとここが回らないので、毎フレーム犯人へ向け直す。
var _player_model: Node3D = null

var _frames: int = 0
var _started: int = -1
var _staggered_frames: int = 0
var _attack_entries: int = 0
var _guard_entries: int = 0
var _guard_frames: int = 0
var _player_hits_taken: int = 0
var _player_hp_last: float = 0.0
var _player_damage_total: float = 0.0
var _combo_hits: int = 0
var _robber_hp_last: float = 0.0


func _ready() -> void:
	print("=== 1対1の殴り合い 計測開始 ===")
	RunState.reset()
	GameDirector.reset()
	GameDirector.notify_prologue_finished()

	var packed := load(STAGE) as PackedScene
	if packed == null:
		push_error("test_stage load 失敗")
		get_tree().quit(1)
		return
	_stage = packed.instantiate() as Node3D
	add_child(_stage)
	_player = _stage.get_node_or_null("Player") as Node3D
	_robber = _stage.get_node_or_null("Robber1") as Node3D
	if _player == null or _robber == null:
		push_error("Player / Robber1 が見つからない")
		get_tree().quit(1)
		return
	_player_health = _player.get_node_or_null("Health") as Health
	_melee = _player.get_node_or_null("PlayerMelee")
	_player_model = _player.get_node_or_null("Model") as Node3D
	_robber_health = _robber.get_node_or_null("Health") as Health
	_player_hp_last = _player_health.max_hp
	_robber_hp_last = _robber_health.max_hp
	if _robber.has_signal("state_entered"):
		_robber.connect("state_entered", _on_robber_state)


func _on_robber_state(state: int) -> void:
	if state == Robber.State.ATTACK:
		_attack_entries += 1
	elif state == Robber.State.GUARD:
		_guard_entries += 1


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < SETUP_FRAMES:
		return
	if _started < 0:
		_started = _frames

	if _robber_health.is_downed() or _player_health.is_downed() \
			or _frames - _started >= MAX_FRAMES:
		_report()
		return

	var robber_state: int = int(_robber.call("current_state"))
	if robber_state == Robber.State.STAGGERED:
		_staggered_frames += 1
	elif robber_state == Robber.State.GUARD:
		_guard_frames += 1

	# プレイヤーの被弾を数える。
	var hp: float = _player_health.current_hp()
	if hp < _player_hp_last:
		_player_hits_taken += 1
		_player_damage_total += _player_hp_last - hp
	_player_hp_last = hp
	# こちらの手数を数える。
	var robber_hp: float = _robber_health.current_hp()
	if robber_hp < _robber_hp_last:
		_combo_hits += 1
	_robber_hp_last = robber_hp

	# 犯人の方を向かせる（近接判定は Model の +Z 側にある）。
	var facing: Vector3 = _robber.global_position - _player.global_position
	facing.y = 0.0
	if _player_model != null and facing.length() > 0.01:
		_player_model.rotation.y = atan2(facing.x, facing.z)

	# 間合いを保ってコンボを回し続ける。
	var state := str(_melee.get("_state"))
	if state == "locomotion":
		if facing.length() > 0.01:
			var pos: Vector3 = _robber.global_position \
				- facing.normalized() * ENGAGE_DISTANCE
			pos.y = _player.global_position.y
			_player.global_position = pos
		_melee.call("attack")
	elif state.begins_with("melee_"):
		_melee.call("attack")


func _report() -> void:
	set_physics_process(false)
	var elapsed: float = float(_frames - _started) / 60.0
	var staggered: float = float(_staggered_frames) / 60.0
	var ratio: float = (staggered / elapsed * 100.0) if elapsed > 0.0 else 0.0
	print("[決着] %.2f 秒  犯人HP=%.1f  プレイヤーHP=%.1f"
		% [elapsed, _robber_health.current_hp(), _player_health.current_hp()])
	var guarding: float = float(_guard_frames) / 60.0
	print("[犯人] のけぞり=%.2f 秒（%.1f%%）  ガード=%.2f 秒（%d 回）  ATTACK 進入=%d 回"
		% [staggered, ratio, guarding, _guard_entries, _attack_entries])
	print("[プレイヤー] 与えた手数=%d 回  被弾=%d 回  受けた総ダメージ=%.1f"
		% [_combo_hits, _player_hits_taken, _player_damage_total])
	print("[所見] のけぞり割合が高く ATTACK 進入が 0 に近いほど、"
		+ "殴り始めた側が一方的に固め続けられる（＝反撃の余地が無い）")
	get_tree().quit(0)
