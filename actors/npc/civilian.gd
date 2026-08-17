extends CharacterBody3D
class_name Civilian

## 客の共通挙動（technical-spec §8）。
## コンテスト版では BREACH を作らないため、FLEE_ROBBER は実装しない。
##
## 見た目は `Model` 子ノード1個に隔離する。差し替えは `model_scene` 1か所で完結する。
## 伏せ・ダウンの姿勢はアニメーションが持ち（伏せ＝うつ伏せで静止、ダウン＝仰向けに
## 倒れる）、Model を倒して表すのはプリミティブ表示のときだけ。
## 向きは犯人と同じく本体を回し、前方は Godot 標準の -Z。

## SHIELDED はリーダーが位置を制御する間の立ち姿と当たり判定を、通常の
## IDLE / PRONE から独立させるための状態。既存IDを保つため末尾へ追加する。
enum CivilianState { IDLE, PRONE, FLEE_ROBBER, FLEE_PLAYER, STAGGERED, DOWNED, SHIELDED }

@export_group("Reaction")
## 被弾でよろけている秒数。
@export var stagger_duration: float = 0.45

@export_group("Flee Player")
## 客が1人以上ダウンした後、プレイヤーを警戒し始める距離（m）。
@export var flee_trigger_distance: float = 4.0
## プレイヤーから逃げる移動速度（m/s）。
@export var flee_speed: float = 3.0
## この距離まで離れたら幕に応じた通常姿勢へ戻る（m）。
@export var flee_stop_distance: float = 7.0
## 逃走中の経路目標を現在位置から離す距離（m）。
@export var flee_path_distance: float = 8.0
## 壁による見失い判定に使う目線の高さ（m）。
@export var flee_eye_height: float = 1.0
## プレイヤーを探すグループ名。
@export var player_group: StringName = &"player"
## 見失い判定を遮る物理レイヤー（既定は world）。
@export_flags_3d_physics var flee_obstacle_mask: int = 1

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
## 被弾フラッシュの色・持続秒数・ピーク時の濃さ。誤爆に気づけるよう、客にも出す。
@export var flash_color: Color = Color(1, 1, 1, 1)
@export var flash_duration: float = 0.08
@export_range(0.0, 1.0) var flash_tint_alpha: float = 0.85
## 見た目。`Model` の下へ差し込むキャラクターのシーン（Mixamo の FBX）。
## 差し替えはここ1か所で完結させる（technical-spec §9）。
@export var model_scene: PackedScene
## 主人公の VRM（MToon）へ寄せるため、写真テクスチャの陰影をトゥーンへ置き換える。
## 切ると Mixamo 本来の見た目に戻る。
@export var toon_skin: bool = true
## 各ステートを識別する色。
@export var color_idle: Color = Color(0.24, 0.46, 0.72)
@export var color_prone: Color = Color(0.22, 0.62, 0.48)
@export var color_shielded: Color = Color(0.82, 0.52, 0.18)
@export var color_flee_player: Color = Color(0.68, 0.28, 0.62)
@export var color_staggered: Color = Color(0.92, 0.68, 0.20)
@export var color_downed: Color = Color(0.30, 0.30, 0.34)

@export_group("Nodes")
@export var model_path: NodePath = ^"Model"
@export var animator_path: NodePath = ^"Animator"
@export var health_path: NodePath = ^"Health"
@export var hurtbox_path: NodePath = ^"Hurtbox"
@export var hurtbox_shape_path: NodePath = ^"Hurtbox/CollisionShape3D"
@export var agent_path: NodePath = ^"NavigationAgent3D"
@export var state_machine_path: NodePath = ^"StateMachine"
@export_group("")

## 現在ステートが変わった（デバッグ表示・テスト用）。
signal state_entered(state: int)

var _model: Node3D = null
var _animator: NpcAnimator = null
var _tint: ModelTint = ModelTint.new()
## 現在のステート色。描画には使わないが、テストとデバッグのために保持する。
var _state_color: Color = Color.WHITE
var _flash_tween: Tween = null
var _health: Health = null
var _hurtbox: Area3D = null
var _hurtbox_shape: CollisionShape3D = null
var _agent: NavigationAgent3D = null
var _sm: StateMachine = null
var _player: Node3D = null
var _flee_mode: bool = false

## STAGGERED 終了後に戻る立ち姿／伏せ姿。
var _return_state: int = CivilianState.IDLE
## プレイヤー側から通知された、意図して近接対象にしている間だけ true。
var _melee_targetable: bool = false
## Hurtbox から通知された、最後に自分へ攻撃を成立させた本体。
var _last_attacker: Node3D = null


