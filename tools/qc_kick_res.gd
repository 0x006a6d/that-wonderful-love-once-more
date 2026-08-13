extends SceneTree

## 生成済み kick_*.res の QC。60Hz で全長を両足 (Foot) サンプリングし、
##   (1) 蹴り足の振り (planar 閾値の上向き横断) がちょうど 1 回
##   (2) 逆足の横断が 0 回 (軸足が暴れない)
##   (3) ピーク値・時刻・保持時間 (>=90% ピーク)
## を数値確認する。最終判定は映像QC (Movie Maker) で行う。
##
## 実行: godot --path . --headless --script res://tools/qc_kick_res.gd

const VRM := "res://assets/vrm/nikechan_player.vrm"
const FPS := 60.0

# [名前, パス, 蹴り足 ("L"/"R"), 指標 ("foot_planar"|"knee_y"), 振り閾値 m]
# kick_2 (ひざ) の打撃はほぼ垂直で、足先 planar は引き足 (後方) を誤検出する。
# ひざ高さ (RightLowerLeg の Y) の横断で数える。
const TARGETS: Array = [
	["kick_1", "res://actors/player/anim/kick_1.res", "R", "knee_y", 0.90],
	["kick_2", "res://actors/player/anim/kick_2.res", "L", "foot_planar", 0.45],
	["kick_3", "res://actors/player/anim/kick_3.res", "R", "foot_planar", 0.45],
]

var _fail: int = 0


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r: Node = _find(c, cls)
		if r != null:
			return r
	return null


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
	for entry in TARGETS:
		var anim := (load(str(entry[1])) as Animation)
		if anim == null:
			print("[FAIL] load ", entry[1])
			_fail += 1
			continue
		var copy := anim.duplicate(true) as Animation
		_strip_method_tracks(copy)
		lib.add_animation(str(entry[0]), copy)
	ap.add_animation_library("qc", lib)

	var b_lf := skel.find_bone("LeftFoot")
	var b_rf := skel.find_bone("RightFoot")
	var b_rk := skel.find_bone("RightLowerLeg")

	for entry in TARGETS:
		_qc_one(ap, skel, str(entry[0]), str(entry[2]), str(entry[3]), float(entry[4]), b_lf, b_rf, b_rk)

	print("=== qc_kick_res: ", "ALL PASS" if _fail == 0 else "HAS FAILURE (%d)" % _fail, " ===")
	vrm.free()
	quit(0 if _fail == 0 else 1)


func _qc_one(ap: AnimationPlayer, skel: Skeleton3D, name: String, foot: String,
		metric: String, threshold: float, b_lf: int, b_rf: int, b_rk: int) -> void:
	var key := "qc/" + name
	var anim := ap.get_animation(key)
	ap.play(key)
	var series_l: Array[float] = []
	var series_r: Array[float] = []
	var series_knee: Array[float] = []
	var knee_y_max := 0.0
	var t := 0.0
	while t <= anim.length + 0.0001:
		ap.seek(t, true, true)
		skel.force_update_all_bone_transforms()
		var lf := skel.get_bone_global_pose(b_lf).origin
		var rf := skel.get_bone_global_pose(b_rf).origin
		var rk := skel.get_bone_global_pose(b_rk).origin
		series_l.append(Vector2(lf.x, lf.z).length())
		series_r.append(Vector2(rf.x, rf.z).length())
		series_knee.append(rk.y)
		knee_y_max = maxf(knee_y_max, rk.y)
		t += 1.0 / FPS

	var strike: Array[float]
	if metric == "knee_y":
		strike = series_knee
	else:
		strike = series_r if foot == "R" else series_l
	var off := series_l if foot == "R" else series_r

	var crossings := 0
	for i in range(1, strike.size()):
		if strike[i - 1] < threshold and strike[i] >= threshold:
			crossings += 1
	var off_crossings := 0
	for i in range(1, off.size()):
		if off[i - 1] < threshold and off[i] >= threshold:
			off_crossings += 1

	var peak := 0.0
	var peak_i := 0
	for i in range(strike.size()):
		if strike[i] > peak:
			peak = strike[i]
			peak_i = i
	var hold := 0
	for v in strike:
		if v >= peak * 0.9:
			hold += 1

	print("--- %s (len=%.3fs, 蹴り足=%s, 閾値=%.2fm) ---" % [name, anim.length, foot, threshold])
	print("  蹴り足ピーク: %.3fm @%.3fs / 振り回数=%d / 逆足横断=%d / 右ひざ最高 %.3fm" %
		[peak, peak_i / FPS, crossings, off_crossings, knee_y_max])
	print("  伸展保持 (>=90%%ピーク): %.3fs" % (hold / FPS))

	if crossings == 1 and off_crossings == 0:
		print("  [PASS]")
	else:
		_fail += 1
		print("  [FAIL] 蹴り足の振りが 1 回でない、または逆足が暴れている")
