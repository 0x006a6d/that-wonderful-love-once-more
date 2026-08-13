extends SceneTree

## 近接コンボ用アニメーションの .res 生成ツール。
##
## インポート済みアニメ（Mixamo FBX）は read-only なので、ここで各クリップを
## 複製 →「パンチ区間だけをキー単位で切り出し」→ 時間スケール → Hips XZ 除去 →
## Call Method Track 追加、の順で加工し res://actors/player/anim/*.res へ保存する。
##
## 区間切り出しの根拠（tools/measure_reach_offline.gd の実測、Hips XZ 除去後の
## 拳の前方到達）:
##   Punch_Combo: 初段は到達 0.28m 止まりの小突き（見た目がもぞもぞの原因）。
##     本命は 2 発目 0.73-1.06s（peak 0.501m @0.89s）→ trim [0.60, 1.20]s
##   Cross_Punch: 0.43-0.89s は引き絞り（到達 -0.27m）、打撃は 0.92-1.25s
##     （peak 0.629m @1.12s）→ trim [0.55, 1.45]s
##
## 判定ウィンドウ（元クリップ等速の秒。trim・スケール後の時刻へ変換して埋め込む）:
##   melee_1: enable 0.76 / disable 1.06（到達 0.25m 以上の区間）
##   melee_2: enable 0.95 / disable 1.28（引き絞りには判定を出さない）
##
## 使い方: godot --path . --headless --script tools/build_melee_anims.gd

const OUT_DIR: String = "res://actors/player/anim"

# [出力名, ソース, アニメキー, trim_start, trim_end, speed, enable_t, disable_t, damage, knockback]
# trim_* / enable_t / disable_t は元クリップ（等速）基準の秒。
const CLIPS: Array = [
	["melee_1", "res://assets/motions/mixamo_punch_combo.fbx", "mixamo_com",
		0.60, 1.20, 1.3, 0.76, 1.06, 12.0, 4.0],
	["melee_2", "res://assets/motions/mixamo_cross_punch.fbx", "mixamo_com",
		0.55, 1.45, 1.3, 0.95, 1.28, 20.0, 7.0],
]


## [trim_start, trim_end] をキー単位で切り出した新しい Animation を作る。
## 境界時刻の姿勢は補間値でキーを打ち、区間内のキーは時刻をシフトしてコピーする。
func _trim(src: Animation, start: float, end: float) -> Animation:
	var out := Animation.new()
	out.length = end - start
	for t in range(src.get_track_count()):
		var type := src.track_get_type(t)
		var nt := out.add_track(type)
		out.track_set_path(nt, src.track_get_path(t))
		out.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
		match type:
			Animation.TYPE_POSITION_3D:
				out.position_track_insert_key(nt, 0.0, src.position_track_interpolate(t, start))
				for k in range(src.track_get_key_count(t)):
					var tm := src.track_get_key_time(t, k)
					if tm > start and tm < end:
						out.position_track_insert_key(nt, tm - start, src.track_get_key_value(t, k))
				out.position_track_insert_key(nt, end - start, src.position_track_interpolate(t, end))
			Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(nt, 0.0, src.rotation_track_interpolate(t, start))
				for k in range(src.track_get_key_count(t)):
					var tm := src.track_get_key_time(t, k)
					if tm > start and tm < end:
						out.rotation_track_insert_key(nt, tm - start, src.track_get_key_value(t, k))
				out.rotation_track_insert_key(nt, end - start, src.rotation_track_interpolate(t, end))
			Animation.TYPE_SCALE_3D:
				out.scale_track_insert_key(nt, 0.0, src.scale_track_interpolate(t, start))
				for k in range(src.track_get_key_count(t)):
					var tm := src.track_get_key_time(t, k)
					if tm > start and tm < end:
						out.scale_track_insert_key(nt, tm - start, src.track_get_key_value(t, k))
				out.scale_track_insert_key(nt, end - start, src.scale_track_interpolate(t, end))
			_:
				# その他のトラック型は区間内キーの単純コピー（現状の素材には存在しない）。
				for k in range(src.track_get_key_count(t)):
					var tm := src.track_get_key_time(t, k)
					if tm >= start and tm <= end:
						out.track_insert_key(nt, tm - start, src.track_get_key_value(t, k))
	return out


