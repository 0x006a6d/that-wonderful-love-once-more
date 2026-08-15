extends CanvasLayer
class_name EndingCard

## 縦切り版のエンディング結果表示。ニュース放送と Aftermath は 8/24 以降に拡張する。

@export var screen_path: NodePath = ^"Screen"
@export var title_path: NodePath = ^"Screen/Center/Content/Title"
@export var details_path: NodePath = ^"Screen/Center/Content/Details"

var _screen: Control = null
var _title: Label = null
var _details: Label = null
var _restart_started: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen = get_node_or_null(screen_path) as Control
	_title = get_node_or_null(title_path) as Label
	_details = get_node_or_null(details_path) as Label
	GameDirector.act_changed.connect(_on_act_changed)
	if GameDirector.current_act == GameTypes.Act.EPILOGUE:
		show_ending()
	else:
		_hide_ending()


func _input(event: InputEvent) -> void:
	if is_displayed() and not _restart_started and event.is_action_pressed(&"ui_accept"):
		restart()
		get_viewport().set_input_as_handled()


func show_ending() -> void:
	var ending := RunState.resolve_ending()
	if _title != null:
		_title.text = _ending_name(ending)
	if _details != null:
		_details.text = (
			("犯人: 無力化 %d（うち死亡 %d / 自分による無力化 %d / 自分による死亡 %d）\n" +
			"客: 無力化 %d（うち死亡 %d / 自分による無力化 %d / 自分による死亡 %d）\n" +
			"経過時間: %.1f 秒\n\nEnter でやり直し")
			% [RunState.robbers_downed, RunState.robbers_killed,
				RunState.robbers_downed_by_player, RunState.robbers_killed_by_player,
				RunState.civilians_downed, RunState.civilians_killed,
				RunState.civilians_downed_by_player, RunState.civilians_killed_by_player,
				RunState.elapsed]
		)
	if _screen != null:
		_screen.visible = true
	get_tree().paused = true


## reload_scene=false はヘッドレス検証用。実ゲームの入力経路は常に再読み込みする。
func restart(reload_scene: bool = true) -> void:
	if _restart_started:
		return
	_restart_started = true
	# この順序を崩すと、再読込したシーンの _ready() が前回の値を参照してしまう。
	RunState.reset()
	GameDirector.reset()
	if reload_scene:
		get_tree().reload_current_scene()
	else:
		_restart_started = false


func is_displayed() -> bool:
	return _screen != null and _screen.visible


func displayed_title() -> String:
	return _title.text if _title != null else ""


func _on_act_changed(act: int) -> void:
	if act == GameTypes.Act.EPILOGUE:
		show_ending()
	else:
		_hide_ending()


func _hide_ending() -> void:
	if _screen != null:
		_screen.visible = false
	# GameDirector.reset() の通知でもここを通り、再読込前にツリーを再開する。
	get_tree().paused = false


func _ending_name(ending: int) -> String:
	# enum の数値順に依存する配列ではなく、各列挙子を明示して対応崩れを防ぐ。
	match ending:
		GameTypes.Ending.IDEAL:
			return "理想"
		GameTypes.Ending.NORMAL:
			return "通常"
		GameTypes.Ending.DRIFT:
			return "逸脱"
		GameTypes.Ending.FAILURE:
			return "失敗"
	return "不明"
