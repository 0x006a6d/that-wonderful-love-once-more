extends Node

## プレイヤーのアニメーション制御。
## locomotion(idle/walk/run ブレンド) → melee_1(ジャブ) → melee_2(ストレート) → melee_3(フック)。
##
## AnimationTree のステートマシンをコード側で組み立てる（.tscn への手書きは誤りやすい）。
## - locomotion: idle/walk/run の BlendSpace1D + TimeScale（速度同期）
## - melee_1..3: 生成済み .res（単発クリップ + Call Method Track 付き）
##
## 入力の流れ（1 押し 1 発）:
##   attack() → locomotion なら melee_1。各段の連鎖受付窓内の再押下のみ次段を予約。
##   予約が無ければその段で locomotion に戻る。melee_3 で打ち止め。
##
## ゲームロジック（player.gd）→ このノード（AnimationTree駆動）の一方向依存のみ。
## Call Method Track が叩く _enable_hitbox / _disable_hitbox は player.gd 側に置く。

const MELEE_1_RES: String = "res://actors/player/anim/melee_1.res"
const MELEE_2_RES: String = "res://actors/player/anim/melee_2.res"
const MELEE_3_RES: String = "res://actors/player/anim/melee_3.res"

## VRM をインスタンス化した Model ノード。
@export var model_path: NodePath = ^"../Model"

@export_group("Locomotion Clips")
## 待機クリップ。Quaternius universal は glTF インポータが "_Loop" を剥がすため
## 実アニメ名は "Idle"。
@export_file("*.gltf", "*.fbx") var idle_scene: String = "res://assets/motions/universal_animation_library.gltf"
@export var idle_key: String = "Idle"
## 歩行クリップ（Mixamo In Place。逸脱時は mixamo_walk_female / mixamo_walk_catwalk
## に差し替え候補あり。パスとキーを変えるだけで試せる）。
@export_file("*.gltf", "*.fbx") var walk_scene: String = "res://assets/motions/mixamo_walk.fbx"
@export var walk_key: String = "mixamo_com"
## 走行クリップ（Mixamo In Place）。
@export_file("*.gltf", "*.fbx") var run_scene: String = "res://assets/motions/mixamo_run.fbx"
@export var run_key: String = "mixamo_com"

@export_group("Locomotion Sync")
## locomotion ブレンドの基準速度（この速度で blend=1.0=走り）。
@export var locomotion_max_speed: float = 4.5
## 歩行クリップの本来の移動速度（m/s。tools/measure_stride.gd の実測: 1.53）。
@export var walk_natural_speed: float = 1.53
## 走行クリップの本来の移動速度（m/s。実測: 2.74）。
@export var run_natural_speed: float = 2.74
## アニメ再生速度スケールのクランプ範囲（足の周期を実速度へ寄せる際の上下限）。
@export var anim_speed_limits: Vector2 = Vector2(0.8, 1.8)

@export_group("Combo")
## melee_1 をこの再生割合まで進めたら次段/待機へ抜ける（判定窓の終了 81% の直後）。
@export var melee_1_out_ratio: float = 0.90
## melee_2 をこの再生割合まで進めたら次段/待機へ抜ける（判定窓の終了 81% の直後）。
@export var melee_2_out_ratio: float = 0.90
## melee_3 をこの再生割合まで進めたら待機へ抜ける（判定窓の終了 89% の直後）。
@export var melee_3_out_ratio: float = 0.95
## melee_1 中に連鎖入力（再押下）を受け付ける窓の開始（再生割合）。
## 打撃判定の開始（クリップの 44%）に合わせ、開始直後に届く押下
## （最初の押下のバウンスやパッドの二重イベント）を連鎖として拾わない。
@export var chain_1_start_ratio: float = 0.45
## melee_1 の連鎖受付窓の終了（再生割合）。既定は melee_1_out_ratio と同じ。
@export var chain_1_end_ratio: float = 0.90
## melee_2 中の連鎖受付窓の開始（打撃判定の開始 44% に合わせる）。
@export var chain_2_start_ratio: float = 0.45
## melee_2 の連鎖受付窓の終了。既定は melee_2_out_ratio と同じ。
@export var chain_2_end_ratio: float = 0.90
@export_group("")

signal combo_started()
signal combo_finished()

var _anim_player: AnimationPlayer = null
var _tree: AnimationTree = null
var _state_machine: AnimationNodeStateMachinePlayback = null
var _model: Node3D = null

var _state: String = "locomotion"
var _buffered: bool = false


