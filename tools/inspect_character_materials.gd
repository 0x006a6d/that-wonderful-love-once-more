extends SceneTree

## キャラクター FBX の各サーフェスのマテリアル設定を出す。
## 髪・まつ毛のアルファ抜きが効いているか（透過設定が付いているか）を見るために使う。
## 実行: godot --path . --headless --script tools/inspect_character_materials.gd

const PATHS: PackedStringArray = [
	"res://assets/characters/mixamo_ch01.fbx",
	"res://assets/characters/mixamo_ch08.fbx",
	"res://assets/characters/mixamo_ch16.fbx",
	"res://assets/characters/mixamo_ch28.fbx",
]

const TRANSPARENCY_NAMES: PackedStringArray = [
	"DISABLED", "ALPHA", "ALPHA_SCISSOR", "ALPHA_HASH", "DEPTH_PRE_PASS", "MAX",
]
const CULL_NAMES: PackedStringArray = ["BACK", "FRONT", "DISABLED"]


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _init() -> void:
	for path in PATHS:
		print("")
		print("========== ", path.get_file(), " ==========")
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			print("[ERROR] load failed")
			continue
		var inst: Node = packed.instantiate()
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(inst, meshes)
		for mi in meshes:
			var mesh: Mesh = mi.mesh
			if mesh == null:
				continue
			for s in range(mesh.get_surface_count()):
				var mat: Material = mesh.surface_get_material(s)
				if mat == null:
					print("  ", mi.name, "[", s, "] material=<null>")
					continue
				if not (mat is StandardMaterial3D):
					print("  ", mi.name, "[", s, "] material=", mat.get_class(),
						" name=", mat.resource_name)
					continue
				var std := mat as StandardMaterial3D
				var albedo: Texture2D = std.albedo_texture
				var albedo_name: String = "<none>"
				if albedo != null:
					albedo_name = albedo.resource_path.get_file()
				print("  ", mi.name, "[", s, "] name=", std.resource_name,
					" transparency=", TRANSPARENCY_NAMES[std.transparency],
					" cull=", CULL_NAMES[std.cull_mode],
					" alpha_scissor=", std.alpha_scissor_threshold,
					" albedo=", albedo_name,
					" albedo_color=", std.albedo_color)
		inst.free()
	quit(0)
