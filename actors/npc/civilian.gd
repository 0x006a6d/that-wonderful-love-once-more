extends CharacterBody3D
class_name Civilian

## 客の最小共通挙動（technical-spec §8）。
## FLEE_ROBBER / FLEE_PLAYER とロックオン連携は 8/22 に実装する。
##
## 見た目は Model 子ノード1個に隔離し、当面はプリミティブで表す。
## 向きは犯人と同じく本体を回し、前方は Godot 標準の -Z。

## SHIELDED はリーダーが位置を制御する間の立ち姿と当たり判定を、通常の
## IDLE / PRONE から独立させるための状態。既存IDを保つため末尾へ追加する。
enum CivilianState { IDLE, PRONE, FLEE_ROBBER, FLEE_PLAYER, STAGGERED, DOWNED, SHIELDED }

@export_group("Reaction")
## 被弾でよろけている秒数。
@export var stagger_duration: float = 0.45

@export_group("Pose")
## 立ち姿の Model の回転（度）と高さ（m）。
@export var idle_model_rotation_degrees: Vector3 = Vector3.ZERO
@export var idle_model_height: float = 0.8
## 伏せ姿の Model の回転（度）と高さ（m）。
@export var prone_model_rotation_degrees: Vector3 = Vector3(90.0, 0.0, 0.0)
@export var prone_model_height: float = 0.35
## ダウン時の固定姿勢（度）と高さ（m）。
@export var downed_model_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 90.0)
@export var downed_model_height: float = 0.35
## Hurtbox の通常時の回転（度）と高さ（m）。
@export var standing_hurtbox_rotation_degrees: Vector3 = Vector3.ZERO
@export var standing_hurtbox_height: float = 0.8
## Hurtbox の伏せ時の回転（度）と高さ（m）。無効化せず、将来の銃撃を受けられるようにする。
@export var prone_hurtbox_rotation_degrees: Vector3 = Vector3(90.0, 0.0, 0.0)
@export var prone_hurtbox_height: float = 0.35
## ロックオン中に近接が届くよう持ち上げる Hurtbox の高さ（m）。
@export var targeted_hurtbox_height: float = 0.8

@export_group("Appearance")
## 各ステートを識別する色。
@export var color_idle: Color = Color(0.24, 0.46, 0.72)
@export var color_prone: Color = Color(0.22, 0.62, 0.48)
@export var color_shielded: Color = Color(0.82, 0.52, 0.18)
@export var color_staggered: Color = Color(0.92, 0.68, 0.20)
@export var color_downed: Color = Color(0.30, 0.30, 0.34)

@export_group("Nodes")
@export var model_path: NodePath = ^"Model"
@export var mesh_path: NodePath = ^"Model/Mesh"
@export var health_path: NodePath = ^"Health"
@export var hurtbox_path: NodePath = ^"Hurtbox"
@export var hurtbox_shape_path: NodePath = ^"Hurtbox/CollisionShape3D"
@export var state_machine_path: NodePath = ^"StateMachine"
@export_group("")

## 現在ステートが変わった（デバッグ表示・テスト用）。
signal state_entered(state: int)

var _model: Node3D = null
var _mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _health: Health = null
var _hurtbox: Area3D = null
var _hurtbox_shape: CollisionShape3D = null
var _sm: StateMachine = null

## STAGGERED 終了後に戻る立ち姿／伏せ姿。
var _return_state: int = CivilianState.IDLE
## プレイヤー側から通知された、意図して近接対象にしている間だけ true。
var _melee_targetable: bool = false


