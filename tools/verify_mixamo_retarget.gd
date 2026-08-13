extends SceneTree

# リターゲット後の Mixamo FBX を検証する。
# スケルトンが GeneralSkeleton 化し、トラックがプロファイル名 (RightHand 等) に
# なっていることを確認する。
# 使い方: godot --path . --headless --script tools/verify_mixamo_retarget.gd

const FBXS: Array[String] = [
	"res://assets/motions/mixamo_cross_punch.fbx",
	"res://assets/motions/mixamo_combo_punch.fbx",
	"res://assets/motions/mixamo_punch_combo.fbx",
	"res://assets/motions/mixamo_hook_1.fbx",
	"res://assets/motions/mixamo_hook_2.fbx",
	"res://assets/motions/mixamo_hook_3.fbx",
	"res://assets/motions/mixamo_hook_4.fbx",
	"res://assets/motions/mixamo_elbow_1.fbx",
	"res://assets/motions/mixamo_elbow_2.fbx",
	"res://assets/motions/mixamo_elbow_3.fbx",
]


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var f: Skeleton3D = _find_skeleton(child)
		if f != null:
			return f
	return null


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var f: AnimationPlayer = _find_anim_player(child)
		if f != null:
			return f
	return null


func _init() -> void:
	for path in FBXS:
		var packed: PackedScene = load(path) as PackedScene
		var inst: Node = packed.instantiate()
		var skel: Skeleton3D = _find_skeleton(inst)
		var ap: AnimationPlayer = _find_anim_player(inst)

		var skel_name: String = skel.name if skel != null else "(none)"
		var first_bones: PackedStringArray = PackedStringArray()
		if skel != null:
			for i in range(min(6, skel.get_bone_count())):
				first_bones.append(skel.get_bone_name(i))

		print("--- ", path.get_file(), " ---")
		print("  Skeleton3D name: ", skel_name, "  bones=", skel.get_bone_count() if skel else 0)
		print("  first bones: ", first_bones)

		var all_anims: PackedStringArray = ap.get_animation_list()
		for a in all_anims:
			var anim: Animation = ap.get_animation(a)
			# 右手 (RightHand) を含むトラックが profile 名になっているか探す
			var sample_path: String = ""
			var right_hand_found: bool = false
			for t in range(anim.get_track_count()):
				var tp: String = str(anim.track_get_path(t))
				if sample_path == "":
					sample_path = tp
				if tp.find("RightHand") >= 0:
					right_hand_found = true
			print("  anim '", a, "' len=", "%.3f" % anim.length, " tracks=", anim.get_track_count())
			print("    sample track path: ", sample_path)
			print("    has RightHand profile track: ", right_hand_found)

		inst.free()
	quit(0)
