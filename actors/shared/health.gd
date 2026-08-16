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
## ダウンに要する最低被弾回数。客は 2（誤爆防止）、犯人・ダミーは 1。
@export var stagger_threshold: int = 1
## ダウン後に追い打ち成立とする命中回数。
@export var finish_hits: int = 2
## よろけ（ダウンには至らない被弾）が発生した。
signal staggered()
## ダウンした。lethal=true なら致死（攻撃側の Hitbox.lethal から渡される）。
signal downed(lethal: bool)
## ダウン後の追い打ちが規定回数に達した。attacker は成立させた加害者。
signal finished(attacker: Node3D)

var _hp: float = 0.0
var _stagger_count: int = 0
var _is_downed: bool = false
var _finish_hit_count: int = 0
var _finished_emitted: bool = false


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


## ダウン後の追い打ちを1回受ける。通常被弾とは独立させ、規定回数に
## 達した瞬間だけ finished を通知する。
func take_finish_hit(attacker: Node3D = null) -> void:
	if not _is_downed or _finished_emitted:
		return
	_finish_hit_count += 1
	if _finish_hit_count >= finish_hits:
		_finished_emitted = true
		finished.emit(attacker)


func current_hp() -> float:
	return _hp


func is_downed() -> bool:
	return _is_downed


## HP を amount だけ回復する。ダウン中は回復せず、よろけ回数も変更しない。
## 全快に加えて全カウンタを初期化する revive() とは別の通常回復処理。
func heal(amount: float) -> void:
	if _is_downed or amount <= 0.0:
		return
	_hp = minf(_hp + amount, max_hp)


## HP・よろけ回数・追い打ち状態を初期状態へ戻す。
## 通常回復だけを行う heal() とは異なり、ダウンからの復帰専用。
func revive() -> void:
	_hp = max_hp
	_stagger_count = 0
	_is_downed = false
	_finish_hit_count = 0
	_finished_emitted = false
