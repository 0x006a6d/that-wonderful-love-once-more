extends Node3D

## 診断用キャプチャシーン (Movie Maker モードで実プレイを連番 PNG 化する)。
## 修正はしない。実行時の挙動を映像と状態 CSV で記録するだけ。
##
## シナリオ (scenario @export):
##   "a": 開始 1.0s 後に attack 1回 → 2.5s 待って終了
##   "b": 1.0s に1回 + 0.15s 後に2回目 → 2.5s 待って終了
##   "c": 1.0s から 0.15s 間隔で3回 → 3.0s 待って終了
##
## 実行 (Windows Godot、GUI あり):
##   godot --path . --write-movie C:/Users/jun/AppData/Local/Temp/combo_frames/a/frame.png \
##     --fixed-fps 30 res://tools/capture_combo_a.tscn
##
## 状態 CSV: C:/Users/jun/AppData/Local/Temp/combo_frames/state_<scenario>.csv
##   (フレーム番号, ステート名, playback position, hitbox.monitoring)

const PLAYER := "res://actors/player/player.tscn"
const DUMMY := "res://actors/npc/dummy.tscn"
const OUT_BASE := "C:/Users/jun/AppData/Local/Temp/combo_frames"

@export var scenario: String = "a"

var _player: Node3D = null
var _melee: Node = null
var _hitbox: Area3D = null
var _playback: AnimationNodeStateMachinePlayback = null

var _frames: int = 0
var _key: Key = KEY_J
var _press_times: Array[float] = []
var _end_time: float = 3.5
var _pressed: Array[bool] = []
var _track_logged: bool = false
var _csv: Array[String] = []


func _ready() -> void:
	_build_stage()
	match scenario:
		"a":
			_press_times = [1.0]
			_end_time = 3.5
		"b":
			_press_times = [1.0, 1.15]
			_end_time = 3.5
		"c":
			_press_times = [1.0, 1.35, 1.70]
			_end_time = 4.0
		"d":
			# 速い連打 (旧・受付窓方式でフックが出なかったテンポ)。
			_press_times = [1.0, 1.15, 1.30]
			_end_time = 4.0
		"k1":
			# キック単発。
			_key = KEY_K
			_press_times = [1.0]
			_end_time = 3.5
		"k3":
			# キック3連 (人間の連打相当 0.35s 間隔)。
			_key = KEY_K
			_press_times = [1.0, 1.35, 1.70]
			_end_time = 4.5
		"kf":
			# キック速い3連 (0.15s 間隔、キュー消化の確認)。
			_key = KEY_K
			_press_times = [1.0, 1.15, 1.30]
			_end_time = 4.5
		"k1b":
			# 新構成 (膝→ミドル→サイド) のキック単発。
			_key = KEY_K
			_press_times = [1.0]
			_end_time = 3.5
		"k3b":
			# 新構成のキック3連 (0.35s 間隔)。
			_key = KEY_K
			_press_times = [1.0, 1.35, 1.70]
			_end_time = 4.5
	for i in range(_press_times.size()):
		_pressed.append(false)
	_csv.append("frame,time,state,node,pos,hitbox_monitoring")


func _build_stage() -> void:
	# 床
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(20, 0.5, 20)
	fshape.shape = fbox
	fshape.position = Vector3(0, -0.25, 0)
	floor_body.add_child(fshape)
	var fmesh := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(20, 0.5, 20)
	fmesh.mesh = fbm
	fmesh.position = Vector3(0, -0.25, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.32, 0.33, 0.36)
	fmesh.material_override = fmat
	floor_body.add_child(fmesh)
	add_child(floor_body)

	# ライト・環境
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.56, 0.62)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	# プレイヤー (原点、+Z を向いたまま)
	_player = (load(PLAYER) as PackedScene).instantiate() as Node3D
	add_child(_player)
	_player.position = Vector3(0, 0.1, 0)
	_melee = _player.get_node("PlayerMelee")
	_hitbox = _player.get_node("Model/MeleeHitbox") as Area3D

	# ダミー (正面 1.1m)
	var dummy := (load(DUMMY) as PackedScene).instantiate() as Node3D
	add_child(dummy)
	dummy.position = Vector3(0, 0.1, 1.1)

	# 固定カメラ: キャラの右斜め前 45°、距離 2.5m (両手が見える画角)
	var cam := Camera3D.new()
	var d := 2.5
	cam.position = Vector3(sin(deg_to_rad(45)) * d, 1.3, cos(deg_to_rad(45)) * d)
	add_child(cam)
	cam.look_at(Vector3(0, 1.1, 0), Vector3.UP)
	cam.make_current()


func _press() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = _key
	ev.pressed = true
	Input.parse_input_event(ev)
	var rel := InputEventKey.new()
	rel.physical_keycode = _key
	rel.pressed = false
	# release は少し後に送る (押下エッジのみ意味を持つ)
	get_tree().create_timer(0.03, true, false, true).timeout.connect(
		func() -> void: Input.parse_input_event(rel))


func _physics_process(_delta: float) -> void:
	_frames += 1
	# physics は 60Hz (プロジェクト既定)。移動秒数は tick レートから換算する。
	var t := _frames / float(Engine.physics_ticks_per_second)

	for i in range(_press_times.size()):
		if not _pressed[i] and t >= _press_times[i]:
			_pressed[i] = true
			_press()

	# トラック解決ログ (0.5s 時点で一度だけ)
	if not _track_logged and t >= 0.5:
		_track_logged = true
		_dump_track_resolution()

	# 状態ログ
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

	if t >= _end_time:
		_save_csv()
		get_tree().quit()


func _save_csv() -> void:
	var path := "%s/state_%s.csv" % [OUT_BASE, scenario]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		for line in _csv:
			f.store_line(line)
		f.close()
		print("[csv] saved: ", path)
	else:
		print("[csv] SAVE FAILED: ", path)


## melee_1 / idle / walk の全トラックについて root_node からの解決可否を列挙する。
func _dump_track_resolution() -> void:
	var lines: Array[String] = []
	var tree := _melee.get_node_or_null("AnimationTree") as AnimationTree
	var ap: AnimationPlayer = null
	if tree != null:
		ap = tree.get_node_or_null(tree.anim_player) as AnimationPlayer
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
	var f := FileAccess.open("%s/trackres_combo_%s.csv" % [OUT_BASE, scenario], FileAccess.WRITE)
	if f != null:
		for l in lines:
			f.store_line(l)
		f.close()
		print("[trackres] saved")
