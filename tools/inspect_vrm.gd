extends SceneTree


func _walk(node: Node, depth: int) -> void:
	var indent: String = ""
	for i in range(depth):
		indent += "  "
	print(indent, node.name, " (", node.get_class(), ")")
	for c in node.get_children():
		_walk(c, depth + 1)


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r: Node = _find(c, cls)
		if r != null:
			return r
	return null


func _init() -> void:
	var packed: PackedScene = load("res://assets/vrm/nikechan_player.vrm") as PackedScene
	var inst: Node = packed.instantiate()
	print("=== VRM scene tree ===")
	_walk(inst, 0)
	var skel: Node = _find(inst, "Skeleton3D")
	if skel != null:
		print("=== Skeleton3D name: ", skel.name, " path: ", inst.get_path_to(skel), " ===")
	var ap: Node = _find(inst, "AnimationPlayer")
	if ap != null:
		print("=== AnimationPlayer path: ", inst.get_path_to(ap), " ===")
	else:
		print("=== no AnimationPlayer in VRM ===")
	inst.free()
	quit(0)
