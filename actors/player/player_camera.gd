extends SpringArm3D

## サードパーソンカメラの回転リグ（キーボード/パッド完結。マウス非使用）。
##
## - 自動追従: プレイヤーが移動している間、ヨーを「移動方向の背後」へ緩やかに補間する。
##   停止中は現在角を維持する
## - 手動オービット: camera_left / camera_right（←→ , . / 右スティック横）の押下中は
##   入力強度に応じて回転し、直後は自動追従を manual_suppress_time 秒抑制する
## - ピッチは固定（見下ろし微角度 pitch_angle）。上下操作は持たない
## - 移動方向は player.gd から set_move_direction() で毎フレーム注入される（直接参照なし）
##
## TODO(ロックオン実装時): ロックオン中は「対象を画面に収める」ヨー制御を最優先に挟む。
## マウス操作対応は将来のオプション（現状の入力マップには含まれない）。

## SpringArm の腕の長さ（カメラ距離）。身長160cm 基準の三人称距離。
@export var arm_length: float = 3.5
## 固定ピッチ（ラジアン、負で見下ろし）。
@export var pitch_angle: float = -0.35
## 自動追従の補間速さ（大きいほど素早く背後に回り込む）。
@export var follow_speed: float = 2.5
## 手動オービットの回転速度（rad/s、入力強度 1.0 のとき）。
@export var orbit_speed: float = 2.8
## 手動オービット後に自動追従を抑制する時間（秒）。
@export var manual_suppress_time: float = 2.0
## オービット入力のデッドゾーン（パッドのスティックドリフト対策）。
@export var orbit_deadzone: float = 0.15
## 自動追従が働く移動方向の前方成分（カメラ視線との内積）の下限。
## 後退 (内積 -1)・真横 (0) では追従せず、前進斜め (0.7) は成分比例の弱さで追従する。
## カメラ相対入力では目標ヨーが常に現在ヨーから一定角ずれるため、
## 角度差の閾値では真横移動の永久旋回を防げない（実測で確認済み）。
@export var follow_forward_min: float = 0.1

var _yaw: float = 0.0
var _move_dir: Vector3 = Vector3.ZERO
var _suppress_timer: float = 0.0


func _ready() -> void:
	spring_length = arm_length
	# world レイヤー(1)の障害物に対してのみ縮む。
	collision_mask = 1
	_yaw = rotation.y
	rotation.x = pitch_angle


## player.gd から毎フレーム注入される移動方向（ワールド水平、停止時は ZERO）。
func set_move_direction(direction: Vector3) -> void:
	_move_dir = direction


func _physics_process(delta: float) -> void:
	# 手動オービット（キー ±1.0 / スティックは倒し量が強度になる）。
	var axis := Input.get_axis("camera_left", "camera_right")
	if absf(axis) > orbit_deadzone:
		_yaw -= axis * orbit_speed * delta
		_suppress_timer = manual_suppress_time
	elif _suppress_timer > 0.0:
		_suppress_timer -= delta
	elif _move_dir.length() > 0.1:
		# 自動追従: カメラの視線 (-Z) が移動方向と一致するヨーへ補間。
		# 追従の強さは移動方向の前方成分 (視線との内積) に比例させ、
		# 後退・真横では追従しない (回り込み続け・永久旋回の防止)。
		var look := -global_transform.basis.z
		look.y = 0.0
		var fwd := _move_dir.normalized().dot(look.normalized())
		if fwd > follow_forward_min:
			var desired := atan2(-_move_dir.x, -_move_dir.z)
			_yaw = lerp_angle(_yaw, desired, 1.0 - exp(-follow_speed * fwd * delta))

	rotation.y = _yaw
	rotation.x = pitch_angle
