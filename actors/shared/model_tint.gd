class_name ModelTint
extends RefCounted

## `Model` 以下のメッシュ全体に色を被せる。
##
## プリミティブ表示だった頃はカプセルの albedo をステート色そのものに置き換えて
## いたが、テクスチャ付きのキャラクターでは同じことができない。そこで
## `material_overlay`（元のマテリアルの上に重ねる層）へ半透明の単色を載せ、
## 警戒・予備動作・被弾フラッシュだけを色で伝える。通常時は重ねない。

var _meshes: Array[MeshInstance3D] = []
var _overlay: StandardMaterial3D = null
var _applied: bool = false


func setup(model: Node3D) -> void:
	_meshes.clear()
	_applied = false
	if model == null:
		return
	_collect(model)
	if _meshes.is_empty():
		return
	# 個体ごとに独立して色を変えるため、マテリアルは共有しない。
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(1, 1, 1, 0)


func is_ready() -> bool:
	return _overlay != null


## 現在被せている色（アルファ込み）。検証用。
func current_color() -> Color:
	return Color(1, 1, 1, 0) if _overlay == null else _overlay.albedo_color


## alpha が 0 のときは overlay 自体を外す。透明の描画パスを毎フレーム積まない。
func apply(color: Color, alpha: float) -> void:
	if _overlay == null:
		return
	var clamped: float = clampf(alpha, 0.0, 1.0)
	_overlay.albedo_color = Color(color.r, color.g, color.b, clamped)
	var want: bool = clamped > 0.0
	if want == _applied:
		return
	_applied = want
	for mesh in _meshes:
		mesh.material_overlay = _overlay if want else null


func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child)
