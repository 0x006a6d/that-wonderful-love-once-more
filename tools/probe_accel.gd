extends SceneTree

## 加減速の実測プローブ。
## 実入力 (Input.action_press) で W を ON→OFF し、水平速度の時系列から
## 立ち上がり (95% 到達) と停止 (0.05 m/s 未満) の所要時間を測る。
## あわせてロコモーションのアニメ速度スケール (TimeScale) が
## 地面速度に同期して動くことを確認する。
##
## 実行: godot --path . --headless --script res://tools/probe_accel.gd

const STAGE := "res://levels/test_stage.tscn"

var _stage: Node = null
var _player: CharacterBody3D = null
var _tree: AnimationTree = null
var _frames: int = 0
var _press_frame: int = -1
var _release_frame: int = -1
var _rise_frames: int = -1
var _stop_frames: int = -1
var _move_speed: float = 4.5


func _initialize() -> void:
	_stage = (load(STAGE) as PackedScene).instantiate()
	get_root().add_child(_stage)
	_player = _stage.get_node("Player") as CharacterBody3D
	_move_speed = float(_player.get("move_speed"))


func _speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _tree == null:
		_tree = _player.get_node_or_null("PlayerMelee/AnimationTree") as AnimationTree
		if _tree == null and _frames > 10:
			print("[FAIL] AnimationTree が生成されていない")
			quit(1)
			return true
	if _frames == 15:
		Input.action_press("move_forward")
		_press_frame = _frames
		print("[press] W ON at f%d" % _frames)
	elif _press_frame > 0 and _rise_frames < 0 and _speed() >= _move_speed * 0.95:
		_rise_frames = _frames - _press_frame
		print("[rise] 95%% (%.2f m/s) 到達: %d フレーム = %.3f s" %
			[_speed(), _rise_frames, _rise_frames / 60.0])
		print("[sync] blend=%.2f  anim_time_scale=%.2f" %
			[float(_tree.get("parameters/locomotion/blend/blend_position")),
			float(_tree.get("parameters/locomotion/speed/scale"))])
	elif _rise_frames > 0 and _release_frame < 0 and _frames >= _press_frame + 90:
		Input.action_release("move_forward")
		_release_frame = _frames
		print("[release] W OFF at f%d (speed=%.2f)" % [_frames, _speed()])
	elif _release_frame > 0 and _stop_frames < 0 and _speed() < 0.05:
		_stop_frames = _frames - _release_frame
		print("[stop] 停止 (<0.05 m/s): %d フレーム = %.3f s" %
			[_stop_frames, _stop_frames / 60.0])
		print("[sync] 停止後 anim_time_scale=%.2f" %
			float(_tree.get("parameters/locomotion/speed/scale")))
		quit(0)
		return true
	elif _frames > 600:
		print("[FAIL] timeout rise=%d stop=%d speed=%.2f" % [_rise_frames, _stop_frames, _speed()])
		quit(1)
		return true
	return false
