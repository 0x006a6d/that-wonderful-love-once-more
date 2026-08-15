extends Robber
class_name Leader

## 犯人のリーダー。共通の知覚・近接・被弾処理は Robber に任せ、
## 視認後に客を確保する経路と、人質を保持した低速移動・方向防御を追加する。

## Robber.State の最大値 DOWNED の直後を使い、基底 enum と既存6ステートを変えない。
const SHIELD: int = State.DOWNED + 1

@export_group("Shield")
## 客へ接近し、掴んだとみなす水平距離（m）。
@export var grab_range: float = 1.2
## 保持中に客を置く、自分の正面方向の距離（m）。
@export var shield_offset: float = 0.7
## SHIELD 中にプレイヤーへ向き直る補間速さ。側面へ回り込めるよう共通値より遅くする。
@export var shield_face_speed: float = 1.5
## 正面からの近接を防ぐ角度（度、全角）。
@export var shield_arc_deg: float = 120.0
## 側面・背面から盾を解除するために必要な命中回数。
@export var shield_break_hits: int = 3
## 盾を離してから次の客を掴めるまでの秒数。
@export var regrab_cooldown: float = 6.0

@export_group("Role Appearance")
## 巡回中のリーダーを識別する色。
@export var leader_color: Color = Color(0.48, 0.16, 0.18)
## SHIELD 中の状態表示色。
@export var shield_color: Color = Color(0.68, 0.30, 0.12)
@export_group("")

var _grab_target: Civilian = null
var _shielded_civilian: Civilian = null
var _shield_hit_count: int = 0
var _regrab_left: float = 0.0


func _ready() -> void:
	color_idle = leader_color
	super._ready()
	if _sm != null:
		_sm.add_state(SHIELD, &"shield", _enter_shield, _physics_shield, _exit_shield)


func _physics_process(delta: float) -> void:
	if _regrab_left > 0.0:
		_regrab_left = maxf(_regrab_left - delta, 0.0)
	super._physics_process(delta)
	# StateMachine の更新後に本体が move_and_slide() するため、最後に同期して
	# 移動したフレームも shield_offset を正確に保つ。
	if current_state() == SHIELD:
		_sync_shielded_civilian()


## テスト・デバッグ用。現在保持している客を返す。
func shielded_civilian() -> Civilian:
	return _shielded_civilian


## Hitbox の汎用方向防御フック。盾を持たない状態では常に false。
func blocks_hit_from(attacker_position: Vector3) -> bool:
	if current_state() != SHIELD or not _is_held_civilian_valid():
		return false
	var toward_attacker := attacker_position - global_position
	toward_attacker.y = 0.0
	if toward_attacker.length_squared() <= 0.0:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var half_arc_radians := deg_to_rad(clampf(shield_arc_deg, 0.0, 360.0) * 0.5)
	return forward.dot(toward_attacker.normalized()) >= cos(half_arc_radians)


# --- Robber の役割拡張点 -----------------------------------------------

func _transition_after_alert() -> void:
	_begin_grab_if_available()
	_sm.transition_to(State.CHASE)


func _on_chase_entered() -> void:
	_begin_grab_if_available()


func _physics_chase(delta: float) -> void:
	if _grab_target != null:
		_update_grab_approach(delta)
		return
	# クールダウン終了後もプレイヤーを視認中なら、共通追跡より先に再確保する。
	if _begin_grab_if_available():
		_update_grab_approach(delta)
		return
	super._physics_chase(delta)


# --- SHIELD ---------------------------------------------------------------

func _enter_shield() -> void:
	_set_color(shield_color)
	_shield_hit_count = 0
	_stop_horizontal_immediate()
	if not _is_held_civilian_valid():
		_release_shield()
		_sm.transition_to(State.CHASE)
		return
	_sync_shielded_civilian()


func _physics_shield(delta: float) -> void:
	# 人質を取った側から間合いを詰めず、プレイヤーに踏み込ませる。
	_stop_horizontal_immediate()
	if GameDirector.current_act == GameTypes.Act.PROLOGUE:
		_release_shield()
		_sm.transition_to(State.CHASE)
		return
	if not _is_held_civilian_valid():
		_release_shield()
		_sm.transition_to(State.CHASE)
		return
	if _target == null:
		_resolve_target()
		if _target == null:
			return
	_face_position_at_speed(_target.global_position, delta, shield_face_speed)


