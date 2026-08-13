extends SceneTree

# Quaternius Universal Animation Library (Rigify DEF- naming) の
# ソースボーン名を SkeletonProfileHumanoid のプロファイルボーン名へマッピングし、
# BoneMap リソースを生成・保存する。


func _init() -> void:
	var profile: SkeletonProfileHumanoid = SkeletonProfileHumanoid.new()
	var bone_map: BoneMap = BoneMap.new()
	bone_map.profile = profile

	# ソース (glTF) の全ボーン名。inspect_motion.gd の出力から取得。
	var source_bones: PackedStringArray = PackedStringArray([
		"root", "DEF-hips", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003",
		"DEF-neck", "DEF-head",
		"DEF-shoulder.L", "DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L",
		"DEF-f_index.01.L", "DEF-f_index.02.L", "DEF-f_index.03.L",
		"DEF-f_middle.01.L", "DEF-f_middle.02.L", "DEF-f_middle.03.L",
		"DEF-f_pinky.01.L", "DEF-f_pinky.02.L", "DEF-f_pinky.03.L",
		"DEF-f_ring.01.L", "DEF-f_ring.02.L", "DEF-f_ring.03.L",
		"DEF-thumb.01.L", "DEF-thumb.02.L", "DEF-thumb.03.L",
		"DEF-shoulder.R", "DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R",
		"DEF-f_index.01.R", "DEF-f_index.02.R", "DEF-f_index.03.R",
		"DEF-f_middle.01.R", "DEF-f_middle.02.R", "DEF-f_middle.03.R",
		"DEF-f_pinky.01.R", "DEF-f_pinky.02.R", "DEF-f_pinky.03.R",
		"DEF-f_ring.01.R", "DEF-f_ring.02.R", "DEF-f_ring.03.R",
		"DEF-thumb.01.R", "DEF-thumb.02.R", "DEF-thumb.03.R",
		"DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "DEF-toe.L",
		"DEF-thigh.R", "DEF-shin.R", "DEF-foot.R", "DEF-toe.R",
	])

	# SkeletonProfileHumanoid のプロファイルボーン名 -> ソースボーン名 の明示エイリアス表。
	# Rigify DEF- 命名に対する対応。指ボーンも可能な範囲でマップする。
	var alias: Dictionary = {
		"Root": "root",
		"Hips": "DEF-hips",
		"Spine": "DEF-spine.001",
		"Chest": "DEF-spine.002",
		"UpperChest": "DEF-spine.003",
		"Neck": "DEF-neck",
		"Head": "DEF-head",

		"LeftShoulder": "DEF-shoulder.L",
		"LeftUpperArm": "DEF-upper_arm.L",
		"LeftLowerArm": "DEF-forearm.L",
		"LeftHand": "DEF-hand.L",
		"RightShoulder": "DEF-shoulder.R",
		"RightUpperArm": "DEF-upper_arm.R",
		"RightLowerArm": "DEF-forearm.R",
		"RightHand": "DEF-hand.R",

		"LeftUpperLeg": "DEF-thigh.L",
		"LeftLowerLeg": "DEF-shin.L",
		"LeftFoot": "DEF-foot.L",
		"LeftToes": "DEF-toe.L",
		"RightUpperLeg": "DEF-thigh.R",
		"RightLowerLeg": "DEF-shin.R",
		"RightFoot": "DEF-foot.R",
		"RightToes": "DEF-toe.R",

		# 指 (左)
		"LeftThumbMetacarpal": "DEF-thumb.01.L",
		"LeftThumbProximal": "DEF-thumb.02.L",
		"LeftThumbDistal": "DEF-thumb.03.L",
		"LeftIndexProximal": "DEF-f_index.01.L",
		"LeftIndexIntermediate": "DEF-f_index.02.L",
		"LeftIndexDistal": "DEF-f_index.03.L",
		"LeftMiddleProximal": "DEF-f_middle.01.L",
		"LeftMiddleIntermediate": "DEF-f_middle.02.L",
		"LeftMiddleDistal": "DEF-f_middle.03.L",
		"LeftRingProximal": "DEF-f_ring.01.L",
		"LeftRingIntermediate": "DEF-f_ring.02.L",
		"LeftRingDistal": "DEF-f_ring.03.L",
		"LeftLittleProximal": "DEF-f_pinky.01.L",
		"LeftLittleIntermediate": "DEF-f_pinky.02.L",
		"LeftLittleDistal": "DEF-f_pinky.03.L",

		# 指 (右)
		"RightThumbMetacarpal": "DEF-thumb.01.R",
		"RightThumbProximal": "DEF-thumb.02.R",
		"RightThumbDistal": "DEF-thumb.03.R",
		"RightIndexProximal": "DEF-f_index.01.R",
		"RightIndexIntermediate": "DEF-f_index.02.R",
		"RightIndexDistal": "DEF-f_index.03.R",
		"RightMiddleProximal": "DEF-f_middle.01.R",
		"RightMiddleIntermediate": "DEF-f_middle.02.R",
		"RightMiddleDistal": "DEF-f_middle.03.R",
		"RightRingProximal": "DEF-f_ring.01.R",
		"RightRingIntermediate": "DEF-f_ring.02.R",
		"RightRingDistal": "DEF-f_ring.03.R",
		"RightLittleProximal": "DEF-f_pinky.01.R",
		"RightLittleIntermediate": "DEF-f_pinky.02.R",
		"RightLittleDistal": "DEF-f_pinky.03.R",
	}

	# 小文字化した完全一致用の索引
	var lower_index: Dictionary = {}
	for sb in source_bones:
		lower_index[sb.to_lower()] = sb

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

		# 1) 完全一致
		for sb in source_bones:
			if sb == pbone:
				resolved = sb
				break
		# 2) 大文字小文字無視
		if resolved == "":
			if lower_index.has(pbone.to_lower()):
				resolved = lower_index[pbone.to_lower()]
		# 3) 既知エイリアス
		if resolved == "" and alias.has(pbone):
			var cand: String = alias[pbone]
			# エイリアス先が実在するボーンか確認
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

	# 必須ボーンの充足チェック
	var missing_required: PackedStringArray = PackedStringArray()
	for r in required:
		if unmapped.has(r):
			missing_required.append(r)
	if missing_required.size() > 0:
		print("[FAIL] required bones unmapped: ", missing_required)
	else:
		print("[OK] all required (Hips/Spine/limbs/Head) mapped")

	var out_path: String = "res://assets/motions/universal_animation_library_bone_map.tres"
	var err: int = ResourceSaver.save(bone_map, out_path)
	if err != OK:
		print("[ERROR] save failed err=", err)
		quit(1)
		return
	print("=== saved: ", out_path, " ===")
	quit(0)
