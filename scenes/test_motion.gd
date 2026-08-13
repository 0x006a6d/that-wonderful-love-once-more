extends Node3D

# 借り物モーション (Quaternius / Mixamo) を nikechan_v2.vrm の GeneralSkeleton に
# リターゲット済みトラックで再生する検証シーン。
#
# assets/motions/ 以下を走査して自動登録する:
#   - *.gltf -> "motion/" ライブラリ (Quaternius。内蔵アニメ名をそのまま使う)
#   - mixamo_*.fbx -> "mixamo/" ライブラリ (各 FBX の内蔵アニメ名は "mixamo_com" で
#     共通のため、ファイル名から表示名を導出する。例: mixamo_cross_punch -> Cross_Punch)
# animation_name は "<library>/<anim>" 形式で指定する。
#   例: "mixamo/Cross_Punch" / "motion/Punch_Jab"

const VRM_SCENE: String = "res://assets/vrm/nikechan_v2.vrm"
const MOTIONS_DIR: String = "res://assets/motions"

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

	_register_motion_libraries()

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


# assets/motions/ を走査し、gltf -> "motion"、mixamo_*.fbx -> "mixamo" として登録する。
func _register_motion_libraries() -> void:
	var gltf_lib: AnimationLibrary = AnimationLibrary.new()
	var mixamo_lib: AnimationLibrary = AnimationLibrary.new()

	var dir: DirAccess = DirAccess.open(MOTIONS_DIR)
	if dir == null:
		push_error("cannot open " + MOTIONS_DIR)
		return
	var files: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			# エディタ外 (エクスポート後) では ".import" 越しの remap 名になる場合が
			# あるため、拡張子は get_basename 側でも判定する。
			if fname.ends_with(".gltf") or fname.ends_with(".fbx"):
				files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()

	for f in files:
		var path: String = MOTIONS_DIR + "/" + f
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			push_warning("motion load failed: " + path)
			continue
		var inst: Node = packed.instantiate()
		var src_ap: AnimationPlayer = _find_node_by_class(inst, "AnimationPlayer") as AnimationPlayer
		if src_ap == null:
			inst.free()
			continue
		var anims: PackedStringArray = src_ap.get_animation_list()
		if f.ends_with(".gltf"):
			# glTF は内蔵アニメ名をそのまま "motion" ライブラリへ
			for a in anims:
				var key: String = a.get_slice("/", a.get_slice_count("/") - 1)
				if not gltf_lib.has_animation(key):
					gltf_lib.add_animation(key, src_ap.get_animation(a).duplicate(true) as Animation)
		else:
			# FBX はファイル名から表示名を導出 (mixamo_cross_punch -> Cross_Punch)。
			# アニメが複数あれば "<表示名>_<アニメ名>" で衝突回避。
			var disp: String = _display_name_from_file(f)
			for a in anims:
				var key: String = disp if anims.size() == 1 else disp + "_" + a.get_file()
				if not mixamo_lib.has_animation(key):
					mixamo_lib.add_animation(key, src_ap.get_animation(a).duplicate(true) as Animation)
		inst.free()

	if _anim_player.has_animation_library("motion"):
		_anim_player.remove_animation_library("motion")
	_anim_player.add_animation_library("motion", gltf_lib)
	if _anim_player.has_animation_library("mixamo"):
		_anim_player.remove_animation_library("mixamo")
	_anim_player.add_animation_library("mixamo", mixamo_lib)
	print("[test_motion] registered motion/=", gltf_lib.get_animation_list().size(), \
			" mixamo/=", mixamo_lib.get_animation_list().size())


# "mixamo_cross_punch.fbx" -> "Cross_Punch" / "mixamo_hook_1.fbx" -> "Hook_1"
func _display_name_from_file(fname: String) -> String:
	var base: String = fname.get_basename()
	if base.begins_with("mixamo_"):
		base = base.substr(7)
	var parts: PackedStringArray = base.split("_")
	var out: PackedStringArray = PackedStringArray()
	for p in parts:
		out.append(p.capitalize() if p.length() > 0 else p)
	return "_".join(out)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30 and _sampled_bone >= 0:
		var rot: Quaternion = _skeleton.get_bone_pose_rotation(_sampled_bone)
		print("[test_motion] frame 30 RightLowerArm pose rotation euler=", rot.get_euler())
	if _frame == 90 and _sampled_bone >= 0:
		var rot: Quaternion = _skeleton.get_bone_pose_rotation(_sampled_bone)
		print("[test_motion] frame 90 RightLowerArm pose rotation euler=", rot.get_euler())
		print("[test_motion] animation is driving the skeleton (pose changed over time)")