func _ready() -> void:
	_model = get_node_or_null(model_path) as Node3D
	if _model == null:
		push_warning("player_melee: Model not found")
		return
	var skeleton := _find(_model, "Skeleton3D") as Skeleton3D
	if skeleton != null:
		skeleton.unique_name_in_owner = true
	_anim_player = _find(_model, "AnimationPlayer") as AnimationPlayer
	if _anim_player == null:
		_anim_player = AnimationPlayer.new()
		_anim_player.name = "AnimationPlayer"
		_model.add_child(_anim_player)
	_anim_player.root_node = _anim_player.get_path_to(_model)

	if not _build_library():
		return
	_build_tree()
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _state_machine == null:
		return
	# クリップ終端の検出は再生位置で行う（自動遷移に任せず、バッファ分岐をコードで握る）。
	if _state == "melee_1":
		if _reached_ratio("melee_1", melee_1_out_ratio):
			if _buffered:
				_advance_to("melee_2")
			else:
				_finish_combo()
	elif _state == "melee_2":
		if _reached_ratio("melee_2", melee_2_out_ratio):
			if _buffered:
				_advance_to("melee_3")
			else:
				_finish_combo()
	elif _state == "melee_3":
		if _reached_ratio("melee_3", melee_3_out_ratio):
			_finish_combo()


## バッファを消費して次段へ進む。
func _advance_to(next_state: String) -> void:
	_buffered = false
	_state = next_state
	_state_machine.travel(next_state)


## 現在ステートのクリップが指定割合まで再生されたか。
func _reached_ratio(state_name: String, ratio: float) -> bool:
	if str(_state_machine.get_current_node()) != state_name:
		return false
	var length := _state_machine.get_current_length()
	var pos := _state_machine.get_current_play_position()
	return length > 0.0 and pos >= length * ratio


## player.gd の locomotion 更新。速度に応じて idle(0)→walk(0.5)→jog(1.0) をブレンド。
func set_locomotion(speed: float) -> void:
	if _tree == null:
		return
	var blend := clampf(speed / locomotion_max_speed, 0.0, 1.0)
	_tree.set("parameters/locomotion/blend/blend_position", blend)
	# アニメ再生速度を地面速度に同期する。ブレンド位置に対応する
	# クリップ本来の速度 (natural) で実速度を割った値が再生スケール。
	# blend<=0.5 (idle↔walk) では natural も blend に比例するため一定値に収束し、
	# 停止直前に再生スケールが暴れない。
	_tree.set("parameters/locomotion/speed/scale", _anim_speed_scale(speed, blend))


## 実移動速度とブレンド位置からアニメ再生スケールを求める。
func _anim_speed_scale(speed: float, blend: float) -> float:
	if speed < 0.1 or blend < 0.01:
		return 1.0
	var natural: float
	if blend <= 0.5:
		# idle(0) → walk(0.5): natural は歩行速度へ比例で立ち上がる。
		natural = walk_natural_speed * (blend / 0.5)
	else:
		natural = lerpf(walk_natural_speed, run_natural_speed, (blend - 0.5) / 0.5)
	if natural < 0.01:
		return 1.0
	return clampf(speed / natural, anim_speed_limits.x, anim_speed_limits.y)


## 攻撃入力（押下イベント 1 回につき 1 コール。押しっぱなしでは再コールされない）。
## - locomotion: melee_1 を開始する。この押下はここで消費され、連鎖には使われない
## - melee_1 / melee_2 中: 各段の連鎖受付窓内の「新たな押下」のみ次段を予約
## - melee_3 中・窓外: 無視（1 押し 1 発。3 段で打ち止め）
func attack() -> void:
	if _state_machine == null:
		return
	if _state == "locomotion":
		_state = "melee_1"
		_buffered = false
		_state_machine.travel("melee_1")
		combo_started.emit()
	elif _state == "melee_1" and _in_chain_window("melee_1", chain_1_start_ratio, chain_1_end_ratio):
		_buffered = true
	elif _state == "melee_2" and _in_chain_window("melee_2", chain_2_start_ratio, chain_2_end_ratio):
		_buffered = true


## 指定ステートの連鎖受付窓の中か。travel 直後（SM がまだ前ステート側）や
## 窓の前後に届いた押下は連鎖として扱わない。
func _in_chain_window(state_name: String, start_ratio: float, end_ratio: float) -> bool:
	if str(_state_machine.get_current_node()) != state_name:
		return false
	var length := _state_machine.get_current_length()
	if length <= 0.0:
		return false
	var ratio := _state_machine.get_current_play_position() / length
	return ratio >= start_ratio and ratio <= end_ratio


func is_attacking() -> bool:
	return _state != "locomotion"


func _finish_combo() -> void:
	_state = "locomotion"
	_buffered = false
	_state_machine.travel("locomotion")
	combo_finished.emit()


