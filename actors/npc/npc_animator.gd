class_name NpcAnimator
extends Node

## NPC の見た目（`Model` 以下のキャラクター）へモーションを再生する。
##
## ステートマシンがこのノードを駆動する。逆向きの依存（アニメ側が NPC の状態を
## 読む）は作らない。`Model` 以下にはノードを足さない方針のため、AnimationPlayer
## はこのノードの子に置き、`root_node` だけをキャラクターのルートへ向ける。
##
## 素材は Mixamo モーション FBX（リターゲット済み）。同じ FBX を NPC ごとに
## インスタンス化すると起動が遅くなるため、取り出した Animation は静的に共有する。

enum Clip { IDLE, WALK, RUN, HIT, DOWN, PRONE, ATTACK, STAND, KNOCKBACK }

## FBX から取り出すクリップ名。Godot の ufbx が Mixamo の FBX に付ける名前。
const FBX_CLIP_NAME: String = "mixamo_com"
## 静止ポーズ用クリップの長さ（秒）。0 だとブレンドの進行が計算できないため、
## 十分短い値を入れてループさせる。
const STATIC_CLIP_LENGTH: float = 0.1

## FBX から取り出した Animation の共有キャッシュ。キーは FBX のリソースパス。
static var _clip_cache: Dictionary = {}

@export var model_path: NodePath = ^"../Model"
## 既定のクロスフェード秒数。
@export var blend_time: float = 0.15
## 歩きと走りを切り替える水平速度（m/s）。
@export var run_speed_threshold: float = 3.6
## この速度未満は待機とみなす（m/s）。
@export var idle_speed_threshold: float = 0.2
## Hips の水平移動（ルートモーション）を殺す。理由と実測値は `RootMotion` を参照。
@export var lock_root_motion: bool = true

@export_group("Clips")
@export var clip_idle: PackedScene
@export var clip_walk: PackedScene
@export var clip_run: PackedScene
## 被弾のけぞり（小）。その場で頭を振られるだけ。
@export var clip_hit: PackedScene
## 被弾のけぞり（大）。ノックバックを伴う被弾で使う。未設定なら clip_hit を使う。
@export var clip_knockback: PackedScene
## ダウン。仰向けに倒れて最終フレームで止まる。
@export var clip_down: PackedScene
## 伏せ。うつ伏せの姿勢で静止させるため、最終フレームだけを使う。
@export var clip_prone: PackedScene
## 攻撃。プレイヤー用の .res はヒットボックスを開く Call Method Track を持つので
## 流用せず、素の Mixamo クリップを使う。
@export var clip_attack: PackedScene
## 何もしていない立ち姿。既存の待機（clip_idle）はボクシングの構えであり、
## 人質には使えない。歩行クリップの先頭フレーム（直立）を静止させて代用する。
## 専用の待機モーションを入れたらここを差し替える。
@export var clip_stand: PackedScene
@export_group("")

var _player: AnimationPlayer = null
var _model: Node3D = null
var _names: Dictionary = {}
var _current: int = -1


## 初期化。子の `_ready()` は親より先に走り、その時点では `Model` がまだ空なので、
## キャラクターを差し込んだ NPC 本体から明示的に呼ばせる。
func setup() -> void:
	_model = get_node_or_null(model_path) as Node3D
	if _model == null:
		push_warning("npc_animator: Model が無い")
		return
	var character: Node3D = _find_skinned_root(_model)
	if character == null:
		# プリミティブ表示のままの個体（テスト用ステージなど）では何もしない。
		return

	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	add_child(_player)
	_player.root_node = _player.get_path_to(character)

	var library := AnimationLibrary.new()
	_register(library, Clip.IDLE, _load_fbx_clip(clip_idle), Animation.LOOP_LINEAR)
	_register(library, Clip.WALK, _load_fbx_clip(clip_walk), Animation.LOOP_LINEAR)
	_register(library, Clip.RUN, _load_fbx_clip(clip_run), Animation.LOOP_LINEAR)
	_register(library, Clip.HIT, _load_fbx_clip(clip_hit), Animation.LOOP_NONE)
	_register(library, Clip.KNOCKBACK, _load_fbx_clip(clip_knockback), Animation.LOOP_NONE)
	_register(library, Clip.DOWN, _load_fbx_clip(clip_down), Animation.LOOP_NONE)
	# 静止ポーズは「その1フレームだけのループクリップ」にして登録する。
	# AnimationPlayer を pause() で止める方式だと、クロスフェードの途中で
	# 固まって中途半端な姿勢（伏せと立ちの中間）になる。
	_register(library, Clip.PRONE,
		_make_static_clip(_load_fbx_clip(clip_prone), -1.0), Animation.LOOP_LINEAR)
	_register(library, Clip.ATTACK, _load_fbx_clip(clip_attack), Animation.LOOP_NONE)
	_register(library, Clip.STAND,
		_make_static_clip(_load_fbx_clip(clip_stand), 0.0), Animation.LOOP_LINEAR)
	_player.add_animation_library(&"npc", library)