func _exit_shield() -> void:
	_stop_horizontal_immediate()


# --- Health 遷移の差分 ---------------------------------------------------

func _on_staggered() -> void:
	if _sm != null and _sm.current() == SHIELD:
		_shield_hit_count += 1
		if _shield_hit_count >= maxi(shield_break_hits, 1):
			_release_shield()
			_sm.transition_to(State.CHASE)
		return
	super._on_staggered()


func _enter_staggered() -> void:
	# 外部から直接 STAGGERED へ遷移させる経路でも保持を残さない。
	_release_shield()
	super._enter_staggered()


func _enter_downed() -> void:
	_release_shield()
	super._enter_downed()


# --- 客の確保・解放 ------------------------------------------------------

func _begin_grab_if_available() -> bool:
	if GameDirector.current_act == GameTypes.Act.PROLOGUE or _regrab_left > 0.0:
		return false
	if _shielded_civilian != null:
		return false
	if _grab_target != null and _is_grabbable_civilian(_grab_target):
		return true
	_grab_target = _nearest_living_civilian()
	return _grab_target != null


func _update_grab_approach(delta: float) -> void:
	if not _is_grabbable_civilian(_grab_target):
		_grab_target = null
		if not _begin_grab_if_available():
			super._physics_chase(delta)
		return
	if _flat_distance_to(_grab_target.global_position) > grab_range:
		_navigate_toward(_grab_target.global_position, chase_speed, delta)
		return
	var civilian := _grab_target
	_grab_target = null
	_shielded_civilian = civilian
	_shielded_civilian.enter_shielded(self)
	if _shielded_civilian.current_state() != Civilian.CivilianState.SHIELDED:
		_shielded_civilian = null
		return
	_sm.transition_to(SHIELD)


func _nearest_living_civilian() -> Civilian:
	var nearest: Civilian = null
	var nearest_distance: float = INF
	for candidate_node: Node in get_tree().get_nodes_in_group(&"civilian"):
		var candidate := candidate_node as Civilian
		if not _is_grabbable_civilian(candidate):
			continue
		var distance := _flat_distance_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest


func _is_grabbable_civilian(candidate: Civilian) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not candidate.is_inside_tree():
		return false
	if candidate.current_state() == Civilian.CivilianState.SHIELDED:
		return false
	var health := candidate.get_node_or_null(candidate.health_path) as Health
	return health != null and not health.is_downed()


func _is_held_civilian_valid() -> bool:
	if _shielded_civilian == null or not is_instance_valid(_shielded_civilian):
		return false
	if not _shielded_civilian.is_inside_tree():
		return false
	var health := _shielded_civilian.get_node_or_null(
		_shielded_civilian.health_path) as Health
	return health != null and not health.is_downed() \
		and _shielded_civilian.current_state() == Civilian.CivilianState.SHIELDED


func _sync_shielded_civilian() -> void:
	if not _is_held_civilian_valid():
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	_shielded_civilian.global_position = global_position + forward * shield_offset
	_shielded_civilian.global_rotation = global_rotation


func _release_shield() -> void:
	var was_holding: bool = _shielded_civilian != null
	_grab_target = null
	if _shielded_civilian != null and is_instance_valid(_shielded_civilian):
		_shielded_civilian.exit_shielded()
	_shielded_civilian = null
	_shield_hit_count = 0
	# 通常の STAGGERED 進入からもこの関数を呼ぶため、客を実際に離した場合だけ
	# クールダウンを開始する。解除後の追撃で残り時間を巻き戻さない。
	if was_holding:
		_regrab_left = maxf(regrab_cooldown, 0.0)


## プレイヤーの銃と GRAPPLE は未実装のため、盾越しの射線を客へ通す処理と
## 格闘モード専用の引き剥がしはここでは扱わない。両方とも8/24以降に追加する。
