extends SceneTree

# Mixamo FBX (Godot ufbx が sanitize した mixamorig4_ 命名) のソースボーン名を
# SkeletonProfileHumanoid のプロファイルボーン名へマッピングし、
# BoneMap リソースを生成・保存する。
#
# 注意: Mixamo 元来の命名は "mixamorig:Hips" だが、Godot 4.7 の ufbx インポータは
# コロンを含む名前を "mixamorig4_Hips" に sanitize する (inspect_mixamo.gd で確認)。
# BoneMap のソース側名はインポート後のスケルトンのボーン名と一致させる必要があるため
# "mixamorig4_" 接頭辞を用いる。


func _init() -> void:
	var profile: SkeletonProfileHumanoid = SkeletonProfileHumanoid.new()
	var bone_map: BoneMap = BoneMap.new()
	bone_map.profile = profile

	const P: String = "mixamorig4_"

	# ソース (FBX) の全ボーン名。inspect_mixamo.gd の出力から取得 (65 本)。
	var source_bones: PackedStringArray = PackedStringArray([
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

	# SkeletonProfileHumanoid のプロファイルボーン名 -> ソースボーン名 の明示エイリアス表。
	# Mixamo は Spine/Spine1/Spine2 の 3 段。プロファイルは Spine/Chest/UpperChest。
	#   Spine <- Spine, Chest <- Spine1, UpperChest <- Spine2。
	# Mixamo の指は Thumb1..4 (4 段) だが末尾 (4) は指先端 (End) なので Distal までの 3 段に割当。
	#   Proximal <- 1, Intermediate <- 2, Distal <- 3 (親指は Metacarpal/Proximal/Distal <- 1/2/3)。
	var alias: Dictionary = {
		"Hips": P + "Hips",
		"Spine": P + "Spine",
		"Chest": P + "Spine1",
		"UpperChest": P + "Spine2",
		"Neck": P + "Neck",
		"Head": P + "Head",

		"LeftShoulder": P + "LeftShoulder",
		"LeftUpperArm": P + "LeftArm",
		"LeftLowerArm": P + "LeftForeArm",
		"LeftHand": P + "LeftHand",
		"RightShoulder": P + "RightShoulder",
		"RightUpperArm": P + "RightArm",
		"RightLowerArm": P + "RightForeArm",
		"RightHand": P + "RightHand",

		"LeftUpperLeg": P + "LeftUpLeg",
		"LeftLowerLeg": P + "LeftLeg",
		"LeftFoot": P + "LeftFoot",
		"LeftToes": P + "LeftToeBase",
		"RightUpperLeg": P + "RightUpLeg",
		"RightLowerLeg": P + "RightLeg",
		"RightFoot": P + "RightFoot",
		"RightToes": P + "RightToeBase",

		# 指 (左)
		"LeftThumbMetacarpal": P + "LeftHandThumb1",
		"LeftThumbProximal": P + "LeftHandThumb2",
		"LeftThumbDistal": P + "LeftHandThumb3",
		"LeftIndexProximal": P + "LeftHandIndex1",
		"LeftIndexIntermediate": P + "LeftHandIndex2",
		"LeftIndexDistal": P + "LeftHandIndex3",
		"LeftMiddleProximal": P + "LeftHandMiddle1",
		"LeftMiddleIntermediate": P + "LeftHandMiddle2",
		"LeftMiddleDistal": P + "LeftHandMiddle3",
		"LeftRingProximal": P + "LeftHandRing1",
		"LeftRingIntermediate": P + "LeftHandRing2",
		"LeftRingDistal": P + "LeftHandRing3",
		"LeftLittleProximal": P + "LeftHandPinky1",
		"LeftLittleIntermediate": P + "LeftHandPinky2",
		"LeftLittleDistal": P + "LeftHandPinky3",

		# 指 (右)
		"RightThumbMetacarpal": P + "RightHandThumb1",
		"RightThumbProximal": P + "RightHandThumb2",
		"RightThumbDistal": P + "RightHandThumb3",
		"RightIndexProximal": P + "RightHandIndex1",
		"RightIndexIntermediate": P + "RightHandIndex2",
		"RightIndexDistal": P + "RightHandIndex3",
		"RightMiddleProximal": P + "RightHandMiddle1",
		"RightMiddleIntermediate": P + "RightHandMiddle2",
		"RightMiddleDistal": P + "RightHandMiddle3",
		"RightRingProximal": P + "RightHandRing1",
		"RightRingIntermediate": P + "RightHandRing2",
		"RightRingDistal": P + "RightHandRing3",
		"RightLittleProximal": P + "RightHandPinky1",
		"RightLittleIntermediate": P + "RightHandPinky2",
		"RightLittleDistal": P + "RightHandPinky3",
	}

	var required: PackedStringArray = PackedStringArray([
		"Hips", "Spine", "Chest", "Neck", "Head",
		"LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
		"RightUpperLeg", "RightLowerLeg", "RightFoot",
	])

	var mapped: PackedStringArray = PackedStringArray()
	var unmapped: PackedStringArray = PackedStringArray()

	var bone_count: int = profile.bone_size
	for i in range(bone_count):
		var pbone: String = profile.get_bone_name(i)
		var resolved: String = ""

		# 1) 完全一致 (プロファイル名がソースにそのまま存在)
		for sb in source_bones:
			if sb == pbone:
				resolved = sb
				break
		# 2) 既知エイリアス (エイリアス先が実在するボーンか確認)
		if resolved == "" and alias.has(pbone):
			var cand: String = alias[pbone]
			if source_bones.has(cand):
				resolved = cand

		if resolved != "":
			bone_map.set_skeleton_bone_name(pbone, resolved)
			mapped.append(pbone + " -> " + resolved)
		else:
			unmapped.append(pbone)

	print("=== profile bone count: ", bone_count, " ===")
	print("=== mapped: ", mapped.size(), " ===")
	for m in mapped:
		print("  ", m)
	print("=== UNMAPPED profile bones: ", unmapped.size(), " ===")
	for u in unmapped:
		print("  ", u)

	var missing_required: PackedStringArray = PackedStringArray()
	for r in required:
		if unmapped.has(r):
			missing_required.append(r)
	if missing_required.size() > 0:
		print("[FAIL] required bones unmapped: ", missing_required)
	else:
		print("[OK] all required (Hips/Spine/limbs/Head) mapped")

	var out_path: String = "res://assets/motions/mixamo_bone_map.tres"
	var err: int = ResourceSaver.save(bone_map, out_path)
	if err != OK:
		print("[ERROR] save failed err=", err)
		quit(1)
		return
	print("=== saved: ", out_path, " ===")
	quit(0)
