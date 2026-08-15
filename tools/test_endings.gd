extends Node

## 実ロビーを読み込み、幕移行を通して4分岐へ到達できることを検証する。

const LOBBY_SCENE: PackedScene = preload("res://levels/bank_lobby.tscn")
const WAIT_FRAMES: int = 8
const DISABLED_BREACH_DELAY: float = 0.05
const BREACH_WAIT_FRAMES: int = 12

const ROBBER_NAMES: Array[StringName] = [
	&"RobberLeader", &"RobberGunner", &"RobberErratic",
]

var _pass: int = 0
var _fail: int = 0
var _original_breach_enabled: bool = false
var _original_breach_delay: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	print("=== エンディング縦切り 検証開始 ===")
	_original_breach_enabled = GameDirector.enable_breach
	_original_breach_delay = GameDirector.breach_delay

	await _test_act_flow_elapsed_and_ideal()
	await _test_ending_case(GameTypes.Ending.NORMAL, "通常", 0, false, true)
	await _test_ending_case(GameTypes.Ending.DRIFT, "逸脱", 3, false, false)
	await _test_ending_case(GameTypes.Ending.FAILURE, "失敗", 1, true, false, true)

	GameDirector.enable_breach = _original_breach_enabled
	GameDirector.breach_delay = _original_breach_delay
	get_tree().paused = false
	_finish()


func _test_act_flow_elapsed_and_ideal() -> void:
	await _reset_without_lobby()
	for _frame: int in range(WAIT_FRAMES):
		await get_tree().process_frame
	_assert("PROLOGUE では elapsed が進まない", is_zero_approx(RunState.elapsed))

	var lobby := await _spawn_lobby()
	_assert("bank_lobby.tscn の実体が INFILTRATION へ進める",
		lobby != null and GameDirector.current_act == GameTypes.Act.INFILTRATION)
	var infiltration_elapsed := RunState.elapsed
	_assert("INFILTRATION に入ると elapsed が進む", infiltration_elapsed > 0.0)

	GameDirector.notify_robber_engaged()
	var engagement_start := RunState.elapsed
	for _frame: int in range(BREACH_WAIT_FRAMES):
		await get_tree().process_frame
	_assert("enable_breach=false なら待っても ENGAGEMENT から BREACH へ進まない",
		GameDirector.current_act == GameTypes.Act.ENGAGEMENT)
	_assert("ENGAGEMENT 中も elapsed が進む", RunState.elapsed > engagement_start)

	_down_all_robbers(lobby, false)
	var ending_card := lobby.get_node_or_null(^"EndingCard") as EndingCard
	var epilogue_elapsed := RunState.elapsed
	_assert("犯人3体のダウンで ENGAGEMENT から EPILOGUE へ進む",
		RunState.robbers_total == 3 and RunState.robbers_downed == 3
		and GameDirector.current_act == GameTypes.Act.EPILOGUE)
	_assert("客無傷・犯人全員非致死なら Ending.IDEAL",
		RunState.resolve_ending() == GameTypes.Ending.IDEAL
		and RunState.civilians_downed == 0 and RunState.robbers_killed == 0)
	_assert("EPILOGUE でエンディング表示が出て分岐名が一致する",
		ending_card != null and ending_card.is_displayed()
		and ending_card.displayed_title() == "理想")
	_assert("エンディング表示中は SceneTree が paused", get_tree().paused)

	# テスト本体だけは ALWAYS なので、手動で再開して EPILOGUE 中の非加算を測れる。
	get_tree().paused = false
	for _frame: int in range(WAIT_FRAMES):
		await get_tree().process_frame
	_assert("EPILOGUE に入った後は elapsed が進まない",
		is_equal_approx(RunState.elapsed, epilogue_elapsed))
	await _free_lobby(lobby)


