extends Node

## カメラシェイク。technical-spec §11.2。プレイヤーの Camera3D の子として置く。
## FastNoiseLite で Camera3D.rotation に微小ノイズを加算し、振幅を Tween で減衰させる。
## shake(strength) で起動する。基準となる rotation はシェイク中も追従できるよう
## 毎フレーム「親から与えられた回転」に対してノイズを足す形にする。

## 揺れの最大振幅（ラジアン）。強さ 1.0 のときのピッチ・ヨーの振れ幅。
@export var max_angle: float = 0.03
## 揺れが減衰しきるまでの時間（秒）。
@export var duration: float = 0.18
## ノイズの時間方向の速さ（大きいほど細かく震える）。
@export var noise_speed: float = 40.0

var _camera: Camera3D = null
var _noise: FastNoiseLite = null
var _trauma: float = 0.0
var _time: float = 0.0
var _base_rotation: Vector3 = Vector3.ZERO
var _tween: Tween = null


func _ready() -> void:
	_camera = get_parent() as Camera3D
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.5
	set_process(false)


## strength: 0.0-1.0。既存の揺れより強ければ上書きする。
func shake(strength: float = 1.0) -> void:
	if _camera == null:
		return
	if not is_processing():
		_base_rotation = _camera.rotation
	_trauma = maxf(_trauma, clampf(strength, 0.0, 1.0))
	_time = 0.0
	set_process(true)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_trauma", 0.0, duration).from(_trauma)


func _process(delta: float) -> void:
	if _camera == null:
		return
	_time += delta * noise_speed
	if _trauma <= 0.001:
		_camera.rotation = _base_rotation
		set_process(false)
		return
	# trauma を2乗して自然な減衰カーブにする。
	var amp := max_angle * _trauma * _trauma
	var off_x := _noise.get_noise_2d(_time, 0.0) * amp
	var off_y := _noise.get_noise_2d(0.0, _time) * amp
	_camera.rotation = _base_rotation + Vector3(off_x, off_y, 0.0)
