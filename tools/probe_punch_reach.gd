extends SceneTree

## 攻撃モーションの見た目診断プローブ。
## (1) 単発攻撃: attack() 1回 → melee 滞在中の RightHand 前方到達を毎フレーム記録
## (2) マッシュ: 毎フレーム attack() 連打 → 300f の間の到達度分布を記録
## 前方到達 = (拳のワールド位置 - プレイヤー位置) を Model の +Z (正面) へ射影した値。
## AnimationTree の実効ステートも同時に記録し、travel の成立を確認する。
##
## 実行: godot --path . --headless --script res://tools/probe_punch_reach.gd

const PLAYER := "res://actors/player/player.tscn"

var _player: Node3D = null
var _melee: Node = null
var _skel: Skeleton3D = null
var _model: Node3D = null
var _hand: int = -1
var _frames: int = 0
var _phase: int = 0
var _series: Array[String] = []
var _max_reach_1: float = -INF
var _max_reach_2: float = -INF
var _mash_max_1: float = -INF
var _mash_max_2: float = -INF
var _mash_combos: int = 0
var _prev_state: String = "locomotion"


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _initialize() -> void:
	_player = (load(PLAYER) as PackedScene).instantiate() as Node3D
	get_root().add_child(_player)
	_melee = _player.get_node("PlayerMelee")
	_model = _player.get_node("Model") as Node3D
	_skel = _find(_player, "Skeleton3D") as Skeleton3D
	_hand = _skel.find_bone("RightHand")


func _reach() -> float:
	_skel.force_update_all_bone_transforms()
	var hand_g := (_skel.global_transform * _skel.get_bone_global_pose(_hand)).origin
	var rel := hand_g - _player.global_position
	var fwd := _model.global_transform.basis.z
	fwd.y = 0.0
	return rel.dot(fwd.normalized())


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false

	if _phase == 0:
		print("=== (1) 単発攻撃: J 1回のみ ===")
		_melee.call("attack")
		_phase = 1
		return false

	if _phase == 1:
		var st := str(_melee.get("_state"))
		var sm := _melee.get_node("AnimationTree").get("parameters/playback") as AnimationNodeStateMachinePlayback
		var node := str(sm.get_current_node())
		var r := _reach()
		if st != "locomotion" or node != "locomotion":
			_series.append("f%03d st=%s node=%s reach=%.3f" % [_frames, st, node, r])
			if node == "melee_1":
				_max_reach_1 = maxf(_max_reach_1, r)
			elif node == "melee_2":
				_max_reach_2 = maxf(_max_reach_2, r)
		elif _series.size() > 0:
			# 終了。時系列を 3 フレームおきに出力。
			for i in range(0, _series.size(), 3):
				print("  ", _series[i])
			print("[単発] melee_1 中の最大前方到達=%.3f m (melee_2=%s)" %
				[_max_reach_1, ("%.3f" % _max_reach_2) if _max_reach_2 > -INF else "未到達"])
			_phase = 2
			_frames = 1000
		return false

	if _phase == 2:
		# マッシュ: 毎フレーム attack() を 300f。
		if _frames < 1030:
			return false
		if _frames == 1030:
			print("=== (2) マッシュ連打 300f ===")
		if _frames <= 1330:
			_melee.call("attack")
			var sm2 := _melee.get_node("AnimationTree").get("parameters/playback") as AnimationNodeStateMachinePlayback
			var node2 := str(sm2.get_current_node())
			var r2 := _reach()
			if node2 == "melee_1":
				_mash_max_1 = maxf(_mash_max_1, r2)
			elif node2 == "melee_2":
				_mash_max_2 = maxf(_mash_max_2, r2)
			var st2 := str(_melee.get("_state"))
			if st2 == "melee_1" and _prev_state != "melee_1":
				_mash_combos += 1
			_prev_state = st2
			return false
		print("[マッシュ] melee_1 最大到達=%.3f m  melee_2 最大到達=%.3f m  コンボ開始回数=%d (300f)" %
			[_mash_max_1, _mash_max_2, _mash_combos])
		quit(0)
		return true

	return false