func _test_ending_case(expected: int, expected_title: String,
		civilian_down_count: int, civilian_lethal: bool, robber_lethal: bool,
		test_restart: bool = false) -> void:
	await _reset_without_lobby()
	var lobby := await _spawn_lobby()
	if lobby == null:
		_assert("%s ケースで bank_lobby.tscn を読み込める" % expected_title, false)
		return

	for index: int in range(civilian_down_count):
		var civilian := lobby.get_node_or_null(
			NodePath("Civilian%d" % (index + 1))) as Civilian
		_down_civilian(civilian, civilian_lethal and index == 0)
	_down_all_robbers(lobby, robber_lethal)

	var card := lobby.get_node_or_null(^"EndingCard") as EndingCard
	var clean_conditions := false
	match expected:
		GameTypes.Ending.NORMAL:
			clean_conditions = RunState.civilians_downed == 0 \
				and RunState.robbers_killed == 1
		GameTypes.Ending.DRIFT:
			clean_conditions = RunState.civilians_downed == 3 \
				and RunState.civilians_killed == 0 and RunState.robbers_killed == 0
		GameTypes.Ending.FAILURE:
			clean_conditions = RunState.civilians_downed == 1 \
				and RunState.civilians_killed == 1 and RunState.robbers_killed == 0
	_assert("%s: 他分岐の条件を混ぜず判定へ到達する" % expected_title,
		GameDirector.current_act == GameTypes.Act.EPILOGUE
		and RunState.resolve_ending() == expected and clean_conditions)
	_assert("%s: 表示名が判定結果と一致する" % expected_title,
		card != null and card.is_displayed() and card.displayed_title() == expected_title)

	if test_restart and card != null:
		card.restart(false)
		_assert("やり直しで RunState と GameDirector が初期状態に戻る",
			GameDirector.current_act == GameTypes.Act.PROLOGUE
			and RunState.civilians_total == 0 and RunState.civilians_downed == 0
			and RunState.civilians_killed == 0 and RunState.robbers_total == 0
			and RunState.robbers_downed == 0 and RunState.robbers_killed == 0
			and is_zero_approx(RunState.elapsed) and not get_tree().paused)
	await _free_lobby(lobby)


func _spawn_lobby() -> Node3D:
	var lobby := LOBBY_SCENE.instantiate() as Node3D
	if lobby == null:
		return null
	add_child(lobby)
	# 入力や役割AIを止めても Health の信号と幕移行は直接呼び出しで検証できる。
	for actor_name: StringName in ROBBER_NAMES:
		var actor := lobby.get_node_or_null(NodePath(String(actor_name)))
		if actor != null:
			actor.process_mode = Node.PROCESS_MODE_DISABLED
	var player := lobby.get_node_or_null(^"Player")
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	for _frame: int in range(WAIT_FRAMES):
		await get_tree().process_frame
	return lobby


func _down_all_robbers(lobby: Node3D, first_lethal: bool) -> void:
	for index: int in range(ROBBER_NAMES.size()):
		var robber := lobby.get_node_or_null(NodePath(String(ROBBER_NAMES[index]))) as Robber
		if robber == null:
			continue
		var health := robber.get_node_or_null(robber.health_path) as Health
		if health != null:
			health.take_hit(health.max_hp, first_lethal and index == 0)


func _down_civilian(civilian: Civilian, lethal: bool) -> void:
	if civilian == null:
		return
	var health := civilian.get_node_or_null(civilian.health_path) as Health
	if health == null:
		return
	for _hit: int in range(health.stagger_threshold):
		health.take_hit(health.max_hp, lethal)


func _reset_without_lobby() -> void:
	get_tree().paused = false
	RunState.reset()
	GameDirector.reset()
	GameDirector.enable_breach = false
	GameDirector.breach_delay = DISABLED_BREACH_DELAY
	await get_tree().process_frame


func _free_lobby(lobby: Node3D) -> void:
	get_tree().paused = false
	if is_instance_valid(lobby):
		lobby.queue_free()
	await get_tree().process_frame


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
