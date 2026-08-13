extends SceneTree

## 近接コンボ用アニメーションの .res 生成ツール。
##
## インポート済みアニメ（Mixamo FBX / universal gltf）は read-only なので、
## そのまま Call Method Track を足せない。ここで各クリップを複製し、
## Player 本体（メソッド保持者）に対する Call Method Track を追加して
## res://actors/player/anim/*.res として保存する。
##
## 生成物:
##   melee_1.res  ← mixamo_punch_combo.fbx の先頭ジャブ（短い直突き）
##   melee_2.res  ← mixamo_cross_punch.fbx（採用済みの右ストレート）
##
## Method Track はアニメ再生中に Player の _enable_hitbox / _disable_hitbox を叩く。
## トラックのノードパスは AnimationPlayer.root_node（= Player）基準の "." とする。
##
## 判定ウィンドウ（実測: tools/measure_combo_window.gd）:
##   melee_1: peak_fwd 0.414m @0.89s → enable 0.33s / disable 0.70s（先頭ジャブのみ）
##   melee_2: peak_fwd 0.450m @1.12s、window 0.79-1.25s → enable 0.75s / disable 1.30s
##
## 使い方: godot --path . --headless --script tools/build_melee_anims.gd

const OUT_DIR: String = "res://actors/player/anim"

# 全クリップに掛ける時間スケール（>1 で速くなる）。method key もまとめてスケールし同期を保つ。
const SPEED: float = 1.5

# [出力名, ソースPackedScene, ソースアニメキー, enable_t, disable_t, damage, knockback]
# enable_t / disable_t は元クリップ（等速）基準の秒。保存時に 1/SPEED でスケールする。
const CLIPS: Array = [
	["melee_1", "res://assets/motions/mixamo_punch_combo.fbx", "mixamo_com", 0.33, 0.70, 12.0, 4.0],
	["melee_2", "res://assets/motions/mixamo_cross_punch.fbx", "mixamo_com", 0.75, 1.30, 20.0, 7.0],
]


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
	var enable_t: float = entry[3]
	var disable_t: float = entry[4]
	var damage: float = entry[5]
	var knockback: float = entry[6]

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

	var anim: Animation = (ap.get_animation(src_key).duplicate(true)) as Animation
	inst.free()

	# 時間スケール: 全トラックのキー時刻と length を 1/SPEED 倍する（method key も後で合わせる）。
	_scale_time(anim, 1.0 / SPEED)

	# ルートモーション除去: Hips 位置トラックのキー XZ を 0 に固定する（Y の上下動は保持）。
	# 残っていると再生中に体が滑って見え、攻撃終了時に待機ポーズ位置へスナップする。
	_strip_hips_xz(anim)

	# Call Method Track を追加。root_node は Model(VRM) なので、Player はその親 ".."。
	var track := anim.add_track(Animation.TYPE_METHOD)
	anim.track_set_path(track, NodePath(".."))
	# 有効化: _enable_hitbox(damage, knockback)
	anim.track_insert_key(track, enable_t / SPEED, {
		"method": "_enable_hitbox",
		"args": [damage, knockback],
	})
	# 無効化: _disable_hitbox()
	anim.track_insert_key(track, disable_t / SPEED, {
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
		"s  enable=", enable_t, "s disable=", disable_t, "s dmg=", damage, " kb=", knockback)
	return true