func _ready() -> void:
	_model = get_node_or_null(model_path) as Node3D
	_mesh = get_node_or_null(mesh_path) as MeshInstance3D
	_health = get_node_or_null(health_path) as Health
	_hurtbox = get_node_or_null(hurtbox_path) as Area3D
	_hurtbox_shape = get_node_or_null(hurtbox_shape_path) as CollisionShape3D
	_sm = get_node_or_null(state_machine_path) as StateMachine

	if _mesh != null:
		# 個体ごとに独立した色変化にするためマテリアルを複製する。
		var base := _mesh.get_active_material(0)
		if base is StandardMaterial3D:
			_material = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			_material = StandardMaterial3D.new()
		_mesh.material_override = _material

	if _health != null:
		_health.staggered.connect(_on_staggered)
		_health.downed.connect(_on_downed)

	RunState.civilians_total += 1
	GameDirector.act_changed.connect(_on_act_changed)

	if _sm == null:
		push_warning("civilian: StateMachine が無い")
		return
	_sm.add_state(CivilianState.IDLE, &"idle", _enter_idle)
	_sm.add_state(CivilianState.PRONE, &"prone", _enter_prone)
	_sm.add_state(CivilianState.SHIELDED, &"shielded", _enter_shielded)
	# FLEE_ROBBER / FLEE_PLAYER の登録と遷移は 8/22 に実装する。
	_sm.add_state(CivilianState.STAGGERED, &"staggered", _enter_staggered, _physics_staggered)
	_sm.add_state(CivilianState.DOWNED, &"downed", _enter_downed)
	_sm.state_changed.connect(func(_from: int, to: int) -> void: state_entered.emit(to))

	_return_state = _rest_state_for_act(GameDirector.current_act)
	_sm.start(_return_state)


func _physics_process(delta: float) -> void:
	if _sm != null:
		_sm.physics_update(delta)

	# 客は自走しない。床への追従に必要な重力だけを適用する。
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0
	move_and_slide()


## 現在のステート（テスト・デバッグ用）。
func current_state() -> int:
	return _sm.current() if _sm != null else CivilianState.IDLE


## ロックオン中の客本人だけ、伏せた見た目を保ったまま近接可能な高さへする。
## Model まで起こすと「狙って屈んで殴る」という意図が姿勢から失われるため、
## 変更するのは Hurtbox の高さだけに限定する。
func set_melee_targetable(enabled: bool) -> void:
	var state := current_state()
	# 保持・ダウン中は外部のロック状態にかかわらず通常の当たり判定へ戻す。
	_melee_targetable = enabled \
		and state != CivilianState.SHIELDED and state != CivilianState.DOWNED
	_apply_hurtbox_pose_for_state(state)


## リーダーから呼ぶ保持開始API。holder は呼び出し元を明示するため受け取るが、
## 客から犯人への依存を作らないよう参照は保存しない。位置と向きも外側が更新する。
func enter_shielded(_holder: Node3D) -> void:
	if _sm == null or _sm.current() == CivilianState.DOWNED:
		return
	_sm.transition_to(CivilianState.SHIELDED)


## リーダーから呼ぶ保持解除API。解除時点の幕に対応する通常姿勢へ戻す。
func exit_shielded() -> void:
	if _sm == null or _sm.current() != CivilianState.SHIELDED:
		return
	_return_state = _rest_state_for_act(GameDirector.current_act)
	_sm.transition_to(_return_state)


# --- IDLE / PRONE ---------------------------------------------------------

func _enter_idle() -> void:
	_set_color(color_idle)
	_set_model_pose(idle_model_rotation_degrees, idle_model_height)
	_apply_hurtbox_pose_for_state(CivilianState.IDLE)


func _enter_prone() -> void:
	_set_color(color_prone)
	_set_model_pose(prone_model_rotation_degrees, prone_model_height)
	_apply_hurtbox_pose_for_state(CivilianState.PRONE)


# --- SHIELDED -------------------------------------------------------------

func _enter_shielded() -> void:
	_melee_targetable = false
	_set_color(color_shielded)
	# 盾の間は伏せず、IDLE と同じ立ち姿と Hurtbox を使う。
	_set_model_pose(idle_model_rotation_degrees, idle_model_height)
	_set_hurtbox_pose(standing_hurtbox_rotation_degrees, standing_hurtbox_height)


