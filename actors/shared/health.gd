extends Node
class_name Health

## NPC/プレイヤー共通の体力・よろけ管理。technical-spec §7.1。
## take_hit(damage) でよろけ回数を数え、stagger_threshold 回に達したら downed を送る。
## ダウンが致死かどうか (lethal) は現在HPが lethal_hp_threshold 以下かで判定する。

## 最大HP。
@export var max_hp: float = 100.0
## ダウンに要する被弾回数。客は 3（誤爆防止）、犯人・ダミーは 1。
@export var stagger_threshold: int = 1
## この値以下のHPまで削られた被弾は致死ダウンとして扱う（0.0 = 致死しない）。
@export var lethal_hp_threshold: float = 0.0

## よろけ（ダウンには至らない被弾）が発生した。
signal staggered()
## ダウンした。lethal=true なら致死。
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

	var lethal := _hp <= lethal_hp_threshold
	if _stagger_count >= stagger_threshold or lethal:
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
