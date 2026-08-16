extends SceneTree

## 近接コンボ用アニメーションの .res 生成ツール。
##
## インポート済みアニメ（Mixamo FBX）は read-only なので、ここで各クリップを
## 複製 →「パンチ区間だけをキー単位で切り出し」→ 時間スケール → Hips XZ 除去 →
## Call Method Track 追加、の順で加工し res://actors/player/anim/*.res へ保存する。
##
## コンボ木で再利用する6技: 左ジャブ / 右ストレート / 左フック /
## 右膝 / 右ミドル / 右ハイ。技と出力クリップの対応は CLIPS に集約する。
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
	# 区間はワインドアップ 0.70 → 伸展 1.00 → 引き戻し 1.15。
	# 等速 (1.0x) で重く見せ、終端を 1.15 まで延ばして伸び切りポーズを一拍見せる。
	# enable はピーク (src 1.00s) 直前の 0.99 に置く: ヒットストップの凍結が
	# 「伸び切ったフック」で起きるようにする。旧 0.96 はピーク手前で凍結し
	# 「伸びきっていない」ように見えた (ユーザー指摘、ジャブと同じ失敗)。
	["melee_3", "res://assets/motions/mixamo_hook_4.fbx", "mixamo_com",
		0.70, 1.15, 1.0, 0.99, 1.10, 26.0, 10.0],

	# --- キックコンボ: 膝 → ミドル → MMA キック (diag_kick_feet.gd の実測) ---
	# kick_1: 右ひざ (Illegal Knee)。単発 (ひざ高さ peak 1.161m @0.80、1.3s で復帰)。
	# 初段のテンポを出すため 1.4x。射程が短いので lunge を深めにする (player.gd 側)。
	["kick_1", "res://assets/motions/mixamo_knee.fbx", "mixamo_com",
		0.35, 1.20, 1.4, 0.68, 0.98, 14.0, 1.2],
	# kick_2: 右ミドル/ハイ (Kicking)。単発 (RF peak 0.868m @0.65)。
	# enable はピーク直前 (0.62)。1.15x。
	["kick_2", "res://assets/motions/mixamo_kick_finish.fbx", "mixamo_com",
		0.30, 0.95, 1.15, 0.62, 0.85, 20.0, 2.0],
	# kick_3: MMA キック (Mma Kick、フィニッシュ)。単発の高蹴り大技。
	# ソースの流れ (映像実測): 溜め=後傾 0.20-0.45 → 膝上げ 0.53-0.75 →
	# 脚が頭上まで伸びる山 0.80-0.87 → 0.93以降は前に折れて復帰。
	# 旧区間 [0.45,1.00]/1.1x は溜めを飛ばして突然始まり、終端が折れ復帰に食い込み、
	# 圧縮もされて「短い・違和感」だった (ユーザー指摘)。
	# 新区間 [0.32,0.95]: 溜め → 膝上げ → 高蹴りの山 → 折れる手前で終える。
	# 等速 (1.0x) で大技の重さを出す。enable は山 (0.87) 直前の 0.80、disable 0.92。
	# 吹き飛ばし。
	["kick_3", "res://assets/motions/mixamo_kick_mma.fbx", "mixamo_com",
		0.32, 0.95, 1.0, 0.80, 0.92, 30.0, 12.0],
	# ユーザー判断でコンボから外れた素材 (実測値は残す。未使用):
	#   Kick Soccerball 右前蹴り RF 0.590m @0.25-0.30:
	#   ["kick_soccer", "res://assets/motions/mixamo_kick_soccer.fbx", "mixamo_com",
	#       0.00, 0.45, 1.0, 0.20, 0.36, 14.0, 1.5],
	#   Kicking2 左ハイ LF 0.880m @1.20-1.25:
	#   [".", "res://assets/motions/mixamo_kick_high_left.fbx", "mixamo_com",
	#       0.60, 1.50, 1.3, 1.05, 1.32, 20.0, 2.0],
	#   Roundhouse 右回し蹴り planar 0.803m @1.10、高さ 1.325m @0.90:
	#   [".", "res://assets/motions/mixamo_kick_roundhouse.fbx", "mixamo_com",
	#       0.50, 1.15, 1.15, 0.85, 1.08, 30.0, 12.0],
	#   Side Kick 右サイド RF 0.765m @0.70:
	#   [".", "res://assets/motions/mixamo_kick_side.fbx", "mixamo_com",
	#       0.30, 0.95, 1.15, 0.62, 0.88, 30.0, 12.0],
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
