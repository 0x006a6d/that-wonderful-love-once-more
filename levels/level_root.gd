class_name LevelRoot
extends Node3D

## レベル共通のルート制御。
## 操作系はキーボード/パッド完結になったため、マウスキャプチャ管理は廃止した。
##
## ナビメッシュはここで実行時にベイクする。エディタでのベイク操作を人間に渡さず
## 済ませるためで、プリミティブ構成のレベルなら同期ベイクでも短時間で終わる。
## 対象ジオメトリは `nav_source` グループ（床・壁・柱・什器）から集める。

## ナビメッシュをベイクする NavigationRegion3D。
@export var navigation_region_path: NodePath = ^"NavigationRegion3D"
## ジオメトリを集めるグループ名。
@export var navigation_source_group: StringName = &"nav_source"
## エージェント（犯人・客）の半径と身長（m）。通路幅の下限を決める。
@export var agent_radius: float = 0.45
@export var agent_height: float = 1.8
## ボクセルの解像度（m）。既定のナビゲーションマップ（プロジェクト設定
## navigation/3d/default_cell_size = 0.25）と一致させる。ここだけ細かくすると
## マップ側のラスタライズ解像度と食い違い、エッジがずれる警告が出る。
@export var nav_cell_size: float = 0.25


func _ready() -> void:
	_bake_navigation()


func _bake_navigation() -> void:
	var region := get_node_or_null(navigation_region_path) as NavigationRegion3D
	if region == null:
		push_warning("level_root: NavigationRegion3D が見つからない")
		return

	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = nav_cell_size
	nav_mesh.agent_radius = agent_radius
	nav_mesh.agent_height = agent_height
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = navigation_source_group
	region.navigation_mesh = nav_mesh
	# 同期ベイク（on_thread=false）。ヘッドレス検証でも結果が同じフレームで確定する。
	region.bake_navigation_mesh(false)
	print("[%s] navmesh baked: polygons=%d vertices=%d" %
		[name, nav_mesh.get_polygon_count(), nav_mesh.vertices.size()])
