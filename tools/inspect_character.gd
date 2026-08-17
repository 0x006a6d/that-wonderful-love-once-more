extends SceneTree

## Mixamo キャラクター FBX (With Skin) の中身を調べる。
## 差し替え前に、スケルトンの接頭辞・メッシュ構成・身長を把握するために使う。
## 実行: godot --path . --headless --script tools/inspect_character.gd

const PATHS: PackedStringArray = [
	"res://assets/characters/mixamo_ch01.fbx",
	"res://assets/characters/mixamo_ch08.fbx",
	"res://assets/characters/mixamo_ch16.fbx",
	"res://assets/characters/mixamo_ch28.fbx",
]


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_anim_player(child)
		if found != null:
			return found
	return null


func _report(path: String) -> void:
	print("")
	print("========== ", path, " ==========")
	if not ResourceLoader.exists(path):
		print("[ERROR] not found")
		return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		print("[ERROR] load failed")
		return
	var inst: Node = packed.instantiate()
	print("root: ", inst.name, " (", inst.get_class(), ")")

	var skel: Skeleton3D = _find_skeleton(inst)
	if skel == null:
		print("[ERROR] no Skeleton3D")
	else:
		var count: int = skel.get_bone_count()
		print("skeleton: ", inst.get_path_to(skel), "  bones=", count)
		if count > 0:
			print("  bone[0]=", skel.get_bone_name(0))
			for i in range(count):
				var bone_name: String = skel.get_bone_name(i)
				if bone_name.ends_with("Hips") or bone_name.ends_with("Head"):
					print("  ", bone_name)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(inst, meshes)
	print("mesh instances: ", meshes.size())
	var total_verts: int = 0
	var aabb: AABB = AABB()
	var first: bool = true
	for mi in meshes:
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var surfaces: int = mesh.get_surface_count()
		var verts: int = 0
		for s in range(surfaces):
			var arrays: Array = mesh.surface_get_arrays(s)
			var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			verts += pos.size()
		total_verts += verts
		var mat_names: PackedStringArray = []
		for s in range(surfaces):
			var mat: Material = mesh.surface_get_material(s)
			mat_names.append("<null>" if mat == null else mat.resource_name)
		print("  ", mi.name, "  surfaces=", surfaces, " verts=", verts, " materials=", mat_names)
		var box: AABB = mi.get_aabb()
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	print("total verts: ", total_verts)
	print("aabb: pos=", aabb.position, " size=", aabb.size, "  (height=", aabb.size.y, ")")

	var ap: AnimationPlayer = _find_anim_player(inst)
	if ap != null:
		print("animations: ", ap.get_animation_list())

	inst.free()


func _init() -> void:
	for path in PATHS:
		_report(path)
	quit(0)