func _build_library() -> bool:
	var lib := AnimationLibrary.new()

	var idle := _extract(idle_scene, idle_key)
	if idle == null:
		push_warning("player_melee: idle (%s) load failed" % idle_key)
		return false
	idle.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("idle", idle)

	var walk := _extract(walk_scene, walk_key)
	if walk != null:
		walk.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("walk", walk)
	else:
		push_warning("player_melee: walk (%s) load failed。idle で代用" % walk_key)
		lib.add_animation("walk", idle.duplicate(true) as Animation)

	var jog := _extract(run_scene, run_key)
	if jog != null:
		jog.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("jog", jog)
	else:
		push_warning("player_melee: run (%s) load failed。idle で代用" % run_key)
		lib.add_animation("jog", idle.duplicate(true) as Animation)

	var m1 := load(MELEE_1_RES) as Animation
	var m2 := load(MELEE_2_RES) as Animation
	var m3 := load(MELEE_3_RES) as Animation
	if m1 == null or m2 == null or m3 == null:
		push_warning("player_melee: melee .res load failed（build_melee_anims.gd を先に実行）")
		return false
	lib.add_animation("melee_1", m1)
	lib.add_animation("melee_2", m2)
	lib.add_animation("melee_3", m3)

	if _anim_player.has_animation_library("player"):
		_anim_player.remove_animation_library("player")
	_anim_player.add_animation_library("player", lib)
	return true


## FBX/gltf から 1 本の Animation を取り出す。見つからなければ null
## （以前の「先頭クリップへのフォールバック」は A_TPose を拾う事故の原因だったため廃止）。
func _extract(scene_path: String, key: String) -> Animation:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var src := _find(inst, "AnimationPlayer") as AnimationPlayer
	if src == null:
		inst.free()
		return null
	var result: Animation = null
	if src.has_animation(key):
		result = src.get_animation(key).duplicate(true) as Animation
	else:
		# ライブラリ接頭辞付き（"lib/Key"）で探す。
		for a in src.get_animation_list():
			if str(a).ends_with("/" + key):
				result = src.get_animation(a).duplicate(true) as Animation
				break
	inst.free()
	return result


func _build_tree() -> void:
	var sm := AnimationNodeStateMachine.new()

	# locomotion: idle(0.0) / walk(0.5) / run(1.0) の BlendSpace1D（速度でブレンド）を
	# TimeScale ノード付きの BlendTree に包み、足の周期を実移動速度へ同期できるようにする。
	var blend := AnimationNodeBlendSpace1D.new()
	blend.min_space = 0.0
	blend.max_space = 1.0
	var n_idle := AnimationNodeAnimation.new()
	n_idle.animation = "player/idle"
	n_idle.resource_name = "idle"
	var n_walk := AnimationNodeAnimation.new()
	n_walk.animation = "player/walk"
	n_walk.resource_name = "walk"
	var n_jog := AnimationNodeAnimation.new()
	n_jog.animation = "player/jog"
	n_jog.resource_name = "run"
	blend.add_blend_point(n_idle, 0.0, -1)
	blend.add_blend_point(n_walk, 0.5, -1)
	blend.add_blend_point(n_jog, 1.0, -1)

	var loco := AnimationNodeBlendTree.new()
	loco.add_node("blend", blend, Vector2(0, 0))
	loco.add_node("speed", AnimationNodeTimeScale.new(), Vector2(250, 0))
	loco.connect_node("speed", 0, "blend")
	loco.connect_node("output", 0, "speed")

	var n_m1 := AnimationNodeAnimation.new()
	n_m1.animation = "player/melee_1"
	var n_m2 := AnimationNodeAnimation.new()
	n_m2.animation = "player/melee_2"
	var n_m3 := AnimationNodeAnimation.new()
	n_m3.animation = "player/melee_3"

	sm.add_node("locomotion", loco, Vector2(0, 0))
	sm.add_node("melee_1", n_m1, Vector2(300, 0))
	sm.add_node("melee_2", n_m2, Vector2(600, 0))
	sm.add_node("melee_3", n_m3, Vector2(900, 0))

	# 全遷移をコード駆動（即時）にする。終端検出と分岐は _physics_process が握る。
	_add_transition(sm, "locomotion", "melee_1", 0.08)
	_add_transition(sm, "melee_1", "melee_2", 0.05)
	_add_transition(sm, "melee_2", "melee_3", 0.05)
	_add_transition(sm, "melee_1", "locomotion", 0.15)
	_add_transition(sm, "melee_2", "locomotion", 0.20)
	_add_transition(sm, "melee_3", "locomotion", 0.20)

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = sm
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	# ツリーに入れてから anim_player を解決する（get_path_to は両者がツリー内である必要）。
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim_player)
	_tree.active = true

	_state_machine = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_state_machine.start("locomotion")


func _add_transition(sm: AnimationNodeStateMachine, from: String, to: String,
		xfade: float) -> void:
	var tr := AnimationNodeStateMachineTransition.new()
	tr.xfade_time = xfade
	tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	sm.add_transition(from, to, tr)


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
