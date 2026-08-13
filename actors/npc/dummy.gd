extends CharacterBody3D

## 殴られ検証用の棒立ちダミー。robber レイヤー(3)。
## Hurtbox から receive_knockback / flash_hit が呼ばれ、Health の downed で倒れる。
## Death モーションは NPC がリグを持ってから。ここは回転で倒す簡易表現に留める。

## ノックバック時の後退速度（m/s）。
@export var knockback_speed: float = 3.0
## ノックバックが減衰しきるまでの時間（秒）。
@export var knockback_decay: float = 0.25
## 被弾フラッシュの色。
@export var flash_color: Color = Color(1, 1, 1, 1)
## フラッシュの持続時間（秒）。
@export var flash_duration: float = 0.08
## ダウン時に倒れる角度（度）。
@export var fall_angle_deg: float = 85.0
## ダウン時に倒れきるまでの時間（秒）。
@export var fall_duration: float = 0.4

@export var mesh_path: NodePath = ^"Mesh"
@export var health_path: NodePath = ^"Health"

var _mesh: MeshInstance3D = null
var _health: Node = null
var _material: StandardMaterial3D = null
var _base_albedo: Color = Color(1, 1, 1, 1)
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0
var _downed: bool = false


func _ready() -> void:
	_mesh = get_node_or_null(mesh_path) as MeshInstance3D
	_health = get_node_or_null(health_path)
	if _mesh != null:
		# 一意なマテリアルにしてフラッシュを個体ごとに独立させる。
		var base := _mesh.get_active_material(0)
		if base is StandardMaterial3D:
			_material = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			_material = StandardMaterial3D.new()
			_material.albedo_color = Color(0.55, 0.45, 0.5)
		_mesh.material_override = _material
		_base_albedo = _material.albedo_color
	if _health != null:
		_health.connect("downed", _on_downed)


func _physics_process(delta: float) -> void:
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
		_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO, (knockback_speed / knockback_decay) * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0

	move_and_slide()


## Hurtbox から呼ばれる。direction は攻撃者→自分の水平方向。
func receive_knockback(direction: Vector3, strength: float) -> void:
	if _downed:
		return
	var d := direction
	d.y = 0.0
	if d.length() < 0.001:
		return
	_knockback_vel = d.normalized() * knockback_speed * clampf(strength / 5.0, 0.5, 2.0)
	_knockback_timer = knockback_decay


## Hurtbox から呼ばれる。一瞬白くフラッシュする。
func flash_hit() -> void:
	if _material == null:
		return
	_material.albedo_color = flash_color
	var tw := create_tween()
	tw.tween_property(_material, "albedo_color", _base_albedo, flash_duration)


func _on_downed(lethal: bool) -> void:
	if _downed:
		return
	_downed = true
	# 犯人としてダウンを記録する（ダミーは robber 陣営扱い）。
	RunState.record_down(self, GameTypes.Faction.ROBBER, lethal)
	# その場に倒れる（回転で簡易表現）。前方 X 軸まわりに倒す。
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", deg_to_rad(fall_angle_deg), fall_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
