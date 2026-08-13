extends SceneTree

## 診断: キック系クリップの両足 (LeftFoot/RightFoot)・両膝 (LeftLowerLeg/RightLowerLeg)
## の軌道を実測する。パンチの diag_punch_hands と同じ「見た目の打撃回数」判定の足版。
## 各サンプルで [XZ 平面到達 (原点からの水平距離), 前方 Z, 高さ Y] を採取し、
## 全時系列と「蹴りのピーク」(局所最大かつ閾値超) を出力する。
##
## 実行: godot --path . --headless --script res://tools/diag_kick_feet.gd

const VRM := "res://assets/vrm/nikechan_player.vrm"
const STEP := 0.05
## 立ち姿勢の足の planar 基準はほぼ 0.05-0.15m。蹴りの「振り」は 0.35m 超で判定。
const PEAK_MIN := 0.35

const SOURCES: Array = [
	["kick_soccer (Kick Soccerball)", "res://assets/motions/mixamo_kick_soccer.fbx"],
	["knee (Illegal Knee)", "res://assets/motions/mixamo_knee.fbx"],
	["kick_finish (Kicking)", "res://assets/motions/mixamo_kick_finish.fbx"],
	["knee_jab (Knee Jab)", "res://assets/motions/mixamo_knee_jab.fbx"],
	["kick_side (Side Kick)", "res://assets/motions/mixamo_kick_side.fbx"],
	["kick_high_left (Kicking2)", "res://assets/motions/mixamo_kick_high_left.fbx"],
	["kick_roundhouse (Roundhouse Kick)", "res://assets/motions/mixamo_kick_roundhouse.fbx"],
	["kick_mma (Mma Kick)", "res://assets/motions/mixamo_kick_mma.fbx"],
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
	var names: Array[String] = []
	for entry in SOURCES:
		var inst := (load(str(entry[1])) as PackedScene).instantiate()
		var src_ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		if src_ap == null or not src_ap.has_animation("mixamo_com"):
			print("[WARN] mixamo_com missing: ", entry[1])
			inst.free()
			continue
		var anim := src_ap.get_animation("mixamo_com").duplicate(true) as Animation
		_strip_hips_xz(anim)
		var key := "k%d" % names.size()
		lib.add_animation(key, anim)
		names.append(str(entry[0]))
		inst.free()
	ap.add_animation_library("diag", lib)

	var b_lf := skel.find_bone("LeftFoot")
	var b_rf := skel.find_bone("RightFoot")
	var b_lk := skel.find_bone("LeftLowerLeg")
	var b_rk := skel.find_bone("RightLowerLeg")
	print("bones LF=", b_lf, " RF=", b_rf, " LK=", b_lk, " RK=", b_rk)

	for i in range(names.size()):
		_measure(ap, skel, "diag/k%d" % i, names[i], b_lf, b_rf, b_lk, b_rk)

	vrm.free()
	quit(0)


func _measure(ap: AnimationPlayer, skel: Skeleton3D, key: String, disp: String,
		b_lf: int, b_rf: int, b_lk: int, b_rk: int) -> void:
	var anim := ap.get_animation(key)
	ap.play(key)
	print("--- %s (len=%.3fs) ---" % [disp, anim.length])
	print("  t     | LF.xz LF.z  LF.y  | RF.xz RF.z  RF.y  | LK.xz LK.y | RK.xz RK.y")
	var series := {"LF": [], "RF": [], "LK": [], "RK": []}
	var times: Array[float] = []
	var t := 0.0
	while t <= anim.length + 0.0001:
		ap.seek(t, true, true)
		skel.force_update_all_bone_transforms()
		var lf := skel.get_bone_global_pose(b_lf).origin
		var rf := skel.get_bone_global_pose(b_rf).origin
		var lk := skel.get_bone_global_pose(b_lk).origin
		var rk := skel.get_bone_global_pose(b_rk).origin
		(series["LF"] as Array).append(Vector2(lf.x, lf.z).length())
		(series["RF"] as Array).append(Vector2(rf.x, rf.z).length())
		(series["LK"] as Array).append(Vector2(lk.x, lk.z).length())
		(series["RK"] as Array).append(Vector2(rk.x, rk.z).length())
		times.append(t)
		print("  %.2f  | %.3f %+.3f %.3f | %.3f %+.3f %.3f | %.3f %.3f | %.3f %.3f" %
			[t, Vector2(lf.x, lf.z).length(), lf.z, lf.y,
			Vector2(rf.x, rf.z).length(), rf.z, rf.y,
			Vector2(lk.x, lk.z).length(), lk.y,
			Vector2(rk.x, rk.z).length(), rk.y])
		t += STEP

	# ピーク一覧 (planar > PEAK_MIN の局所最大)。
	var peaks: Array = []
	for part in ["LF", "RF", "LK", "RK"]:
		var s: Array = series[part]
		for i in range(s.size()):
			var v: float = s[i]
			if v <= PEAK_MIN:
				continue
			var prev: float = s[i - 1] if i > 0 else -INF
			var next: float = s[i + 1] if i < s.size() - 1 else -INF
			if v >= prev and v >= next:
				peaks.append([times[i], part, v])
	peaks.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	print("  [peaks >%.2fm]" % PEAK_MIN)
	for p in peaks:
		print("    t=%.2fs %s %.3fm" % [float(p[0]), str(p[1]), float(p[2])])
