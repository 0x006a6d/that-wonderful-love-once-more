extends SceneTree

## 診断専用: 各クリップの LeftHand / RightHand の XZ 平面到達 (原点からの水平距離) を
## 0.05s 刻みで採取し、「振りのピーク」(局所最大かつ閾値超) を全て列挙する。
## フックの横弧も拾えるよう、前方 Z ではなく XZ 合成距離を使う。
## ガード基準: L≈0.33m / R≈0.29m。視覚上の「振り」は ≈0.42m 以上のスパイク。
## 見た目の発数 (視覚上何回振っているか) を確定するための計測。修正は行わない。
##
## 条件はゲーム内表示と揃える:
## - melee_*.res はそのまま (Hips XZ 除去済み・1.3倍速圧縮済み)。Method Track は
##   計測環境で誤発火するため複製から除去する
## - ソース FBX は Hips XZ を除去した複製を等速で測る
## 到達 = 手ボーンのスケルトン原点相対 +Z 成分 (VRM 正面)。
##
## 実行: godot --path . --headless --script res://tools/diag_punch_hands.gd

const VRM := "res://assets/vrm/nikechan_v2.vrm"
const STEP := 0.05
const PEAK_MIN := 0.40

# [表示名, 種別("res"|"fbx"), パス, アニメキー]
const SOURCES: Array = [
	["melee_1.res (使用中)", "res", "res://actors/player/anim/melee_1.res", ""],
	["melee_2.res (使用中)", "res", "res://actors/player/anim/melee_2.res", ""],
	["melee_3.res (使用中)", "res", "res://actors/player/anim/melee_3.res", ""],
	["punch_combo 全長", "fbx", "res://assets/motions/mixamo_punch_combo.fbx", "mixamo_com"],
	["cross_punch 全長", "fbx", "res://assets/motions/mixamo_cross_punch.fbx", "mixamo_com"],
	["hook_1 全長", "fbx", "res://assets/motions/mixamo_hook_1.fbx", "mixamo_com"],
	["hook_2 全長", "fbx", "res://assets/motions/mixamo_hook_2.fbx", "mixamo_com"],
	["hook_3 全長", "fbx", "res://assets/motions/mixamo_hook_3.fbx", "mixamo_com"],
	["hook_4 全長", "fbx", "res://assets/motions/mixamo_hook_4.fbx", "mixamo_com"],
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


func _strip_method_tracks(anim: Animation) -> void:
	for t in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(t) == Animation.TYPE_METHOD:
			anim.remove_track(t)


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
		var disp: String = entry[0]
		var kind: String = entry[1]
		var path: String = entry[2]
		var anim: Animation = null
		if kind == "res":
			anim = (load(path) as Animation)
			if anim != null:
				anim = anim.duplicate(true) as Animation
				_strip_method_tracks(anim)
		else:
			var inst := (load(path) as PackedScene).instantiate()
			var src_ap := _find(inst, "AnimationPlayer") as AnimationPlayer
			if src_ap != null and src_ap.has_animation(str(entry[3])):
				anim = src_ap.get_animation(str(entry[3])).duplicate(true) as Animation
				_strip_hips_xz(anim)
			inst.free()
		if anim == null:
			print("[WARN] load failed: ", path)
			continue
		var key := "c%d" % names.size()
		lib.add_animation(key, anim)
		names.append(disp)
	if ap.has_animation_library("diag"):
		ap.remove_animation_library("diag")
	ap.add_animation_library("diag", lib)

	var b_l := skel.find_bone("LeftHand")
	var b_r := skel.find_bone("RightHand")
	print("bone idx LeftHand=", b_l, " RightHand=", b_r)
	print("(注: これまでの計測ツールは全て RightHand のみだった)")

	for i in range(names.size()):
		_measure(ap, skel, "diag/c%d" % i, names[i], b_l, b_r)

	vrm.free()
	quit(0)


func _measure(ap: AnimationPlayer, skel: Skeleton3D, key: String, disp: String,
		b_l: int, b_r: int) -> void:
	var anim := ap.get_animation(key)
	ap.play(key)
	var series_l: Array[float] = []
	var series_r: Array[float] = []
	var times: Array[float] = []
	var t := 0.0
	while t <= anim.length + 0.0001:
		ap.seek(t, true, true)
		skel.force_update_all_bone_transforms()
		var lp := skel.get_bone_global_pose(b_l).origin
		var rp := skel.get_bone_global_pose(b_r).origin
		series_l.append(Vector2(lp.x, lp.z).length())
		series_r.append(Vector2(rp.x, rp.z).length())
		times.append(t)
		t += STEP

	print("--- %s (len=%.3fs) ---" % [disp, anim.length])
	var peaks := _find_peaks(times, series_l, "L") + _find_peaks(times, series_r, "R")
	peaks.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if peaks.is_empty():
		print("  (reach>%.2fm のピークなし)" % PEAK_MIN)
	for p in peaks:
		print("  t=%.2fs  hand=%s  reach=%.3fm" % [float(p[0]), str(p[1]), float(p[2])])


## 局所最大 (両隣以上) かつ PEAK_MIN 超のピークを列挙。
func _find_peaks(times: Array[float], series: Array[float], hand: String) -> Array:
	var peaks: Array = []
	for i in range(series.size()):
		var v := series[i]
		if v <= PEAK_MIN:
			continue
		var prev := series[i - 1] if i > 0 else -INF
		var next := series[i + 1] if i < series.size() - 1 else -INF
		if v >= prev and v >= next:
			peaks.append([times[i], hand, v])
	return peaks
