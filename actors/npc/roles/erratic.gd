extends Robber
class_name Erratic

## 犯人の不安定型。知覚・追跡・近接・ダウンは Robber に任せ、
## 客への周期射撃とランダム巡回だけを差し替える。

@export_group("Civilian Shooting")
## 生存していて射線が通る最寄りの客を狙い始める間隔（秒）。
@export var shoot_civilian_interval: float = 8.0
## 客を狙ってから発砲するまでの予備動作（秒）。
@export var shoot_telegraph_duration: float = 0.6
## 客本体の原点から狙う高さ（m）。伏せ姿の Hurtbox 中心に合わせる。
@export var civilian_aim_height: float = 0.35

@export_group("Erratic Patrol")
## patrol_wait の前後に加えるランダムな幅（秒）。
@export var patrol_wait_variation: float = 0.75

@export_group("Role Appearance")
## 共通のステート色とは別に、巡回中の不安定型を識別する色。
@export var erratic_color: Color = Color(0.52, 0.24, 0.68)

@export_group("Role Nodes")
@export var hitscan_gun_path: NodePath = ^"MuzzlePoint/HitscanGun"
@export_group("")

var _gun: HitscanGun = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _shoot_elapsed: float = 0.0
var _aim_elapsed: float = 0.0
var _civilian_target: Node3D = null


func _ready() -> void:
	# 固定シードを使わず、生成のたびに巡回順と待ち時間を変える。
	_rng.randomize()
	color_idle = erratic_color
	super._ready()
	_gun = get_node_or_null(hitscan_gun_path) as HitscanGun
	if _gun == null:
		push_warning("erratic: HitscanGun が無い")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_civilian_shooting(delta)


# --- 客への周期射撃 -------------------------------------------------------

func _update_civilian_shooting(delta: float) -> void:
	if GameDirector.current_act == GameTypes.Act.PROLOGUE:
		_shoot_elapsed = 0.0
		_cancel_aim()
		return

	var state := current_state()
	if state == State.DOWNED:
		_cancel_aim()
		return
	if state == State.STAGGERED:
		# よろけ中は撃たず、予備動作をやり直す。射撃間隔は消費しない。
		_cancel_aim()
		return
	if _gun == null:
		return

	if _civilian_target != null:
		_update_aim(delta)
		return

	_shoot_elapsed = minf(_shoot_elapsed + delta, shoot_civilian_interval)
	if _shoot_elapsed < shoot_civilian_interval:
		return

	# 見える客がいなければタイマーを満了のまま保ち、無駄撃ちで間隔を消費しない。
	_civilian_target = _nearest_visible_civilian()
	_aim_elapsed = 0.0


func _update_aim(delta: float) -> void:
	if not _is_living_civilian(_civilian_target):
		_cancel_aim()
		return

	var target_position := _civilian_target_position(_civilian_target)
	if not _gun.has_clear_shot(_civilian_target, target_position):
		# 予備動作中に遮蔽へ入った場合も発砲せず、間隔を消費しない。
		_cancel_aim()
		return

	_stop_horizontal_immediate()
	_face_position(target_position, delta)
	_aim_elapsed += delta
	if _aim_elapsed < shoot_telegraph_duration:
		return

	# 発砲直前にも射線を確認する。壁が入ったフレームでは撃たない。
	if not _gun.has_clear_shot(_civilian_target, target_position):
		_cancel_aim()
		return
	_gun.fire_at(target_position)
	_shoot_elapsed = 0.0
	_cancel_aim()


func _nearest_visible_civilian() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance: float = INF
	for candidate_node: Node in get_tree().get_nodes_in_group(&"civilian"):
		var candidate := candidate_node as Node3D
		if not _is_living_civilian(candidate):
			continue
		var aim_position := _civilian_target_position(candidate)
		if not _gun.has_clear_shot(candidate, aim_position):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest


func _is_living_civilian(candidate: Node3D) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not candidate.is_inside_tree():
		return false
	if not candidate.is_in_group(&"civilian"):
		return false
	var health := _find_child_health(candidate)
	return health != null and not health.is_downed()


func _find_child_health(body: Node) -> Health:
	for child: Node in body.get_children():
		if child is Health:
			return child as Health
	return null


func _civilian_target_position(civilian: Node3D) -> Vector3:
	return civilian.global_position + Vector3.UP * civilian_aim_height


func _cancel_aim() -> void:
	_civilian_target = null
	_aim_elapsed = 0.0


# --- PATROL の差分 --------------------------------------------------------

func _on_patrol_entered() -> void:
	if not patrol_points.is_empty():
		_patrol_index = _rng.randi_range(0, patrol_points.size() - 1)


func _next_patrol_index(current_index: int) -> int:
	var count := patrol_points.size()
	if count <= 1:
		return 0
	if current_index < 0 or current_index >= count:
		return _rng.randi_range(0, count - 1)
	# 現在地以外の範囲から一様に選ぶ。順番巡回にも同じ地点の連続選択にもならない。
	var next_index := _rng.randi_range(0, count - 2)
	if next_index >= current_index:
		next_index += 1
	return next_index


func _next_patrol_wait() -> float:
	var variation := maxf(patrol_wait_variation, 0.0)
	return maxf(patrol_wait + _rng.randf_range(-variation, variation), 0.0)
