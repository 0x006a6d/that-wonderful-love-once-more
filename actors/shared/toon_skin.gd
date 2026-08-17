class_name ToonSkin
extends RefCounted

## Mixamo キャラクター（写真テクスチャ + StandardMaterial3D）を、主人公の VRM と
## 同じ MToon（トゥーン陰影 + アウトライン）へ寄せる。
##
## 主人公は VRM で 75,739 頂点・MToon シェーダ 13 枚、犯人・客は Mixamo で
## 23,000〜37,000 頂点・4K の写真テクスチャ。頂点数の差は残るが、**陰影の系統**が
## 揃うだけで「別のゲームの人が混ざっている」感はかなり減る。
##
## 元のマテリアルは触らず、`MeshInstance3D.set_surface_override_material()` で
## 上書きする。`toon_skin = false` にすれば元の見た目へ戻せる。

const MTOON_SHADER: Shader = preload("res://addons/Godot-MToon-Shader/mtoon.gdshader")
const MTOON_CUTOUT_SHADER: Shader = preload(
	"res://addons/Godot-MToon-Shader/mtoon_cutout.gdshader")
const OUTLINE_SHADER: Shader = preload(
	"res://addons/Godot-MToon-Shader/mtoon_outline.gdshader")

## 陰影とアウトラインの値は、主人公 VRM の MToon マテリアル（13枚とも同値）から
## そのまま持ってきている。主人公と系統を揃えるのが目的なので、独自に決めない。
##   _ShadeToony 0.9 / _ShadeShift 0.0 / _IndirectLightIntensity 0.1
##   _OutlineWidth 0.05 / _OutlineWidthMode 1 / _OutlineColor 黒
const SHADE_TOONY: float = 0.9
const SHADE_SHIFT: float = 0.0
const INDIRECT_INTENSITY: float = 0.1
## VRM は 0.05 だが、Mixamo メッシュでは細すぎて線が出ない（実機で比較）。
## 0.05 / 0.4 / 1.0 を並置して 0.4 を採った。1.0 は靴の縁が太くなりすぎる。
const OUTLINE_WIDTH: float = 0.4
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
## 影側の色。VRM は専用の陰テクスチャを持つが Mixamo は持たないので、
## アルベドを暗くしたものを影色に使う。
const SHADE_FACTOR: float = 0.62
## アルファ抜きのしきい値。まつ毛・髪のカードに使う。
const ALPHA_CUTOFF: float = 0.5


## `model` 以下の全 MeshInstance3D を MToon へ差し替える。
static func apply(model: Node3D) -> void:
	if model == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect(model, meshes)
	for instance in meshes:
		var mesh: Mesh = instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var source := instance.get_active_material(surface) as StandardMaterial3D
			instance.set_surface_override_material(surface, _build(source))


## 元へ戻す（オーバーライドを外す）。見比べるときに使う。
static func clear(model: Node3D) -> void:
	if model == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect(model, meshes)
	for instance in meshes:
		var mesh: Mesh = instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			instance.set_surface_override_material(surface, null)


static func _build(source: StandardMaterial3D) -> ShaderMaterial:
	var albedo: Texture2D = null
	var color := Color.WHITE
	var cutout: bool = false
	if source != null:
		albedo = source.albedo_texture
		# Mixamo の取り込み結果はアルファが 0.8 になっている。そのまま MToon へ
		# 渡すと体が半透明になるので、不透明へ戻す。
		color = Color(source.albedo_color.r, source.albedo_color.g,
			source.albedo_color.b, 1.0)
		cutout = source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED

	var material := ShaderMaterial.new()
	material.shader = MTOON_CUTOUT_SHADER if cutout else MTOON_SHADER
	_set_common(material, albedo, color)
	material.set_shader_parameter("_AlphaCutoutEnable", 1.0 if cutout else 0.0)
	material.set_shader_parameter("_Cutoff", ALPHA_CUTOFF)

	# アウトラインは次パス。material_overlay は被弾フラッシュ（ModelTint）が使う。
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	_set_common(outline, albedo, color)
	outline.set_shader_parameter("_AlphaCutoutEnable", 1.0 if cutout else 0.0)
	outline.set_shader_parameter("_Cutoff", ALPHA_CUTOFF)
	# 1 = ワールド座標基準。距離で太さが変わらない。
	outline.set_shader_parameter("_OutlineWidthMode", 1.0)
	outline.set_shader_parameter("_OutlineWidth", OUTLINE_WIDTH)
	outline.set_shader_parameter("_OutlineColorMode", 0.0)
	outline.set_shader_parameter("_OutlineColor", OUTLINE_COLOR)
	outline.set_shader_parameter("_OutlineLightingMix", 0.0)
	material.next_pass = outline
	return material


static func _set_common(material: ShaderMaterial, albedo: Texture2D,
		color: Color) -> void:
	material.set_shader_parameter("_Color", color)
	material.set_shader_parameter("_ShadeColor",
		Color(color.r * SHADE_FACTOR, color.g * SHADE_FACTOR,
			color.b * SHADE_FACTOR, 1.0))
	if albedo != null:
		material.set_shader_parameter("_MainTex", albedo)
		material.set_shader_parameter("_ShadeTexture", albedo)
	material.set_shader_parameter("_ShadeToony", SHADE_TOONY)
	material.set_shader_parameter("_ShadeShift", SHADE_SHIFT)
	material.set_shader_parameter("_IndirectLightIntensity", INDIRECT_INTENSITY)
	material.set_shader_parameter("_ReceiveShadowRate", 1.0)
	material.set_shader_parameter("_ShadingGradeRate", 1.0)


static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, out)
