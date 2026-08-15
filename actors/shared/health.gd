extends Node
class_name Health

## NPC/プレイヤー共通の体力・よろけ管理。technical-spec §7.1。
##
## 意味論:
## - staggered: ダウンに至らない被弾のたびに発火する
## - downed: HP が 0 まで削られたときに発火する。致死かどうかは攻撃側が持ち、
##   take_hit() の lethal 引数をそのまま通知する。ただし被弾回数が
##   stagger_threshold に達するまではダウンさせない（客の「規定回数叩かないと
##   ダウンしない」誤爆防止ルールはこの下限として機能する。HP が先に尽きても
##   回数未達なら HP 0 のまま耐えてよろけ扱いになる）。ただし、これは近接の
##   誤爆で客がダウンするのを防ぐための下限（game-design.md §6.2 の3番目）であり、
##   狙って撃つ銃撃には適用しない。

## 最大HP。
@export var max_hp: float = 100.0
## ダウンに要する最低被弾回数。客は 3（誤爆防止）、犯人・ダミーは 1。
@export var stagger_threshold: int = 1
## よろけ（ダウンには至らない被弾）が発生した。
signal staggered()
## ダウンした。lethal=true なら致死（攻撃側の Hitbox.lethal から渡される）。
signal downed(lethal: bool)

var _hp: float = 0.0
var _stagger_count: int = 0
var _is_downed: bool = false


func _ready() -> void:
	_hp = max_hp


## ダメージを受ける。ダウン済みなら何もしない。
## 既定は非致死（近接）。銃撃側は lethal=true と
## ignore_stagger_threshold=true を明示する。両方の既定を false に保つため、
## 既存の呼び出しの挙動は変わらない。
func take_hit(damage: float, lethal: bool = false,
		ignore_stagger_threshold: bool = false) -> void:
	if _is_downed:
		return
	_hp = maxf(_hp - damage, 0.0)
	_stagger_count += 1

	var threshold_met: bool = ignore_stagger_threshold or _stagger_count >= stagger_threshold
	if _hp <= 0.0 and threshold_met:
		_is_downed = true
		downed.emit(lethal)
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
