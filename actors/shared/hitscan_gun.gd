extends Node3D
class_name HitscanGun

## world と hurtbox の最初の交点だけを採用するヒットスキャン銃。
## 自身の位置を銃口とし、見た目・音・弾道は 8/24 の演出フェーズへ委ねる。

const WORLD_MASK: int = 1 << 0
const HURTBOX_MASK: int = 1 << 6

## 一発のダメージ。既定値なら Health.max_hp=100 の対象を一発でダウンさせる。
@export var damage: float = 100.0
## 銃撃を致死として記録するか。
@export var lethal: bool = true
## 客の近接誤爆防止用 stagger_threshold を無視するか。
@export var ignore_stagger_threshold: bool = true
## 射程（m）。
@export var max_range: float = 30.0

## 発砲した。to は壁または Hurtbox との交点、外れた場合は射程端。
signal shot_fired(from: Vector3, to: Vector3, hit_body: Node3D)


## target_position へ発砲し、最初に命中した Hurtbox の本体を返す。
## 最初の交点が壁の場合は遮蔽されているため null を返す。
func fire_at(target_position: Vector3) -> Node3D:
	var from := global_position
	var to := _clamped_endpoint(target_position)
	var hit := _cast_ray(to)
	var hit_body: Node3D = _body_from_hit(hit)
	var impact_position: Vector3 = hit.get("position", to) as Vector3

	if hit_body != null:
		var hurtbox := hit.get("collider") as Hurtbox
		if hurtbox != null:
			hurtbox.receive_shot(_shooter(), damage, lethal, ignore_stagger_threshold)

	shot_fired.emit(from, impact_position, hit_body)
	return hit_body


## 発砲せず、同じレイ条件で target が射線の最初の Hurtbox かを調べる。
## 不安定型が遮蔽された客を狙って射撃間隔を消費しないために使う。
func has_clear_shot(target: Node3D, target_position: Vector3) -> bool:
	if target == null or global_position.distance_to(target_position) > max_range:
		return false
	return _body_from_hit(_cast_ray(target_position)) == target


func _cast_ray(to: Vector3) -> Dictionary:
	if not is_inside_tree() or global_position.is_equal_approx(to):
		return {}
	var excluded: Array[RID] = []
	var shooter := _shooter()
	if shooter is CollisionObject3D:
		excluded.append((shooter as CollisionObject3D).get_rid())
	if shooter != null:
		_append_hurtbox_exclusions(shooter, excluded)
	var query := PhysicsRayQueryParameters3D.create(
		global_position, to, WORLD_MASK | HURTBOX_MASK, excluded)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _append_hurtbox_exclusions(node: Node, excluded: Array[RID]) -> void:
	for child: Node in node.get_children():
		if child is Hurtbox:
			excluded.append((child as Hurtbox).get_rid())
		_append_hurtbox_exclusions(child, excluded)


func _body_from_hit(hit: Dictionary) -> Node3D:
	if hit.is_empty():
		return null
	var hurtbox := hit.get("collider") as Hurtbox
	return hurtbox.owner_body() if hurtbox != null else null


func _clamped_endpoint(target_position: Vector3) -> Vector3:
	var offset := target_position - global_position
	if offset.length() <= max_range:
		return target_position
	return global_position + offset.normalized() * max_range


## MuzzlePoint の親を上へたどり、最初の CollisionObject3D を射手とする。
## これによりシーン階層への固定 NodePath を持たず、共有部品として再利用できる。
func _shooter() -> Node3D:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is CollisionObject3D:
			return ancestor as Node3D
		ancestor = ancestor.get_parent()
	return null
