extends Area3D
class_name LockOn

## 犯人・客から、カメラ前方に最も近い生存対象を選ぶロックオン検出器。
## カメラと所有者は player.gd から注入し、親階層への直接参照を持たない。

const WORLD_MASK: int = 1 << 0
const ROBBER_MASK: int = 1 << 2
const CIVILIAN_MASK: int = 1 << 3

## ロックオン候補を検出する距離（m）。
@export var lock_on_range: float = 12.0
## カメラ前方から候補までに許容する最大角度（度）。
@export var lock_on_fov_deg: float = 100.0
## 対象の角度・遮蔽判定で狙う、本体原点からの高さ（m）。
@export var target_aim_height: float = 0.8
## ロック中の対象を距離で解除する閾値（m）。検出距離より広いヒステリシス。
@export var lock_on_release_range: float = 16.0
## 遮蔽がこの秒数だけ連続した場合にロックを解除する。
@export var lose_target_grace: float = 0.6

@export_group("Placeholder Marker")
## 8/24 の HUD ロックオンマーカー実装で置き換える暫定 3D 表示。
@export var show_placeholder_marker: bool = true
@export var marker_color: Color = Color(1.0, 0.78, 0.16, 1.0)
## 暫定マーカー球の半径（m）。
@export var marker_size: float = 0.12
## 対象本体の原点からマーカーまでの高さ（m）。
@export var marker_height: float = 2.1
@export_group("")

signal target_acquired(target: Node3D)
signal target_released()

var _camera: Camera3D = null
var _owner_body: Node3D = null
var _target: Node3D = null
var _target_health: Health = null
var _occluded_time: float = 0.0
var _marker: MeshInstance3D = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = ROBBER_MASK | CIVILIAN_MASK
	monitoring = true
	monitorable = false
	_apply_detector_range()
	_create_placeholder_marker()


## player.gd から注入される、候補選択に使う実カメラ。
func set_camera(camera: Camera3D) -> void:
	_camera = camera


## player.gd から注入される、距離判定とレイ除外に使うプレイヤー本体。
func set_owner_body(owner_body: Node3D) -> void:
	_owner_body = owner_body


func current_target() -> Node3D:
	return _target


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"lock_on"):
		return
	if _target != null:
		_release_target()
	else:
		_acquire_best_target()
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_update_marker()
	if _target == null:
		return
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
	var best_angle: float = INF
	var best_distance: float = INF
	for body: Node3D in get_overlapping_bodies():
		var health := _find_health(body)
		if health == null or health.is_downed():
			continue
		var to_target := _aim_position(body) - _camera.global_position
		if to_target.is_zero_approx():
			continue
		var angle := camera_forward.angle_to(to_target.normalized())
		if rad_to_deg(angle) > lock_on_fov_deg:
			continue
		if _is_occluded(body):
			continue
		var distance := _candidate_origin().distance_to(body.global_position)
		if distance > lock_on_range:
			continue
		if angle < best_angle or (is_equal_approx(angle, best_angle) and distance < best_distance):
			best = body
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
	_update_marker()
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
	if _marker != null:
		_marker.visible = false
	target_released.emit()


func _on_target_downed(_lethal: bool) -> void:
	# ダウン済みの相手へ攻撃意図を残さず、次の対象を明示的に選び直させる。
	_release_target()


func _on_target_tree_exiting() -> void:
	# 対象がシーンから除去される前に参照と暫定表示を片付ける。
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


func _create_placeholder_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.name = "PlaceholderMarker"
	var sphere := SphereMesh.new()
	sphere.radius = marker_size
	sphere.height = marker_size * 2.0
	_marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = marker_color
	_marker.material_override = material
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)
	_marker.top_level = true
	_marker.visible = false


func _update_marker() -> void:
	if _marker == null:
		return
	var can_show: bool = (show_placeholder_marker and _target != null
		and is_instance_valid(_target) and _target.is_inside_tree())
	_marker.visible = can_show
	if can_show:
		_marker.global_position = _target.global_position + Vector3.UP * marker_height
