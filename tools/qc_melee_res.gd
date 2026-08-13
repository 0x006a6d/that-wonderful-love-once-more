extends SceneTree

## 生成済み melee_*.res の QC (ベイク方式の検収)。60Hz で全長を両手サンプリングし、
## 以下を数値確認する:
##   (1) 伸展ピーク (XZ 平面到達の局所最大) がちょうど 1 つ (打ち手側)
##   (2) 伸展保持時間 (ピーク値の 90% 以上に留まる時間)
##   (3) 開始・終了ポーズがガード位置 (基準: L 0.333m / R 0.285m) に近いこと
##
## 実行: godot --path . --headless --script res://tools/qc_melee_res.gd

const VRM := "res://assets/vrm/nikechan_v2.vrm"
const FPS := 60.0
## 「振り」とみなす XZ 到達のしきい値。ガード帯 (0.28-0.35) より上。
const SWING_MIN := 0.36
const GUARD_L := 0.333
const GUARD_R := 0.285

# [名前, パス, 打ち手 ("L"/"R")]
const TARGETS: Array = [
	["melee_1", "res://actors/player/anim/melee_1.res", "L"],
	["melee_2", "res://actors/player/anim/melee_2.res", "R"],
	["melee_3", "res://actors/player/anim/melee_3.res", "R"],
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

	var b_l := skel.find_bone("LeftHand")
	var b_r := skel.find_bone("RightHand")

	for entry in TARGETS:
		_qc_one(ap, skel, str(entry[0]), str(entry[2]), b_l, b_r)

	print("=== qc_melee_res: ", "ALL PASS" if _fail == 0 else "HAS FAILURE (%d)" % _fail, " ===")
	vrm.free()
	quit(0 if _fail == 0 else 1)


func _qc_one(ap: AnimationPlayer, skel: Skeleton3D, name: String, hand: String,
		b_l: int, b_r: int) -> void:
	var key := "qc/" + name
	var anim := ap.get_animation(key)
	ap.play(key)
	var series_l: Array[float] = []
	var series_r: Array[float] = []
	var t := 0.0
	while t <= anim.length + 0.0001:
		ap.seek(t, true, true)
		skel.force_update_all_bone_transforms()
		var lp := skel.get_bone_global_pose(b_l).origin
		var rp := skel.get_bone_global_pose(b_r).origin
		series_l.append(Vector2(lp.x, lp.z).length())
		series_r.append(Vector2(rp.x, rp.z).length())
		t += 1.0 / FPS

	var strike := series_l if hand == "L" else series_r
	var off := series_r if hand == "L" else series_l

	# (1) 打ち手の振り回数: SWING_MIN の上向き横断回数。
	var crossings := 0
	for i in range(1, strike.size()):
		if strike[i - 1] < SWING_MIN and strike[i] >= SWING_MIN:
			crossings += 1
	var off_crossings := 0
	for i in range(1, off.size()):
		if off[i - 1] < SWING_MIN and off[i] >= SWING_MIN:
			off_crossings += 1

	# (2) ピークと保持時間 (ピークの 90% 以上)。
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
	var hold_s := hold / FPS

	# (3) 開始・終了ポーズのガードからの差。
	var guard := GUARD_L if hand == "L" else GUARD_R
	var start_d: float = absf(strike[0] - guard)
	var end_d: float = absf(strike[strike.size() - 1] - guard)

	print("--- %s (len=%.3fs, 打ち手=%s) ---" % [name, anim.length, hand])
	print("  打ち手ピーク: %.3fm @%.3fs / 振り回数(>%.2fm横断)=%d / 逆手横断=%d" %
		[peak, peak_i / FPS, SWING_MIN, crossings, off_crossings])
	print("  伸展保持 (>=90%%ピーク): %.3fs" % hold_s)
	print("  開始ポーズ ガード差=%.3fm / 終了ポーズ ガード差=%.3fm" % [start_d, end_d])

	var ok := crossings == 1 and off_crossings == 0 and hold_s <= 0.12 \
		and start_d < 0.08 and end_d < 0.08
	if not ok:
		_fail += 1
		print("  [FAIL] 基準未達 (振り1回・逆手0回・保持<=0.12s・端点ガード差<0.08m)")
	else:
		print("  [PASS]")
