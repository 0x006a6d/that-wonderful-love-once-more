extends SceneTree

## カメラ自動追従の実測プローブ。
## 実際の入力アクション (Input.action_press) で S / 斜め後退 / W を駆動し、
## player.gd → player_camera.gd の実経路でヨーの時間変化を記録する。
## 各ケース 180 フレームの累積回転量 |Δyaw| と最終 60 フレームの回転量を出す。
## 後退時にカメラが回り続けるなら累積が発散する (毎フレーム回転が乗る)。
##
## 実行: godot --path . --headless --script res://tools/probe_camera_follow.gd

const STAGE := "res://levels/test_stage.tscn"
const PHASE_FRAMES := 180

var _stage: Node = null
var _cam: Node3D = null
var _frames: int = 0
var _phase: int = -1
var _prev_yaw: float = 0.0
var _accum: float = 0.0
var _tail_accum: float = 0.0

# [ラベル, 押すアクション配列]
const CASES: Array = [
	["後退 S", ["move_back"]],
	["斜め後退 S+A", ["move_back", "move_left"]],
	["前進 W", ["move_forward"]],
	["左 A (真横: 追従しない)", ["move_left"]],
	["前進斜め W+D (弱い旋回のみ)", ["move_forward", "move_right"]],
]


func _initialize() -> void:
	var packed := load(STAGE) as PackedScene
	_stage = packed.instantiate()
	get_root().add_child(_stage)
	var player := _stage.get_node("Player") as Node3D
	_cam = player.get_node("SpringArm3D") as Node3D


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 15:
		return false

	var local := _frames - 15
	var idx := local / PHASE_FRAMES
	var in_phase := local % PHASE_FRAMES

	if idx >= CASES.size():
		return true

	if in_phase == 0:
		# 前ケースの結果を出してから次ケースへ。
		if _phase >= 0:
			_report(_phase)
		_phase = idx
		for c in CASES:
			for a in c[1]:
				Input.action_release(a)
		for a in CASES[idx][1]:
			Input.action_press(a)
		_prev_yaw = _cam.rotation.y
		_accum = 0.0
		_tail_accum = 0.0
		return false

	var yaw := _cam.rotation.y
	var d := absf(wrapf(yaw - _prev_yaw, -PI, PI))
	_accum += d
	if in_phase >= PHASE_FRAMES - 60:
		_tail_accum += d
	_prev_yaw = yaw

	# 最終ケースの最終フレームで締める。
	if idx == CASES.size() - 1 and in_phase == PHASE_FRAMES - 1:
		_report(_phase)
		for c in CASES:
			for a in c[1]:
				Input.action_release(a)
		quit(0)
		return true
	return false


func _report(idx: int) -> void:
	print("[%s] 累積回転=%.3f rad (%.1f deg)  最終60f=%.3f rad (%.1f deg)" %
		[CASES[idx][0], _accum, rad_to_deg(_accum), _tail_accum, rad_to_deg(_tail_accum)])
