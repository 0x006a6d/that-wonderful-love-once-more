extends CharacterBody3D
class_name Robber

## 犯人の共通挙動（technical-spec §9 / tasks.md 8/17）。
## 役割差（leader / gunner / erratic）は後日 `roles/` で注入する。ここは3体共通の骨格。
##
## 見た目は当面プリミティブ。Mixamo素材は Without Skin でメッシュを持たず、
## 主人公VRMは公式アセットのため流用しない（CLAUDE.md「使用できるアセット」）。
## 状態はメッシュの色で示す（通常 / 警戒 / 攻撃の予備動作）。
##
## 攻撃判定の窓はこのスクリプトのタイマーで開閉する。主人公（§6.3）は
## AnimationPlayer の Call Method Track を使うが、犯人はまだリグとクリップを
## 持たないため。リグを入れた時点で Call Method Track 方式へ移す。
##
## 向きの規約: 犯人は本体（CharacterBody3D）を回し、前方は Godot 標準の -Z。
## 主人公は VRM の都合で Model ノードの +Z が前方であり、そちらとは規約が異なる。

enum State { PATROL, ALERT, CHASE, ATTACK, STAGGERED, DOWNED }

## 追跡対象を探すグループ名。プレイヤーが自分を登録している。
@export var target_group: StringName = &"player"

@export_group("Movement")
## 巡回時の移動速度（m/s）。
@export var patrol_speed: float = 1.4
## 追跡時の移動速度（m/s）。プレイヤー（4.5）より遅くし、逃げれば振り切れるようにする。
@export var chase_speed: float = 3.2
## 向き直りの補間速さ（lerp 係数）。
@export var rotation_speed: float = 8.0
## 巡回する地点。空なら初期位置で待機する。`Marker3D` を並べて指定する。
@export var patrol_points: Array[NodePath] = []
## 巡回地点に到達したとみなす距離（m）。
@export var patrol_arrive_distance: float = 0.6
## 巡回地点で立ち止まる秒数。
@export var patrol_wait: float = 1.5

@export_group("Perception")
## 視認距離（m）。
@export var sight_range: float = 12.0
## 視野角（度、全角）。この外は見えない。
@export var sight_fov_deg: float = 110.0
## 視野角に関係なく気づく距離（m）。背後に張り付かれても反応する。
@export var close_notice_range: float = 2.5
## 見失ってから巡回へ戻るまでの秒数。
@export var lose_sight_duration: float = 4.0
## 目の高さ（m）。視線判定の始点。
@export var eye_height: float = 1.5

@export_group("Combat")
## 攻撃を始める距離（m）。
@export var attack_range: float = 1.7
## 攻撃を中断せず追撃を続ける距離（m）。attack_range より少し広く取る。
@export var attack_keep_range: float = 2.4
## 予備動作の秒数（プレイヤーが見てから避けられる長さ）。
@export var attack_telegraph: float = 0.45
## 判定を開いている秒数。
@export var attack_active: float = 0.18
## 硬直の秒数。
@export var attack_recovery: float = 0.35
## 次の攻撃までの間隔（秒）。
@export var attack_cooldown: float = 0.8
## 攻撃の踏み込み初速（m/s）。
@export var attack_lunge_speed: float = 2.2
## 与ダメージ。
@export var attack_damage: float = 12.0
## 与ノックバック強度。
@export var attack_knockback: float = 3.0

@export_group("Reaction")
## 被弾でよろけている秒数。
@export var stagger_duration: float = 0.45
## ノックバックの初速（m/s）。
@export var knockback_speed: float = 3.0
## ノックバックが減衰しきるまでの秒数。
@export var knockback_decay: float = 0.25
## 被弾フラッシュの色と持続秒数。
@export var flash_color: Color = Color(1, 1, 1, 1)
@export var flash_duration: float = 0.08
## ダウン時に倒れる角度（度）と所要秒数。ラグドールは使わない（tasks.md）。
@export var fall_angle_deg: float = 85.0
@export var fall_duration: float = 0.4

@export_group("Appearance")
## 通常時の色。
@export var color_idle: Color = Color(0.42, 0.24, 0.26)
## 警戒・追跡時の色。
@export var color_alert: Color = Color(0.72, 0.52, 0.18)
## 攻撃の予備動作中の色。
@export var color_telegraph: Color = Color(0.85, 0.18, 0.16)

