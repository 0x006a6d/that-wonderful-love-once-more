extends SceneTree

## 診断: フック系クリップの横方向 (X) と XZ 合成到達の計測。
## フックは横弧を描くため前方到達 (Z) だけでは振りが見えない。
## 両手について [X, Z, XZ平面での原点からの距離] を 0.05s 刻みで採取し、
## 「右手の明確なフック」(X が体側→内側へ大きく掃引しつつ XZ 到達が立つ) を判定する。
##
## 実行: godot --path . --headless --script res://tools/diag_hook_lateral.gd

const VRM := "res://assets/vrm/nikechan_player.vrm"
const STEP := 0.05

const SOURCES: Array = [
	["jab_left", "res://assets/motions/mixamo_jab_left.fbx"],
	["cross_punch", "res://assets/motions/mixamo_cross_punch.fbx"],
	["hook_1", "res://assets/motions/mixamo_hook_1.fbx"],
	["hook_2", "res://assets/motions/mixamo_hook_2.fbx"],
	["hook_3", "res://assets/motions/mixamo_hook_3.fbx"],
	["hook_4", "res://assets/motions/mixamo_hook_4.fbx"],
]


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r: Node = _find(c, cls)
		if r != null:
			return r
	return null


func _strip_hips_xz(anim: Animation) -> void:
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(t)).ends_with(":Hips"):
			continue
		for k in range(anim.track_get_key_count(t)):
			var v: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, Vector3(0.0, v.y, 0.0))


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var vrm := (load(VRM) as PackedScene).instantiate() as Node3D
	get_root().add_child(vrm)
	await process_frame

	var skel := _find(vrm, "Skeleton3D") as Skeleton3D
	skel.unique_name_in_owner = true
	var ap := _find(vrm, "AnimationPlayer") as AnimationPlayer
	ap.root_node = ap.get_path_to(vrm)

	var lib := AnimationLibrary.new()
	for entry in SOURCES:
		var inst := (load(entry[1]) as PackedScene).instantiate()
		var src_ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		var anim := src_ap.get_animation("mixamo_com").duplicate(true) as Animation
		_strip_hips_xz(anim)
		lib.add_animation(entry[0], anim)
		inst.free()
	ap.add_animation_library("d", lib)

	var b_l := skel.find_bone("LeftHand")
	var b_r := skel.find_bone("RightHand")

	for entry in SOURCES:
		var key: String = "d/" + str(entry[0])
		var anim := ap.get_animation(key)
		ap.play(key)
		print("--- %s (len=%.3fs) ---" % [entry[0], anim.length])
		print("  t     |  L.x    L.z    L.xz  |  R.x    R.z    R.xz")
		var t := 0.0
		while t <= anim.length + 0.0001:
			ap.seek(t, true, true)
			skel.force_update_all_bone_transforms()
			var lp := skel.get_bone_global_pose(b_l).origin
			var rp := skel.get_bone_global_pose(b_r).origin
			print("  %.2f  | %+.3f %+.3f  %.3f | %+.3f %+.3f  %.3f" %
				[t, lp.x, lp.z, Vector2(lp.x, lp.z).length(),
				rp.x, rp.z, Vector2(rp.x, rp.z).length()])
			t += STEP
	vrm.free()
	quit(0)
