extends SceneTree

# Mixamo FBX (Godot ufbx が sanitize した命名) のソースボーン名を
# SkeletonProfileHumanoid のプロファイルボーン名へマッピングし、
# BoneMap リソースを生成・保存する。
#
# 注意: Mixamo 元来の命名は "mixamorig:Hips" だが、Godot 4.7 の ufbx インポータは
# コロンを含む名前を "mixamorig4_Hips" 等に sanitize する (inspect_mixamo.gd で確認)。
# 数字はダウンロードごとに変わりうるため、--prefix と --output で切り替えられる。
# BoneMap のソース側名はインポート後のスケルトンのボーン名と一致させる必要があるため
# sanitize 後の接頭辞を用いる。引数なしの場合は従来どおり mixamorig4_ 版を同じパスへ出力する。

const DEFAULT_PREFIX: String = "mixamorig4_"
const DEFAULT_OUTPUT: String = "res://assets/motions/mixamo_bone_map.tres"


func _init() -> void:
	var profile: SkeletonProfileHumanoid = SkeletonProfileHumanoid.new()
	var bone_map: BoneMap = BoneMap.new()
	bone_map.profile = profile

	var options: Dictionary = _parse_options(OS.get_cmdline_user_args())
	if options.is_empty():
		quit(1)
		return
	var prefix: String = options["prefix"]
	var out_path: String = options["output"]

	# ソース (FBX) の全ボーン名。inspect_mixamo.gd の出力から取得 (65 本)。
	var source_bones: PackedStringArray = PackedStringArray([
		prefix + "Hips", prefix + "Spine", prefix + "Spine1", prefix + "Spine2", prefix + "Neck", prefix + "Head", prefix + "HeadTop_End",
		prefix + "LeftShoulder", prefix + "LeftArm", prefix + "LeftForeArm", prefix + "LeftHand",
		prefix + "LeftHandThumb1", prefix + "LeftHandThumb2", prefix + "LeftHandThumb3", prefix + "LeftHandThumb4",
		prefix + "LeftHandIndex1", prefix + "LeftHandIndex2", prefix + "LeftHandIndex3", prefix + "LeftHandIndex4",
		prefix + "LeftHandMiddle1", prefix + "LeftHandMiddle2", prefix + "LeftHandMiddle3", prefix + "LeftHandMiddle4",
		prefix + "LeftHandRing1", prefix + "LeftHandRing2", prefix + "LeftHandRing3", prefix + "LeftHandRing4",
		prefix + "LeftHandPinky1", prefix + "LeftHandPinky2", prefix + "LeftHandPinky3", prefix + "LeftHandPinky4",
		prefix + "RightShoulder", prefix + "RightArm", prefix + "RightForeArm", prefix + "RightHand",
		prefix + "RightHandThumb1", prefix + "RightHandThumb2", prefix + "RightHandThumb3", prefix + "RightHandThumb4",
		prefix + "RightHandIndex1", prefix + "RightHandIndex2", prefix + "RightHandIndex3", prefix + "RightHandIndex4",
		prefix + "RightHandMiddle1", prefix + "RightHandMiddle2", prefix + "RightHandMiddle3", prefix + "RightHandMiddle4",
		prefix + "RightHandRing1", prefix + "RightHandRing2", prefix + "RightHandRing3", prefix + "RightHandRing4",
		prefix + "RightHandPinky1", prefix + "RightHandPinky2", prefix + "RightHandPinky3", prefix + "RightHandPinky4",
		prefix + "LeftUpLeg", prefix + "LeftLeg", prefix + "LeftFoot", prefix + "LeftToeBase", prefix + "LeftToe_End",
		prefix + "RightUpLeg", prefix + "RightLeg", prefix + "RightFoot", prefix + "RightToeBase", prefix + "RightToe_End",
	])

	# SkeletonProfileHumanoid のプロファイルボーン名 -> ソースボーン名 の明示エイリアス表。
	# Mixamo は Spine/Spine1/Spine2 の 3 段。プロファイルは Spine/Chest/UpperChest。
	#   Spine <- Spine, Chest <- Spine1, UpperChest <- Spine2。
	# Mixamo の指は Thumb1..4 (4 段) だが末尾 (4) は指先端 (End) なので Distal までの 3 段に割当。
	#   Proximal <- 1, Intermediate <- 2, Distal <- 3 (親指は Metacarpal/Proximal/Distal <- 1/2/3)。
	var alias: Dictionary = {
		"Hips": prefix + "Hips",
		"Spine": prefix + "Spine",
		"Chest": prefix + "Spine1",
		"UpperChest": prefix + "Spine2",
		"Neck": prefix + "Neck",
		"Head": prefix + "Head",

		"LeftShoulder": prefix + "LeftShoulder",
		"LeftUpperArm": prefix + "LeftArm",
		"LeftLowerArm": prefix + "LeftForeArm",
		"LeftHand": prefix + "LeftHand",
		"RightShoulder": prefix + "RightShoulder",
		"RightUpperArm": prefix + "RightArm",
		"RightLowerArm": prefix + "RightForeArm",
		"RightHand": prefix + "RightHand",

		"LeftUpperLeg": prefix + "LeftUpLeg",
		"LeftLowerLeg": prefix + "LeftLeg",
		"LeftFoot": prefix + "LeftFoot",
		"LeftToes": prefix + "LeftToeBase",
		"RightUpperLeg": prefix + "RightUpLeg",
		"RightLowerLeg": prefix + "RightLeg",
		"RightFoot": prefix + "RightFoot",
		"RightToes": prefix + "RightToeBase",

		# 指 (左)
		"LeftThumbMetacarpal": prefix + "LeftHandThumb1",
		"LeftThumbProximal": prefix + "LeftHandThumb2",
		"LeftThumbDistal": prefix + "LeftHandThumb3",
		"LeftIndexProximal": prefix + "LeftHandIndex1",
		"LeftIndexIntermediate": prefix + "LeftHandIndex2",
		"LeftIndexDistal": prefix + "LeftHandIndex3",
		"LeftMiddleProximal": prefix + "LeftHandMiddle1",
		"LeftMiddleIntermediate": prefix + "LeftHandMiddle2",
		"LeftMiddleDistal": prefix + "LeftHandMiddle3",
		"LeftRingProximal": prefix + "LeftHandRing1",
		"LeftRingIntermediate": prefix + "LeftHandRing2",
		"LeftRingDistal": prefix + "LeftHandRing3",
		"LeftLittleProximal": prefix + "LeftHandPinky1",
		"LeftLittleIntermediate": prefix + "LeftHandPinky2",
		"LeftLittleDistal": prefix + "LeftHandPinky3",

		# 指 (右)
		"RightThumbMetacarpal": prefix + "RightHandThumb1",
		"RightThumbProximal": prefix + "RightHandThumb2",
		"RightThumbDistal": prefix + "RightHandThumb3",
		"RightIndexProximal": prefix + "RightHandIndex1",
		"RightIndexIntermediate": prefix + "RightHandIndex2",
		"RightIndexDistal": prefix + "RightHandIndex3",
		"RightMiddleProximal": prefix + "RightHandMiddle1",
		"RightMiddleIntermediate": prefix + "RightHandMiddle2",
		"RightMiddleDistal": prefix + "RightHandMiddle3",
		"RightRingProximal": prefix + "RightHandRing1",
		"RightRingIntermediate": prefix + "RightHandRing2",
		"RightRingDistal": prefix + "RightHandRing3",
		"RightLittleProximal": prefix + "RightHandPinky1",
		"RightLittleIntermediate": prefix + "RightHandPinky2",
		"RightLittleDistal": prefix + "RightHandPinky3",
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

	var err: int = ResourceSaver.save(bone_map, out_path)
	if err != OK:
		print("[ERROR] save failed err=", err)
		quit(1)
		return
	print("=== saved: ", out_path, " ===")
	quit(0)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var prefix: String = DEFAULT_PREFIX
	var output: String = DEFAULT_OUTPUT
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--prefix" or arg == "--output":
			if i + 1 >= args.size():
				print("[ERROR] value missing for ", arg)
				return {}
			if arg == "--prefix":
				prefix = args[i + 1]
			else:
				output = args[i + 1]
			i += 2
			continue
		print("[ERROR] unknown argument: ", arg)
		return {}
	if prefix.is_empty() or output.is_empty():
		print("[ERROR] prefix/output must not be empty")
		return {}
	return {"prefix": prefix, "output": output}
