extends SceneTree

## test_stage をロードし、数フレーム物理を回した後の Player.global_position.y を
## 出力する。床をすり抜けて落下していないことを確認する。
## 実行: godot --headless --path . --script res://tools/check_player_stands.gd

const STAGE: String = "res://levels/test_stage.tscn"
const SETTLE_FRAMES: int = 60

var _frames: int = 0
var _player: Node3D = null


func _initialize() -> void:
	var packed := load(STAGE) as PackedScene
	if packed == null:
		print("[FAIL] test_stage load failed")
		quit(1)
		return
	var stage := packed.instantiate()
	get_root().add_child(stage)
	_player = stage.get_node_or_null("Player") as Node3D
	if _player == null:
		print("[FAIL] Player not found in stage")
		quit(1)


# SceneTree の物理フレームごとに呼ばれる。false を返すと継続。
func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1 and _player != null:
		print("[check] frame 1 player.y=%f" % _player.global_position.y)
	if _frames >= SETTLE_FRAMES and _player != null:
		var y := _player.global_position.y
		print("[check] frame %d player.y=%f" % [_frames, y])
		if y > -0.5:
			print("[PASS] プレイヤーは床に立っている")
		else:
			print("[FAIL] プレイヤーが落下している y=%f" % y)
		quit(0 if y > -0.5 else 1)
		return true
	return false