func _ready() -> void:
	_model = get_node_or_null(model_path) as Node3D
	_health = get_node_or_null(health_path) as Health
	_hurtbox = get_node_or_null(hurtbox_path) as Area3D
	_hurtbox_shape = get_node_or_null(hurtbox_shape_path) as CollisionShape3D
	_agent = get_node_or_null(agent_path) as NavigationAgent3D
	_sm = get_node_or_null(state_machine_path) as StateMachine

	if _model != null and model_scene != null:
		_model.add_child(model_scene.instantiate())
	if toon_skin:
		ToonSkin.apply(_model)
	_tint.setup(_model)
	# Animator は Model を読むので、キャラクターを差し込んだ後に初期化させる。
	_animator = get_node_or_null(animator_path) as NpcAnimator
	if _animator != null:
		_animator.setup()

	if _health != null:
		_health.staggered.connect(_on_staggered)
		_health.downed.connect(_on_downed)

	RunState.civilians_total += 1
	_flee_mode = RunState.civilians_downed > 0
	RunState.civilian_downed.connect(_on_civilian_downed)
	GameDirector.act_changed.connect(_on_act_changed)

	if _sm == null:
		push_warning("civilian: StateMachine が無い")
		return
	_sm.add_state(CivilianState.IDLE, &"idle", _enter_idle, _physics_rest)
	_sm.add_state(CivilianState.PRONE, &"prone", _enter_prone, _physics_rest)
	_sm.add_state(CivilianState.SHIELDED, &"shielded", _enter_shielded)
	_sm.add_state(CivilianState.FLEE_PLAYER, &"flee_player",
		_enter_flee_player, _physics_flee_player)
	# FLEE_ROBBER は Act.BREACH 以降の仕様であり、BREACH のないコンテスト版では登録しない。
	_sm.add_state(CivilianState.STAGGERED, &"staggered", _enter_staggered, _physics_staggered)
	_sm.add_state(CivilianState.DOWNED, &"downed", _enter_downed)
	_sm.state_changed.connect(func(_from: int, to: int) -> void: state_entered.emit(to))

	_return_state = _rest_state_for_act(GameDirector.current_act)
	_sm.start(_return_state)


func _physics_process(delta: float) -> void:
	if _sm != null:
		_sm.physics_update(delta)

	if current_state() != CivilianState.FLEE_PLAYER:
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
	# 客に構えを取らせない。直立で静止させる。
	_play(NpcAnimator.Clip.STAND)
	_set_model_pose(idle_model_rotation_degrees, idle_model_height)
	_apply_hurtbox_pose_for_state(CivilianState.IDLE)


func _enter_prone() -> void:
	_set_color(color_prone)
	# うつ伏せで静止させる。仰向けに倒れるダウンと見分けが付く。
	_play(NpcAnimator.Clip.PRONE)
	_set_model_pose(prone_model_rotation_degrees, prone_model_height)
	_apply_hurtbox_pose_for_state(CivilianState.PRONE)


func _physics_rest(_delta: float) -> void:
	if not _flee_mode:
		return
	_resolve_player()
	if _player == null:
		return
	if _flat_distance_to(_player.global_position) <= flee_trigger_distance \
			and _can_see_player():
		_sm.transition_to(CivilianState.FLEE_PLAYER)


# --- FLEE_PLAYER ----------------------------------------------------------

func _enter_flee_player() -> void:
	_melee_targetable = false
	_set_color(color_flee_player)
	# 走行中は立ち姿に戻す。停止時に幕に応じて IDLE / PRONE を選び直す。
	_set_model_pose(idle_model_rotation_degrees, idle_model_height)
	_set_hurtbox_pose(standing_hurtbox_rotation_degrees, standing_hurtbox_height)


func _physics_flee_player(_delta: float) -> void:
	_resolve_player()
	if _player == null or not _can_see_player():
		_return_to_rest()
		return

	var distance := _flat_distance_to(_player.global_position)
	if distance >= flee_stop_distance:
		_return_to_rest()
		return

	var away := global_position - _player.global_position
	away.y = 0.0
	if away.length_squared() <= 0.0:
		away = global_transform.basis.z
	away = away.normalized()
	if _agent == null:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# 目標点をプレイヤーの反対側へ更新し、NavigationAgent3D の経路に沿う。
	# 直線移動を使わないため、壁や什器に向かって走り続けない。
	var desired_target := _player.global_position + away * flee_path_distance
	# 毎フレーム現在位置基準で目標を動かすと経路が先頭へ戻り続けるため、
	# プレイヤー基準の安定した目標を、有意に変わったときだけ更新する。
	if _agent.target_position.distance_to(desired_target) > _agent.path_desired_distance:
		_agent.target_position = desired_target
	var next_position := _agent.get_next_path_position()
	var move_direction := next_position - global_position
	move_direction.y = 0.0
	if move_direction.length_squared() <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	move_direction = move_direction.normalized()
	velocity.x = move_direction.x * flee_speed
	velocity.z = move_direction.z * flee_speed
	if _animator != null and _animator.is_active():
		_animator.drive_locomotion(Vector2(velocity.x, velocity.z).length())


