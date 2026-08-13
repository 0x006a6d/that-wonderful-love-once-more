extends SceneTree

## universal_animation_library.gltf の AnimationPlayer 内の実アニメ名一覧。
## 実行: godot --path . --headless --script res://tools/probe_univ_names.gd


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _init() -> void:
	var inst := (load("res://assets/motions/universal_animation_library.gltf") as PackedScene).instantiate()
	var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
	print("[libs] ", ap.get_animation_library_list())
	var names: Array[String] = []
	for a in ap.get_animation_list():
		names.append(str(a))
	print("[anims] ", names)
	print("[has Jog_Fwd_Loop] ", ap.has_animation("Jog_Fwd_Loop"))
	print("[has Idle_Loop] ", ap.has_animation("Idle_Loop"))
	inst.free()
	quit(0)
