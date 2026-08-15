extends RefCounted

## test_civilian.gd から呼ぶ、実ロビー上の FLEE_PLAYER 専用ハーネス。

const LOBBY_SCENE: PackedScene = preload("res://levels/bank_lobby.tscn")
const SYNC_FRAMES: int = 12
const STATE_WAIT_FRAMES: int = 60
const FLEE_WAIT_FRAMES: int = 360
const DISTANCE_EPSILON: float = 0.1

func run(host: Node) -> Dictionary[StringName, Variant]:
	var result: Dictionary[StringName, Variant] = {
		&"no_flee_before_down": false,
		&"entered_and_moved_away": false,
		&"returned_to_rest": false,
		&"incapacitated_did_not_flee": false,
		&"distance_before": 0.0,
		&"distance_after": 0.0,
	}
	RunState.reset()
	GameDirector.reset()
	var lobby := LOBBY_SCENE.instantiate() as Node3D
	if lobby == null:
		return result
	host.add_child(lobby)

	var player := lobby.get_node_or_null(^"Player") as Node3D
	var target := lobby.get_node_or_null(^"Civilian3") as Civilian
	var downed := lobby.get_node_or_null(^"Civilian1") as Civilian
	var shielded := lobby.get_node_or_null(^"Civilian2") as Civilian
	for robber_name: StringName in [&"RobberLeader", &"RobberGunner", &"RobberErratic"]:
		var robber := lobby.get_node_or_null(NodePath(String(robber_name)))
		if robber != null:
			robber.process_mode = Node.PROCESS_MODE_DISABLED
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	for _frame: int in range(SYNC_FRAMES):
		await host.get_tree().physics_frame
	if player == null or target == null or downed == null or shielded == null:
		await _free_lobby(host, lobby)
		return result

	# まだ客が倒れていない状態では、接近しても通常姿勢のまま。
	player.global_position = target.global_position + Vector3(3.0, 0.0, 0.0)
	var position_before := target.global_position
	for _frame: int in range(STATE_WAIT_FRAMES):
		await host.get_tree().physics_frame
	result[&"no_flee_before_down"] = (
		RunState.civilians_downed == 0
		and target.current_state() == Civilian.CivilianState.PRONE
		and _flat_distance(position_before, target.global_position) <= DISTANCE_EPSILON
	)

	# 別の客を倒すと全生存客が逃走モードに入り、近い target が逃げ始める。
	var downed_health := downed.get_node_or_null(downed.health_path) as Health
	if downed_health != null:
		for _hit: int in range(downed_health.stagger_threshold):
			downed_health.take_hit(downed_health.max_hp, false)
	result[&"distance_before"] = _flat_distance(target.global_position, player.global_position)
	for _frame: int in range(STATE_WAIT_FRAMES):
		await host.get_tree().physics_frame
		if target.current_state() == Civilian.CivilianState.FLEE_PLAYER:
			break
	var entered_flee := target.current_state() == Civilian.CivilianState.FLEE_PLAYER
	for _frame: int in range(FLEE_WAIT_FRAMES):
		await host.get_tree().physics_frame
		if entered_flee and target.current_state() != Civilian.CivilianState.FLEE_PLAYER:
			break
	var distance_after := _flat_distance(target.global_position, player.global_position)
	var distance_before := float(result[&"distance_before"])
	result[&"distance_after"] = distance_after
	result[&"entered_and_moved_away"] = entered_flee \
		and distance_after > distance_before + DISTANCE_EPSILON
	result[&"returned_to_rest"] = (
		distance_after >= target.flee_stop_distance - DISTANCE_EPSILON
		and target.current_state() == Civilian.CivilianState.PRONE
	)
	# DOWNED と SHIELDED は、逃走条件を満たしていてもステートを維持する。
	player.global_position = downed.global_position + Vector3(1.0, 0.0, 0.0)
	for _frame: int in range(STATE_WAIT_FRAMES):
		await host.get_tree().physics_frame
	var downed_stayed := downed.current_state() == Civilian.CivilianState.DOWNED
	shielded.enter_shielded(player)
	player.global_position = shielded.global_position + Vector3(1.0, 0.0, 0.0)
	for _frame: int in range(STATE_WAIT_FRAMES):
		await host.get_tree().physics_frame
	var shielded_stayed := shielded.current_state() == Civilian.CivilianState.SHIELDED
	result[&"incapacitated_did_not_flee"] = downed_stayed and shielded_stayed

	await _free_lobby(host, lobby)
	RunState.reset()
	GameDirector.reset()
	return result


func _free_lobby(host: Node, lobby: Node3D) -> void:
	lobby.queue_free()
	await host.get_tree().process_frame


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
