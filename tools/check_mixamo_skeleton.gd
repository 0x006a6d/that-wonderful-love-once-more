extends SceneTree

# 追加 Mixamo FBX (BoneMap 未適用状態) のスケルトンが既存 10 本と同一構成
# (65 ボーン, mixamorig4_ 接頭辞, 同一ボーン名列) かを確認する。
# あわせて各アニメの長さ・トラック数・メッシュ有無を一覧する。
# 使い方: godot --path . --headless --script tools/check_mixamo_skeleton.gd <fbx名...>
#   引数なしの場合は assets/motions/ の mixamo_*.fbx 全部を対象にする。

const MOTIONS_DIR: String = "res://assets/motions"

# 既存 10 本で確認済みの基準ボーン名列 (generate_mixamo_bone_map.gd と同じ 65 本)
const P: String = "mixamorig4_"


func _reference_bones() -> PackedStringArray:
	return PackedStringArray([
		P + "Hips", P + "Spine", P + "Spine1", P + "Spine2", P + "Neck", P + "Head", P + "HeadTop_End",
		P + "LeftShoulder", P + "LeftArm", P + "LeftForeArm", P + "LeftHand",
		P + "LeftHandThumb1", P + "LeftHandThumb2", P + "LeftHandThumb3", P + "LeftHandThumb4",
		P + "LeftHandIndex1", P + "LeftHandIndex2", P + "LeftHandIndex3", P + "LeftHandIndex4",
		P + "LeftHandMiddle1", P + "LeftHandMiddle2", P + "LeftHandMiddle3", P + "LeftHandMiddle4",
		P + "LeftHandRing1", P + "LeftHandRing2", P + "LeftHandRing3", P + "LeftHandRing4",
		P + "LeftHandPinky1", P + "LeftHandPinky2", P + "LeftHandPinky3", P + "LeftHandPinky4",
		P + "RightShoulder", P + "RightArm", P + "RightForeArm", P + "RightHand",
		P + "RightHandThumb1", P + "RightHandThumb2", P + "RightHandThumb3", P + "RightHandThumb4",
		P + "RightHandIndex1", P + "RightHandIndex2", P + "RightHandIndex3", P + "RightHandIndex4",
		P + "RightHandMiddle1", P + "RightHandMiddle2", P + "RightHandMiddle3", P + "RightHandMiddle4",
		P + "RightHandRing1", P + "RightHandRing2", P + "RightHandRing3", P + "RightHandRing4",
		P + "RightHandPinky1", P + "RightHandPinky2", P + "RightHandPinky3", P + "RightHandPinky4",
		P + "LeftUpLeg", P + "LeftLeg", P + "LeftFoot", P + "LeftToeBase", P + "LeftToe_End",
		P + "RightUpLeg", P + "RightLeg", P + "RightFoot", P + "RightToeBase", P + "RightToe_End",
	])


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


func _has_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child in node.get_children():
		if _has_mesh(child):
			return true
	return false


func _list_targets() -> PackedStringArray:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		return args
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(MOTIONS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with("mixamo_") and fname.ends_with(".fbx"):
			out.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _init() -> void:
	var reference: PackedStringArray = _reference_bones()
	var targets: PackedStringArray = _list_targets()
	var mismatches: PackedStringArray = PackedStringArray()

	for fname in targets:
		var path: String = MOTIONS_DIR + "/" + fname
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			print("[ERROR] load failed: ", path)
			mismatches.append(fname + " (load failed)")
			continue
		var inst: Node = packed.instantiate()
		var skel: Skeleton3D = _find_skeleton(inst)
		var ap: AnimationPlayer = _find_anim_player(inst)

		var bones: PackedStringArray = PackedStringArray()
		if skel != null:
			for i in range(skel.get_bone_count()):
				bones.append(skel.get_bone_name(i))

		# BoneMap 適用済み (GeneralSkeleton) の場合は基準と一致しないのが正常なので
		# スケルトン名で分岐して判定する。
		var status: String = ""
		if skel == null:
			status = "[FAIL] no skeleton"
			mismatches.append(fname + " (no skeleton)")
		elif skel.name == "GeneralSkeleton":
			status = "retargeted (GeneralSkeleton, " + str(bones.size()) + " bones)"
		elif bones == reference:
			status = "[OK] identical to reference (65 mixamorig4_ bones)"
		else:
			status = "[MISMATCH] bones=" + str(bones.size())
			mismatches.append(fname)

		var anim_desc: String = "(no AnimationPlayer)"
		if ap != null:
			var parts: PackedStringArray = PackedStringArray()
			for a in ap.get_animation_list():
				var anim: Animation = ap.get_animation(a)
				parts.append("'" + a + "' len=" + ("%.3f" % anim.length) + "s tracks=" + str(anim.get_track_count()))
			anim_desc = ", ".join(parts)

		print(fname, " | mesh=", _has_mesh(inst), " | ", status, " | ", anim_desc)
		inst.free()

	print("\n=== mismatch summary: ", mismatches.size(), " ===")
	for m in mismatches:
		print("  ", m)
	quit(0)
