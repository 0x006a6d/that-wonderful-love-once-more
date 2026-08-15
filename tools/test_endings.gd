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
	await _test_normal_finish_case()
	await _test_erratic_civilian_attribution()
	await _test_player_civilian_attribution()
	await _test_ending_case(GameTypes.Ending.DRIFT, "逸脱", 3, false)
	await _test_ending_case(GameTypes.Ending.FAILURE, "失敗", 1, true, true)
	_test_resolve_ending_regression()

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
	_assert("客無傷・犯人を倒しただけなら robbers_killed=0 で Ending.IDEAL",
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


func _test_normal_finish_case() -> void:
	await _reset_without_lobby()
	var lobby := await _spawn_lobby()
	if lobby == null:
		_assert("通常 ケースで bank_lobby.tscn を読み込める", false)
		return
	var robber := lobby.get_node_or_null(^"RobberLeader") as Robber
	var player := lobby.get_node_or_null(^"Player") as Node3D
	var finish_path_ok := await _finish_robber_with_player(player, robber)
	_down_all_robbers(lobby, false)

	var card := lobby.get_node_or_null(^"EndingCard") as EndingCard
	var clean_conditions: bool = RunState.civilians_downed == 0 \
		and RunState.robbers_killed == 1
	_assert("通常: 実際の再ロック＋2回の追い打ち経路で判定へ到達する",
		finish_path_ok and GameDirector.current_act == GameTypes.Act.EPILOGUE
		and RunState.resolve_ending() == GameTypes.Ending.NORMAL and clean_conditions)
	_assert("通常: プレイヤーの追い打ちは robbers_killed_by_player に記録される",
		RunState.robbers_killed_by_player == 1)
	_assert("通常: 表示名が判定結果と一致する",
		card != null and card.is_displayed() and card.displayed_title() == "通常")
	await _free_lobby(lobby)


func _test_erratic_civilian_attribution() -> void:
	await _reset_without_lobby()
	var lobby := await _spawn_lobby()
	if lobby == null:
		_assert("不安定型の加害者記録ケースでロビーを読み込める", false)
		return
	var erratic := lobby.get_node_or_null(^"RobberErratic") as Erratic
	var civilian := lobby.get_node_or_null(^"Civilian1") as Civilian
	var gun := erratic.get_node_or_null(erratic.hitscan_gun_path) as HitscanGun
	var hurtbox := civilian.get_node_or_null(civilian.hurtbox_path) as Hurtbox
	var health := civilian.get_node_or_null(civilian.health_path) as Health
	if erratic != null and civilian != null and gun != null and hurtbox != null and health != null:
		hurtbox.receive_shot(erratic, gun.damage, gun.lethal, gun.ignore_stagger_threshold)
	print("[erratic attribution] killed=%d / killed_by_player=%d / attacker=%s" %
		[RunState.civilians_killed, RunState.civilians_killed_by_player,
		str(RunState.downed[0].attacker if not RunState.downed.is_empty() else null)])
	_assert("不安定型が客を殺すと総死亡数だけ増え、プレイヤー死亡数は増えない",
		health != null and health.is_downed() and RunState.civilians_killed == 1
		and RunState.civilians_killed_by_player == 0
		and not RunState.downed.is_empty() and RunState.downed[0].attacker == erratic)
	await _free_lobby(lobby)


func _test_player_civilian_attribution() -> void:
	await _reset_without_lobby()
	var lobby := await _spawn_lobby()
	if lobby == null:
		_assert("プレイヤーの客ダウン記録ケースでロビーを読み込める", false)
		return
	var player := lobby.get_node_or_null(^"Player") as Node3D
	var civilian := lobby.get_node_or_null(^"Civilian1") as Civilian
	var hitbox := player.get_node_or_null(^"Model/MeleeHitbox") as Hitbox
	var hurtbox := civilian.get_node_or_null(civilian.hurtbox_path) as Hurtbox
	var health := civilian.get_node_or_null(civilian.health_path) as Health
	if player != null and civilian != null and hitbox != null and hurtbox != null and health != null:
		hitbox.exempt_body = civilian
		for _hit: int in range(health.stagger_threshold):
			hitbox.configure(health.max_hp, 0.0, false)
			hitbox.call("_try_hit", hurtbox)
	print("[player civilian attribution] threshold=%d downed=%d / by_player=%d" %
		[health.stagger_threshold if health != null else -1,
		RunState.civilians_downed, RunState.civilians_downed_by_player])
	_assert("プレイヤーが客を2回でダウンさせると civilians_downed_by_player が増える",
		health != null and health.stagger_threshold == 2 and health.is_downed()
		and RunState.civilians_downed == 1 and RunState.civilians_downed_by_player == 1
		and RunState.civilians_killed_by_player == 0)
	await _free_lobby(lobby)


func _test_resolve_ending_regression() -> void:
	RunState.reset()
	var ideal := RunState.resolve_ending()
	RunState.robbers_killed = 1
	var normal := RunState.resolve_ending()
	RunState.reset()
	RunState.civilians_downed = 3
	var drift := RunState.resolve_ending()
	RunState.civilians_killed = 1
	var failure := RunState.resolve_ending()
	print("[resolve regression] ideal=%d normal=%d drift=%d failure=%d" %
		[ideal, normal, drift, failure])
	_assert("resolve_ending の4分岐は加害者集計の追加後も従来どおり",
		ideal == GameTypes.Ending.IDEAL and normal == GameTypes.Ending.NORMAL
		and drift == GameTypes.Ending.DRIFT and failure == GameTypes.Ending.FAILURE)


func _test_ending_case(expected: int, expected_title: String,
		civilian_down_count: int, civilian_lethal: bool,
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
	_down_all_robbers(lobby, false)

	var card := lobby.get_node_or_null(^"EndingCard") as EndingCard
	var clean_conditions := false
	match expected:
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


## ロビー内の実 Player → LockOn → Hitbox → Hurtbox → Health.finished 経路で
## 非致死ダウン済みの犯人を追い打ちし、RunState の記録を後から更新する。
func _finish_robber_with_player(player: Node3D, robber: Robber) -> bool:
	if player == null or robber == null:
		return false
	var health := robber.get_node_or_null(robber.health_path) as Health
	var hurtbox := robber.get_node_or_null(robber.hurtbox_path) as Hurtbox
	var detector := player.get_node_or_null(^"LockOnDetector") as LockOn
	var hitbox := player.get_node_or_null(^"Model/MeleeHitbox") as Hitbox
	var model := player.get_node_or_null(^"Model") as Node3D
	if health == null or hurtbox == null or detector == null or hitbox == null or model == null:
		return false

	# AIの物理更新だけ止め、ロックオン検出に必要な PhysicsBody は有効へ戻す。
	robber.process_mode = Node.PROCESS_MODE_INHERIT
	robber.set_physics_process(false)
	robber.fall_duration = 0.0
	# x=0,z=4 の柱をカメラレイが横切らない、ロビー中央の開けた位置を使う。
	robber.global_position = Vector3(2.0, 0.05, 0.0)
	player.global_position = Vector3(2.0, 0.05, 1.0)
	model.rotation.y = PI
	health.take_hit(health.max_hp)
	for _frame: int in range(WAIT_FRAMES):
		await get_tree().physics_frame
	var camera := player.get_node_or_null(^"SpringArm3D/Camera3D") as Camera3D
	var distance := player.global_position.distance_to(robber.global_position)
	var overlapping: Array[Node3D] = detector.get_overlapping_bodies()
	var occluded: bool = bool(detector.call("_is_occluded", robber))
	print("[normal finish acquire] distance=%.3f range=%.3f overlapping=%d contains=%s downed=%s finishable=%s occluded=%s camera=%s" %
		[distance, detector.finish_lock_range, overlapping.size(), str(overlapping.has(robber)),
		str(health.is_downed()), str(robber.can_receive_finish_hit()), str(occluded),
		str(camera.global_position if camera != null else Vector3.ZERO)])
	detector.call("_acquire_best_target")
	var acquired: bool = detector.current_target() == robber and hitbox.exempt_body == robber
	var killed_before: int = RunState.robbers_killed
	for _hit: int in range(health.finish_hits):
		hitbox.configure(1.0, 0.0, false)
		hitbox.call("_try_hit", hurtbox)
	var killed_after: int = RunState.robbers_killed
	print("[normal finish path] acquired=%s finish_hits=%d killed=%d -> %d" %
		[str(acquired), health.finish_hits, killed_before, killed_after])
	return acquired and health.finish_hits == 2 and killed_before == 0 and killed_after == 1


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
		# 移動だけ止め、LockOnDetector と Hitbox の実経路は動かして通常分岐を検証する。
		player.set_physics_process(false)
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
