extends CharacterBody3D

## プレイヤー本体。カメラ相対の WASD 移動と、移動方向への回転補間。
## 攻撃入力を受けて PlayerMelee（AnimationTree 駆動）にコンボを走らせる。
## 攻撃判定 MeleeHitbox の ON/OFF は melee クリップの Call Method Track が
## _enable_hitbox / _disable_hitbox を叩いて行う（コードでタイマーを持たない・§6.3）。
## 命中時（Hitbox.hit_landed）に手応え演出（ヒットストップ＋カメラシェイク）を起動する。

## 平地移動速度（m/s）。身長160cm 基準の等身に合わせた既定値。
@export var move_speed: float = 4.5
## 加速度（m/s²）。一歩目がわずかに遅れることで質量感を出す。
@export var accel: float = 10.0
## 減速度（m/s²）。入力を離してもピタッと止まらず短い減速を挟む。
@export var decel: float = 14.0
## 攻撃開始時のブレーキ（m/s²）。移動慣性を踏み込み一歩ぶんだけ残して殺す。
@export var attack_brake: float = 30.0
## パンチ各段の踏み込み初速（m/s、x=ジャブ y=ストレート z=フック）。
## 段が進むほど深く踏み込み、ノックバックした相手にフィニッシュが届くようにする。
## attack_brake で減衰するため「一歩踏み込んで止まる」挙動になる。
@export var lunge_speeds: Vector3 = Vector3(1.5, 2.5, 3.5)
## キック各段の踏み込み初速（m/s、x=ひざ y=左ハイ z=回し蹴り）。
## 初段のひざは射程が短いため深めに踏み込む。
@export var kick_lunge_speeds: Vector3 = Vector3(3.0, 2.0, 2.0)
## 移動方向へ向き直る回転補間の速さ（rad/s 相当の lerp 係数）。
@export var rotation_speed: float = 12.0

@export_group("Hurt")
## 被弾時のノックバック初速（m/s）。
@export var hurt_knockback_speed: float = 3.5
## ノックバックが減衰しきるまでの時間（秒）。この間は移動入力を受け付けない。
@export var hurt_knockback_decay: float = 0.28
## 被弾時のカメラシェイク強度（0.0-1.0）。VRM は色を変えられないため、
## 手応えの提示はカメラ側で行う。
@export var hurt_shake_strength: float = 0.8
@export_group("")

## 命中時のヒットストップ時間（実時間・秒）。
@export var hit_stop_duration: float = 0.09
## 命中時のヒットストップのスロー係数（0 に近いほど強く止まる）。
@export var hit_stop_scale: float = 0.05
## 命中時のカメラシェイク強度（0.0-1.0）。
@export var hit_shake_strength: float = 0.6

@export var camera_path: NodePath = ^"SpringArm3D"
@export var model_path: NodePath = ^"Model"
@export var melee_path: NodePath = ^"PlayerMelee"
@export var hitbox_path: NodePath = ^"Model/MeleeHitbox"
@export var camera_shake_path: NodePath = ^"SpringArm3D/Camera3D/CameraShake"
@export var health_path: NodePath = ^"Health"

## HP が尽きた。ゲームオーバー処理・リスタートは後日（tasks.md にまだ無い）。
signal player_downed()

var _camera_rig: Node3D = null
var _model: Node3D = null
var _melee: Node = null
var _hitbox: Hitbox = null
var _camera_shake: Node = null
var _health: Health = null

## 被弾ロックの残り時間（秒）。0 より大きい間は移動入力を受け付けない。
var _hurt_timer: float = 0.0
var _knockback_vel: Vector3 = Vector3.ZERO
var _downed: bool = false


func _ready() -> void:
	_camera_rig = get_node_or_null(camera_path) as Node3D
	_model = get_node_or_null(model_path) as Node3D
	_melee = get_node_or_null(melee_path)
	_hitbox = get_node_or_null(hitbox_path) as Hitbox
	_camera_shake = get_node_or_null(camera_shake_path)
	_health = get_node_or_null(health_path) as Health

	if _hitbox != null:
		_hitbox.hit_landed.connect(_on_hit_landed)
	if _melee != null and _melee.has_signal("stage_started"):
		_melee.connect("stage_started", _on_stage_started)
	if _health != null:
		_health.downed.connect(_on_health_downed)


## コンボの段開始で前方へ踏み込む（attack_brake が減衰を担う）。
func _on_stage_started(kind: StringName, stage: int) -> void:
	if _model == null:
		return
	var yaw := _model.global_rotation.y
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var speeds := kick_lunge_speeds if kind == &"kick" else lunge_speeds
	var speed_for_stage: float = [speeds.x, speeds.y, speeds.z][stage - 1]
	velocity.x = forward.x * speed_for_stage
	velocity.z = forward.z * speed_for_stage


