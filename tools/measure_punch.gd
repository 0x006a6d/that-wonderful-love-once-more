extends SceneTree

# パンチモーションの姿勢 QC 計測スクリプト。
# VRM (GeneralSkeleton) にモーション gltf の AnimationLibrary をリターゲット済みトラックで
# 登録し、0.1s 刻みでサンプリングして拳・肩の global position を測る。
#
# 指標:
#   (a) 拳が最も前 (−Z 方向) に出た瞬間の「拳の高さ − 肩の高さ」(m)
#   (b) その瞬間の拳の前方距離 (肩基準の前方成分, m)
#   (c) サンプル全体での拳高さの最大値 (m)
#
# 使い方:
#   godot --path . --headless --script tools/measure_punch.gd
# 対象アニメは ANIMS 配列で指定。

const MOTION_SCENE: String = "res://assets/motions/universal_animation_library.gltf"
const VRM_SCENE: String = "res://assets/vrm/nikechan_v2.vrm"
const ANIMS: Array[String] = ["Punch_Cross", "Punch_Jab", "Punch_Enter"]
const SAMPLE_STEP: float = 0.1


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
	# VRM をインスタンス化してツリーに追加 (global transform 計算のため実際に add する)
	var vrm_packed: PackedScene = load(VRM_SCENE) as PackedScene
	var vrm: Node3D = vrm_packed.instantiate() as Node3D
	get_root().add_child(vrm)
	# ノードがツリーに完全に入るまで 1 フレーム待つ
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

	# モーション gltf から AnimationLibrary を取り出して登録
	var motion_packed: PackedScene = load(MOTION_SCENE) as PackedScene
	var motion_inst: Node = motion_packed.instantiate()
	var src_ap: AnimationPlayer = _find_node_by_class(motion_inst, "AnimationPlayer") as AnimationPlayer
	var lib: AnimationLibrary = src_ap.get_animation_library("")
	var lib_copy: AnimationLibrary = lib.duplicate(true) as AnimationLibrary
	if ap.has_animation_library("motion"):
		ap.remove_animation_library("motion")
	ap.add_animation_library("motion", lib_copy)
	motion_inst.free()

	# ボーン索引を解決
	var b_hand: int = skel.find_bone("RightHand")
	var b_shoulder: int = skel.find_bone("RightShoulder")
	var b_upperarm: int = skel.find_bone("RightUpperArm")
	if b_hand < 0 or b_upperarm < 0:
		print("[ERROR] bones not found  hand=", b_hand, " shoulder=", b_shoulder, " upperarm=", b_upperarm)
		quit(1)
		return

	print("=== measure_punch (step=", SAMPLE_STEP, "s) ===")
	print("bone idx  RightHand=", b_hand, " RightShoulder=", b_shoulder, " RightUpperArm=", b_upperarm)

	for anim_name in ANIMS:
		var key: String = "motion/" + anim_name
		if not ap.has_animation(key):
			print("[WARN] missing anim: ", key)
			continue
		_measure_one(ap, skel, key, anim_name, b_hand, b_shoulder, b_upperarm)

	vrm.free()
	quit(0)


func _measure_one(ap: AnimationPlayer, skel: Skeleton3D, key: String, anim_name: String, \
		b_hand: int, b_shoulder: int, b_upperarm: int) -> void:
	var anim: Animation = ap.get_animation(key)
	var length: float = anim.length
	ap.play(key)

	# 肩基準は RightShoulder があればそれ、無ければ RightUpperArm
	var b_ref: int = b_shoulder if b_shoulder >= 0 else b_upperarm

	var best_fwd: float = -INF          # 最も前 (−Z が大) の瞬間
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

		# 前方 = キャラの正面。VRM は +Z 前方 (Godot 既定は −Z 前方だが VRM モデルは +Z を向く場合がある)。
		# ここでは肩→拳の水平前後成分の絶対値が最大になる向きを「前方」として拾うため、
		# 拳の Z を肩基準からの差で評価し、符号は後で判定する。
		var fwd_signed: float = ref_g.z - hand_g.z   # −Z 前方系での前方量 (拳が前=大)
		var fwd_abs: float = abs(hand_g.z - ref_g.z)

		if hand_g.y > max_hand_y:
			max_hand_y = hand_g.y

		# 「最も前に出た」= 肩からの水平前後距離が最大の瞬間
		if fwd_abs > best_fwd:
			best_fwd = fwd_abs
			best_t = t
			best_hand_y = hand_g.y
			best_ref_y = ref_g.y
			best_fwd_dist = fwd_abs

		t += SAMPLE_STEP

	var height_diff: float = best_hand_y - best_ref_y
	print("--- ", anim_name, " (len=", "%.2f" % length, "s) ---")
	print("  peak_t=", "%.2f" % best_t, "s")
	print("  (a) hand_y - shoulder_y at peak = ", "%+.4f" % height_diff, " m")
	print("  (b) hand forward dist at peak    = ", "%.4f" % best_fwd_dist, " m")
	print("  (c) max hand_y over samples      = ", "%.4f" % max_hand_y, " m")
	print("      hand_y=", "%.4f" % best_hand_y, "  shoulder_y=", "%.4f" % best_ref_y)
