extends Node3D

## Mixamo キャラクターを正面から並べて撮る QC 用キャプチャ。
## 役割の割り当て（誰をリーダー・ガンナー・不安定型にするか）をシルエットで
## 判断すること、およびリターゲット後にメッシュが崩れていないかの確認に使う。
## 描画結果が要るので --headless では実行しない。
##
## 実行例:
##   godot --path . tools/capture_characters.tscn
##   godot --path . tools/capture_characters.tscn -- \
##     --motion res://assets/motions/mixamo_walk.fbx --time 0.35 \
##     --output res://docs/img/qc_characters_walk.png
##   godot --path . tools/capture_characters.tscn -- \
##     --only Ch28 --distance 0.75 --height 1.62 --output res://docs/img/qc_ch28_head.png

const DEFAULT_OUTPUT_PATH: String = "res://docs/img/qc_characters_lineup.png"
const MOTION_CLIP_NAME: String = "mixamo_com"
const CAPTURE_SIZE: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 10
## T ポーズの両腕は 1.78 m あるので、重ならない間隔を取る。
const SPACING: float = 1.9
const CAMERA_HEIGHT: float = 0.95
const CAMERA_DISTANCE: float = 3.6

const CHARACTERS: Array[Dictionary] = [
	{"label": "Ch01", "path": "res://assets/characters/mixamo_ch01.fbx"},
	{"label": "Ch08", "path": "res://assets/characters/mixamo_ch08.fbx"},
	{"label": "Ch16", "path": "res://assets/characters/mixamo_ch16.fbx"},
	{"label": "Ch28", "path": "res://assets/characters/mixamo_ch28.fbx"},
]

var _motion_path: String = ""
var _motion_time: float = 0.0
var _output_path: String = DEFAULT_OUTPUT_PATH
## 顔まわりの寄りを撮るためのカメラ上書きと、1体だけに絞る指定。
var _only_label: String = ""
var _camera_distance: float = CAMERA_DISTANCE
var _camera_height: float = CAMERA_HEIGHT
## 名前に含まれる文字列で MeshInstance3D を隠す（例: Hair,Eyelashes）。
var _hidden_meshes: PackedStringArray = []


func _ready() -> void:
	_parse_options(OS.get_cmdline_user_args())
	get_window().size = CAPTURE_SIZE

	_add_environment()

	var clip: Animation = _load_clip(_motion_path) if _motion_path != "" else null
	if _motion_path != "" and clip == null:
		printerr("[capture_characters] モーションを読めませんでした: %s" % _motion_path)
		get_tree().quit(1)
		return

	var shown: Array[Dictionary] = []
	for entry in CHARACTERS:
		if _only_label == "" or entry["label"] == _only_label:
			shown.append(entry)
	var count: int = shown.size()
	var left: float = -SPACING * float(count - 1) * 0.5
	for i in range(count):
		var entry: Dictionary = shown[i]
		var x: float = left + SPACING * float(i)
		_add_character(entry["path"] as String, entry["label"] as String, x, clip)

	_add_camera()

	for _frame: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var save_error: Error = image.save_png(_output_path)
	if save_error != OK:
		printerr("[capture_characters] PNGを保存できませんでした: %s" % _output_path)
		get_tree().quit(1)
		return
	print("[capture_characters] saved: %s" % ProjectSettings.globalize_path(_output_path))
	get_tree().quit()


func _parse_options(args: PackedStringArray) -> void:
	var i: int = 0
	while i + 1 < args.size():
		match args[i]:
			"--motion":
				_motion_path = args[i + 1]
			"--time":
				_motion_time = args[i + 1].to_float()
			"--output":
				_output_path = args[i + 1]
			"--only":
				_only_label = args[i + 1]
			"--distance":
				_camera_distance = args[i + 1].to_float()
			"--height":
				_camera_height = args[i + 1].to_float()
			"--hide":
				_hidden_meshes = args[i + 1].split(",", false)
		i += 2


func _load_clip(path: String) -> Animation:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var clip: Animation = null
	var player: AnimationPlayer = _find_anim_player(inst)
	if player != null and player.has_animation(MOTION_CLIP_NAME):
		clip = player.get_animation(MOTION_CLIP_NAME).duplicate() as Animation
	inst.free()
	return clip


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_anim_player(child)
		if found != null:
			return found
	return null


func _add_character(path: String, label: String, x: float, clip: Animation) -> void:
	var holder := Node3D.new()
	holder.name = label
	holder.position = Vector3(x, 0.0, 0.0)
	add_child(holder)

	var packed := load(path) as PackedScene
	if packed == null:
		printerr("[capture_characters] 読み込めませんでした: %s" % path)
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		printerr("[capture_characters] インスタンス化できませんでした: %s" % path)
		return
	# Mixamo の FBX は +Z 向き。カメラは +Z 側に置くので正面が映る。
	holder.add_child(inst)
	_hide_meshes(inst)

	if clip != null:
		var player := AnimationPlayer.new()
		inst.add_child(player)
		player.root_node = ^".."
		var library := AnimationLibrary.new()
		library.add_animation(&"pose", clip)
		player.add_animation_library(&"qc", library)
		player.play("qc/pose")
		player.seek(_motion_time, true)
		player.pause()

	# 寄りのときはラベルが顔にかぶるので出さない。
	if _only_label != "":
		return
	var text := Label3D.new()
	text.text = label
	text.font_size = 96
	text.pixel_size = 0.002
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.position = Vector3(0.0, 2.1, 0.0)
	holder.add_child(text)


func _hide_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		for needle in _hidden_meshes:
			if String(node.name).contains(needle):
				(node as MeshInstance3D).visible = false
				break
	for child in node.get_children():
		_hide_meshes(child)


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
	camera.position = Vector3(0.0, _camera_height, _camera_distance)
	add_child(camera)
	camera.look_at(Vector3(0.0, _camera_height, 0.0), Vector3.UP)
	camera.make_current.call_deferred()
