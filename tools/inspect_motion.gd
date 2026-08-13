extends SceneTree


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


func _init() -> void:
	var path: String = "res://assets/motions/universal_animation_library.gltf"
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		print("[ERROR] load failed: ", path)
		quit(1)
		return
	var inst: Node = packed.instantiate()
	print("=== root node: ", inst.name, " (", inst.get_class(), ") ===")

	var skel: Skeleton3D = _find_skeleton(inst)
	if skel == null:
		print("[ERROR] no Skeleton3D found")
	else:
		print("=== Skeleton3D node name: ", skel.name, " ===")
		print("=== Skeleton3D scene path: ", inst.get_path_to(skel), " ===")
		var count: int = skel.get_bone_count()
		print("=== bone count: ", count, " ===")
		for i in range(count):
			print("bone[", i, "] = ", skel.get_bone_name(i))

	var ap: AnimationPlayer = _find_anim_player(inst)
	if ap == null:
		print("[ERROR] no AnimationPlayer found")
	else:
		print("=== AnimationPlayer node name: ", ap.name, " ===")
		var libs: PackedStringArray = ap.get_animation_library_list()
		for lib_name in libs:
			var lib: AnimationLibrary = ap.get_animation_library(lib_name)
			print("=== library: '", lib_name, "' anims: ", lib.get_animation_list().size(), " ===")
			for a in lib.get_animation_list():
				print("  anim: ", a)
		# Track paths of one attack anim
		var all_anims: PackedStringArray = ap.get_animation_list()
		for target in ["Punch_Cross", "Punch_Jab"]:
			if ap.has_animation(target):
				var anim: Animation = ap.get_animation(target)
				print("=== tracks of '", target, "' (len=", anim.length, ", count=", anim.get_track_count(), ") ===")
				for t in range(min(anim.get_track_count(), 12)):
					print("  track[", t, "] type=", anim.track_get_type(t), " path=", anim.track_get_path(t))
				break

	inst.free()
	quit(0)
