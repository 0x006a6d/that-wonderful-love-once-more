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
##   (6) キックコンボでも命中し Dummy2 がダウンする（キック hitbox の実効確認）
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
var _dummy2: Node3D = null
var _dummy2_health: Node = null

var _dummy_start_pos: Vector3 = Vector3.ZERO
var _dummy_start_hp: float = 0.0
var _hp_after_first_hit: float = -1.0
var _downed_after_first_hit: bool = false
var _staggered_count: int = 0
var _living_hit_landed_count: int = 0
var _max_moved: float = 0.0
var _reached_melee_2: bool = false
var _key_attack_ok: bool = false
var _key_deadline: int = 0
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
	# 犯人（8/17 で仮ステージに追加）はこの検証の対象外。殴られて条件が変わるのを
	# 防ぐため外す。犯人側の検証は tools/test_robber_ai.tscn が担当する。
	var robber := _stage.get_node_or_null("Robber1")
	if robber != null:
		robber.queue_free()
	_player = _stage.get_node_or_null("Player") as Node3D
	_dummy = _stage.get_node_or_null("Dummy1") as Node3D
	if _player == null or _dummy == null:
		_fatal("Player / Dummy1 が見つからない")
		return
	_melee = _player.get_node_or_null("PlayerMelee")
	_dummy_health = _dummy.get_node_or_null("Health")
	_dummy2 = _stage.get_node_or_null("Dummy2") as Node3D
	_dummy2_health = _dummy2.get_node_or_null("Health") if _dummy2 != null else null
	var hitbox := _player.get_node_or_null("Model/MeleeHitbox") as Hitbox
	if _melee == null or _dummy_health == null or _dummy2_health == null or hitbox == null:
		_fatal("PlayerMelee / Hitbox / Health が見つからない")
		return
	_dummy_health.connect("staggered", _on_staggered)
	hitbox.hit_landed.connect(_on_hit_landed)


func _on_staggered() -> void:
	_staggered_count += 1
	if _hp_after_first_hit < 0.0:
		_hp_after_first_hit = float(_dummy_health.call("current_hp"))
		_downed_after_first_hit = bool(_dummy_health.call("is_downed"))


func _on_hit_landed(target: Node3D) -> void:
	if target == _dummy and not bool(_dummy_health.call("is_downed")):
		_living_hit_landed_count += 1


func _physics_process(_delta: float) -> void:
	_frames += 1

	if _phase == 0:
		if _frames < 10:
			return
		_dummy_start_pos = _dummy.global_position
		_dummy_start_hp = float(_dummy_health.call("current_hp"))
		print("[init] dummy hp=%.1f pos=%s" % [_dummy_start_hp, str(_dummy_start_pos)])
		# 最初のコンボは attack アクション (キー J) のイベント経由で発火させ、
		# 入力マップ→_unhandled_input→PlayerMelee の経路を検証する。
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_J
		ev.pressed = true
		Input.parse_input_event(ev)
		_key_deadline = _frames + 15
		_phase = 1
		return

	if _phase == 1:
		# J キーイベントで攻撃が始まったか（15 フレーム以内）。
		# 検証ウィンドウ中は直接 attack() を呼ばない（呼ぶと検証にならない）。
		if not _key_attack_ok:
			if bool(_melee.call("is_attacking")):
				_key_attack_ok = true
				var rel := InputEventKey.new()
				rel.physical_keycode = KEY_J
				rel.pressed = false
				Input.parse_input_event(rel)
			elif _frames < _key_deadline:
				return
			# deadline 超過: FAIL のまま直接駆動の grind に進む。
		_max_moved = maxf(_max_moved, _dummy.global_position.distance_to(_dummy_start_pos))
		var state := str(_melee.get("_state"))
		if state == "melee_2":
			_reached_melee_2 = true

		var downed: bool = bool(_dummy_health.call("is_downed"))
		if downed:
			_phase = 2
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
		return

	if _phase == 2:
		# キックコンボで Dummy2 を殴れるかの実効確認。
		var state2 := str(_melee.get("_state"))
		if bool(_dummy2_health.call("is_downed")):
			_evaluate()
			return
		if _frames >= MAX_FRAMES + 800:
			print("[timeout kick] frames=%d" % _frames)
			_evaluate()
			return
		if state2 == "locomotion":
			var pos2 := _dummy2.global_position
			pos2.z -= 1.0
			pos2.y = _player.global_position.y
			_player.global_position = pos2
			_melee.call("kick")
		elif state2 == "kick_1" or state2 == "kick_2":
			_melee.call("kick")


func _evaluate() -> void:
	var hp := float(_dummy_health.call("current_hp"))
	var downed: bool = bool(_dummy_health.call("is_downed"))

	print("[result] dummy hp %.1f -> %.1f  staggered=%d 回  max_moved=%.3f m" %
		[_dummy_start_hp, hp, _staggered_count, _max_moved])
	print("[result] 初撃後 hp=%.1f downed=%s / 最終 downed=%s reached_melee_2=%s frames=%d" %
		[_hp_after_first_hit, str(_downed_after_first_hit), str(downed), str(_reached_melee_2), _frames])
	print("[result] RunState.robbers_downed=%d  downed_records=%d" %
		[RunState.robbers_downed, RunState.downed.size()])

	_assert("attack アクション (キー J) でコンボが発火した", _key_attack_ok)
	_assert("被弾で HP が減り staggered が発火した",
		_hp_after_first_hit >= 0.0 and _hp_after_first_hit < _dummy_start_hp and _staggered_count >= 1)
	_assert("生存している相手への通常命中で hit_landed が発火した",
		_living_hit_landed_count >= 1)
	_assert("1発ではダウンしない（初撃後は非ダウン）", not _downed_after_first_hit)
	_assert("ノックバックでダミーが動いた", _max_moved > 0.05)
	_assert("コンボが 2 段目まで連鎖した", _reached_melee_2)
	_assert("連打で HP が尽きてダウンした", downed and hp <= 0.0)
	_assert("RunState に robber ダウンが記録された", RunState.robbers_downed >= 1)
	var kick_hp := float(_dummy2_health.call("current_hp"))
	var kick_downed: bool = bool(_dummy2_health.call("is_downed"))
	print("[result] kick: dummy2 hp=%.1f downed=%s" % [kick_hp, str(kick_downed)])
	_assert("キックコンボでも命中し Dummy2 がダウンした", kick_downed)

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