# --- STAGGERED ------------------------------------------------------------

func _enter_staggered() -> void:
	_set_color(color_staggered)


func _physics_staggered(_delta: float) -> void:
	if _sm.time_in_state() >= stagger_duration:
		_sm.transition_to(_return_state)


# --- DOWNED ---------------------------------------------------------------

func _enter_downed() -> void:
	_melee_targetable = false
	_set_color(color_downed)
	_set_model_pose(downed_model_rotation_degrees, downed_model_height)
	_set_hurtbox_pose(prone_hurtbox_rotation_degrees, prone_hurtbox_height)
	# ダウンは Hitbox → Hurtbox → Health の信号処理中に確定するため、
	# Area3D の監視フラグは物理ステップの終わりに反映させる。
	if _hurtbox != null:
		_hurtbox.set_deferred("monitoring", false)
		_hurtbox.set_deferred("monitorable", false)


# --- Health / GameDirector からの通知 ------------------------------------

func _on_staggered() -> void:
	if _sm == null or _sm.current() == CivilianState.DOWNED:
		return
	var current := _sm.current()
	# 保持中の姿勢・位置制御を軽い被弾で解除しない。HPが尽きた場合は
	# Health.downed から通常どおり DOWNED へ遷移する。
	if current == CivilianState.SHIELDED:
		return
	if current == CivilianState.IDLE or current == CivilianState.PRONE:
		_return_state = current
	# 連続被弾でよろけ時間を延長する。
	_sm.transition_to(CivilianState.STAGGERED, true)


func _on_downed(lethal: bool) -> void:
	if _sm == null or _sm.current() == CivilianState.DOWNED:
		return
	RunState.record_down(self, GameTypes.Faction.CIVILIAN, lethal)
	_sm.transition_to(CivilianState.DOWNED)


func _on_act_changed(act: int) -> void:
	if _sm == null or _sm.current() == CivilianState.DOWNED:
		return
	_return_state = _rest_state_for_act(act)
	var current := _sm.current()
	if current == CivilianState.IDLE or current == CivilianState.PRONE:
		_sm.transition_to(_return_state)
	# SHIELDED 中は立ち姿を維持し、解除時にここで更新した _return_state を使う。
	# BREACH 以降の FLEE_ROBBER と、客ダウン後の FLEE_PLAYER は 8/22 に実装する。


func _rest_state_for_act(act: int) -> int:
	return CivilianState.IDLE if act == GameTypes.Act.PROLOGUE else CivilianState.PRONE


# --- 表示・姿勢ヘルパ ------------------------------------------------------

func _set_color(color: Color) -> void:
	if _material != null:
		_material.albedo_color = color


func _set_model_pose(pose_rotation_degrees: Vector3, height: float) -> void:
	if _model == null:
		return
	_model.rotation_degrees = pose_rotation_degrees
	var position := _model.position
	position.y = height
	_model.position = position


func _set_hurtbox_pose(pose_rotation_degrees: Vector3, height: float) -> void:
	if _hurtbox_shape == null:
		return
	_hurtbox_shape.rotation_degrees = pose_rotation_degrees
	var position := _hurtbox_shape.position
	position.y = height
	_hurtbox_shape.position = position


func _apply_hurtbox_pose_for_state(state: int) -> void:
	var pose_state := state
	if state == CivilianState.STAGGERED:
		pose_state = _return_state
	if pose_state == CivilianState.PRONE:
		var height := targeted_hurtbox_height if _melee_targetable else prone_hurtbox_height
		_set_hurtbox_pose(prone_hurtbox_rotation_degrees, height)
		return
	if pose_state == CivilianState.DOWNED:
		_set_hurtbox_pose(prone_hurtbox_rotation_degrees, prone_hurtbox_height)
		return
	_set_hurtbox_pose(standing_hurtbox_rotation_degrees, standing_hurtbox_height)
