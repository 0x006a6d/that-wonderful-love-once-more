extends SceneTree

## クリップ単体の「拳の前方到達」時系列を実測する (Hips XZ 除去を適用した状態)。
## 到達 = RightHand の (スケルトン原点相対) +Z 成分。ゲーム内の見た目と同じ条件。
## melee_1/melee_2 の切り出し区間と判定窓を決めるための一次データ。
##
## 実行: godot --path . --headless --script res://tools/measure_reach_offline.gd

const VRM := "res://assets/vrm/nikechan_v2.vrm"
const STEP := 0.033

const SOURCES: Array = [
	["Punch_Combo", "res://assets/motions/mixamo_punch_combo.fbx"],
	["Cross_Punch", "res://assets/motions/mixamo_cross_punch.fbx"],
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
	ap.add_animation_library("m", lib)

	var b_hand := skel.find_bone("RightHand")

	for entry in SOURCES:
		var key: String = "m/" + str(entry[0])
		var anim := ap.get_animation(key)
		print("--- ", entry[0], " (len=", "%.3f" % anim.length, "s, 元クリップ等速) ---")
		ap.play(key)
		var t := 0.0
		while t <= anim.length + 0.0001:
			ap.seek(t, true, true)
			skel.force_update_all_bone_transforms()
			var hand := skel.get_bone_global_pose(b_hand).origin
			# スケルトン原点相対の +Z 成分 (VRM の正面)。
			print("  t=%.2f reach=%.3f" % [t, hand.z])
			t += STEP
	vrm.free()
	quit(0)