func _physics_process(delta: float) -> void:
	var attacking: bool = _melee != null and bool(_melee.call("is_attacking"))

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _camera_relative_direction(input_dir)

	if _hurt_timer > 0.0:
		_hurt_timer = maxf(_hurt_timer - delta, 0.0)

	# 速度は目標値へ加減速で寄せる（即時切替をやめて慣性＝質量感を出す）。
	var horizontal := Vector2(velocity.x, velocity.z)
	if _downed:
		horizontal = horizontal.move_toward(Vector2.ZERO, decel * delta)
	elif _hurt_timer > 0.0:
		# 被弾ロック中。ノックバックに流されるだけで、入力・攻撃は通らない。
		horizontal = Vector2(_knockback_vel.x, _knockback_vel.z)
		_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO,
			(hurt_knockback_speed / hurt_knockback_decay) * delta)
	elif attacking:
		# 攻撃中は移動入力を無視し、強めのブレーキで踏み込み一歩ぶんだけ滑って止まる。
		horizontal = horizontal.move_toward(Vector2.ZERO, attack_brake * delta)
	elif direction.length() > 0.001:
		var target := Vector2(direction.x, direction.z) * move_speed
		horizontal = horizontal.move_toward(target, accel * delta)
		_face_direction(direction, delta)
	else:
		horizontal = horizontal.move_toward(Vector2.ZERO, decel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	if _melee != null:
		var planar := Vector2(velocity.x, velocity.z).length()
		_melee.call("set_locomotion", planar)

	# カメラの自動追従へ移動方向を注入する（攻撃中・被弾中・停止中は ZERO）。
	if _camera_rig != null and _camera_rig.has_method("set_move_direction"):
		var locked: bool = attacking or _downed or _hurt_timer > 0.0
		var cam_dir := Vector3.ZERO if locked else direction
		_camera_rig.call("set_move_direction", cam_dir)


func _unhandled_input(event: InputEvent) -> void:
	if _downed or _hurt_timer > 0.0:
		return
	if event.is_action_pressed("attack"):
		if _melee != null:
			_melee.call("attack")
	elif event.is_action_pressed("kick"):
		if _melee != null:
			_melee.call("kick")


## MeleeHitbox の Call Method Track から呼ばれる（有効化）。
func _enable_hitbox(damage: float, knockback: float) -> void:
	if _hitbox == null:
		return
	_hitbox.configure(damage, knockback, false)
	_hitbox.activate()


## MeleeHitbox の Call Method Track から呼ばれる（無効化）。
func _disable_hitbox() -> void:
	if _hitbox == null:
		return
	_hitbox.deactivate()


## Hitbox が誰かに当たった瞬間の手応え演出。
func _on_hit_landed(_target: Node3D) -> void:
	var hs := get_node_or_null(^"/root/HitStop")
	if hs != null and hs.has_method("apply"):
		hs.call("apply", hit_stop_duration, hit_stop_scale)
	if _camera_shake != null and _camera_shake.has_method("shake"):
		_camera_shake.call("shake", hit_shake_strength)


## Hurtbox から呼ばれる。direction は攻撃者→自分の水平方向。
## 被弾ロックの間は移動入力と攻撃入力を受け付けない（一方的な連打で押し切れないように）。
func receive_knockback(direction: Vector3, strength: float) -> void:
	if _downed:
		return
	var d := direction
	d.y = 0.0
	if d.length() < 0.001:
		return
	_knockback_vel = d.normalized() * hurt_knockback_speed * clampf(strength / 5.0, 0.5, 2.0)
	_hurt_timer = hurt_knockback_decay


## Hurtbox から呼ばれる。VRM のマテリアルは触らず、カメラで被弾を提示する。
func flash_hit() -> void:
	if _camera_shake != null and _camera_shake.has_method("shake"):
		_camera_shake.call("shake", hurt_shake_strength)


func _on_health_downed(_lethal: bool) -> void:
	if _downed:
		return
	_downed = true
	_hurt_timer = 0.0
	player_downed.emit()


func is_downed() -> bool:
	return _downed


func current_hp() -> float:
	return _health.current_hp() if _health != null else 0.0


func _camera_relative_direction(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var yaw := 0.0
	if _camera_rig != null:
		yaw = _camera_rig.global_rotation.y
	var basis := Basis(Vector3.UP, yaw)
	var dir := basis * Vector3(input_dir.x, 0.0, input_dir.y)
	dir.y = 0.0
	return dir.normalized()


func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(direction.x, direction.z)
	if _model != null:
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, rotation_speed * delta)
