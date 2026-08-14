extends Node

## 犯人AI（共通挙動）のヘッドレス検証（シーンハーネス版）。
## autoload（RunState / GameDirector / GameTypes）を解決させるため、--script ではなく
## シーンとして起動する:
##   godot --path . --headless res://tools/test_robber_ai.tscn
##
## 検証項目:
##   (1) ナビメッシュが実行時ベイクで生成される
##   (2) 視界外では PATROL のまま巡回地点へ移動する
##   (3) 視界に入れると ALERT → CHASE へ遷移し、GameDirector が ENGAGEMENT へ進む
##   (4) 距離を詰めて ATTACK に入り、プレイヤーの HP が減ってノックバックする
##   (5) プレイヤーの近接がヒットすると STAGGERED に入る
##   (6) HP が尽きると DOWNED になり RunState.robbers_downed が増える
##
## 位置の直接代入で状況を作る（歩き寄り・入力の再現は test_combat.gd 側の担当）。

const STAGE := "res://levels/test_stage.tscn"

## 各フェーズの制限フレーム数（60Hz 前提）。
const PATROL_FRAMES := 260
const SIGHT_FRAMES := 600
const ATTACK_FRAMES := 900
const FIGHT_FRAMES := 3000

var _pass: int = 0
var _fail: int = 0

var _stage: Node3D = null
var _player: Node3D = null
var _player_health: Health = null
var _melee: Node = null
var _robber: Node3D = null
var _robber_health: Health = null

var _navmesh_polygons: int = 0
var _patrol_moved: float = 0.0
var _patrol_state_kept: bool = true
var _saw_alert: bool = false
var _saw_chase: bool = false
var _saw_attack: bool = false
var _saw_staggered: bool = false
var _saw_downed: bool = false
var _act_on_alert: int = -1
var _min_distance: float = 1e9
var _player_hp_min: float = 1e9
var _player_pushed: float = 0.0

var _patrol_start: Vector3 = Vector3.ZERO
var _player_hold: Vector3 = Vector3.ZERO
var _frames: int = 0
var _phase: int = 0
var _phase_started: int = 0


func _ready() -> void:
	print("=== 犯人AI 検証開始 ===")
	RunState.reset()
	GameDirector.reset()
	# 幕を INFILTRATION まで進めておく（ALERT で ENGAGEMENT へ進むことを見るため）。
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
	_player_health = _player.get_node_or_null("Health") as Health
	_melee = _player.get_node_or_null("PlayerMelee")
	_robber_health = _robber.get_node_or_null("Health") as Health
	if _player_health == null or _melee == null or _robber_health == null:
		_fatal("Health / PlayerMelee が見つからない")
		return

	var region := _stage.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if region != null and region.navigation_mesh != null:
		_navmesh_polygons = region.navigation_mesh.get_polygon_count()

	if _robber.has_signal("state_entered"):
		_robber.connect("state_entered", _on_robber_state)


func _on_robber_state(state: int) -> void:
	match state:
		Robber.State.ALERT:
			if not _saw_alert:
				_saw_alert = true
				_act_on_alert = GameDirector.current_act
		Robber.State.CHASE:
			_saw_chase = true
		Robber.State.ATTACK:
			_saw_attack = true
		Robber.State.STAGGERED:
			_saw_staggered = true
		Robber.State.DOWNED:
			_saw_downed = true


func _physics_process(_delta: float) -> void:
	_frames += 1

	match _phase:
		0:
			_phase_patrol_setup()
		1:
			_phase_patrol()
		2:
			_phase_sight()
		3:
			_phase_attack()
		4:
			_phase_fight()


## 巡回の観察に入る前に、プレイヤーを視界外（対角の隅）へ退避させる。
func _phase_patrol_setup() -> void:
	if _frames < 6:
		return
	_player.global_position = Vector3(9.0, 0.2, 9.0)
	_patrol_start = _robber.global_position
	print("[init] navmesh polygons=%d robber=%s" % [_navmesh_polygons, str(_patrol_start)])
	_advance(1)


func _phase_patrol() -> void:
	# プレイヤーを隅に固定し続ける（重力で沈む・押されるのを無視するため）。
	_player.global_position = Vector3(9.0, 0.2, 9.0)
	_patrol_moved = maxf(_patrol_moved, _robber.global_position.distance_to(_patrol_start))
	if int(_robber.call("current_state")) != Robber.State.PATROL:
		_patrol_state_kept = false
	if _frames - _phase_started >= PATROL_FRAMES:
		print("[patrol] moved=%.2f m  state=%s" % [_patrol_moved, str(_robber.call("current_state"))])
		_advance(2)


