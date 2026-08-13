extends Node

## 待機モーションだけを VRM の GeneralSkeleton へ流す最小プレイヤー。
## AnimationTree は 8/15 に組む。それまでは Mixamo の待機モーションを 1 本、
## ループ再生するだけに留める（無理はしない設計）。
## 対象の VRM ルートは @export で注入する（get_node("../..") を避ける）。

const MOTION_PATH: String = "res://assets/motions/mixamo_boxing_idle.fbx"
const IDLE_KEY: String = "idle/pose"

## VRM をインスタンス化した Model ノード（Node3D）。
@export var model_path: NodePath = ^"../Model"

var _anim_player: AnimationPlayer = null


func _ready() -> void:
	var model := get_node_or_null(model_path) as Node3D
	if model == null:
		return
	var skeleton := _find_by_class(model, "Skeleton3D") as Skeleton3D
	if skeleton != null:
		skeleton.unique_name_in_owner = true
	_anim_player = _find_by_class(model, "AnimationPlayer") as AnimationPlayer
	if _anim_player == null:
		return
	# %GeneralSkeleton を解決できるよう root を VRM ルートにする。
	_anim_player.root_node = _anim_player.get_path_to(model)
	if not _load_idle():
		return
	var anim := _anim_player.get_animation(IDLE_KEY)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
		_anim_player.play(IDLE_KEY)


## 待機モーション FBX を読み込み、"idle" ライブラリへ 1 本だけ登録する。
func _load_idle() -> bool:
	var packed := load(MOTION_PATH) as PackedScene
	if packed == null:
		return false
	var inst := packed.instantiate()
	var src := _find_by_class(inst, "AnimationPlayer") as AnimationPlayer
	if src == null:
		inst.free()
		return false
	var anims := src.get_animation_list()
	if anims.is_empty():
		inst.free()
		return false
	var lib := AnimationLibrary.new()
	lib.add_animation("pose", src.get_animation(anims[0]).duplicate(true) as Animation)
	inst.free()
	if _anim_player.has_animation_library("idle"):
		_anim_player.remove_animation_library("idle")
	_anim_player.add_animation_library("idle", lib)
	return true


func _find_by_class(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r := _find_by_class(c, cls)
		if r != null:
			return r
	return null
