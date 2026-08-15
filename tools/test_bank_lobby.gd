extends Node

## 銀行ロビーのヘッドレス検証（シーンハーネス版）。
## autoload とナビゲーションサーバーを解決させるため、--script ではなく
## シーンとして起動する:
##   godot --path . --headless res://tools/test_bank_lobby.tscn

const LOBBY_SCENE: String = "res://levels/bank_lobby.tscn"
const COVER_GROUP: StringName = &"cover"
const NAV_SOURCE_GROUP: StringName = &"nav_source"
const EXPECTED_COVER_COUNT: int = 16
const EXPECTED_ROBBER_COUNT: int = 3
const EXPECTED_CIVILIAN_COUNT: int = 6
const MAX_NAV_DISTANCE: float = 1.0
const NAVIGATION_SYNC_FRAMES: int = 8
const PLAYER_SETTLE_FRAMES: int = 90
const RUNTIME_CHECK_FRAMES: int = 540
const MIN_ROBBER_MOVEMENT: float = 0.25
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

const ACTOR_NAMES: Array[StringName] = [
	&"RobberLeader",
	&"RobberGunner",
	&"RobberErratic",
	&"Civilian1",
	&"Civilian2",
	&"Civilian3",
	&"Civilian4",
	&"Civilian5",
	&"Civilian6",
]

