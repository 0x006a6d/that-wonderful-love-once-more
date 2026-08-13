extends SceneTree

# コンボ採用クリップ (melee_1 = универсал Punch_Jab, melee_2 = mixamo Cross_Punch) の
# 拳前方距離を細かい刻みでサンプリングし、判定ウィンドウ (拳が前方に出ている区間) を出す。
# 使い方: godot --path . --headless --script tools/measure_combo_window.gd

const VRM_SCENE: String = "res://assets/vrm/nikechan_v2.vrm"
const UNIV_SCENE: String = "res://assets/motions/universal_animation_library.gltf"
const CROSS_FBX: String = "res://assets/motions/mixamo_cross_punch.fbx"
const SAMPLE_STEP: float = 0.033
const FWD_THRESHOLD: float = 0.22  # 前方距離がこの値以上の区間を判定窓とする


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
	var vrm: Node3D = (load(VRM_SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(vrm)
	await process_frame

	var skel: Skeleton3D = _find(vrm, "Skeleton3D") as Skeleton3D
	skel.unique_name_in_owner = true
	var ap: AnimationPlayer = _find(vrm, "AnimationPlayer") as AnimationPlayer
	ap.root_node = ap.get_path_to(vrm)

	var candidates: Array = [
		["Punch_Combo", "res://assets/motions/mixamo_punch_combo.fbx"],
		["Combo_Punch", "res://assets/motions/mixamo_combo_punch.fbx"],
		["Hook_1", "res://assets/motions/mixamo_hook_1.fbx"],
		["Cross_Punch", "res://assets/motions/mixamo_cross_punch.fbx"],
	]
	var lib: AnimationLibrary = AnimationLibrary.new()
	for entry in candidates:
		var inst: Node = (load(entry[1]) as PackedScene).instantiate()
		var src_ap: AnimationPlayer = _find(inst, "AnimationPlayer") as AnimationPlayer
		lib.add_animation(entry[0], src_ap.get_animation("mixamo_com").duplicate(true) as Animation)
		inst.free()
	ap.add_animation_library("combo", lib)

	var b_hand: int = skel.find_bone("RightHand")
	var b_ref: int = skel.find_bone("RightShoulder")

	for entry in candidates:
		_window(ap, skel, "combo/" + str(entry[0]), str(entry[0]), b_hand, b_ref)

	vrm.free()
	quit(0)


func _window(ap: AnimationPlayer, skel: Skeleton3D, key: String, disp: String, b_hand: int, b_ref: int) -> void:
	var anim: Animation = ap.get_animation(key)
	var length: float = anim.length
	ap.play(key)
	print("--- ", disp, " (len=", "%.3f" % length, "s, threshold=", FWD_THRESHOLD, "m) ---")
	var enter_t: float = -1.0
	var exit_t: float = -1.0
	var peak_fwd: float = -INF
	var peak_t: float = 0.0
	var t: float = 0.0
	while t <= length + 0.0001:
		ap.seek(t, true, true)
		skel.force_update_all_bone_transforms()
		var hand_g: Vector3 = (skel.global_transform * skel.get_bone_global_pose(b_hand)).origin
		var ref_g: Vector3 = (skel.global_transform * skel.get_bone_global_pose(b_ref)).origin
		var fwd: float = abs(hand_g.z - ref_g.z)
		if fwd > peak_fwd:
			peak_fwd = fwd
			peak_t = t
		if fwd >= FWD_THRESHOLD:
			if enter_t < 0.0:
				enter_t = t
			exit_t = t
		t += SAMPLE_STEP
	print("  peak_fwd=", "%.3f" % peak_fwd, "m at t=", "%.3f" % peak_t, "s")
	print("  window (fwd>=thr): enter=", "%.3f" % enter_t, "s  exit=", "%.3f" % exit_t, "s")
	print("  window ratio: enter=", "%.3f" % (enter_t / length), "  exit=", "%.3f" % (exit_t / length))
