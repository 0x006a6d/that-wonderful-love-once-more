extends SceneTree

## RunState の判定ロジックをヘッドレスで検証する。
## resolve_ending() が 4 分岐すべて返すこと、および
## deviation_level() / police_threat_level() の境界を確認する。
##
## 実行: godot --headless --path . --script res://tools/test_run_state.gd
##
## 注意: --script モードでは autoload グローバル（RunState / GameTypes）が
## 登録されないため、対象スクリプトを直接ロードして検証する。
## run_state.gd は GameTypes を参照するので、先に GameTypes を
## Engine.register_singleton() でグローバル名として登録してから
## RunState をインスタンス化する。

const GameTypesScript := preload("res://autoload/game_types.gd")
const RunStateScript := preload("res://autoload/run_state.gd")

var RunState: Node = null

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	print("=== RunState 検証開始 ===")

	# run_state.gd 内の "GameTypes.Faction.*" 等を解決させるため、
	# GameTypes をグローバル singleton 名として登録する。
	if not Engine.has_singleton("GameTypes"):
		Engine.register_singleton("GameTypes", GameTypesScript.new())
	RunState = RunStateScript.new()

	_test_ending_ideal()
	_test_ending_normal()
	_test_ending_drift()
	_test_ending_failure()
	_test_ending_priority_failure_over_drift()
	_test_deviation_level()
	_test_police_threat_level()
	_test_reset()

	print("=== 結果: PASS=%d FAIL=%d ===" % [_pass, _fail])
	if _fail == 0:
		print("ALL PASS")
	else:
		print("HAS FAILURE")
	if RunState != null:
		RunState.free()
		RunState = null
	if Engine.has_singleton("GameTypes"):
		var gt := Engine.get_singleton("GameTypes")
		Engine.unregister_singleton("GameTypes")
		if is_instance_valid(gt):
			gt.free()
	quit(0 if _fail == 0 else 1)


func _assert(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("[PASS] %s" % label)
	else:
		_fail += 1
		print("[FAIL] %s" % label)


func _ending_name(e: int) -> String:
	match e:
		GameTypesScript.Ending.IDEAL: return "IDEAL"
		GameTypesScript.Ending.NORMAL: return "NORMAL"
		GameTypesScript.Ending.DRIFT: return "DRIFT"
		GameTypesScript.Ending.FAILURE: return "FAILURE"
	return "UNKNOWN"


# --- resolve_ending の 4 分岐 ---

func _test_ending_ideal() -> void:
	RunState.reset()
	RunState.civilians_total = 5
	# 犯人を殺さず、客のダウンも 0 → 理想
	var e: int = RunState.resolve_ending()
	_assert("IDEAL: killed=0 downed=0 robbers_killed=0 -> %s" % _ending_name(e),
		e == GameTypesScript.Ending.IDEAL)


func _test_ending_normal() -> void:
	RunState.reset()
	RunState.civilians_total = 5
	RunState.robbers_killed = 1
	# 客は無事だが犯人を殺した → 通常
	var e: int = RunState.resolve_ending()
	_assert("NORMAL: robbers_killed=1 civ_downed=0 -> %s" % _ending_name(e),
		e == GameTypesScript.Ending.NORMAL)


func _test_ending_drift() -> void:
	RunState.reset()
	RunState.civilians_total = 5
	RunState.civilians_downed = 3
	# 客を 3 人ダウンさせたが死者なし → 逸脱
	var e: int = RunState.resolve_ending()
	_assert("DRIFT: civ_downed=3 killed=0 -> %s" % _ending_name(e),
		e == GameTypesScript.Ending.DRIFT)


func _test_ending_failure() -> void:
	RunState.reset()
	RunState.civilians_total = 5
	RunState.civilians_downed = 1
	RunState.civilians_killed = 1
	# 客を 1 人でも殺した → 失敗
	var e: int = RunState.resolve_ending()
	_assert("FAILURE: civ_killed=1 -> %s" % _ending_name(e),
		e == GameTypesScript.Ending.FAILURE)


func _test_ending_priority_failure_over_drift() -> void:
	# 上から順に評価。killed>0 は downed>=3 より優先されること。
	RunState.reset()
	RunState.civilians_total = 5
	RunState.civilians_downed = 4
	RunState.civilians_killed = 1
	var e: int = RunState.resolve_ending()
	_assert("優先順位: killed>0 は DRIFT より FAILURE 優先 -> %s" % _ending_name(e),
		e == GameTypesScript.Ending.FAILURE)


# --- deviation_level 境界 ---

func _test_deviation_level() -> void:
	RunState.reset()
	# total=0 のとき 0.0
	_assert("deviation: total=0 -> 0.0", is_equal_approx(RunState.deviation_level(), 0.0))

	RunState.reset()
	RunState.civilians_total = 10
	RunState.civilians_downed = 2
	# (2 + 0) / 10 = 0.2
	_assert("deviation: downed=2/10 -> 0.2", is_equal_approx(RunState.deviation_level(), 0.2))

	RunState.reset()
	RunState.civilians_total = 10
	RunState.civilians_downed = 2
	RunState.civilians_killed = 1
	# (2 + 1*2) / 10 = 0.4
	_assert("deviation: downed=2 killed=1 /10 -> 0.4", is_equal_approx(RunState.deviation_level(), 0.4))

	RunState.reset()
	RunState.civilians_total = 3
	RunState.civilians_downed = 3
	RunState.civilians_killed = 3
	# (3 + 6) / 3 = 3.0 -> clamp 1.0
	_assert("deviation: 上限 clamp -> 1.0", is_equal_approx(RunState.deviation_level(), 1.0))


# --- police_threat_level 境界 ---

func _test_police_threat_level() -> void:
	RunState.reset()
	_assert("threat: 初期 -> 0", RunState.police_threat_level() == 0)

	RunState.reset()
	RunState.civilians_downed = 1
	_assert("threat: downed=1 killed=0 -> 1", RunState.police_threat_level() == 1)

	RunState.reset()
	RunState.civilians_downed = 2
	RunState.civilians_killed = 1
	_assert("threat: killed=1 -> 2", RunState.police_threat_level() == 2)


# --- reset ---

func _test_reset() -> void:
	RunState.civilians_total = 9
	RunState.civilians_downed = 9
	RunState.civilians_killed = 9
	RunState.robbers_killed = 9
	RunState.player_fired_gun = true
	RunState.elapsed = 123.0
	RunState.reset()
	var ok: bool = RunState.civilians_total == 0 \
		and RunState.civilians_downed == 0 \
		and RunState.civilians_killed == 0 \
		and RunState.civilians_rescued == 0 \
		and RunState.robbers_downed == 0 \
		and RunState.robbers_killed == 0 \
		and RunState.player_fired_gun == false \
		and is_equal_approx(RunState.elapsed, 0.0) \
		and RunState.downed.is_empty()
	_assert("reset: 全フィールド初期化", ok)
