extends Node3D

## 銀行ロビーを目線の高さから撮る QC 用キャプチャ。俯瞰の `capture_lobby.gd` では
## キャラクターの見え方が分からないため、差し替え後の確認にはこちらを使う。
## 描画結果が要るので --headless では実行しない。
##
## 実行: godot --path . tools/capture_lobby_eye.tscn
##   -- --frames 120 --output res://docs/img/qc_lobby_eye.png

const LOBBY_SCENE_PATH: String = "res://levels/bank_lobby.tscn"
const DEFAULT_OUTPUT_PATH: String = "res://docs/img/qc_lobby_eye.png"
const CAPTURE_SIZE: Vector2i = Vector2i(1600, 900)
## 幕やAIが動き出してからの状態を見たいので、既定でも数秒ぶん進める。
const DEFAULT_FRAMES: int = 90
const CAMERA_HEIGHT: float = 1.7

var _frames: int = DEFAULT_FRAMES
var _output_path: String = DEFAULT_OUTPUT_PATH
## `--toon off` で NPC のトゥーン化を外し、Mixamo 本来の見た目と並置比較する。
var _toon: bool = true


func _ready() -> void:
	_parse_options(OS.get_cmdline_user_args())
	get_window().size = CAPTURE_SIZE

	var packed := load(LOBBY_SCENE_PATH) as PackedScene
	if packed == null:
		printerr("[capture_lobby_eye] bank_lobby.tscn を読み込めませんでした")
		get_tree().quit(1)
		return
	var lobby := packed.instantiate() as Node3D
	add_child(lobby)

	if not _toon:
		for group in [&"civilian", &"robber"]:
			for node in get_tree().get_nodes_in_group(group):
				var body := node as Node3D
				if body != null and lobby.is_ancestor_of(body):
					ToonSkin.clear(body.get_node_or_null(^"Model") as Node3D)

	for _frame: int in range(_frames):
		await get_tree().process_frame

	_add_camera(lobby)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var save_error: Error = image.save_png(_output_path)
	if save_error != OK:
		printerr("[capture_lobby_eye] PNGを保存できませんでした: %s" % _output_path)
		get_tree().quit(1)
		return
	print("[capture_lobby_eye] saved: %s" % ProjectSettings.globalize_path(_output_path))
	get_tree().quit()


func _parse_options(args: PackedStringArray) -> void:
	var i: int = 0
	while i + 1 < args.size():
		match args[i]:
			"--frames":
				_frames = args[i + 1].to_int()
			"--output":
				_output_path = args[i + 1]
			"--toon":
				_toon = args[i + 1] != "off"
		i += 2


## 客と犯人がまとまって映る位置へカメラを置く。全 NPC の重心を見て、
## そこから一定距離だけ離れた高さ 1.7 m から狙う。
func _add_camera(lobby: Node3D) -> void:
	var center := Vector3.ZERO
	var count: int = 0
	for group in [&"civilian", &"robber"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and lobby.is_ancestor_of(body):
				center += body.global_position
				count += 1
	if count > 0:
		center /= float(count)

	var camera := Camera3D.new()
	camera.position = center + Vector3(0.0, CAMERA_HEIGHT, 7.0)
	add_child(camera)
	camera.look_at(center + Vector3(0.0, 0.9, 0.0), Vector3.UP)
	camera.make_current.call_deferred()
