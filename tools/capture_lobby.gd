extends Node3D

## 銀行ロビーの俯瞰キャプチャ。描画結果を取得するため、--headless ではなく
## ウィンドウありで実行すること。

const LOBBY_SCENE_PATH: String = "res://levels/bank_lobby.tscn"
const OUTPUT_DIRECTORY: String = "res://docs/img"
const OUTPUT_PATH: String = "res://docs/img/bank_lobby_top.png"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 1024)
const CAMERA_HEIGHT: float = 25.0
const ORTHOGONAL_SIZE: float = 22.0
const SETTLE_FRAMES: int = 5
const COVER_GROUP: StringName = &"cover"

const COVER_COLOR: Color = Color(0.95, 0.08, 0.08, 1.0)
const PATROL_COLOR: Color = Color(1.0, 0.9, 0.05, 1.0)
const PLAYER_COLOR: Color = Color(0.05, 0.25, 1.0, 1.0)
const ROBBER_COLOR: Color = Color(1.0, 0.38, 0.02, 1.0)
const CIVILIAN_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const SMALL_MARKER_RADIUS: float = 0.25
const LARGE_MARKER_RADIUS: float = 0.35


func _ready() -> void:
	get_window().size = CAPTURE_SIZE

	var packed := load(LOBBY_SCENE_PATH) as PackedScene
	if packed == null:
		printerr("[capture_lobby] bank_lobby.tscn を読み込めませんでした")
		get_tree().quit(1)
		return

	var lobby := packed.instantiate() as Node3D
	if lobby == null:
		printerr("[capture_lobby] bank_lobby.tscn をインスタンス化できませんでした")
		get_tree().quit(1)
		return
	add_child(lobby)
	_hide_runtime_characters(lobby)
	_add_overlays(lobby)
	_add_top_camera()

	for _frame: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var directory_path: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		printerr("[capture_lobby] 出力ディレクトリを作成できませんでした: %s" % directory_path)
		get_tree().quit(1)
		return

	var save_error: Error = image.save_png(OUTPUT_PATH)
	if save_error != OK:
		printerr("[capture_lobby] PNGを保存できませんでした: %s" % OUTPUT_PATH)
		get_tree().quit(1)
		return

	var absolute_path: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	print("[capture_lobby] saved: %s" % absolute_path)
	print("[capture_lobby] image size: %d x %d" % [image.get_width(), image.get_height()])
	get_tree().quit()


func _hide_runtime_characters(lobby: Node3D) -> void:
	var player := lobby.get_node_or_null(^"Player") as Node3D
	if player != null:
		player.visible = false


func _add_overlays(lobby: Node3D) -> void:
	var overlay_root := Node3D.new()
	overlay_root.name = "CaptureOverlays"
	add_child(overlay_root)

	for cover_node: Node in get_tree().get_nodes_in_group(COVER_GROUP):
		var cover_marker := cover_node as Marker3D
		if cover_marker != null and lobby.is_ancestor_of(cover_marker):
			_add_sphere(overlay_root, cover_marker.global_position,
				SMALL_MARKER_RADIUS, COVER_COLOR)

	for child: Node in lobby.get_children():
		var marker := child as Marker3D
		if marker == null:
			continue
		var marker_name: String = String(marker.name)
		if marker_name.begins_with("Patrol_"):
			_add_sphere(overlay_root, marker.global_position,
				SMALL_MARKER_RADIUS, PATROL_COLOR)
		elif marker_name == "PlayerSpawn":
			_add_sphere(overlay_root, marker.global_position,
				LARGE_MARKER_RADIUS, PLAYER_COLOR)
		elif marker_name.begins_with("RobberSpawn"):
			_add_sphere(overlay_root, marker.global_position,
				LARGE_MARKER_RADIUS, ROBBER_COLOR)
		elif marker_name.begins_with("CivilianSpawn"):
			_add_sphere(overlay_root, marker.global_position,
				SMALL_MARKER_RADIUS, CIVILIAN_COLOR)


func _add_sphere(parent: Node3D, position: Vector3, radius: float, color: Color) -> void:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	sphere.mesh = mesh
	sphere.position = position
	parent.add_child(sphere)


func _add_top_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "TopCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ORTHOGONAL_SIZE
	camera.position = Vector3(0.0, CAMERA_HEIGHT, 0.0)
	add_child(camera)
	# 視線は真下、画面上方向は北 (-Z)。
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.make_current.call_deferred()
