extends Node

## プレイヤーのアニメーション制御。locomotion(idle/move ブレンド) → melee_1 → melee_2。
##
## AnimationTree のステートマシンをコード側で組み立てる（.tscn への手書きは誤りやすい）。
## - locomotion: idle と move を BlendSpace1D（速度でブレンド）
## - melee_1 / melee_2: 生成済み .res（Call Method Track 付き）
##
## 入力の流れ:
##   attack() が呼ばれる → locomotion なら melee_1 へ。
##   melee_1 再生中に attack() が来たらバッファし、melee_1 終了で melee_2 へ連鎖。
##   melee_2 終了、または melee_1 単発終了で locomotion に戻る。
##
## ゲームロジック（player.gd）→ このノード（AnimationTree駆動）の一方向依存のみ。
## Call Method Track が叩く _enable_hitbox / _disable_hitbox は player.gd 側に置く。

const IDLE_MOTION: String = "res://assets/motions/mixamo_boxing_idle.fbx"
const MOVE_MOTION: String = "res://assets/motions/universal_animation_library.gltf"
const MOVE_KEY: String = "Jog_Fwd_Loop"
const MELEE_1_RES: String = "res://actors/player/anim/melee_1.res"
const MELEE_2_RES: String = "res://actors/player/anim/melee_2.res"

## VRM をインスタンス化した Model ノード。
@export var model_path: NodePath = ^"../Model"
## locomotion で move とみなす速度（m/s）。
@export var move_speed_threshold: float = 0.3
## melee_1 をこの再生割合まで進めたら次段/待機へ抜ける（判定窓を過ぎたら素早く戻す）。
@export var melee_1_out_ratio: float = 0.55
## melee_2 をこの再生割合まで進めたら待機へ抜ける。
@export var melee_2_out_ratio: float = 0.70

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
				_buffered = false
				_state = "melee_2"
				_state_machine.travel("melee_2")
			else:
				_finish_combo()
	elif _state == "melee_2":
		if _reached_ratio("melee_2", melee_2_out_ratio):
			_finish_combo()


## 現在ステートのクリップが指定割合まで再生されたか。
func _reached_ratio(state_name: String, ratio: float) -> bool:
	if str(_state_machine.get_current_node()) != state_name:
		return false
	var length := _state_machine.get_current_length()
	var pos := _state_machine.get_current_play_position()
	return length > 0.0 and pos >= length * ratio


## player.gd の locomotion 更新。攻撃中でなければ move/idle をブレンド。
func set_locomotion(speed: float) -> void:
	if _tree == null:
		return
	var blend := 1.0 if speed > move_speed_threshold else 0.0
	_tree.set("parameters/locomotion/blend_position", blend)


## 攻撃入力。locomotion なら melee_1 開始、melee_1 中なら次段をバッファ。
func attack() -> void:
	if _state_machine == null:
		return
	if _state == "locomotion":
		_state = "melee_1"
		_buffered = false
		_state_machine.travel("melee_1")
		combo_started.emit()
	elif _state == "melee_1":
		_buffered = true


func is_attacking() -> bool:
	return _state != "locomotion"


func _finish_combo() -> void:
	_state = "locomotion"
	_buffered = false
	_state_machine.travel("locomotion")
	combo_finished.emit()


func _build_library() -> bool:
	var lib := AnimationLibrary.new()

	var idle := _extract(IDLE_MOTION, "")
	if idle == null:
		push_warning("player_melee: idle load failed")
		return false
	idle.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("idle", idle)

	var move := _extract(MOVE_MOTION, MOVE_KEY)
	if move != null:
		move.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("move", move)
	else:
		# 移動モーションが取れなくても idle で代用（コンボ検証を止めない）。
		lib.add_animation("move", idle.duplicate(true) as Animation)

	var m1 := load(MELEE_1_RES) as Animation
	var m2 := load(MELEE_2_RES) as Animation
	if m1 == null or m2 == null:
		push_warning("player_melee: melee .res load failed（build_melee_anims.gd を先に実行）")
		return false
	lib.add_animation("melee_1", m1)
	lib.add_animation("melee_2", m2)

	if _anim_player.has_animation_library("player"):
		_anim_player.remove_animation_library("player")
	_anim_player.add_animation_library("player", lib)
	return true


## FBX/gltf から 1 本の Animation を取り出す。key が空なら最初の非 RESET を拾う。
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
	if not key.is_empty() and src.has_animation(key):
		result = src.get_animation(key).duplicate(true) as Animation
	elif not key.is_empty():
		# ライブラリ接頭辞付きで探す。
		for a in src.get_animation_list():
			if str(a).ends_with(key):
				result = src.get_animation(a).duplicate(true) as Animation
				break
	if result == null:
		for a in src.get_animation_list():
			if str(a) != "RESET":
				result = src.get_animation(a).duplicate(true) as Animation
				break
	inst.free()
	return result


func _build_tree() -> void:
	var sm := AnimationNodeStateMachine.new()

	# locomotion: idle(0.0) / move(1.0) の BlendSpace1D
	var blend := AnimationNodeBlendSpace1D.new()
	blend.min_space = 0.0
	blend.max_space = 1.0
	var n_idle := AnimationNodeAnimation.new()
	n_idle.animation = "player/idle"
	n_idle.resource_name = "idle"
	var n_move := AnimationNodeAnimation.new()
	n_move.animation = "player/move"
	n_move.resource_name = "move"
	blend.add_blend_point(n_idle, 0.0, -1)
	blend.add_blend_point(n_move, 1.0, -1)

	var n_m1 := AnimationNodeAnimation.new()
	n_m1.animation = "player/melee_1"
	var n_m2 := AnimationNodeAnimation.new()
	n_m2.animation = "player/melee_2"

	sm.add_node("locomotion", blend, Vector2(0, 0))
	sm.add_node("melee_1", n_m1, Vector2(300, 0))
	sm.add_node("melee_2", n_m2, Vector2(600, 0))

	# 全遷移をコード駆動（即時）にする。終端検出と分岐は _physics_process が握る。
	_add_transition(sm, "locomotion", "melee_1", 0.08)
	_add_transition(sm, "melee_1", "melee_2", 0.05)
	_add_transition(sm, "melee_1", "locomotion", 0.15)
	_add_transition(sm, "melee_2", "locomotion", 0.20)

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
