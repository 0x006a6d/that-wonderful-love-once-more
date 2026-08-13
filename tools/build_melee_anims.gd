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
## 区間は「ガード → 伸展 → ガード復帰」だけに絞る (予備動作の長い区間を含めない)。
## 根拠 (両手計測、Hips XZ 除去後):
##   Lead Jab (mixamo_jab_left): 左 1 発のみ (L peak 0.497m @0.40s、右は全編ガード)。
##     拳が動き出す直前 0.22s 〜 ガード復帰 0.62s → trim [0.22, 0.62]s、1.4x
##   Cross_Punch: 右 1 発のみ (R peak 0.629m @1.12s)。長い引き絞り (0.43-0.90s) は
##     ほぼ除外し、打撃直前 0.80s 〜 戻り 1.42s → trim [0.80, 1.42]s。
##     伸展保持 (≥0.55m が 0.17s) を 0.1s に収めるため 1.7x
##   hook_4: 右フック 1 発 (xz peak 0.386m @0.75s)。trim [0.50, 0.92]s、1.15x
##
## 使い方: godot --path . --headless --script tools/build_melee_anims.gd

const OUT_DIR: String = "res://actors/player/anim"

# [出力名, ソース, アニメキー, trim_start, trim_end, speed, enable_t, disable_t, damage, knockback]
# trim_* / enable_t / disable_t は元クリップ（等速）基準の秒。
const CLIPS: Array = [
	# 左ジャブ。ジャブらしく速め (1.4x)。
	# enable はピーク (src 0.40s) 直前に置く: ヒットストップの凍結が「伸び切った打撃
	# ポーズ」で起きるようにするため。早すぎると伸びかけで凍結→再開が2発目に見える
	# (state_a3.csv の tick 69-72 で実証)。
	# ノックバックは途中段を小さく (その場でよろけ)、フィニッシュのフックだけ吹き飛ばす。
	# 途中段で飛ばすと次段が射程外になり空振りする (ユーザー実機で確認)。
	["melee_1", "res://assets/motions/mixamo_jab_left.fbx", "mixamo_com",
		0.22, 0.62, 1.4, 0.36, 0.48, 10.0, 1.2],
	# 右ストレート。伸展保持を 0.1s に収める (1.7x)。enable はピーク (src 1.12s) 直前。
	["melee_2", "res://assets/motions/mixamo_cross_punch.fbx", "mixamo_com",
		0.80, 1.42, 1.7, 1.08, 1.27, 20.0, 2.0],
	# 左フック (フィニッシュ)。hook_4 の本命は 1.00s の左フック (L 0.513m)。
	# 0.75s 付近の右手の揺れ (R 0.386m) はパンチではない — 旧区間 [0.50,0.92] は
	# これを掴んで左フックの直前 (腕を引いた所) で切れていた (ユーザー実機指摘で発覚)。
	# 区間はワインドアップ 0.70 → 伸展 1.00 → 引き戻し 1.08 で「伸ばした所」で終わる。
	# 重さを出すため速度スケールは控えめ (1.15)。
	["melee_3", "res://assets/motions/mixamo_hook_4.fbx", "mixamo_com",
		0.70, 1.08, 1.15, 0.96, 1.05, 26.0, 10.0],
]


## [start, end] 区間を 60Hz で全トラックサンプリングし、密なキーで新規 Animation を
## 構築する (ベイク方式)。時間スケールもここで直接埋め込む
## (出力時刻 s に対しソース時刻 start + s*speed をサンプリング)。
##
## 旧方式の欠陥 2 点 (どちらも実行時の見た目多峰化・伸びっぱなしの原因):
## 1. キー流用スライスは、キーが疎なトラックで区間境界外のポーズが補間で漏れ込む
## 2. 事後の _scale_time は track_set_key_time がキー配列を並べ替えるため
##    インデックスがずれ、一部のキーが未スケール/二重スケールになる
##    (length だけ縮み、キー時刻は元のまま → クリップ前半だけの等速再生になっていた)
## ベイク+直接スケールは元のキー配置・事後変換に一切依存しない。
const BAKE_FPS: float = 60.0

func _bake(src: Animation, start: float, end: float, speed: float) -> Animation:
	var out := Animation.new()
	out.length = (end - start) / speed
	var dt := 1.0 / BAKE_FPS
	for t in range(src.get_track_count()):
		var type := src.track_get_type(t)
		if type != Animation.TYPE_POSITION_3D \
				and type != Animation.TYPE_ROTATION_3D \
				and type != Animation.TYPE_SCALE_3D:
			# ボーン姿勢以外のトラックは現状の素材に存在しない。
			continue
		var nt := out.add_track(type)
		out.track_set_path(nt, src.track_get_path(t))
		out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		var s := 0.0
		while s <= out.length + 0.0001:
			var src_t := clampf(start + s * speed, 0.0, src.length)
			match type:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(nt, s, src.position_track_interpolate(t, src_t))
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(nt, s, src.rotation_track_interpolate(t, src_t))
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(nt, s, src.scale_track_interpolate(t, src_t))
			s += dt
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

	# 1. パンチ区間のベイク (60Hz 密キー、時間スケールはベイク内で埋め込み)
	var anim := _bake(src, trim_start, trim_end, speed)
	inst.free()

	# 2. ルートモーション除去（Hips XZ）
	_strip_hips_xz(anim)

	# 3. Call Method Track。root_node は Model(VRM) なので、Player はその親 ".."。
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
