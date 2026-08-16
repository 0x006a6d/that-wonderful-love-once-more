extends Area3D
class_name LockOn

## 犯人・客の生存対象と、至近距離の追い打ち可能対象から、カメラ前方に
## 最も近い相手を選ぶロックオン検出器。
## カメラと所有者は player.gd から注入し、親階層への直接参照を持たない。

const WORLD_MASK: int = 1 << 0
const ROBBER_MASK: int = 1 << 2
const CIVILIAN_MASK: int = 1 << 3
const ROBBER_GROUP: StringName = &"robber"
const CIVILIAN_GROUP: StringName = &"civilian"

enum TargetPriority {
	LIVE_THREAT,
	LIVE_CIVILIAN,
	DOWNED_ROBBER,
	COUNT,
}

## HUD へ公開する対象種別。判定は具体的なNPC型ではなくグループと Health だけで行う。
enum TargetKind {
	NONE,
	LIVE_ROBBER,
	LIVE_CIVILIAN,
	DOWNED_ROBBER,
}

## ロックオン候補を検出する距離（m）。
@export var lock_on_range: float = 12.0
## ダウン済みの追い打ち可能対象を候補に含める距離（m）。
@export var finish_lock_range: float = 2.0
## カメラ前方から候補までに許容する最大角度（度）。
@export var lock_on_fov_deg: float = 100.0
## 対象の角度・遮蔽判定で狙う、本体原点からの高さ（m）。
@export var target_aim_height: float = 0.8
## ロック中の対象を距離で解除する閾値（m）。検出距離より広いヒステリシス。
@export var lock_on_release_range: float = 16.0
## 遮蔽がこの秒数だけ連続した場合にロックを解除する。
@export var lose_target_grace: float = 0.6

signal target_acquired(target: Node3D)
signal target_released()

var _camera: Camera3D = null
var _owner_body: Node3D = null
var _target: Node3D = null
var _target_health: Health = null
var _occluded_time: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = ROBBER_MASK | CIVILIAN_MASK
	monitoring = true
	monitorable = false
	_apply_detector_range()


## player.gd から注入される、候補選択に使う実カメラ。
func set_camera(camera: Camera3D) -> void:
	_camera = camera


## player.gd から注入される、距離判定とレイ除外に使うプレイヤー本体。
func set_owner_body(owner_body: Node3D) -> void:
	_owner_body = owner_body


func current_target() -> Node3D:
	return _target


## HUD が見た目を選ぶための公開問い合わせ。対象の具体型には依存しない。
func current_target_kind() -> int:
	if _target == null or not is_instance_valid(_target):
		return TargetKind.NONE
	if _target_health != null and _target_health.is_downed() \
			and _target.is_in_group(ROBBER_GROUP):
		return TargetKind.DOWNED_ROBBER
	if _target.is_in_group(CIVILIAN_GROUP):
		return TargetKind.LIVE_CIVILIAN
	# 所属不明の生存脅威は候補順位と同様、生存犯人と同じ表示にまとめる。
	return TargetKind.LIVE_ROBBER


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"lock_on"):
		return
	if _target != null:
		_release_target()
	else:
		_acquire_best_target()
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	# ロック中は候補を再評価しない。上位候補が現れても入力なしの乗り換えは行わない。
	if not is_instance_valid(_target) or not _target.is_inside_tree():
		# ツリーから消えた対象は追跡もシグナル購読も継続できないため解除する。
		_release_target()
		return
	var origin := _owner_body.global_position if _owner_body != null else global_position
	if origin.distance_to(_target.global_position) > lock_on_release_range:
		# 検出距離より広い解除距離を使い、境界付近での頻繁な切断を防ぐ。
		_release_target()
		return
	if _is_occluded(_target):
		_occluded_time += delta
		if _occluded_time >= lose_target_grace:
			# 短い遮蔽は許容し、柱の裏を一瞬横切っただけでは切らない。
			_release_target()
	else:
		_occluded_time = 0.0


