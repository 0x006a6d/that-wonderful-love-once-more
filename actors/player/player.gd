extends CharacterBody3D

## プレイヤー本体。カメラ相対の WASD 移動と、移動方向への回転補間を担う。
## カメラ回転そのものは SpringArm3D 側（player_camera.gd）が担当する。
## 攻撃・ステートマシン・AnimationTree は 8/15 以降に追加する。

## 平地移動速度（m/s）。身長160cm 基準の等身に合わせた既定値。
@export var move_speed: float = 4.5
## 移動方向へ向き直る回転補間の速さ（rad/s 相当の lerp 係数）。
@export var rotation_speed: float = 12.0
## マウス感度（player_camera.gd へ注入する）。
@export var mouse_sensitivity: float = 0.003

@export var camera_path: NodePath = ^"SpringArm3D"
@export var model_path: NodePath = ^"Model"

var _camera_rig: Node3D = null
var _model: Node3D = null


func _ready() -> void:
	_camera_rig = get_node_or_null(camera_path) as Node3D
	_model = get_node_or_null(model_path) as Node3D
	# カメラ側へマウス感度を注入する（直接参照を残さない）。
	var cam := _camera_rig as Node
	if cam != null and cam.has_method("configure"):
		cam.call("configure", mouse_sensitivity)


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _camera_relative_direction(input_dir)

	if direction.length() > 0.001:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		_face_direction(direction, delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# 重力（床に立たせるための最小限。ジャンプは未実装）。
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0

	move_and_slide()


## 入力ベクトルをカメラのヨーを基準にワールド方向へ変換する。
func _camera_relative_direction(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var yaw := 0.0
	if _camera_rig != null:
		yaw = _camera_rig.global_rotation.y
	var basis := Basis(Vector3.UP, yaw)
	# input_dir.y: 前後（W が -y 相当で前方 -Z）、input_dir.x: 左右。
	var dir := basis * Vector3(input_dir.x, 0.0, input_dir.y)
	dir.y = 0.0
	return dir.normalized()


## 進行方向へモデル（と本体）を滑らかに向ける。
func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(direction.x, direction.z)
	if _model != null:
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, rotation_speed * delta)
