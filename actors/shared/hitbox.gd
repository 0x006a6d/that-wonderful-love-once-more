extends Area3D
class_name Hitbox

## 攻撃判定。technical-spec §2 のとおり layer=6(hitbox) / mask=7(hurtbox)。
## AnimationPlayer の Call Method Track から configure() と activate()/deactivate() を叩く。
## コード側でタイマーは持たない（§6.3）。
##
## 命中検出は area_entered に一本化する。monitoring を有効化すると、Godot は次の
## 物理ステップで現在の重なりを再評価し、有効化時点で既に重なっていた Hurtbox に対しても
## area_entered を送出する。したがって「有効化時に重なり済み」「有効化中に侵入」の両方を
## area_entered が拾う。1 回の有効化中は同一相手を二重ヒットさせない。
##
## 注意: activate() 直後に get_overlapping_areas() を読む方式は使わない。有効化直後は
## 物理判定キャッシュが未更新で、重なりが反映されず取りこぼす（同一物理ステップ内で
## activate→deactivate すると特に顕著）。判定窓は必ず複数フレーム開ける。

## この Hitbox を出している本体（ノックバック方向の起点）。攻撃者。
@export var source_body_path: NodePath = ^".."

## この Hitbox が当てない相手のグループ。犯人が味方の犯人を殴って
## RunState.robbers_downed が勝手に増える（＝幕が進む）事故を防ぐ。
## 客への攻撃規則（technical-spec §6.4 のロックオン必須）はここではなく
## 8/22 の客実装で別途入れる。
@export var ignore_groups: Array[StringName] = []

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


## Call Method Track（またはコード）から。判定を有効化する。
## 重なり済み・侵入いずれの相手も area_entered（次の物理ステップ）で拾う。
func activate() -> void:
	_active = true
	monitoring = true


## 判定を無効化する。
func deactivate() -> void:
	_active = false
	monitoring = false


## 被弾処理（area_entered → Hurtbox → Health → ダウン）の最中から無効化する場合に使う。
## 信号の処理中に monitoring を直接書き換えると Godot が弾くため
## （"Function blocked during in/out signal"）、フラグの反映だけ物理ステップの
## 終わりへ回す。判定そのものは _active で即座に閉じるので、1 フレームぶん
## monitoring が残っても命中はしない。
func deactivate_deferred() -> void:
	_active = false
	set_deferred("monitoring", false)


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
	for group in ignore_groups:
		if target.is_in_group(group):
			return
	if _already_hit.has(target):
		return
	_already_hit.append(target)
	hurtbox.receive_hit(self)
	hit_landed.emit(target)