## 再生できる状態か。プリミティブ表示のままの個体では false。
func is_active() -> bool:
	return _player != null


## そのクリップが登録されているか。素材が無いときの代替を選ぶのに使う。
func has_clip(clip: int) -> bool:
	return _names.has(clip)


## 速度から待機・歩き・走りを選ぶ。
func drive_locomotion(horizontal_speed: float) -> void:
	if horizontal_speed >= run_speed_threshold:
		play(Clip.RUN)
	elif horizontal_speed >= idle_speed_threshold:
		play(Clip.WALK)
	elif _names.has(Clip.IDLE):
		play(Clip.IDLE)
	else:
		# 客のように待機の構えを持たない個体は直立で止める。
		play(Clip.STAND)


## クリップの長さ（秒）。単発クリップをステートの所要時間へ合わせるのに使う。
func clip_length(clip: int) -> float:
	if _player == null or not _names.has(clip):
		return 0.0
	return _player.get_animation(_names[clip]).length


## 同じクリップの再指定は無視する（毎フレーム呼ばれても再生位置が飛ばない）。
## 連続被弾のように頭から再生し直したい場合だけ force を立てる。
func play(clip: int, custom_blend: float = -1.0, speed_scale: float = 1.0,
		force: bool = false) -> void:
	if _player == null or not _names.has(clip):
		return
	if _current == clip and not force:
		return
	_current = clip
	_player.play(_names[clip], custom_blend if custom_blend >= 0.0 else blend_time,
		speed_scale)


## クリップの time 時点の姿勢だけを持つ、長さ 0 の静止クリップを作る。
## time が負なら最終フレーム。位置・回転・拡縮トラックのみを写す。
func _make_static_clip(animation: Animation, time: float) -> Animation:
	if animation == null:
		return null
	var at: float = time if time >= 0.0 else animation.length
	var static_clip := Animation.new()
	static_clip.length = STATIC_CLIP_LENGTH
	for track in range(animation.get_track_count()):
		var type: int = animation.track_get_type(track)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D \
				and type != Animation.TYPE_SCALE_3D:
			continue
		var index: int = static_clip.add_track(type)
		static_clip.track_set_path(index, animation.track_get_path(track))
		match type:
			Animation.TYPE_POSITION_3D:
				static_clip.position_track_insert_key(index, 0.0,
					animation.position_track_interpolate(track, at))
			Animation.TYPE_ROTATION_3D:
				static_clip.rotation_track_insert_key(index, 0.0,
					animation.rotation_track_interpolate(track, at))
			Animation.TYPE_SCALE_3D:
				static_clip.scale_track_insert_key(index, 0.0,
					animation.scale_track_interpolate(track, at))
	return static_clip


func _register(library: AnimationLibrary, clip: int, animation: Animation,
		loop_mode: Animation.LoopMode) -> void:
	if animation == null:
		return
	var copy: Animation = animation.duplicate() as Animation
	copy.loop_mode = loop_mode
	if lock_root_motion:
		RootMotion.lock_horizontal(copy)
	var name := StringName("clip_%d" % clip)
	library.add_animation(name, copy)
	_names[clip] = StringName("npc/%s" % name)


func _load_fbx_clip(scene: PackedScene) -> Animation:
	if scene == null:
		return null
	var key: String = scene.resource_path
	if _clip_cache.has(key):
		return _clip_cache[key] as Animation
	var inst: Node = scene.instantiate()
	var source: AnimationPlayer = _find_anim_player(inst)
	var clip: Animation = null
	if source != null and source.has_animation(FBX_CLIP_NAME):
		clip = source.get_animation(FBX_CLIP_NAME).duplicate() as Animation
	inst.free()
	_clip_cache[key] = clip
	return clip


## スキンを持つメッシュがぶら下がっているルート（FBX のルート Node3D）を探す。
func _find_skinned_root(node: Node) -> Node3D:
	for child in node.get_children():
		if _find_skeleton(child) != null:
			return child as Node3D
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_anim_player(child)
		if found != null:
			return found
	return null
