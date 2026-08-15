extends Robber
class_name Gunner

## 犯人の銃持ち。共通の知覚・近接・被弾処理は Robber に任せ、
## 視認後の遮蔽地点選択・移動とプレイヤーへの周期射撃だけを追加する。

## Robber.State の最大値 DOWNED の直後を使うことで、基底 enum を変更せず、
## 既存6ステートと衝突しない役割固有IDにする。
const COVER: int = State.DOWNED + 1

@export_group("Cover")
## 遮蔽地点を探すグループ名。
@export var cover_group: StringName = &"cover"
## プレイヤーからこの距離（m）以上離れた候補だけを使う。
@export var min_cover_distance: float = 6.0
## 選択済みの遮蔽地点を再評価する間隔（秒）。
@export var cover_reevaluate_interval: float = 1.0
## 遮蔽地点に到着したとみなす水平距離（m）。
@export var cover_arrive_distance: float = 0.6
## Marker3D は足元を示すため、候補地点の射線始点へ加える銃口の高さ（m）。
@export var cover_muzzle_height: float = 1.0

@export_group("Player Shooting")
## 遮蔽地点へ到着してから発砲を始める間隔（秒）。
@export var shoot_interval: float = 2.2
## 対象へ向き直ってから発砲するまでの予備動作（秒）。
@export var shoot_telegraph_duration: float = 0.5
## プレイヤー本体の原点から狙う高さ（m）。
@export var player_aim_height: float = 1.2

@export_group("Role Appearance")
## 共通型の暗赤・不安定型の紫と区別する、銃持ち固有の青緑。
@export var gunner_color: Color = Color(0.16, 0.48, 0.50)

@export_group("Role Nodes")
@export var hitscan_gun_path: NodePath = ^"MuzzlePoint/HitscanGun"
@export_group("")

var _gun: HitscanGun = null
var _cover_target: Marker3D = null
var _reevaluate_elapsed: float = 0.0
var _shoot_elapsed: float = 0.0
var _telegraph_elapsed: float = 0.0
var _telegraph_active: bool = false
var _arrived_at_cover: bool = false


func _ready() -> void:
	color_idle = gunner_color
	super._ready()
	_gun = get_node_or_null(hitscan_gun_path) as HitscanGun
	if _gun == null:
		push_warning("gunner: HitscanGun が無い")
	if _sm != null:
		_sm.add_state(COVER, &"cover", _enter_cover, _physics_cover, _exit_cover)


## テスト・デバッグ表示用に現在選んでいる地点を返す。
func selected_cover() -> Marker3D:
	return _cover_target


# --- Robber の役割拡張点 -----------------------------------------------

func _transition_after_alert() -> void:
	_transition_to_cover_or_chase()


func _on_chase_entered() -> void:
	# 近接やよろけから CHASE へ戻る場合も、視認中なら追跡前に遮蔽を探す。
	if _sees_target():
		_transition_to_cover_if_available()


# --- COVER ---------------------------------------------------------------

func _enter_cover() -> void:
	_set_color(color_alert)
	_reevaluate_elapsed = 0.0
	_reset_shooting()
	if _cover_target == null or not _is_cover_candidate_valid(_cover_target):
		_cover_target = _nearest_valid_cover()
	if _cover_target == null:
		_sm.transition_to(State.CHASE)


func _physics_cover(delta: float) -> void:
	if _target == null:
		_resolve_target()
		if _target == null:
			_sm.transition_to(State.PATROL)
			return

	var target_position := _target.global_position
	var target_distance := _flat_distance_to(target_position)
	if target_distance <= attack_range:
		_reset_shooting()
		_stop_horizontal(delta)
		_face_position(target_position, delta)
		if _cooldown_left <= 0.0:
			_sm.transition_to(State.ATTACK)
		return

	_reevaluate_elapsed += delta
	if _reevaluate_elapsed >= cover_reevaluate_interval:
		_reevaluate_elapsed = 0.0
		var reevaluated := _nearest_valid_cover()
		if reevaluated == null:
			_cover_target = null
			_sm.transition_to(State.CHASE)
			return
		if reevaluated != _cover_target:
			_cover_target = reevaluated
			_reset_shooting()

	if _cover_target == null:
		_sm.transition_to(State.CHASE)
		return

	var distance_to_cover := _flat_distance_to(_cover_target.global_position)
	if distance_to_cover > cover_arrive_distance:
		_reset_shooting()
		_navigate_toward(_cover_target.global_position, chase_speed, delta)
		return

	if not _arrived_at_cover:
		_arrived_at_cover = true
		_shoot_elapsed = 0.0
	_stop_horizontal(delta)
	_face_position(target_position, delta)
	_update_player_shooting(delta)


func _exit_cover() -> void:
	_reset_shooting()


func _transition_to_cover_or_chase() -> void:
	if not _transition_to_cover_if_available():
		_sm.transition_to(State.CHASE)


func _transition_to_cover_if_available() -> bool:
	_cover_target = _nearest_valid_cover()
	if _cover_target == null:
		return false
	_sm.transition_to(COVER)
	return true


func _nearest_valid_cover() -> Marker3D:
	if _target == null or _gun == null:
		return null
	var nearest: Marker3D = null
	var nearest_distance: float = INF
	for candidate_node: Node in get_tree().get_nodes_in_group(cover_group):
		var candidate := candidate_node as Marker3D
		if not _is_cover_candidate_valid(candidate):
			continue
		var distance := _flat_distance_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest


func _is_cover_candidate_valid(candidate: Marker3D) -> bool:
	if candidate == null or _target == null or _gun == null:
		return false
	if not is_instance_valid(candidate) or not candidate.is_inside_tree():
		return false
	if not candidate.is_in_group(cover_group):
		return false
	if _flat_distance_between(candidate.global_position, _target.global_position) \
			< min_cover_distance:
		return false
	var from := candidate.global_position + Vector3.UP * cover_muzzle_height
	return _gun.has_clear_shot_from(from, _target, _player_aim_position())


func _update_player_shooting(delta: float) -> void:
	if GameDirector.current_act == GameTypes.Act.PROLOGUE or _gun == null:
		_shoot_elapsed = 0.0
		_telegraph_elapsed = 0.0
		_telegraph_active = false
		return

	_shoot_elapsed = minf(_shoot_elapsed + delta, shoot_interval)
	if not _telegraph_active:
		# 予備動作は周期の末尾に含め、発砲間隔自体を shoot_interval に保つ。
		var telegraph_start := maxf(shoot_interval - shoot_telegraph_duration, 0.0)
		if _shoot_elapsed >= telegraph_start:
			_telegraph_active = true
			_telegraph_elapsed = 0.0

	if _telegraph_active:
		_telegraph_elapsed += delta
		_face_position(_target.global_position, delta)
		if _shoot_elapsed < shoot_interval:
			return
		# 発砲時の最初の Hurtbox は HitscanGun に任せる。予備動作中に射線へ
		# 入った客へ当たり得るため、流れ弾も同じ一発として処理される。
		_gun.fire_at(_player_aim_position())
		_shoot_elapsed = 0.0
		_telegraph_elapsed = 0.0
		_telegraph_active = false
		return


func _player_aim_position() -> Vector3:
	return _target.global_position + Vector3.UP * player_aim_height


func _reset_shooting() -> void:
	_shoot_elapsed = 0.0
	_telegraph_elapsed = 0.0
	_telegraph_active = false
	_arrived_at_cover = false


func _flat_distance_between(a: Vector3, b: Vector3) -> float:
	var offset := a - b
	return Vector2(offset.x, offset.z).length()