# --- SHIELDED -------------------------------------------------------------

func _enter_shielded() -> void:
	_melee_targetable = false
	_set_color(color_shielded)
	_play(NpcAnimator.Clip.STAND)
	# 盾の間は伏せず、IDLE と同じ立ち姿と Hurtbox を使う。
	_set_model_pose(idle_model_rotation_degrees, idle_model_height)
	_set_hurtbox_pose(standing_hurtbox_rotation_degrees, standing_hurtbox_height)


# --- STAGGERED ------------------------------------------------------------

func _enter_staggered() -> void:
	_set_color(color_staggered)
	# 連続被弾では頭から出し直す。
	_play(NpcAnimator.Clip.HIT, true)


func _physics_staggered(_delta: float) -> void:
	if _sm.time_in_state() >= stagger_duration:
		_sm.transition_to(_return_state)


# --- DOWNED ---------------------------------------------------------------

func _enter_downed() -> void:
	_melee_targetable = false
	_set_color(color_downed)
	_play(NpcAnimator.Clip.DOWN, true)
	_set_model_pose(downed_model_rotation_degrees, downed_model_height)
	_set_hurtbox_pose(prone_hurtbox_rotation_degrees, prone_hurtbox_height)
	# ダウンは Hitbox → Hurtbox → Health の信号処理中に確定するため、
	# Area3D の監視フラグは物理ステップの終わりに反映させる。
	# 客の遺体を追い打ち可能にすると「失敗」への事故経路が増えるため、犯人と違い
	# monitorable も切ったままにし、追い打ち対象にはしない。
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
	RunState.record_down(self, GameTypes.Faction.CIVILIAN, lethal, _last_attacker)
	_sm.transition_to(CivilianState.DOWNED)


## Hurtbox から具体的な攻撃種別に依存せず、最後の加害者を受け取る。
func record_attacker(attacker: Node3D) -> void:
	_last_attacker = attacker


func _on_civilian_downed(total: int) -> void:
	if total > 0:
		_flee_mode = true


func _on_act_changed(act: int) -> void:
	if _sm == null or _sm.current() == CivilianState.DOWNED:
		return
	_return_state = _rest_state_for_act(act)
	var current := _sm.current()
	if current == CivilianState.IDLE or current == CivilianState.PRONE:
		_sm.transition_to(_return_state)
	# SHIELDED 中は立ち姿を維持し、解除時にここで更新した _return_state を使う。
	# FLEE_PLAYER 中は停止時に更新済みの _return_state へ戻る。


func _rest_state_for_act(act: int) -> int:
	return CivilianState.IDLE if act == GameTypes.Act.PROLOGUE else CivilianState.PRONE


func _return_to_rest() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_return_state = _rest_state_for_act(GameDirector.current_act)
	_sm.transition_to(_return_state)


func _resolve_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group) as Node3D


func _can_see_player() -> bool:
	if _player == null:
		return false
	var from := global_position + Vector3.UP * flee_eye_height
	var to := _player.global_position + Vector3.UP * flee_eye_height
	var query := PhysicsRayQueryParameters3D.create(
		from, to, flee_obstacle_mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _flat_distance_to(position: Vector3) -> float:
	return Vector2(global_position.x - position.x, global_position.z - position.z).length()


# --- 表示・姿勢ヘルパ ------------------------------------------------------

## ステート色を記録する。描画には使わない。ステートは姿勢（立つ・伏せる・逃げる・
## 倒れる）で伝わるため、色を重ねると犯人側の色と混ざって読めなくなる。
## 見た目に出すのは被弾フラッシュだけ（flash_hit）。
func _set_color(color: Color) -> void:
	_state_color = color


## Hurtbox から呼ばれる被弾フラッシュ。白を短く重ねる。
func flash_hit() -> void:
	if not _tint.is_ready():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(_apply_flash_mix, 1.0, 0.0, flash_duration)


func _apply_flash_mix(amount: float) -> void:
	if _tint.is_ready():
		_tint.apply(flash_color, amount * flash_tint_alpha)


func _play(clip: int, force: bool = false) -> void:
	if _animator != null and _animator.is_active():
		_animator.play(clip, -1.0, 1.0, force)


## プリミティブ表示（カプセル）のときだけ Model を倒して姿勢を表す。
## キャラクターモデルが入っている場合は、姿勢はアニメーションが持つ。
func _set_model_pose(pose_rotation_degrees: Vector3, height: float) -> void:
	if _animator != null and _animator.is_active():
		return
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
