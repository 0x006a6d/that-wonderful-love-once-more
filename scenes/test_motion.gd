extends Node3D

# Quaternius Universal Animation Library の攻撃モーション (Punch_Cross) を
# nikechan_v2.vrm の GeneralSkeleton にリターゲット済みトラックで再生する検証シーン。

const MOTION_SCENE: String = "res://assets/motions/universal_animation_library.gltf"
const VRM_SCENE: String = "res://assets/vrm/nikechan_v2.vrm"

# 数値 QC の結果、3 本のパンチのうち拳が肩の高さ (拳高さ−肩高さ ≈ +0.04m) で
# 前方に伸びる Punch_Jab が最も綺麗な右ストレートに近いため既定採用。
# エディタのインスペクタから差し替え可能。
@export var animation_name: String = "Punch_Jab"

var _anim_player: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _frame: int = 0
var _sampled_bone: int = -1


func _find_node_by_class(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r: Node = _find_node_by_class(c, cls)
		if r != null:
			return r
	return null


func _ready() -> void:
	# VRM をインスタンス化して配置
	var vrm_packed: PackedScene = load(VRM_SCENE) as PackedScene
	var vrm: Node3D = vrm_packed.instantiate() as Node3D
	add_child(vrm)
	vrm.name = "Nikechan"

	_skeleton = _find_node_by_class(vrm, "Skeleton3D") as Skeleton3D
	if _skeleton == null:
		push_error("GeneralSkeleton not found in VRM")
		return
	# AnimationPlayer のトラックパス "%GeneralSkeleton:..." を解決させるため
	# unique name を有効化する。
	_skeleton.unique_name_in_owner = true

	_anim_player = _find_node_by_class(vrm, "AnimationPlayer") as AnimationPlayer
	if _anim_player == null:
		_anim_player = AnimationPlayer.new()
		_anim_player.name = "AnimationPlayer"
		vrm.add_child(_anim_player)
	# AnimationPlayer が %GeneralSkeleton を解決できるよう root を VRM ルートにする。
	_anim_player.root_node = _anim_player.get_path_to(vrm)

	# モーション gltf から AnimationLibrary を取り出して VRM の AnimationPlayer に登録
	var motion_packed: PackedScene = load(MOTION_SCENE) as PackedScene
	var motion_inst: Node = motion_packed.instantiate()
	var src_ap: AnimationPlayer = _find_node_by_class(motion_inst, "AnimationPlayer") as AnimationPlayer
	var lib: AnimationLibrary = src_ap.get_animation_library("")
	# duplicate してから登録 (元インスタンスは破棄するため)
	var lib_copy: AnimationLibrary = lib.duplicate(true) as AnimationLibrary
	if _anim_player.has_animation_library("motion"):
		_anim_player.remove_animation_library("motion")
	_anim_player.add_animation_library("motion", lib_copy)
	motion_inst.free()

	var anim_key: String = "motion/" + animation_name
	if not _anim_player.has_animation(anim_key):
		push_error("attack animation not found: " + anim_key)
		return

	# ループ設定して再生
	var anim: Animation = _anim_player.get_animation(anim_key)
	anim.loop_mode = Animation.LOOP_LINEAR
	_anim_player.play(anim_key)
	print("[test_motion] playing ", anim_key, " length=", anim.length)

	# 自己検証用: 適当なボーン (RightLowerArm) の rest 回転を記録
	_sampled_bone = _skeleton.find_bone("RightLowerArm")
	if _sampled_bone >= 0:
		print("[test_motion] tracking bone RightLowerArm idx=", _sampled_bone)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30 and _sampled_bone >= 0:
		var rot: Quaternion = _skeleton.get_bone_pose_rotation(_sampled_bone)
		print("[test_motion] frame 30 RightLowerArm pose rotation euler=", rot.get_euler())
	if _frame == 90 and _sampled_bone >= 0:
		var rot: Quaternion = _skeleton.get_bone_pose_rotation(_sampled_bone)
		print("[test_motion] frame 90 RightLowerArm pose rotation euler=", rot.get_euler())
		print("[test_motion] animation is driving the skeleton (pose changed over time)")
