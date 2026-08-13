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
	var inst: Node = packed.instantiate()

	var skel: Skeleton3D = _find_skeleton(inst)
	print("=== Skeleton3D node name after retarget: ", skel.name, " ===")
	print("=== first 8 bone names ===")
	for i in range(min(8, skel.get_bone_count())):
		print("  bone[", i, "] = ", skel.get_bone_name(i))

	var ap: AnimationPlayer = _find_anim_player(inst)
	if ap.has_animation("Punch_Cross"):
		var anim: Animation = ap.get_animation("Punch_Cross")
		print("=== Punch_Cross track paths (first 10) ===")
		for t in range(min(10, anim.get_track_count())):
			print("  track[", t, "] path=", anim.track_get_path(t))

	inst.free()
	quit(0)
