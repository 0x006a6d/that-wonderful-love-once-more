extends SceneTree

## 歩行系クリップの QC 計測。
## - natural speed 概算: 左右の足 (Foot ボーン) の前後分離の最大値 ≒ 1 歩の歩幅、
##   1 周期 = 2 歩として natural speed ≈ 2 × max_step / クリップ長
##   (足滑りの厳密一致は不要。アニメ速度同期係数の初期値決めが目的)
## - In Place 検証: Hips 位置トラックの XZ 変位幅。0.05m を超えたら In Place でない
##
## 実行: godot --path . --headless --script res://tools/measure_stride.gd

const VRM := "res://assets/vrm/nikechan_v2.vrm"
const STEP := 0.033

# [表示名, シーン, アニメキー]
const SOURCES: Array = [
	["univ_Walk", "res://assets/motions/universal_animation_library.gltf", "Walk"],
	["univ_Jog_Fwd", "res://assets/motions/universal_animation_library.gltf", "Jog_Fwd"],
	["mixamo_walk", "res://assets/motions/mixamo_walk.fbx", "mixamo_com"],
	["mixamo_run", "res://assets/motions/mixamo_run.fbx", "mixamo_com"],
	["mixamo_walk_female", "res://assets/motions/mixamo_walk_female.fbx", "mixamo_com"],
	["mixamo_walk_catwalk", "res://assets/motions/mixamo_walk_catwalk.fbx", "mixamo_com"],
]


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r: Node = _find(c, cls)
		if r != null:
			return r
	return null


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
		if src_ap == null or not src_ap.has_animation(entry[2]):
			print("[WARN] ", entry[0], ": アニメ '", entry[2], "' が見つからない")
			inst.free()
			continue
		lib.add_animation(entry[0], src_ap.get_animation(entry[2]).duplicate(true) as Animation)
		inst.free()
	ap.add_animation_library("m", lib)

	var b_l := skel.find_bone("LeftFoot")
	var b_r := skel.find_bone("RightFoot")

	for entry in SOURCES:
		var key: String = "m/" + str(entry[0])
		if not ap.has_animation(key):
			continue
		var anim := ap.get_animation(key)
		# Hips XZ 変位幅 (In Place 検証)
		var hips_min := Vector3(INF, INF, INF)
		var hips_max := Vector3(-INF, -INF, -INF)
		var net := Vector3.ZERO
		for t in range(anim.get_track_count()):
			if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
				continue
			if not str(anim.track_get_path(t)).ends_with(":Hips"):
				continue
			var n := anim.track_get_key_count(t)
			for k in range(n):
				var v: Vector3 = anim.track_get_key_value(t, k)
				hips_min = hips_min.min(v)
				hips_max = hips_max.max(v)
			if n > 0:
				net = (anim.track_get_key_value(t, n - 1) as Vector3) \
					- (anim.track_get_key_value(t, 0) as Vector3)
		var xz_range := Vector2(hips_max.x - hips_min.x, hips_max.z - hips_min.z)

		ap.play(key)
		var max_sep := 0.0
		var t2 := 0.0
		while t2 <= anim.length + 0.0001:
			ap.seek(t2, true, true)
			skel.force_update_all_bone_transforms()
			var lz := skel.get_bone_global_pose(b_l).origin.z
			var rz := skel.get_bone_global_pose(b_r).origin.z
			max_sep = maxf(max_sep, absf(lz - rz))
			t2 += STEP
		var speed := 2.0 * max_sep / anim.length
		# In Place 判定は「ループ1周の正味ドリフト」で行う。変位幅 (xz_range) は
		# 体の揺れ (sway) を含むため、こちらは参考値。
		var net_xz := Vector2(net.x, net.z).length()
		var in_place := "IN-PLACE" if net_xz < 0.05 else "NOT-IN-PLACE!"
		print("[%s] len=%.3fs max_step=%.3fm natural≈%.2f m/s  net_drift=%.3fm sway_range=(%.3f, %.3f) %s" %
			[entry[0], anim.length, max_sep, speed, net_xz, xz_range.x, xz_range.y, in_place])
	vrm.free()
	quit(0)
