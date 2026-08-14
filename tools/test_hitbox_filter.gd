extends Node

## Hitbox の陣営フィルタ（ignore_groups）の検証。
##   godot --path . --headless res://tools/test_hitbox_filter.tscn
##
## 経緯: 犯人の近接判定は「自分自身」しか除外していなかったため、犯人3体構成
## （8/18〜）で密集すると味方を殴り、RunState.robbers_downed が勝手に増えて
## 幕が進む恐れがあった。
##
## 検証項目:
##   (1) 犯人の判定は同じ robber グループの犯人に当たらない
##   (2) 同じ判定がプレイヤーには当たる（フィルタが効きすぎていない）
##
## AI のタイミングに依存しないよう、判定は _open_hitbox() を直接叩いて開く。

const STAGE := "res://levels/test_stage.tscn"
const ROBBER := "res://actors/npc/robber.tscn"
## 判定を開いてから結果を見るまでの待ちフレーム数（重なり判定は次の物理ステップ）。
const SETTLE_FRAMES := 12

var _pass: int = 0
var _fail: int = 0

var _stage: Node3D = null
var _player: Node3D = null
var _player_health: Health = null
var _attacker: Node3D = null
var _victim: Node3D = null
var _victim_health: Health = null

var _victim_hp_after: float = -1.0
var _player_hp_after: float = -1.0
var _frames: int = 0
var _phase: int = 0
var _phase_started: int = 0


func _ready() -> void:
	print("=== Hitbox 陣営フィルタ 検証開始 ===")
	RunState.reset()
	GameDirector.reset()

	var packed := load(STAGE) as PackedScene
	if packed == null:
		_fatal("test_stage load 失敗")
		return
	_stage = packed.instantiate() as Node3D
	add_child(_stage)
	_player = _stage.get_node_or_null("Player") as Node3D
	_attacker = _stage.get_node_or_null("Robber1") as Node3D
	if _player == null or _attacker == null:
		_fatal("Player / Robber1 が見つからない")
		return
	_player_health = _player.get_node_or_null("Health") as Health

	var robber_packed := load(ROBBER) as PackedScene
	_victim = robber_packed.instantiate() as Node3D
	_stage.add_child(_victim)
	_victim_health = _victim.get_node_or_null("Health") as Health


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < 6:
		return

	match _phase:
		0:
			# 犯人2をアタッカーの攻撃球の中へ置き、プレイヤーは視界外へ逃がす。
			_player.global_position = Vector3(9.0, 0.2, 9.0)
			_victim.global_position = _hitbox_center()
			_advance(1)
		1:
			_player.global_position = Vector3(9.0, 0.2, 9.0)
			_victim.global_position = _hitbox_center()
			if _frames - _phase_started == 1:
				_attacker.call("_open_hitbox")
			if _frames - _phase_started >= SETTLE_FRAMES:
				_victim_hp_after = _victim_health.current_hp()
				print("[robber→robber] 犯人2の HP=%.1f（判定を %d フレーム開いた）" %
					[_victim_hp_after, SETTLE_FRAMES])
				_attacker.call("_close_hitbox")
				_victim.global_position = Vector3(-9.0, 0.2, 9.0)
				_advance(2)
		2:
			# 同じ判定をプレイヤーに当てる（フィルタが効きすぎていないことの確認）。
			_player.global_position = _hitbox_center()
			if _frames - _phase_started == 1:
				_attacker.call("_open_hitbox")
			if _frames - _phase_started >= SETTLE_FRAMES:
				_player_hp_after = _player_health.current_hp()
				print("[robber→player] プレイヤーの HP=%.1f" % _player_hp_after)
				_evaluate()


## アタッカーの MeleeHitbox のワールド座標。
func _hitbox_center() -> Vector3:
	var hitbox := _attacker.get_node("MeleeHitbox") as Node3D
	var pos := hitbox.global_position
	# 体の中心が判定球に入るよう、足元基準へ落とす。
	pos.y = _attacker.global_position.y
	return pos


func _advance(phase: int) -> void:
	_phase = phase
	_phase_started = _frames


func _evaluate() -> void:
	_assert("犯人の判定は味方の犯人に当たらない",
		is_equal_approx(_victim_hp_after, _victim_health.max_hp))
	_assert("同じ判定がプレイヤーには当たる", _player_hp_after < _player_health.max_hp)
	_assert("味方誤爆で RunState に犯人ダウンが記録されていない", RunState.robbers_downed == 0)

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
