extends SpringArm3D

## サードパーソンカメラの回転リグ。マウス移動でヨー（自身の Y 回転）と
## ピッチ（自身の X 回転）を制御する。壁のめり込みは SpringArm3D が自動処理する。
## マウス感度は player.gd から configure() で注入される。

## ピッチのクランプ（ラジアン）。下向き・上向きの見込み角を制限する。
@export var pitch_min: float = -1.2
@export var pitch_max: float = 0.5
## SpringArm の腕の長さ（カメラ距離）。身長160cm 基準の三人称距離。
@export var arm_length: float = 3.5

var _mouse_sensitivity: float = 0.003
var _yaw: float = 0.0
var _pitch: float = -0.2


func _ready() -> void:
	spring_length = arm_length
	# world レイヤー(1)の障害物に対してのみ縮む。
	collision_mask = 1
	_yaw = rotation.y
	_pitch = rotation.x


## player.gd からマウス感度を注入する。
func configure(mouse_sensitivity: float) -> void:
	_mouse_sensitivity = mouse_sensitivity


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	_yaw -= motion.relative.x * _mouse_sensitivity
	_pitch -= motion.relative.y * _mouse_sensitivity
	_pitch = clampf(_pitch, pitch_min, pitch_max)
	rotation.y = _yaw
	rotation.x = _pitch
