extends Node

## 銀行ロビーのヘッドレス検証（シーンハーネス版）。
## autoload とナビゲーションサーバーを解決させるため、--script ではなく
## シーンとして起動する:
##   godot --path . --headless res://tools/test_bank_lobby.tscn

const LOBBY_SCENE: String = "res://levels/bank_lobby.tscn"
const COVER_GROUP: StringName = &"cover"
const NAV_SOURCE_GROUP: StringName = &"nav_source"
const EXPECTED_COVER_COUNT: int = 16
const MAX_NAV_DISTANCE: float = 1.0
const NAVIGATION_SYNC_FRAMES: int = 8
const PLAYER_SETTLE_FRAMES: int = 90
const MIN_STANDING_Y: float = -0.05

const SPAWN_NAMES: Array[StringName] = [
	&"PlayerSpawn",
	&"RobberSpawn1",
	&"RobberSpawn2",
	&"RobberSpawn3",
	&"CivilianSpawn1",
	&"CivilianSpawn2",
	&"CivilianSpawn3",
	&"CivilianSpawn4",
	&"CivilianSpawn5",
	&"CivilianSpawn6",
]

const REQUIRED_NAV_SOURCES: Array[StringName] = [
	&"Floor",
	&"WallNorth",
	&"WallEast",
	&"WallWest",
	&"WallSouthWest",
	&"WallSouthEast",
	&"TellerCounter",
	&"PillarA",
	&"PillarB",
	&"PillarC",
	&"PillarD",
	&"PillarE",
	&"PillarF",
	&"AtmA",
	&"AtmB",
	&"AtmC",
	&"VaultDoor",
]

var _pass: int = 0
var _fail: int = 0
var _lobby: Node3D = null


func _ready() -> void:
	print("=== 銀行ロビー 検証開始 ===")

	var packed := load(LOBBY_SCENE) as PackedScene
	_assert("bank_lobby.tscn を読み込めた", packed != null)
	if packed == null:
		_finish()
		return

	_lobby = packed.instantiate() as Node3D
	_assert("bank_lobby.tscn をインスタンス化できた", _lobby != null)
	if _lobby == null:
		_finish()
		return
	add_child(_lobby)

	# NavigationServer3D が同期ベイク後のマップを反映するまで物理フレームを進める。
	for _frame: int in range(NAVIGATION_SYNC_FRAMES):
		await get_tree().physics_frame

	var region := _lobby.get_node_or_null(^"NavigationRegion3D") as NavigationRegion3D
	var navmesh_ready: bool = region != null and region.navigation_mesh != null \
		and region.navigation_mesh.get_polygon_count() > 0
	_assert("ナビメッシュがベイクされ、ポリゴンが生成された", navmesh_ready)
	if not navmesh_ready:
		_finish()
		return

	var navigation_map: RID = region.get_navigation_map()
	_check_spawns(navigation_map)
	_check_cover_markers(navigation_map)
	_check_path(navigation_map)
	_check_nav_sources()
	await _check_player_floor()
	_finish()


func _check_spawns(navigation_map: RID) -> void:
	var all_on_navigation: bool = true
	for spawn_name: StringName in SPAWN_NAMES:
		var marker := _lobby.get_node_or_null(NodePath(String(spawn_name))) as Marker3D
		if marker == null or not _is_on_navigation(navigation_map, marker.global_position):
			all_on_navigation = false
			print("[spawn] navmesh 外: %s" % spawn_name)
	_assert("Player / Robber / Civilian の全スポーン地点がナビメッシュ上にある",
		all_on_navigation)


func _check_cover_markers(navigation_map: RID) -> void:
	var cover_nodes := get_tree().get_nodes_in_group(COVER_GROUP)
	var all_on_navigation: bool = cover_nodes.size() == EXPECTED_COVER_COUNT
	for cover_node: Node in cover_nodes:
		var marker := cover_node as Marker3D
		if marker == null or not _is_on_navigation(navigation_map, marker.global_position):
			all_on_navigation = false
			print("[cover] navmesh 外または Marker3D ではない: %s" % cover_node.name)
	_assert("cover グループのマーカーが16点ある", cover_nodes.size() == EXPECTED_COVER_COUNT)
	_assert("cover マーカーがすべてナビメッシュ上にある", all_on_navigation)


func _check_path(navigation_map: RID) -> void:
	var robber_spawn := _lobby.get_node_or_null(^"RobberSpawn1") as Marker3D
	var player_spawn := _lobby.get_node_or_null(^"PlayerSpawn") as Marker3D
	var path := PackedVector3Array()
	if robber_spawn != null and player_spawn != null:
		path = NavigationServer3D.map_get_path(navigation_map,
			robber_spawn.global_position, player_spawn.global_position, true)
	var reaches_player: bool = path.size() > 0 and player_spawn != null \
		and _horizontal_distance(path[path.size() - 1], player_spawn.global_position) \
		<= MAX_NAV_DISTANCE
	_assert("RobberSpawn1 から PlayerSpawn まで経路を引ける", reaches_player)


func _check_nav_sources() -> void:
	var all_registered: bool = true
	for source_name: StringName in REQUIRED_NAV_SOURCES:
		var source := _lobby.get_node_or_null(NodePath(String(source_name)))
		if source == null or not source.is_in_group(NAV_SOURCE_GROUP):
			all_registered = false
			print("[nav_source] 未登録: %s" % source_name)
	_assert("床・壁・柱・カウンター・ATM・金庫扉が nav_source に登録されている",
		all_registered)


func _check_player_floor() -> void:
	var player := _lobby.get_node_or_null(^"Player") as CharacterBody3D
	var player_spawn := _lobby.get_node_or_null(^"PlayerSpawn") as Marker3D
	if player == null or player_spawn == null:
		_assert("プレイヤーが床の上に立っている", false)
		return
	for _frame: int in range(PLAYER_SETTLE_FRAMES):
		await get_tree().physics_frame
	var remained_above_floor: bool = player.global_position.y >= MIN_STANDING_Y
	_assert("プレイヤーが床を抜けず PlayerSpawn 付近に立っている",
		remained_above_floor and
		_horizontal_distance(player.global_position, player_spawn.global_position) <= MAX_NAV_DISTANCE)


func _is_on_navigation(navigation_map: RID, position: Vector3) -> bool:
	var closest := NavigationServer3D.map_get_closest_point(navigation_map, position)
	return _horizontal_distance(position, closest) <= MAX_NAV_DISTANCE


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _assert(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[PASS] %s" % label)
	else:
		_fail += 1
		print("[FAIL] %s" % label)


func _finish() -> void:
	print("=== 結果: PASS=%d FAIL=%d ===" % [_pass, _fail])
	print("ALL PASS" if _fail == 0 else "FAILED")
	get_tree().quit(0 if _fail == 0 else 1)