@export_group("Nodes")
@export var mesh_path: NodePath = ^"Mesh"
@export var health_path: NodePath = ^"Health"
@export var hurtbox_path: NodePath = ^"Hurtbox"
@export var hitbox_path: NodePath = ^"MeleeHitbox"
@export var agent_path: NodePath = ^"NavigationAgent3D"
@export var state_machine_path: NodePath = ^"StateMachine"
@export_group("")

## 現在ステートが変わった（デバッグ表示・テスト用）。
signal state_entered(state: int)

var _mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _health: Health = null
var _hurtbox: Area3D = null
var _hitbox: Hitbox = null
var _agent: NavigationAgent3D = null
var _sm: StateMachine = null

var _target: Node3D = null
var _home_position: Vector3 = Vector3.ZERO
var _patrol_index: int = 0
var _patrol_wait_left: float = 0.0
var _lost_sight_for: float = 0.0
var _cooldown_left: float = 0.0
var _hitbox_open: bool = false
var _engaged_notified: bool = false

var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0


func _ready() -> void:
	_mesh = get_node_or_null(mesh_path) as MeshInstance3D
	_health = get_node_or_null(health_path) as Health
	_hurtbox = get_node_or_null(hurtbox_path) as Area3D
	_hitbox = get_node_or_null(hitbox_path) as Hitbox
	_agent = get_node_or_null(agent_path) as NavigationAgent3D
	_sm = get_node_or_null(state_machine_path) as StateMachine

	_home_position = global_position

	if _mesh != null:
		# 個体ごとに独立した色変化にするためマテリアルを複製する。
		var base := _mesh.get_active_material(0)
		if base is StandardMaterial3D:
			_material = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			_material = StandardMaterial3D.new()
		_mesh.material_override = _material
		_material.albedo_color = color_idle

	if _health != null:
		_health.staggered.connect(_on_staggered)
		_health.downed.connect(_on_downed)

	if _sm == null:
		push_warning("robber: StateMachine が無い")
		return
	_sm.add_state(State.PATROL, &"patrol", _enter_patrol, _physics_patrol)
	_sm.add_state(State.ALERT, &"alert", _enter_alert, _physics_alert)
	_sm.add_state(State.CHASE, &"chase", _enter_chase, _physics_chase)
	_sm.add_state(State.ATTACK, &"attack", _enter_attack, _physics_attack, _exit_attack)
	_sm.add_state(State.STAGGERED, &"staggered", _enter_staggered, _physics_staggered)
	_sm.add_state(State.DOWNED, &"downed", _enter_downed)
	_sm.state_changed.connect(func(_from: int, to: int) -> void: state_entered.emit(to))
	# ナビゲーションマップの初期化は次フレーム以降のため、1 フレーム待ってから開始する。
	call_deferred("_start_state_machine")


func _start_state_machine() -> void:
	_resolve_target()
	_sm.start(State.PATROL)


func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if _sm != null:
		_sm.physics_update(delta)

	# ノックバックは全ステートに優先して水平速度を上書きする。
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
		_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO,
			(knockback_speed / knockback_decay) * delta)

	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0
	move_and_slide()


## 現在のステート（テスト・デバッグ用）。
func current_state() -> int:
	return _sm.current() if _sm != null else State.PATROL


# --- PATROL ---------------------------------------------------------------

func _enter_patrol() -> void:
	_set_color(color_idle)
	_lost_sight_for = 0.0
	_patrol_wait_left = 0.0


func _physics_patrol(delta: float) -> void:
	if _sees_target():
		_sm.transition_to(State.ALERT)
		return

	if patrol_points.is_empty():
		# 巡回地点が無ければ初期位置で待機する。
		_stop_horizontal(delta)
		return

	var point := _patrol_point(_patrol_index)
	if point == null:
		_stop_horizontal(delta)
		return

	if _patrol_wait_left > 0.0:
		_patrol_wait_left -= delta
		_stop_horizontal(delta)
		return

	var flat_distance := _flat_distance_to(point.global_position)
	if flat_distance <= patrol_arrive_distance:
		_patrol_wait_left = patrol_wait
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		_stop_horizontal(delta)
		return

	_navigate_toward(point.global_position, patrol_speed, delta)


# --- ALERT ----------------------------------------------------------------

