extends Node
class_name Health

## NPC/プレイヤー共通の体力・よろけ管理。technical-spec §7.1。
##
## 意味論:
## - staggered: ダウンに至らない被弾のたびに発火する
## - downed: HP が 0 まで削られたときに発火する。ただし被弾回数が
##   stagger_threshold に達するまではダウンさせない（客の「規定回数叩かないと
##   ダウンしない」誤爆防止ルールはこの下限として機能する。HP が先に尽きても
##   回数未達なら HP 0 のまま耐えてよろけ扱いになる）

## 最大HP。
@export var max_hp: float = 100.0
## ダウンに要する最低被弾回数。客は 3（誤爆防止）、犯人・ダミーは 1。
@export var stagger_threshold: int = 1
## 致死ダウン判定のしきい値（将来用）。lethal の確定方法は 8/22 の客実装時に
## 詰めるため、現時点では未使用。downed は lethal=false 固定で発火する。
@export var lethal_hp_threshold: float = 0.0

## よろけ（ダウンには至らない被弾）が発生した。
signal staggered()
## ダウンした。lethal=true なら致死（現時点では常に false。上記コメント参照）。
signal downed(lethal: bool)

var _hp: float = 0.0
var _stagger_count: int = 0
var _is_downed: bool = false


func _ready() -> void:
	_hp = max_hp


## ダメージを受ける。ダウン済みなら何もしない。
func take_hit(damage: float) -> void:
	if _is_downed:
		return
	_hp = maxf(_hp - damage, 0.0)
	_stagger_count += 1

	if _hp <= 0.0 and _stagger_count >= stagger_threshold:
		_is_downed = true
		# lethal は 8/22（客実装）で確定方法を詰める。今日は false 固定。
		downed.emit(false)
	else:
		staggered.emit()


func current_hp() -> float:
	return _hp


func is_downed() -> bool:
	return _is_downed


## HP・よろけ回数を初期状態へ戻す。
func revive() -> void:
	_hp = max_hp
	_stagger_count = 0
	_is_downed = false
