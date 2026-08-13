extends SceneTree

# Mixamo FBX 3 本のシーン構造・ボーン名・アニメ名・トラック数を調べる。
# 使い方: godot --path . --headless --script tools/inspect_mixamo.gd

const FBXS: Array[String] = [
	"res://assets/motions/mixamo_cross_punch.fbx",
	"res://assets/motions/mixamo_combo_punch.fbx",
	"res://assets/motions/mixamo_punch_combo.fbx",
]


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


func _has_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child in node.get_children():
		if _has_mesh(child):
			return true
	return false


func _init() -> void:
	var all_bone_sets: Array = []
	for path in FBXS:
		print("\n########## ", path, " ##########")
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			print("[ERROR] load failed: ", path)
			continue
		var inst: Node = packed.instantiate()
		print("root node: ", inst.name, " (", inst.get_class(), ")")
		print("has mesh (MeshInstance3D): ", _has_mesh(inst))

		var skel: Skeleton3D = _find_skeleton(inst)
		if skel == null:
			print("[ERROR] no Skeleton3D found")
		else:
			print("Skeleton3D node name: ", skel.name)
			print("Skeleton3D scene path (from root): ", inst.get_path_to(skel))
			var count: int = skel.get_bone_count()
			print("bone count: ", count)
			var names: PackedStringArray = PackedStringArray()
			for i in range(count):
				names.append(skel.get_bone_name(i))
			all_bone_sets.append(names)
			for i in range(count):
				print("  bone[", i, "] = ", names[i])

		var ap: AnimationPlayer = _find_anim_player(inst)
		if ap == null:
			print("[ERROR] no AnimationPlayer found")
		else:
			print("AnimationPlayer node name: ", ap.name)
			var libs: PackedStringArray = ap.get_animation_library_list()
			for lib_name in libs:
				var lib: AnimationLibrary = ap.get_animation_library(lib_name)
				print("library: '", lib_name, "' anims: ", lib.get_animation_list().size())
				for a in lib.get_animation_list():
					var anim: Animation = lib.get_animation(a)
					print("  anim: '", a, "' len=", "%.3f" % anim.length, " tracks=", anim.get_track_count())

		inst.free()

	# 3 本のボーン名一致確認
	print("\n########## bone-set identity check ##########")
	if all_bone_sets.size() >= 2:
		var base: PackedStringArray = all_bone_sets[0]
		var all_same: bool = true
		for i in range(1, all_bone_sets.size()):
			var other: PackedStringArray = all_bone_sets[i]
			if base != other:
				all_same = false
				print("[DIFF] set[0] vs set[", i, "] differ (sizes ", base.size(), " vs ", other.size(), ")")
		if all_same:
			print("[OK] all ", all_bone_sets.size(), " skeletons have identical bone names")

	quit(0)
