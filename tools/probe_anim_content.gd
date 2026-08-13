extends SceneTree

## player の各アニメの中身を確認する。長さ・トラック数・腕系トラックの有無と、
## melee .res の Hips 位置トラック（ルートモーション）の移動量を出力する。
## 実行: godot --path . --headless --script res://tools/probe_anim_content.gd

const PLAYER := "res://actors/player/player.tscn"

var _frames: int = 0
var _player: Node3D = null


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _initialize() -> void:
	_player = (load(PLAYER) as PackedScene).instantiate() as Node3D
	get_root().add_child(_player)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var ap := _find(_player, "AnimationPlayer") as AnimationPlayer
	for key in ["player/idle", "player/walk", "player/jog", "player/melee_1", "player/melee_2"]:
		var anim := ap.get_animation(key)
		if anim == null:
			print("[", key, "] MISSING")
			continue
		var arm_tracks := 0
		var hips_pos_track := -1
		for t in range(anim.get_track_count()):
			var p := str(anim.track_get_path(t))
			if p.contains("Arm") or p.contains("Hand") or p.contains("Shoulder"):
				arm_tracks += 1
			if p.ends_with(":Hips") and anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				hips_pos_track = t
		print("[", key, "] len=", "%.3f" % anim.length, " tracks=", anim.get_track_count(),
			" arm_tracks=", arm_tracks, " hips_pos_track=", hips_pos_track)
		if hips_pos_track >= 0:
			var n := anim.track_get_key_count(hips_pos_track)
			var first: Vector3 = anim.track_get_key_value(hips_pos_track, 0)
			var last: Vector3 = anim.track_get_key_value(hips_pos_track, n - 1)
			var mn := first
			var mx := first
			for k in range(n):
				var v: Vector3 = anim.track_get_key_value(hips_pos_track, k)
				mn = mn.min(v)
				mx = mx.max(v)
			print("    hips keys=", n, " first=", first, " last=", last)
			print("    hips range x=[%.3f,%.3f] y=[%.3f,%.3f] z=[%.3f,%.3f]" %
				[mn.x, mx.x, mn.y, mx.y, mn.z, mx.z])
	quit(0)
	return true