func _acquire_best_target() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var camera_forward := -_camera.global_transform.basis.z
	camera_forward = camera_forward.normalized()
	var best: Node3D = null
	var best_priority: int = TargetPriority.COUNT
	var best_angle: float = INF
	var best_distance: float = INF
	for body: Node3D in get_overlapping_bodies():
		var health := _find_health(body)
		if health == null:
			continue
		var distance := _candidate_origin().distance_to(body.global_position)
		if health.is_downed():
			# 追い打ちは robber グループかつ公開問い合わせで許可された対象だけに限定する。
			if not body.is_in_group(ROBBER_GROUP) or distance > finish_lock_range \
					or not body.has_method("can_receive_finish_hit"):
				continue
			if not bool(body.call("can_receive_finish_hit")):
				continue
		elif distance > lock_on_range:
			continue
		var to_target := _aim_position(body) - _camera.global_position
		if to_target.is_zero_approx():
			continue
		var angle := camera_forward.angle_to(to_target.normalized())
		if rad_to_deg(angle) > lock_on_fov_deg:
			continue
		if _is_occluded(body):
			continue
		var priority := _target_priority(body, health)
		if priority < best_priority \
				or (priority == best_priority and (angle < best_angle \
				or (is_equal_approx(angle, best_angle) and distance < best_distance))):
			best = body
			best_priority = priority
			best_angle = angle
			best_distance = distance
	if best != null:
		_set_target(best)


func _set_target(target: Node3D) -> void:
	_target = target
	_target_health = _find_health(target)
	_occluded_time = 0.0
	if _target_health != null:
		_target_health.downed.connect(_on_target_downed)
	_target.tree_exiting.connect(_on_target_tree_exiting)
	target_acquired.emit(_target)


func _release_target() -> void:
	if _target == null:
		return
	if is_instance_valid(_target_health) \
			and _target_health.downed.is_connected(_on_target_downed):
		_target_health.downed.disconnect(_on_target_downed)
	if is_instance_valid(_target) and _target.tree_exiting.is_connected(_on_target_tree_exiting):
		_target.tree_exiting.disconnect(_on_target_tree_exiting)
	_target = null
	_target_health = null
	_occluded_time = 0.0
	target_released.emit()


func _on_target_downed(_lethal: bool) -> void:
	# ダウン済みの相手へ攻撃意図を残さず、次の対象を明示的に選び直させる。
	_release_target()


func _on_target_tree_exiting() -> void:
	# 対象がシーンから除去される前に参照を片付ける。
	_release_target()


func _is_occluded(target: Node3D) -> bool:
	if _camera == null or not is_instance_valid(_camera) or not is_inside_tree():
		return true
	var excluded: Array[RID] = [get_rid()]
	if _owner_body is CollisionObject3D:
		excluded.append((_owner_body as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		excluded.append((target as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		_camera.global_position, _aim_position(target), WORLD_MASK, excluded)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _aim_position(target: Node3D) -> Vector3:
	return target.global_position + Vector3.UP * target_aim_height


func _candidate_origin() -> Vector3:
	return _owner_body.global_position if _owner_body != null else global_position


func _find_health(body: Node) -> Health:
	for child: Node in body.get_children():
		if child is Health:
			return child as Health
	return null


func _target_priority(body: Node3D, health: Health) -> int:
	if health.is_downed():
		return TargetPriority.DOWNED_ROBBER
	if body.is_in_group(ROBBER_GROUP):
		return TargetPriority.LIVE_THREAT
	if body.is_in_group(CIVILIAN_GROUP):
		return TargetPriority.LIVE_CIVILIAN
	# 将来追加される警察など所属不明の生存対象も、脅威として犯人と同じ最優先に扱う。
	return TargetPriority.LIVE_THREAT


func _apply_detector_range() -> void:
	for child: Node in get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape == null:
			continue
		var source_sphere := collision_shape.shape as SphereShape3D
		if source_sphere == null:
			continue
		# サブリソースを直接変更して別インスタンスへ半径を波及させない。
		var sphere := source_sphere.duplicate() as SphereShape3D
		sphere.radius = lock_on_range
		collision_shape.shape = sphere
		return