func _enter_alert() -> void:
	_set_color(color_alert)
	# 幕の進行を促す（INFILTRATION -> ENGAGEMENT）。1体が気づけば十分。
	if not _engaged_notified:
		_engaged_notified = true
		GameDirector.notify_robber_engaged()


func _physics_alert(delta: float) -> void:
	_stop_horizontal(delta)
	if _target != null:
		_face_position(_target.global_position, delta)
	# 気づいてから飛びかかるまでの一拍。予備動作として見せる。
	if _sm.time_in_state() >= 0.4:
		_sm.transition_to(State.CHASE)


# --- CHASE ----------------------------------------------------------------

func _enter_chase() -> void:
	_set_color(color_alert)
	_lost_sight_for = 0.0


func _physics_chase(delta: float) -> void:
	if _target == null:
		_resolve_target()
		if _target == null:
			_sm.transition_to(State.PATROL)
			return

	if _sees_target():
		_lost_sight_for = 0.0
	else:
		_lost_sight_for += delta
		if _lost_sight_for >= lose_sight_duration:
			_sm.transition_to(State.PATROL)
			return

	var distance := _flat_distance_to(_target.global_position)
	if distance <= attack_range and _cooldown_left <= 0.0:
		_sm.transition_to(State.ATTACK)
		return

	if distance <= attack_range * 0.8:
		# 射程内だがクールダウン中。踏み込まず間合いを保つ。
		_stop_horizontal(delta)
		_face_position(_target.global_position, delta)
		return

	_navigate_toward(_target.global_position, chase_speed, delta)


# --- ATTACK ---------------------------------------------------------------

func _enter_attack() -> void:
	_set_color(color_telegraph)
	_hitbox_open = false
	_stop_horizontal_immediate()


func _physics_attack(delta: float) -> void:
	var t := _sm.time_in_state()
	var active_end := attack_telegraph + attack_active
	var recovery_end := active_end + attack_recovery

	if t < attack_telegraph:
		# 予備動作。向きだけ合わせて踏みとどまる。
		_stop_horizontal(delta)
		if _target != null:
			_face_position(_target.global_position, delta)
		return

	if t < active_end:
		# 判定窓。開くのは1回だけ（Hitbox 側が二重ヒットを防ぐ）。
		if not _hitbox_open:
			_hitbox_open = true
			_set_color(color_alert)
			_open_hitbox()
			_lunge_forward()
		return

	if _hitbox_open:
		_close_hitbox()

	if t < recovery_end:
		# 硬直。次の攻撃までここで足を止める。
		_stop_horizontal(delta)
		return

	_cooldown_left = attack_cooldown
	_sm.transition_to(State.CHASE)


func _exit_attack() -> void:
	_close_hitbox()


# --- STAGGERED ------------------------------------------------------------

func _enter_staggered() -> void:
	_close_hitbox()
	_set_color(color_alert)


func _physics_staggered(delta: float) -> void:
	# のけぞり中は自走しない（ノックバックは _physics_process 側が上書きする）。
	_stop_horizontal(delta)
	if _sm.time_in_state() >= stagger_duration:
		# 殴られた時点でプレイヤーの位置は分かっている。追跡へ戻す。
		_resolve_target()
		_sm.transition_to(State.CHASE)


# --- DOWNED ---------------------------------------------------------------

func _enter_downed() -> void:
	_close_hitbox()
	_stop_horizontal_immediate()
	# これ以上殴られない・押されない。
	# ダウンは Hitbox → Hurtbox → Health の信号処理中に確定するため、Area3D の
	# 監視フラグは即時に書き換えられない（"Function blocked during in/out signal"）。
	# 物理ステップの終わりに反映させる。
	if _hurtbox != null:
		_hurtbox.set_deferred("monitoring", false)
		_hurtbox.set_deferred("monitorable", false)
	set_collision_layer_value(3, false)
	# 固定ポーズで倒す（ラグドールはコンテスト版では扱わない）。
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", deg_to_rad(fall_angle_deg), fall_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# --- Health からの通知 -----------------------------------------------------

func _on_staggered() -> void:
	if _sm == null or _sm.current() == State.DOWNED:
		return
	# 連続被弾で滞在時間を延ばす（force=true で再進入）。
	_sm.transition_to(State.STAGGERED, true)


