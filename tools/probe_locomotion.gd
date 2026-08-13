extends SceneTree

## locomotion 配線の実測プローブ。
## player.tscn を単体でインスタンス化し、
##   (1) AnimationPlayer に player/idle・player/move が存在するか
##   (2) idle 時と move 時で骨のポーズが実際に変わるか（RightHand の位置差）
##   (3) blend_position が set_locomotion で動くか
## を出力する。
## 実行: godot --path . --headless --script res://tools/probe_locomotion.gd

const PLAYER := "res://actors/player/player.tscn"

var _player: Node3D = null
var _melee: Node = null
var _skel: Skeleton3D = null
var _hand: int = -1
var _frames: int = 0
var _idle_pos: Vector3 = Vector3.ZERO
var _phase: int = 0


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _initialize() -> void:
	var packed := load(PLAYER) as PackedScene
	_player = packed.instantiate() as Node3D
	get_root().add_child(_player)
	_melee = _player.get_node_or_null("PlayerMelee")
	_skel = _find(_player, "Skeleton3D") as Skeleton3D
	if _skel != null:
		_hand = _skel.find_bone("RightHand")


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0 and _frames == 5:
		var ap := _find(_player, "AnimationPlayer") as AnimationPlayer
		var names: Array[String] = []
		for a in ap.get_animation_list():
			names.append(str(a))
		print("[anims] ", names)
		var tree := _melee.get_node_or_null("AnimationTree") as AnimationTree
		print("[tree] active=", tree.active if tree else "no-tree")
		_phase = 1
	elif _phase == 1:
		# idle のまま 60f 回してポーズ記録。
		_melee.call("set_locomotion", 0.0)
		if _frames >= 65:
			_idle_pos = (_skel.global_transform * _skel.get_bone_global_pose(_hand)).origin
			var tree := _melee.get_node_or_null("AnimationTree") as AnimationTree
			print("[idle] hand=", _idle_pos, " blend=", tree.get("parameters/locomotion/blend/blend_position"))
			_phase = 2
	elif _phase == 2:
		# move にして 60f。
		_melee.call("set_locomotion", 4.5)
		if _frames >= 130:
			var pos := (_skel.global_transform * _skel.get_bone_global_pose(_hand)).origin
			var tree := _melee.get_node_or_null("AnimationTree") as AnimationTree
			print("[move] hand=", pos, " blend=", tree.get("parameters/locomotion/blend/blend_position"))
			print("[diff] idle→move hand moved=", "%.4f" % _idle_pos.distance_to(pos), " m")
			quit(0)
			return true
	return false