const ROBBER_NAMES: Array[StringName] = [
	&"RobberLeader",
	&"RobberGunner",
	&"RobberErratic",
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
	RunState.reset()
	GameDirector.reset()

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
	var initial_actor_positions := _collect_actor_positions()

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
	_check_population()
	_check_actor_navigation(navigation_map, initial_actor_positions)
	_check_actor_spacing(initial_actor_positions)
	_check_start_act()
	_check_gunner_cover(navigation_map)
	await _check_player_floor()
	await _check_runtime_behavior(initial_actor_positions)
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


func _check_population() -> void:
	var leader_count: int = 0
	var gunner_count: int = 0
	var erratic_count: int = 0
	var civilian_count: int = 0
	for child: Node in _lobby.get_children():
		if child is Leader:
			leader_count += 1
		elif child is Gunner:
			gunner_count += 1
		elif child is Erratic:
			erratic_count += 1
		if child is Civilian:
			civilian_count += 1
	_assert("Leader / Gunner / Erratic がロビーに1体ずつ存在する",
		leader_count == 1 and gunner_count == 1 and erratic_count == 1
		and leader_count + gunner_count + erratic_count == EXPECTED_ROBBER_COUNT)
	_assert("客が6人存在する", civilian_count == EXPECTED_CIVILIAN_COUNT)
	_assert("RunState.civilians_total が6になる",
		RunState.civilians_total == EXPECTED_CIVILIAN_COUNT)


func _collect_actor_positions() -> Dictionary[StringName, Vector3]:
	var positions: Dictionary[StringName, Vector3] = {}
	for actor_name: StringName in ACTOR_NAMES:
		var actor := _lobby.get_node_or_null(NodePath(String(actor_name))) as Node3D
		if actor != null:
			positions[actor_name] = actor.global_position
	return positions


func _check_actor_navigation(navigation_map: RID,
		initial_positions: Dictionary[StringName, Vector3]) -> void:
	var all_on_navigation: bool = initial_positions.size() == ACTOR_NAMES.size()
	for actor_name: StringName in ACTOR_NAMES:
		if not initial_positions.has(actor_name):
			all_on_navigation = false
			print("[actor] 初期位置を取得できない: %s" % actor_name)
			continue
		var position: Vector3 = initial_positions[actor_name]
		if not _is_on_navigation(navigation_map, position):
			all_on_navigation = false
			print("[actor] 初期位置が navmesh 外: %s %s" % [actor_name, position])
	_assert("犯人3体と客6人の初期位置がすべてナビメッシュ上にある",
		all_on_navigation)


func _check_actor_spacing(initial_positions: Dictionary[StringName, Vector3]) -> void:
	var level := _lobby as LevelRoot
	var required_distance: float = level.agent_radius * 2.0 if level != null else INF
	var minimum_distance: float = INF
	var minimum_pair: String = "取得不能"
	for first_index: int in range(ACTOR_NAMES.size()):
		var first_name: StringName = ACTOR_NAMES[first_index]
		if not initial_positions.has(first_name):
			continue
		for second_index: int in range(first_index + 1, ACTOR_NAMES.size()):
			var second_name: StringName = ACTOR_NAMES[second_index]
			if not initial_positions.has(second_name):
				continue
			var distance := _horizontal_distance(
				initial_positions[first_name], initial_positions[second_name])
			if distance < minimum_distance:
				minimum_distance = distance
				minimum_pair = "%s / %s" % [first_name, second_name]
	print("[spacing] 最小間隔=%.3f m (%s), 必要間隔=%.3f m" %
		[minimum_distance, minimum_pair, required_distance])
	_assert("犯人3体と客6人が agent_radius * 2 以上離れている",
		initial_positions.size() == ACTOR_NAMES.size()
		and minimum_distance >= required_distance)


func _check_start_act() -> void:
	_assert("start_act の既定で INFILTRATION から開始する",
		GameDirector.current_act == GameTypes.Act.INFILTRATION)
	var all_prone: bool = true
	for actor_name: StringName in ACTOR_NAMES:
		if not String(actor_name).begins_with("Civilian"):
			continue
		var civilian := _lobby.get_node_or_null(NodePath(String(actor_name))) as Civilian
		if civilian == null or civilian.current_state() != Civilian.CivilianState.PRONE:
			all_prone = false
	_assert("INFILTRATION 開始時に客6人が PRONE に入る", all_prone)


func _check_gunner_cover(navigation_map: RID) -> void:
	var gunner := _lobby.get_node_or_null(^"RobberGunner") as Gunner
	var player := _lobby.get_node_or_null(^"Player") as Node3D
	var gun: HitscanGun = null
	if gunner != null:
		gun = gunner.get_node_or_null(gunner.hitscan_gun_path) as HitscanGun
	var nearest_cover: Marker3D = null
	var nearest_distance: float = INF
	var valid_count: int = 0
	if gunner != null and player != null and gun != null:
		var aim_position := player.global_position + Vector3.UP * gunner.player_aim_height
		for cover_node: Node in get_tree().get_nodes_in_group(COVER_GROUP):
			var marker := cover_node as Marker3D
			if marker == null or not _lobby.is_ancestor_of(marker):
				continue
			if _horizontal_distance(marker.global_position, player.global_position) \
					< gunner.min_cover_distance:
				continue
			var muzzle_position := marker.global_position \
				+ Vector3.UP * gunner.cover_muzzle_height
			if not gun.has_clear_shot_from(muzzle_position, player, aim_position):
				continue
			valid_count += 1
			var distance := _horizontal_distance(
				gunner.global_position, marker.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_cover = marker
	if nearest_cover != null:
		print("[cover] 銃持ちの初期最寄り候補=%s、有効候補=%d" %
			[nearest_cover.name, valid_count])
	_assert("銃持ちが実ロビーの16点からナビメッシュ上の遮蔽候補を選べる",
		nearest_cover != null
		and nearest_cover.is_in_group(COVER_GROUP)
		and _is_on_navigation(navigation_map, nearest_cover.global_position))


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


func _check_runtime_behavior(
		initial_positions: Dictionary[StringName, Vector3]) -> void:
	var maximum_movements: Dictionary[StringName, float] = {}
	for robber_name: StringName in ROBBER_NAMES:
		maximum_movements[robber_name] = 0.0
	for _frame: int in range(RUNTIME_CHECK_FRAMES):
		await get_tree().physics_frame
		for robber_name: StringName in ROBBER_NAMES:
			var robber := _lobby.get_node_or_null(NodePath(String(robber_name))) as Robber
			if robber == null or not initial_positions.has(robber_name):
				continue
			var moved := _horizontal_distance(
				initial_positions[robber_name], robber.global_position)
			maximum_movements[robber_name] = maxf(maximum_movements[robber_name], moved)
	var all_robbers_progressed: bool = true
	for robber_name: StringName in ROBBER_NAMES:
		var robber := _lobby.get_node_or_null(NodePath(String(robber_name))) as Robber
		if robber == null or not initial_positions.has(robber_name):
			all_robbers_progressed = false
			continue
		var maximum_movement: float = maximum_movements[robber_name]
		print("[runtime] %s: 最大移動=%.3f m, state=%d" %
			[robber_name, maximum_movement, robber.current_state()])
		if maximum_movement < MIN_ROBBER_MOVEMENT:
			all_robbers_progressed = false
	var leader := _lobby.get_node_or_null(^"RobberLeader") as Leader
	var shielded_name: String = "なし"
	if leader != null and leader.shielded_civilian() != null:
		shielded_name = String(leader.shielded_civilian().name)
	print("[runtime] civilians_downed=%d, leader_shielded=%s" %
		[RunState.civilians_downed, shielded_name])
	_assert("数秒進めても犯人3体がスタックせず巡回または役割行動を進める",
		all_robbers_progressed)


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