## 犯人の正面 6m にプレイヤーを置き、視認 → ALERT → CHASE を確認する。
func _phase_sight() -> void:
	var robber_pos := _robber.global_position
	var forward := -_robber.global_transform.basis.z
	_player_hold = robber_pos + forward * 6.0
	_player_hold.y = 0.2
	_player.global_position = _player_hold

	if _saw_chase:
		print("[sight] ALERT/CHASE 到達 frames=%d act=%d" % [_frames - _phase_started, _act_on_alert])
		_advance(3)
		return
	if _frames - _phase_started >= SIGHT_FRAMES:
		print("[sight] タイムアウト alert=%s chase=%s" % [str(_saw_alert), str(_saw_chase)])
		_advance(3)


## プレイヤーを動かさずに置き、犯人が接近して殴ってくるのを確認する。
func _phase_attack() -> void:
	# ノックバックで飛ばされた分は戻す（一定の間合いで殴られ続ける状況を作る）。
	if _player.global_position.distance_to(_player_hold) > 0.05:
		_player_pushed = maxf(_player_pushed, _player.global_position.distance_to(_player_hold))
	_player.global_position = _player_hold

	_min_distance = minf(_min_distance, _flat_distance(_robber.global_position, _player_hold))
	_player_hp_min = minf(_player_hp_min, _player_health.current_hp())

	var hit_taken: bool = _player_hp_min < _player_health.max_hp
	if _saw_attack and hit_taken and _player_pushed > 0.02:
		print("[attack] 最短距離=%.2f m  player hp=%.1f  押された距離=%.3f m" %
			[_min_distance, _player_hp_min, _player_pushed])
		_advance(4)
		return
	if _frames - _phase_started >= ATTACK_FRAMES:
		print("[attack] タイムアウト attack=%s hp=%.1f pushed=%.3f" %
			[str(_saw_attack), _player_hp_min, _player_pushed])
		_advance(4)


## こちらから殴り返し、よろけ → ダウンまで持っていく。
## 検証の主題は犯人側の反応なので、プレイヤーは殴られても倒れないよう回復させる。
func _phase_fight() -> void:
	_player_health.revive()
	if bool(_robber_health.is_downed()):
		_evaluate()
		return
	if _frames - _phase_started >= FIGHT_FRAMES:
		print("[fight] タイムアウト robber hp=%.1f" % _robber_health.current_hp())
		_evaluate()
		return

	# 犯人の手前 1m に立ってコンボを回す（ノックバックで離れるため毎回寄せ直す）。
	var state := str(_melee.get("_state"))
	if state == "locomotion":
		var pos := _robber.global_position
		pos.z -= 1.0
		pos.y = _player.global_position.y
		_player.global_position = pos
		_melee.call("attack")
	elif state == "melee_1" or state == "melee_2":
		_melee.call("attack")


func _advance(phase: int) -> void:
	_phase = phase
	_phase_started = _frames


func _flat_distance(a: Vector3, b: Vector3) -> float:
	var d := a - b
	return Vector2(d.x, d.z).length()


func _evaluate() -> void:
	print("[result] robber hp=%.1f downed=%s  RunState.robbers_downed=%d" %
		[_robber_health.current_hp(), str(_robber_health.is_downed()), RunState.robbers_downed])

	_assert("ナビメッシュが実行時ベイクで生成された", _navmesh_polygons > 0)
	_assert("視界外では PATROL のまま巡回地点へ移動した",
		_patrol_moved > 1.0 and _patrol_state_kept)
	_assert("視認して ALERT に入った", _saw_alert)
	_assert("ALERT で幕が ENGAGEMENT へ進んだ", _act_on_alert == GameTypes.Act.ENGAGEMENT)
	_assert("CHASE で追跡に移った", _saw_chase)
	_assert("間合いを詰めて ATTACK に入った", _saw_attack and _min_distance <= 2.0)
	_assert("犯人の攻撃でプレイヤーの HP が減った", _player_hp_min < _player_health.max_hp)
	_assert("犯人の攻撃でプレイヤーがノックバックした", _player_pushed > 0.02)
	_assert("殴り返すと犯人が STAGGERED に入った", _saw_staggered)
	_assert("HP が尽きて DOWNED になった", _saw_downed and bool(_robber_health.is_downed()))
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
