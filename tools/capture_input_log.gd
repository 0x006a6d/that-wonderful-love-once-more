extends Node3D

## 入力表示（`ui/input_log.gd`）が実際に出ているかを撮る QC 用キャプチャ。
## 入力は `Input.action_press()` で本物のアクションとして流すので、プレイヤー本体の
## コンボ処理も一緒に走る。描画結果が要るので --headless では実行しない。
##
## 実行: godot --path . tools/capture_input_log.tscn

const STAGE: String = "res://levels/test_stage.tscn"
const DEFAULT_OUTPUT_PATH: String = "res://docs/img/qc_input_log.png"
## 殴る相手。Dummy1 は動かないので HIT の確認向き、Robber1 はガードの確認向き。
const DEFAULT_TARGET: StringName = &"Dummy1"
const CAPTURE_SIZE: Vector2i = Vector2i(1600, 900)
## 犯人との間合い（m）。近接が届く距離に置く。
const ENGAGE_DISTANCE: float = 0.9
## 1入力あたりの押下フレームと、次の入力までの待ちフレーム。
const PRESS_FRAMES: int = 3
const GAP_FRAMES: int = 12
## 最後の入力から撮影までの待ちフレーム。判定窓が開くのを待つ。
const SETTLE_AFTER_FRAMES: int = 14

## 押す順番。J J K と入れて、履歴・段数・派生の3行が埋まった状態を撮る。
const SEQUENCE: Array[StringName] = [&"attack", &"attack"]


var _output_path: String = DEFAULT_OUTPUT_PATH
var _target_name: StringName = DEFAULT_TARGET


func _parse_options(args: PackedStringArray) -> void:
	var i: int = 0
	while i + 1 < args.size():
		match args[i]:
			"--output":
				_output_path = args[i + 1]
			"--target":
				_target_name = StringName(args[i + 1])
		i += 2


func _ready() -> void:
	_parse_options(OS.get_cmdline_user_args())
	get_window().size = CAPTURE_SIZE
	# 幕が PROLOGUE のままだと攻撃入力が通らない。
	RunState.reset()
	GameDirector.reset()
	GameDirector.notify_prologue_finished()

	var packed := load(STAGE) as PackedScene
	if packed == null:
		printerr("[capture_input_log] test_stage を読み込めませんでした")
		get_tree().quit(1)
		return
	var stage := packed.instantiate() as Node3D
	add_child(stage)

	var player := stage.get_node_or_null(^"Player") as Node3D
	var robber := stage.get_node_or_null(NodePath(_target_name)) as Node3D
	if player == null or robber == null:
		printerr("[capture_input_log] Player / %s が見つかりません" % _target_name)
		get_tree().quit(1)
		return

	for _frame: int in range(20):
		await get_tree().process_frame

	# 犯人の手前へ置いて向ける。近接判定は Model の +Z 側にある。
	var facing: Vector3 = robber.global_position - player.global_position
	facing.y = 0.0
	if facing.length() > 0.01:
		var spot: Vector3 = robber.global_position - facing.normalized() * ENGAGE_DISTANCE
		spot.y = player.global_position.y
		player.global_position = spot
		var model := player.get_node_or_null(^"Model") as Node3D
		if model != null:
			model.rotation.y = atan2(facing.x, facing.z)

	for action in SEQUENCE:
		_send(action, true)
		for _frame: int in range(PRESS_FRAMES):
			await get_tree().process_frame
		_send(action, false)
		for _frame: int in range(GAP_FRAMES):
			await get_tree().process_frame

	# 最後の技の判定窓が開くまで待ってから撮る（HIT / MISS が確定する）。
	for _frame: int in range(SETTLE_AFTER_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var save_error: Error = image.save_png(_output_path)
	if save_error != OK:
		printerr("[capture_input_log] PNGを保存できませんでした: %s" % _output_path)
		get_tree().quit(1)
		return
	print("[capture_input_log] saved: %s" % ProjectSettings.globalize_path(_output_path))
	get_tree().quit()


## プレイヤー本体は `_unhandled_input()` でイベントを読む。`Input.action_press()` は
## ポーリング用の状態を変えるだけでイベントを流さないので、実際の入力として
## 届かない（入力表示だけ反応して技が出ない状態になった）。イベントを合成して流す。
func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
