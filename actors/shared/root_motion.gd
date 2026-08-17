class_name RootMotion
extends RefCounted

## Mixamo クリップのルートモーション（Hips の位置トラック）を扱う。
##
## 本作では位置を `CharacterBody3D` が持つ。クリップ側が体を運ぶと、見た目と
## 当たり判定・ナビゲーションがずれる。Mixamo の "In Place" で落とせなかった
## クリップは、取り込み後にここで水平成分を潰す。
##
## 実測（`tools/inspect_motion.gd` 系で確認）:
## - `mixamo_walk` / `mixamo_run`: 0 m（In Place で取得済み）
## - `mixamo_step_forward`: 0.93 m
## - `mixamo_death_backward_01`: 1.37 m
## - `mixamo_dying`: 0.33 m

const HIPS_SUFFIX: String = ":Hips"


## Hips の位置トラックから水平成分を抜き、先頭フレームの値で固定する。
## 上下（倒れ込みで腰が落ちる、歩行で腰が上下する）はそのまま残す。
static func lock_horizontal(animation: Animation) -> void:
	if animation == null:
		return
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track)).ends_with(HIPS_SUFFIX):
			continue
		var key_count: int = animation.track_get_key_count(track)
		if key_count == 0:
			continue
		var base: Vector3 = animation.track_get_key_value(track, 0)
		for key in range(key_count):
			var value: Vector3 = animation.track_get_key_value(track, key)
			animation.track_set_key_value(track, key, Vector3(base.x, value.y, base.z))


## 水平方向のルートモーション量（m）。取り込んだクリップの素性を確かめるのに使う。
static func horizontal_travel(animation: Animation) -> float:
	if animation == null:
		return 0.0
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track)).ends_with(HIPS_SUFFIX):
			continue
		var first: Vector3 = animation.position_track_interpolate(track, 0.0)
		var last: Vector3 = animation.position_track_interpolate(track, animation.length)
		return Vector2(last.x - first.x, last.z - first.z).length()
	return 0.0
