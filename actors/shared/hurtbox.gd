extends Area3D
class_name Hurtbox

## 被弾判定。technical-spec §2 のとおり layer=7(hurtbox) / mask=6(hitbox)。
## 検出は Hitbox 側が主導する（Hitbox.activate() / area_entered）。
## Hurtbox は本体（owner_body）と Health への橋渡しと、ノックバック方向の算出を担う。
## ノックバック方向は「攻撃者 → 被弾側」の水平ベクトルで算出し、被弾側へ渡す。

## この Hurtbox を持つ本体（Health / ノックバック受け手）。
@export var owner_body_path: NodePath = ^".."
## Health ノード（未指定なら owner_body から探索）。
@export var health_path: NodePath = ^""

var _owner_body: Node3D = null
var _health: Health = null


func _ready() -> void:
	collision_layer = 1 << 6   # layer 7 = hurtbox
	collision_mask = 1 << 5    # mask 6 = hitbox
	monitoring = true
	monitorable = true

	_owner_body = get_node_or_null(owner_body_path) as Node3D
	if not health_path.is_empty():
		_health = get_node_or_null(health_path) as Health
	if _health == null and _owner_body != null:
		_health = _find_health(_owner_body)


func owner_body() -> Node3D:
	return _owner_body


## Hitbox から呼ばれる。payload を本体の Health / ノックバックへ伝える。
func receive_hit(hitbox: Hitbox) -> void:
	var dir := _knockback_direction(hitbox.source_body())
	if _owner_body != null and _owner_body.has_method("receive_knockback"):
		_owner_body.call("receive_knockback", dir, hitbox.knockback)
	if _owner_body != null and _owner_body.has_method("flash_hit"):
		_owner_body.call("flash_hit")
	if _health != null:
		_health.take_hit(hitbox.damage)


## 攻撃者から被弾側への水平方向（ノックバックの向き）。
func _knockback_direction(attacker: Node3D) -> Vector3:
	if attacker == null or _owner_body == null:
		return Vector3.ZERO
	var d := _owner_body.global_position - attacker.global_position
	d.y = 0.0
	if d.length() < 0.001:
		return -attacker.global_transform.basis.z.normalized()
	return d.normalized()


func _find_health(node: Node) -> Health:
	for c in node.get_children():
		if c is Health:
			return c as Health
	return null
