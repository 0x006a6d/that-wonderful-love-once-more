extends SceneTree

## リターゲット済みキャラクター FBX に、既存の Mixamo モーションがそのまま
## 適用できるかを確認する。ボーン名が GeneralSkeleton のプロファイル名へ
## 揃っていれば、モーション側のトラックがそのまま解決するはず。
##
## あわせて、ルートモーションを潰す処理が効いているかも見る。位置は
## CharacterBody3D が持つので、クリップが体を運ぶと見た目と当たり判定がずれる。
##
## 実行: godot --path . --headless --script tools/test_character_anim.gd

const CHARACTERS: PackedStringArray = [
	"res://assets/characters/mixamo_ch01.fbx",
	"res://assets/characters/mixamo_ch08.fbx",
	"res://assets/characters/mixamo_ch16.fbx",
	"res://assets/characters/mixamo_ch28.fbx",
]
const MOTIONS: PackedStringArray = [
	"res://assets/motions/mixamo_idle.fbx",
	"res://assets/motions/mixamo_walk.fbx",
	"res://assets/motions/mixamo_death_backward_01.fbx",
	"res://assets/motions/mixamo_hit_head.fbx",
	"res://assets/motions/mixamo_dying.fbx",
	"res://assets/motions/mixamo_walk_female.fbx",
	"res://assets/motions/mixamo_step_forward.fbx",
	"res://assets/motions/mixamo_kip_up.fbx",
]
const CLIP_NAME: String = "mixamo_com"
## 姿勢の差分を見るボーン。位置トラックを持つ Hips と、回転が大きい四肢を含める。
const SAMPLE_BONES: PackedStringArray = [
	"Hips", "Spine", "Head", "LeftUpperArm", "RightUpperArm", "LeftLowerLeg", "RightLowerLeg",
]
## 姿勢が動いたと判定する最小差分（m または rad）。
const MOVED_EPSILON: float = 0.001

var _failures: int = 0


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_anim_player(child)
		if found != null:
			return found
	return null


func _load_clip(path: String) -> Animation:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var ap: AnimationPlayer = _find_anim_player(inst)
	var clip: Animation = null
	if ap != null and ap.has_animation(CLIP_NAME):
		clip = ap.get_animation(CLIP_NAME).duplicate() as Animation
	inst.free()
	return clip


func _sample_pose(skel: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for bone_name in SAMPLE_BONES:
		var index: int = skel.find_bone(bone_name)
		poses.append(Transform3D.IDENTITY if index < 0 else skel.get_bone_pose(index))
	return poses


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)
		_failures += 1


func _init() -> void:
	var clips: Dictionary = {}
	for motion_path in MOTIONS:
		var clip: Animation = _load_clip(motion_path)
		clips[motion_path] = clip
		if clip == null:
			print("[FAIL] モーションを読めない: ", motion_path)
			_failures += 1

	for char_path in CHARACTERS:
		print("--- ", char_path.get_file(), " ---")
		var packed: PackedScene = load(char_path) as PackedScene
		if packed == null:
			print("  [FAIL] 読み込み失敗")
			_failures += 1
			continue
		var inst: Node3D = packed.instantiate() as Node3D
		root.add_child(inst)

		var skel: Skeleton3D = _find_skeleton(inst)
		_check("GeneralSkeleton がある", skel != null and skel.name == "GeneralSkeleton")
		if skel == null:
			inst.queue_free()
			continue

		var player := AnimationPlayer.new()
		player.name = "TestPlayer"
		inst.add_child(player)
		player.root_node = ^".."

		var library := AnimationLibrary.new()
		for motion_path in MOTIONS:
			var clip: Animation = clips[motion_path] as Animation
			if clip != null:
				library.add_animation(motion_path.get_file().get_basename(), clip)
		player.add_animation_library(&"test", library)

		for motion_path in MOTIONS:
			var clip_key: String = "test/" + motion_path.get_file().get_basename()
			if not player.has_animation(clip_key):
				continue
			var clip: Animation = player.get_animation(clip_key)
			player.play(clip_key)
			player.seek(0.0, true)
			var pose_start: Array[Transform3D] = _sample_pose(skel)
			player.seek(clip.length * 0.5, true)
			var pose_mid: Array[Transform3D] = _sample_pose(skel)

			var moved: float = 0.0
			for i in range(pose_start.size()):
				moved = maxf(moved, pose_start[i].origin.distance_to(pose_mid[i].origin))
				moved = maxf(moved,
					pose_start[i].basis.get_rotation_quaternion().angle_to(
						pose_mid[i].basis.get_rotation_quaternion()))
			_check("%s が姿勢を動かす (差分 %.4f)" % [motion_path.get_file(), moved],
				moved > MOVED_EPSILON)

			# 未解決トラックがあると Godot は警告のみで無音失敗するため、
			# トラックのノードパスが実在するかを直接確かめる。
			var unresolved: int = 0
			for t in range(clip.get_track_count()):
				var track_path: NodePath = clip.track_get_path(t)
				if inst.get_node_or_null(NodePath(track_path.get_concatenated_names())) == null:
					unresolved += 1
			_check("%s の全トラックが解決する (未解決 %d/%d)"
				% [motion_path.get_file(), unresolved, clip.get_track_count()],
				unresolved == 0)

		inst.queue_free()

	# ルートモーションを潰す処理の回帰チェック。
	print("--- ルートモーション ---")
	for motion_path in MOTIONS:
		var clip: Animation = clips[motion_path] as Animation
		if clip == null:
			continue
		var locked: Animation = clip.duplicate() as Animation
		RootMotion.lock_horizontal(locked)
		var before: float = RootMotion.horizontal_travel(clip)
		var after: float = RootMotion.horizontal_travel(locked)
		_check("%s の水平移動が消える (%.3f m -> %.3f m)"
			% [motion_path.get_file(), before, after], after <= MOVED_EPSILON)

	print("")
	if _failures == 0:
		print("[OK] 全チェック PASS")
		quit(0)
	else:
		print("[NG] 失敗 ", _failures, " 件")
		quit(1)
