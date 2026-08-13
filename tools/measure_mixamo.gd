extends SceneTree

# Mixamo パンチ系モーションの姿勢 QC 計測。
# 各 FBX の 'mixamo_com' アニメ (リターゲット済み) を VRM (GeneralSkeleton) に
# 固有キーで載せ、0.05s 刻みでサンプリングして拳・肩の global position を測る。
#
# 指標:
#   (a) 拳が最も前方に出た瞬間の「拳の高さ − 肩の高さ」(m)
#   (b) その瞬間の拳の前方距離 (肩基準の水平前後成分, m)
#   (c) サンプル全体での拳高さの最大値 (m)
#
# 使い方: godot --path . --headless --script tools/measure_mixamo.gd

const VRM_SCENE: String = "res://assets/vrm/nikechan_player.vrm"
const SAMPLE_STEP: float = 0.05

# 表示名 -> FBX パス
const SOURCES: Array = [
	["Cross_Punch", "res://assets/motions/mixamo_cross_punch.fbx"],
	["Combo_Punch", "res://assets/motions/mixamo_combo_punch.fbx"],
	["Punch_Combo", "res://assets/motions/mixamo_punch_combo.fbx"],
	["Hook_1", "res://assets/motions/mixamo_hook_1.fbx"],
	["Hook_2", "res://assets/motions/mixamo_hook_2.fbx"],
	["Hook_3", "res://assets/motions/mixamo_hook_3.fbx"],
	["Hook_4", "res://assets/motions/mixamo_hook_4.fbx"],
	["Elbow_1", "res://assets/motions/mixamo_elbow_1.fbx"],
	["Elbow_2", "res://assets/motions/mixamo_elbow_2.fbx"],
	["Elbow_3", "res://assets/motions/mixamo_elbow_3.fbx"],
]


func _find_node_by_class(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r: Node = _find_node_by_class(c, cls)
		if r != null:
			return r
	return null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var vrm_packed: PackedScene = load(VRM_SCENE) as PackedScene
	var vrm: Node3D = vrm_packed.instantiate() as Node3D
	get_root().add_child(vrm)
	await process_frame

	var skel: Skeleton3D = _find_node_by_class(vrm, "Skeleton3D") as Skeleton3D
	if skel == null:
		print("[ERROR] GeneralSkeleton not found")
		quit(1)
		return
	skel.unique_name_in_owner = true

	var ap: AnimationPlayer = _find_node_by_class(vrm, "AnimationPlayer") as AnimationPlayer
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		vrm.add_child(ap)
	ap.root_node = ap.get_path_to(vrm)

	# 各 FBX から 'mixamo_com' を固有キーで登録
	var lib: AnimationLibrary = AnimationLibrary.new()
	for entry in SOURCES:
		var disp: String = entry[0]
		var fbx_path: String = entry[1]
		var motion_packed: PackedScene = load(fbx_path) as PackedScene
		var motion_inst: Node = motion_packed.instantiate()
		var src_ap: AnimationPlayer = _find_node_by_class(motion_inst, "AnimationPlayer") as AnimationPlayer
		var src_anim: Animation = src_ap.get_animation("mixamo_com")
		lib.add_animation(disp, src_anim.duplicate(true) as Animation)
		motion_inst.free()
	if ap.has_animation_library("mixamo"):
		ap.remove_animation_library("mixamo")
	ap.add_animation_library("mixamo", lib)

	var b_hand: int = skel.find_bone("RightHand")
	var b_shoulder: int = skel.find_bone("RightShoulder")
	var b_upperarm: int = skel.find_bone("RightUpperArm")
	if b_hand < 0 or b_upperarm < 0:
		print("[ERROR] bones not found hand=", b_hand, " shoulder=", b_shoulder, " upperarm=", b_upperarm)
		quit(1)
		return

	print("=== measure_mixamo (step=", SAMPLE_STEP, "s) ===")
	print("bone idx RightHand=", b_hand, " RightShoulder=", b_shoulder, " RightUpperArm=", b_upperarm)

	for entry in SOURCES:
		var disp: String = entry[0]
		var key: String = "mixamo/" + disp
		if not ap.has_animation(key):
			print("[WARN] missing anim: ", key)
			continue
		_measure_one(ap, skel, key, disp, b_hand, b_shoulder, b_upperarm)

	vrm.free()
	quit(0)


func _measure_one(ap: AnimationPlayer, skel: Skeleton3D, key: String, disp: String, \
		b_hand: int, b_shoulder: int, b_upperarm: int) -> void:
	var anim: Animation = ap.get_animation(key)
	var length: float = anim.length
	ap.play(key)

	var b_ref: int = b_shoulder if b_shoulder >= 0 else b_upperarm

	var best_fwd: float = -INF
	var best_t: float = 0.0
	var best_hand_y: float = 0.0
	var best_ref_y: float = 0.0
	var best_fwd_dist: float = 0.0
	var max_hand_y: float = -INF

	var t: float = 0.0
	while t <= length + 0.0001:
		ap.seek(t, true, true)
		skel.force_update_all_bone_transforms()

		var hand_g: Vector3 = (skel.global_transform * skel.get_bone_global_pose(b_hand)).origin
		var ref_g: Vector3 = (skel.global_transform * skel.get_bone_global_pose(b_ref)).origin

		var fwd_abs: float = abs(hand_g.z - ref_g.z)

		if hand_g.y > max_hand_y:
			max_hand_y = hand_g.y

		if fwd_abs > best_fwd:
			best_fwd = fwd_abs
			best_t = t
			best_hand_y = hand_g.y
			best_ref_y = ref_g.y
			best_fwd_dist = fwd_abs

		t += SAMPLE_STEP

	var height_diff: float = best_hand_y - best_ref_y
	print("--- ", disp, " (len=", "%.2f" % length, "s) ---")
	print("  peak_t=", "%.2f" % best_t, "s")
	print("  (a) hand_y - shoulder_y at peak = ", "%+.4f" % height_diff, " m")
	print("  (b) hand forward dist at peak   = ", "%.4f" % best_fwd_dist, " m")
	print("  (c) max hand_y over samples     = ", "%.4f" % max_hand_y, " m")
	print("      hand_y=", "%.4f" % best_hand_y, "  shoulder_y=", "%.4f" % best_ref_y)
