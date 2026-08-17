extends Node3D

## 差し替え後の NPC を、姿勢が変わるステートへ強制的に入れて撮る QC 用キャプチャ。
## 伏せ・ダウン・のけぞりが人体として成立しているか、床にめり込んでいないかを見る。
## 描画結果が要るので --headless では実行しない。
##
## 実行: godot --path . tools/capture_npc_states.tscn

const OUTPUT_PATH: String = "res://docs/img/qc_npc_states.png"
const CAPTURE_SIZE: Vector2i = Vector2i(1600, 900)
## ステート進入後、アニメーションが目的の姿勢まで進むのを待つフレーム数。
const SETTLE_FRAMES: int = 180
## 入れ直したステートを撮るまでの待ちフレーム数。
const RESTAGE_FRAMES: int = 40
const SPACING: float = 2.6
const CAMERA_HEIGHT: float = 1.9
const CAMERA_DISTANCE: float = 6.0

const CASES: Array[Dictionary] = [
	{
		"label": "客 伏せ",
		"path": "res://actors/npc/civilian.tscn",
		"state": Civilian.CivilianState.PRONE,
	},
	{
		"label": "客 ダウン",
		"path": "res://actors/npc/civilian.tscn",
		"state": Civilian.CivilianState.DOWNED,
	},
	{
		"label": "犯人 のけぞり",
		"path": "res://actors/npc/roles/leader.tscn",
		"state": Robber.State.STAGGERED,
		# のけぞりは短いので、撮る直前に入れ直して途中を捉える。
		"restage": true,
	},
	{
		"label": "犯人 ダウン",
		"path": "res://actors/npc/roles/gunner.tscn",
		"state": Robber.State.DOWNED,
	},
	{
		"label": "客 盾",
		"path": "res://actors/npc/civilian.tscn",
		# 伏せてから盾に取られる経路を再現する。立ち姿へ戻らないと、
		# リーダーの前で寝たままになる。
		"state": Civilian.CivilianState.PRONE,
		"restage": true,
		"restage_state": Civilian.CivilianState.SHIELDED,
	},
]


func _ready() -> void:
	get_window().size = CAPTURE_SIZE
	_add_environment()
	_add_floor()

	var count: int = CASES.size()
	var left: float = -SPACING * float(count - 1) * 0.5
	var npcs: Array[Node3D] = []
	for i in range(count):
		var entry: Dictionary = CASES[i]
		var npc: Node3D = _add_npc(entry["path"] as String, entry["label"] as String,
			left + SPACING * float(i))
		npcs.append(npc)

	_add_camera()

	# ステートマシンは 1 フレーム遅れて開始するので、少し待ってから遷移させる。
	for _frame: int in range(5):
		await get_tree().process_frame
	for i in range(count):
		var npc: Node3D = npcs[i]
		if npc == null:
			continue
		var machine := npc.get("_sm") as StateMachine
		if machine == null:
			continue
		machine.transition_to(CASES[i]["state"] as int, true)

	for _frame: int in range(SETTLE_FRAMES):
		await get_tree().process_frame

	for i in range(count):
		if not CASES[i].get("restage", false):
			continue
		var restaged: Node3D = npcs[i]
		if restaged == null:
			continue
		var restage_machine := restaged.get("_sm") as StateMachine
		if restage_machine != null:
			restage_machine.transition_to(
				CASES[i].get("restage_state", CASES[i]["state"]) as int, true)
	for _frame: int in range(RESTAGE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var save_error: Error = image.save_png(OUTPUT_PATH)
	if save_error != OK:
		printerr("[capture_npc_states] PNGを保存できませんでした: %s" % OUTPUT_PATH)
		get_tree().quit(1)
		return
	print("[capture_npc_states] saved: %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
	get_tree().quit()


func _add_npc(path: String, label: String, x: float) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		printerr("[capture_npc_states] 読み込めませんでした: %s" % path)
		return null
	var npc := packed.instantiate() as Node3D
	if npc == null:
		return null
	npc.position = Vector3(x, 0.0, 0.0)
	# NPC の前方は -Z。カメラは +Z 側にいるので、正面を向かせるため半回転させる。
	npc.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	add_child(npc)

	var text := Label3D.new()
	text.text = label
	text.font_size = 64
	text.pixel_size = 0.002
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.position = Vector3(x, 2.1, 0.0)
	add_child(text)
	return npc


func _add_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.31, 0.34)
	plane.material = material
	floor_mesh.mesh = plane
	add_child(floor_mesh)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 0.2, 30.0)
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
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	light.light_energy = 1.2
	add_child(light)


func _add_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, CAMERA_HEIGHT, CAMERA_DISTANCE)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.3, 0.0), Vector3.UP)
	camera.make_current.call_deferred()
