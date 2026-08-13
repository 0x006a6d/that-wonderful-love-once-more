extends Area3D
class_name Hitbox

## 攻撃判定。technical-spec §2 のとおり layer=6(hitbox) / mask=7(hurtbox)。
## AnimationPlayer の Call Method Track から configure() と activate()/deactivate() を叩く。
## コード側でタイマーは持たない（§6.3）。
##
## 命中検出は Hitbox が主導する:
##   - 有効化した瞬間に既に重なっている Hurtbox を走査する（enable 時に重なり済みの相手）
##   - 有効化中に新たに入ってきた Hurtbox は area_entered で拾う
## どちらも Hurtbox.receive_hit() を呼ぶ。1 回の有効化中は同一相手を二重ヒットさせない。

## この Hitbox を出している本体（ノックバック方向の起点）。攻撃者。
@export var source_body_path: NodePath = ^".."

var damage: float = 0.0
var knockback: float = 0.0
var lethal: bool = false

var _source_body: Node3D = null
var _active: bool = false
## 1 回の有効化中に同じ相手を二重ヒットさせないためのセット。
var _already_hit: Array[Node] = []

## この Hitbox が誰かに当たった瞬間に送る（攻撃側の手応え演出のトリガに使う）。
signal hit_landed(target: Node3D)


func _ready() -> void:
	collision_layer = 1 << 5   # layer 6 = hitbox
	collision_mask = 1 << 6    # mask 7 = hurtbox
	monitoring = false
	monitorable = false
	_source_body = get_node_or_null(source_body_path) as Node3D
	area_entered.connect(_on_area_entered)


## Call Method Track から呼ぶ。有効化のたびに二重ヒット防止セットをリセットする。
func configure(new_damage: float, new_knockback: float, new_lethal: bool) -> void:
	damage = new_damage
	knockback = new_knockback
	lethal = new_lethal
	_already_hit.clear()


## Call Method Track（またはコード）から。判定を有効化し、重なり済みの相手も拾う。
func activate() -> void:
	_active = true
	monitoring = true
	# 有効化フレームで既に重なっている相手を即座に処理する。
	for area in get_overlapping_areas():
		_try_hit(area as Area3D)


## 判定を無効化する。
func deactivate() -> void:
	_active = false
	monitoring = false


func source_body() -> Node3D:
	return _source_body


func _on_area_entered(area: Area3D) -> void:
	if _active:
		_try_hit(area)


func _try_hit(area: Area3D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox == null:
		return
	var target := hurtbox.owner_body()
	if target == null or target == _source_body:
		return
	if _already_hit.has(target):
		return
	_already_hit.append(target)
	hurtbox.receive_hit(self)
	hit_landed.emit(target)
