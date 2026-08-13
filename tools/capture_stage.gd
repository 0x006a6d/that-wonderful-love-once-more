extends Node3D

## 診断用キャプチャ (本物の test_stage 版)。修正はしない。
## res://levels/test_stage.tscn をそのままインスタンス化し、
## 入力注入ドライバと固定キャプチャカメラを「追加するだけ」。
## シナリオA: 1.0s に attack 1回 → 3.5s で終了。
##
## あわせて AnimationPlayer の root_node と、melee_1 / idle / walk 各アニメの
## 全トラックが root_node から解決できるかを CSV に出力する。
##
## 実行 (Windows Godot / Movie Maker):
##   godot --path . --write-movie C:/Users/jun/AppData/Local/Temp/combo_frames/a2/frame.png \
##     --fixed-fps 30 res://tools/capture_stage.tscn

const OUT_BASE := "C:/Users/jun/AppData/Local/Temp/combo_frames"
const TAG := "a3"

var _player: Node3D = null
var _melee: Node = null
var _hitbox: Area3D = null
var _playback: AnimationNodeStateMachinePlayback = null

var _frames: int = 0
var _pressed: bool = false
var _track_logged: bool = false
var _csv: Array[String] = []


func _ready() -> void:
	var stage := (load("res://levels/test_stage.tscn") as PackedScene).instantiate()
	add_child(stage)
	_player = stage.get_node("Player") as Node3D
	_melee = _player.get_node("PlayerMelee")
	_hitbox = _player.get_node("Model/MeleeHitbox") as Area3D

	# 固定キャプチャカメラ: プレイヤーの右斜め前 45°、距離 2.5m。
	var cam := Camera3D.new()
	add_child(cam)
	var base := _player.position
	cam.position = base + Vector3(sin(deg_to_rad(45)) * 2.5, 1.2, cos(deg_to_rad(45)) * 2.5)
	cam.look_at(base + Vector3(0, 1.1, 0), Vector3.UP)
	# 既存カメラ (SpringArm 配下) より後から current を奪う。
	cam.make_current.call_deferred()

	_csv.append("frame,time,state,node,pos,hitbox_monitoring")


func _physics_process(_delta: float) -> void:
	_frames += 1
	var t := _frames / float(Engine.physics_ticks_per_second)

	if not _track_logged and t >= 0.5:
		_track_logged = true
		_dump_track_resolution()

	if not _pressed and t >= 1.0:
		_pressed = true
		_press()

	if _playback == null and _melee != null:
		var tree := _melee.get_node_or_null("AnimationTree") as AnimationTree
		if tree != null:
			_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	var state := str(_melee.get("_state")) if _melee != null else "?"
	var node := "?"
	var pos := -1.0
	if _playback != null:
		node = str(_playback.get_current_node())
		pos = _playback.get_current_play_position()
	var mon := _hitbox.monitoring if _hitbox != null else false
	_csv.append("%d,%.3f,%s,%s,%.3f,%s" % [_frames, t, state, node, pos, str(mon)])

	if t >= 3.5:
		_save_csv()
		get_tree().quit()


func _press() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	Input.parse_input_event(ev)
	var rel := InputEventKey.new()
	rel.physical_keycode = KEY_J
	rel.pressed = false
	get_tree().create_timer(0.03, true, false, true).timeout.connect(
		func() -> void: Input.parse_input_event(rel))


## melee_1 / idle / walk の全トラックについて root_node からの解決可否を列挙する。
func _dump_track_resolution() -> void:
	var lines: Array[String] = []
	var tree := _melee.get_node_or_null("AnimationTree") as AnimationTree
	var ap_path: NodePath = tree.anim_player if tree != null else NodePath("")
	var ap := tree.get_node_or_null(ap_path) as AnimationPlayer if tree != null else null
	if ap == null:
		lines.append("ERROR,AnimationPlayer not found")
		_write_lines(lines)
		return
	lines.append("root_node=%s" % str(ap.root_node))
	var root := ap.get_node_or_null(ap.root_node)
	lines.append("root_resolved=%s (%s)" % [str(root != null), root.name if root else "NULL"])
	lines.append("anim,track,path,resolved,target")
	for anim_key in ["player/melee_1", "player/idle", "player/walk"]:
		if not ap.has_animation(anim_key):
			lines.append("%s,-,MISSING,-,-" % anim_key)
			continue
		var anim := ap.get_animation(anim_key)
		for i in range(anim.get_track_count()):
			var p := str(anim.track_get_path(i))
			var node_part := p.split(":")[0]
			var target: Node = root.get_node_or_null(NodePath(node_part)) if root != null else null
			lines.append("%s,%d,%s,%s,%s" %
				[anim_key, i, p.replace(",", ";"), str(target != null),
				target.name if target != null else "NULL"])
	_write_lines(lines)


func _write_lines(lines: Array[String]) -> void:
	var f := FileAccess.open("%s/trackres_%s.csv" % [OUT_BASE, TAG], FileAccess.WRITE)
	if f != null:
		for l in lines:
			f.store_line(l)
		f.close()
		print("[trackres] saved")


func _save_csv() -> void:
	var f := FileAccess.open("%s/state_%s.csv" % [OUT_BASE, TAG], FileAccess.WRITE)
	if f != null:
		for line in _csv:
			f.store_line(line)
		f.close()
		print("[csv] saved")
