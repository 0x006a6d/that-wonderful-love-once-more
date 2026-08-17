extends Node3D

## 差し替え後の NPC シーン（役割3種＋客）を並べて撮る QC 用キャプチャ。
## キャラクターが入っているか、向きが合っているか、床にめり込んでいないかを見る。
## 描画結果が要るので --headless では実行しない。
##
## 実行: godot --path . tools/capture_npcs.tscn

const OUTPUT_PATH: String = "res://docs/img/qc_npcs.png"
const CAPTURE_SIZE: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 30
const SPACING: float = 1.5
const CAMERA_HEIGHT: float = 1.0
const CAMERA_DISTANCE: float = 4.2

const NPCS: Array[Dictionary] = [
	{"label": "Leader", "path": "res://actors/npc/roles/leader.tscn"},
	{"label": "Gunner", "path": "res://actors/npc/roles/gunner.tscn"},
	{"label": "Erratic", "path": "res://actors/npc/roles/erratic.tscn"},
	{"label": "Civilian", "path": "res://actors/npc/civilian.tscn"},
]


var _toon: bool = true
var _output_path: String = OUTPUT_PATH
## アウトラインの太さを上書きして見比べるための一時指定（負なら既定のまま）。
var _outline_width: float = -1.0


func _ready() -> void:
	_parse_options(OS.get_cmdline_user_args())
	get_window().size = CAPTURE_SIZE
	_add_environment()
	_add_floor()

	var count: int = NPCS.size()
	var left: float = -SPACING * float(count - 1) * 0.5
	for i in range(count):
		var entry: Dictionary = NPCS[i]
		_add_npc(entry["path"] as String, entry["label"] as String,
			left + SPACING * float(i))

	_add_camera()

	for _frame: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var save_error: Error = image.save_png(_output_path)
	if save_error != OK:
		printerr("[capture_npcs] PNGを保存できませんでした: %s" % _output_path)
		get_tree().quit(1)
		return
	print("[capture_npcs] saved: %s" % ProjectSettings.globalize_path(_output_path))
	get_tree().quit()


func _add_npc(path: String, label: String, x: float) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		printerr("[capture_npcs] 読み込めませんでした: %s" % path)
		return
	var npc := packed.instantiate() as Node3D
	if npc == null:
		return
	npc.position = Vector3(x, 0.0, 0.0)
	# NPC の前方は -Z。カメラは +Z 側にいるので、正面を向かせるため半回転させる。
	npc.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	if not _toon:
		npc.set("toon_skin", false)
	add_child(npc)
	if _toon and _outline_width >= 0.0:
		_override_outline_width(npc)

	var text := Label3D.new()
	text.text = label
	text.font_size = 72
	text.pixel_size = 0.002
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.position = Vector3(x, 2.1, 0.0)
	add_child(text)


func _parse_options(args: PackedStringArray) -> void:
	var i: int = 0
	while i + 1 < args.size():
		match args[i]:
			"--toon":
				_toon = args[i + 1] != "off"
			"--output":
				_output_path = args[i + 1]
			"--outline":
				_outline_width = args[i + 1].to_float()
		i += 2


func _override_outline_width(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface in range(instance.get_surface_override_material_count()):
			var material := instance.get_surface_override_material(surface) as ShaderMaterial
			if material == null:
				continue
			var outline := material.next_pass as ShaderMaterial
			if outline != null:
				outline.set_shader_parameter("_OutlineWidth", _outline_width)
	for child in node.get_children():
		_override_outline_width(child)


func _add_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.31, 0.34)
	plane.material = material
	floor_mesh.mesh = plane
	add_child(floor_mesh)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.2, 20.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.1, 0.0)
	body.add_child(shape)
	add_child(body)


func _add_environment() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.17, 0.20)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.76, 0.80)
	environment.ambient_light_energy = 1.0
	env.environment = environment
	add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	light.light_energy = 1.2
	add_child(light)


func _add_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, CAMERA_HEIGHT, CAMERA_DISTANCE)
	add_child(camera)
	camera.look_at(Vector3(0.0, CAMERA_HEIGHT, 0.0), Vector3.UP)
	camera.make_current.call_deferred()
