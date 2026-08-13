extends SceneTree

## 近接コンボ用アニメーションの .res 生成ツール。
##
## インポート済みアニメ（Mixamo FBX）は read-only なので、ここで各クリップを
## 複製 →「パンチ区間だけをキー単位で切り出し」→ 時間スケール → Hips XZ 除去 →
## Call Method Track 追加、の順で加工し res://actors/player/anim/*.res へ保存する。
##
## 3段コンボ: 1押し目=左ジャブ / 2押し目=右ストレート / 3押し目=右フック。
##
## 教訓 (diag_punch_hands.gd の両手計測): Punch_Combo は L-R-L-R の4連フラリーで
## 隣接振りの間隔が 0.2s しかなく、どの窓で切っても複数の振りが混入する
## (旧 melee_1 に視覚上3発入っていた原因)。単発クリップのみを使うこと。
## 使うクリップは必ず両手計測で「視覚上1発」を確認してから載せる。
##
## 区間切り出しの根拠 (両手計測、Hips XZ 除去後):
##   Cross_Punch: 右 1 発のみ (R peak 0.626m @1.10s、L は全編ガード帯 0.35-0.40)
##     → trim [0.55, 1.45]s。打撃 0.92-1.25s
##   hook_4: 右フック 1 発 (R が x -0.31→+0.11 へ横断、xz peak 0.386m @0.75s。
##     フック中の L は前方 0.35 以下)。左スイングが 0.95s から始まるため
##     trim [0.45, 0.90]s で単発に切れる (diag_hook_lateral.gd)
##   ※ melee_1 は左ジャブ素材 (mixamo_jab_left) が届くまで Cross_Punch を仮使用
##
## 使い方: godot --path . --headless --script tools/build_melee_anims.gd

const OUT_DIR: String = "res://actors/player/anim"

# [出力名, ソース, アニメキー, trim_start, trim_end, speed, enable_t, disable_t, damage, knockback]
# trim_* / enable_t / disable_t は元クリップ（等速）基準の秒。
const CLIPS: Array = [
	# 暫定: 左ジャブ素材待ち。届いたら mixamo_jab_left.fbx に差し替える。
	["melee_1", "res://assets/motions/mixamo_cross_punch.fbx", "mixamo_com",
		0.55, 1.45, 1.3, 0.95, 1.28, 10.0, 3.0],
	["melee_2", "res://assets/motions/mixamo_cross_punch.fbx", "mixamo_com",
		0.55, 1.45, 1.3, 0.95, 1.28, 20.0, 7.0],
	# フックは重さを出すため速度スケールを控えめに (1.15)。
	["melee_3", "res://assets/motions/mixamo_hook_4.fbx", "mixamo_com",
		0.45, 0.90, 1.15, 0.65, 0.85, 26.0, 9.0],
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