func _on_downed(lethal: bool) -> void:
	if _sm == null or _sm.current() == State.DOWNED:
		return
	RunState.record_down(self, GameTypes.Faction.ROBBER, lethal)
	# 犯人が1体ダウンしても幕は進む（technical-spec §5）。
	if not _engaged_notified:
		_engaged_notified = true
		GameDirector.notify_robber_engaged()
	_sm.transition_to(State.DOWNED)


# --- Hurtbox からの呼び出し -------------------------------------------------

## direction は攻撃者→自分の水平方向。
func receive_knockback(direction: Vector3, strength: float) -> void:
	if _sm != null and _sm.current() == State.DOWNED:
		return
	var d := direction
	d.y = 0.0
	if d.length() < 0.001:
		return
	_knockback_vel = d.normalized() * knockback_speed * clampf(strength / 5.0, 0.5, 2.0)
	_knockback_timer = knockback_decay


func flash_hit() -> void:
	if _material == null:
		return
	var restore := _material.albedo_color
	_material.albedo_color = flash_color
	var tw := create_tween()
	tw.tween_property(_material, "albedo_color", restore, flash_duration)


# --- 内部ヘルパ -------------------------------------------------------------

func _resolve_target() -> void:
	_target = get_tree().get_first_node_in_group(target_group) as Node3D


## 視界内にプレイヤーがいるか。距離・視野角・遮蔽の3段で判定する。
func _sees_target() -> bool:
	if _target == null:
		_resolve_target()
		if _target == null:
			return false
	var to := _target.global_position - global_position
	var flat := Vector2(to.x, to.z)
	var distance := flat.length()
	if distance > sight_range:
		return false
	if distance > close_notice_range:
		var forward := -global_transform.basis.z
		var angle := absf(rad_to_deg(Vector2(forward.x, forward.z).angle_to(flat)))
		if angle > sight_fov_deg * 0.5:
			return false
	return _has_line_of_sight()


## 目の高さから相手の胸へレイを飛ばし、world レイヤー（1）に遮られていないか見る。
func _has_line_of_sight() -> bool:
	if _target == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * eye_height
	var to := _target.global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := space.intersect_ray(query)
	return hit.is_empty()


## NavigationAgent3D の経路に沿って進む。マップが未生成の場合は直線で寄る
## （ベイク前のステージでも動作確認できるようにするための保険）。
func _navigate_toward(destination: Vector3, speed: float, delta: float) -> void:
	var direction := Vector3.ZERO
	if _agent != null and _navigation_ready():
		_agent.target_position = destination
		var next := _agent.get_next_path_position()
		direction = next - global_position
	if direction.length() < 0.05:
		direction = destination - global_position
	direction.y = 0.0
	if direction.length() < 0.05:
		_stop_horizontal(delta)
		return
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_face_direction(direction, delta)


func _navigation_ready() -> bool:
	if _agent == null:
		return false
	var map := _agent.get_navigation_map()
	if not map.is_valid():
		return false
	return NavigationServer3D.map_get_iteration_id(map) > 0


func _flat_distance_to(point: Vector3) -> float:
	var d := point - global_position
	return Vector2(d.x, d.z).length()


func _patrol_point(index: int) -> Node3D:
	if index < 0 or index >= patrol_points.size():
		return null
	return get_node_or_null(patrol_points[index]) as Node3D


func _face_position(point: Vector3, delta: float) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	_face_direction(d.normalized(), delta)


## 前方は -Z。atan2(x, z) の結果に π を足すと -Z 向きのヨーになる。
func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(direction.x, direction.z) + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, rotation_speed * delta)


func _stop_horizontal(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z)
	horizontal = horizontal.move_toward(Vector2.ZERO, 20.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


func _stop_horizontal_immediate() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _lunge_forward() -> void:
	var forward := -global_transform.basis.z
	velocity.x = forward.x * attack_lunge_speed
	velocity.z = forward.z * attack_lunge_speed


func _open_hitbox() -> void:
	if _hitbox == null:
		return
	_hitbox.configure(attack_damage, attack_knockback, false)
	_hitbox.activate()


func _close_hitbox() -> void:
	_hitbox_open = false
	if _hitbox != null:
		_hitbox.deactivate()


func _set_color(color: Color) -> void:
	if _material != null:
		_material.albedo_color = color