## Hips の位置トラックを探し、全キーの X/Z を 0 に固定する（Y は保持）。
func _strip_hips_xz(anim: Animation) -> void:
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(t)).ends_with(":Hips"):
			continue
		for k in range(anim.track_get_key_count(t)):
			var v: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, Vector3(0.0, v.y, 0.0))


## 全トラックのキー時刻と length を factor 倍する（factor<1 で再生が速くなる）。
## 後ろのキーから set することで、同一トラック内の時刻衝突を避ける。
func _scale_time(anim: Animation, factor: float) -> void:
	for t in range(anim.get_track_count()):
		var count := anim.track_get_key_count(t)
		for k in range(count - 1, -1, -1):
			var tm := anim.track_get_key_time(t, k)
			anim.track_set_key_time(t, k, tm * factor)
	anim.length = anim.length * factor


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r: Node = _find(c, cls)
		if r != null:
			return r
	return null


func _init() -> void:
	var da := DirAccess.open("res://")
	if not da.dir_exists(OUT_DIR):
		da.make_dir_recursive(OUT_DIR)

	var ok := true
	for entry in CLIPS:
		if not _build_one(entry):
			ok = false
	print("=== build_melee_anims: ", "OK" if ok else "HAS FAILURE", " ===")
	quit(0 if ok else 1)


func _build_one(entry: Array) -> bool:
	var out_name: String = entry[0]
	var src_scene: String = entry[1]
	var src_key: String = entry[2]
	var trim_start: float = entry[3]
	var trim_end: float = entry[4]
	var speed: float = entry[5]
	var enable_t: float = entry[6]
	var disable_t: float = entry[7]
	var damage: float = entry[8]
	var knockback: float = entry[9]

	var packed: PackedScene = load(src_scene) as PackedScene
	if packed == null:
		print("[FAIL] load ", src_scene)
		return false
	var inst: Node = packed.instantiate()
	var ap: AnimationPlayer = _find(inst, "AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(src_key):
		print("[FAIL] anim '", src_key, "' missing in ", src_scene)
		inst.free()
		return false

	var src: Animation = ap.get_animation(src_key)

	# 1. パンチ区間の切り出し
	var anim := _trim(src, trim_start, trim_end)
	inst.free()

	# 2. 時間スケール
	_scale_time(anim, 1.0 / speed)

	# 3. ルートモーション除去（Hips XZ）
	_strip_hips_xz(anim)

	# 4. Call Method Track。root_node は Model(VRM) なので、Player はその親 ".."。
	var track := anim.add_track(Animation.TYPE_METHOD)
	anim.track_set_path(track, NodePath(".."))
	var enable_local := (enable_t - trim_start) / speed
	var disable_local := (disable_t - trim_start) / speed
	anim.track_insert_key(track, enable_local, {
		"method": "_enable_hitbox",
		"args": [damage, knockback],
	})
	anim.track_insert_key(track, disable_local, {
		"method": "_disable_hitbox",
		"args": [],
	})

	# コンボは1回再生。ループさせない。
	anim.loop_mode = Animation.LOOP_NONE

	var out_path := OUT_DIR + "/" + out_name + ".res"
	var err := ResourceSaver.save(anim, out_path)
	if err != OK:
		print("[FAIL] save ", out_path, " err=", err)
		return false
	print("[OK] ", out_path, "  len=", "%.3f" % anim.length,
		"s  enable=", "%.3f" % enable_local, "s disable=", "%.3f" % disable_local,
		"s dmg=", damage, " kb=", knockback)
	return true
