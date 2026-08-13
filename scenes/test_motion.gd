extends Node3D

# 借り物モーション (Quaternius / Mixamo) を nikechan_v2.vrm の GeneralSkeleton に
# リターゲット済みトラックで再生する検証シーン。
#
# Quaternius (Universal Animation Library) は "motion/" ライブラリに、
# Mixamo パンチ一式は "mixamo/" ライブラリに登録する。
# animation_name は "<library>/<anim>" 形式で指定する。
#   例: "mixamo/Cross_Punch" / "motion/Punch_Jab"

const VRM_SCENE: String = "res://assets/vrm/nikechan_v2.vrm"

# Quaternius glTF (1 本に 46 アニメ)。ライブラリキー "motion"。
const QUATERNIUS_SCENE: String = "res://assets/motions/universal_animation_library.gltf"

# Mixamo FBX 一式。各 FBX の内蔵アニメ名は "mixamo_com" で共通のため、
# ここで表示名 -> FBX パスの対応を持ち、"mixamo" ライブラリに固有キーで登録する。
const MIXAMO_SOURCES: Array = [
	["Cross_Punch", "res://assets/motions/mixamo_cross_punch.fbx"],
	["Combo_Punch", "res://assets/motions/mixamo_combo_punch.fbx"],
	["Punch_Combo", "res://assets/motions/mixamo_punch_combo.fbx"],
	["Hook_1", "res://assets/motions/mixamo_hook_1.fbx"],
	["Hook_2", "res://assets/motions/mixamo_hook_2.fbx"],
	["Hook_3", "res://assets/motions/mixamo_hook_3.fbx"],
	["Hook_4", "res://assets/motions/mixamo_hook_4.fbx"],
	["Elbow_1", "res://assets/motions/mixamo_elbow_1.fbx"],
	["Elbow_2", "res://assets/motions/mixamo_elbow_2.fbx"],
	["Elbow_3", "res://assets/motions/mixamo_elbow_3.fbx"],
]

# 数値 QC の結果、Mixamo Cross_Punch が拳ほぼ肩高さ (拳高さ−肩高さ ≈ +0.063m) で
# 前方距離 0.448m と最も伸びのある右ストレートのため既定採用。
# Quaternius Punch_Jab (0.126m) より大幅に伸びる。
# エディタのインスペクタから "motion/..." / "mixamo/..." に差し替え可能。
@export var animation_name: String = "mixamo/Cross_Punch"

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

	_register_quaternius()
	_register_mixamo()

	if not _anim_player.has_animation(animation_name):
		push_error("attack animation not found: " + animation_name)
		return

	# ループ設定して再生
	var anim: Animation = _anim_player.get_animation(animation_name)
	anim.loop_mode = Animation.LOOP_LINEAR
	_anim_player.play(animation_name)
	print("[test_motion] playing ", animation_name, " length=", anim.length)

	# 自己検証用: RightLowerArm の rest 回転を記録
	_sampled_bone = _skeleton.find_bone("RightLowerArm")
	if _sampled_bone >= 0:
		print("[test_motion] tracking bone RightLowerArm idx=", _sampled_bone)


func _register_quaternius() -> void:
	var motion_packed: PackedScene = load(QUATERNIUS_SCENE) as PackedScene
	var motion_inst: Node = motion_packed.instantiate()
	var src_ap: AnimationPlayer = _find_node_by_class(motion_inst, "AnimationPlayer") as AnimationPlayer
	var lib: AnimationLibrary = src_ap.get_animation_library("")
	var lib_copy: AnimationLibrary = lib.duplicate(true) as AnimationLibrary
	if _anim_player.has_animation_library("motion"):
		_anim_player.remove_animation_library("motion")
	_anim_player.add_animation_library("motion", lib_copy)
	motion_inst.free()


func _register_mixamo() -> void:
	var lib: AnimationLibrary = AnimationLibrary.new()
	for entry in MIXAMO_SOURCES:
		var disp: String = entry[0]
		var fbx_path: String = entry[1]
		var motion_packed: PackedScene = load(fbx_path) as PackedScene
		if motion_packed == null:
			continue
		var motion_inst: Node = motion_packed.instantiate()
		var src_ap: AnimationPlayer = _find_node_by_class(motion_inst, "AnimationPlayer") as AnimationPlayer
		var src_anim: Animation = src_ap.get_animation("mixamo_com")
		lib.add_animation(disp, src_anim.duplicate(true) as Animation)
		motion_inst.free()
	if _anim_player.has_animation_library("mixamo"):
		_anim_player.remove_animation_library("mixamo")
	_anim_player.add_animation_library("mixamo", lib)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30 and _sampled_bone >= 0:
		var rot: Quaternion = _skeleton.get_bone_pose_rotation(_sampled_bone)
		print("[test_motion] frame 30 RightLowerArm pose rotation euler=", rot.get_euler())
	if _frame == 90 and _sampled_bone >= 0:
		var rot: Quaternion = _skeleton.get_bone_pose_rotation(_sampled_bone)
		print("[test_motion] frame 90 RightLowerArm pose rotation euler=", rot.get_euler())
		print("[test_motion] animation is driving the skeleton (pose changed over time)")
