extends Node

## ヒットストップ。technical-spec §11.1。autoload 名 HitStop で登録する。
## Engine.time_scale を一瞬落として手応えを出す。
## create_timer の第4引数 ignore_time_scale=true が必須。これが無いと
## time_scale の影響で待ち時間が伸び、復帰しなくなる。

## 既定のストップ時間（実時間・秒）。
@export var default_duration: float = 0.08
## 既定のスロー係数（0 に近いほど強く止まる）。
@export var default_scale: float = 0.05

var _active: bool = false


func apply(duration: float = -1.0, scale: float = -1.0) -> void:
	var dur := duration if duration >= 0.0 else default_duration
	var scl := scale if scale >= 0.0 else default_scale
	# 多重発火時は上書きせず、既に走っているストップを尊重する。
	if _active:
		return
	_active = true
	Engine.time_scale = scl
	# 第2引数 process_always=true, 第3 process_in_physics=false, 第4 ignore_time_scale=true。
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = 1.0
	_active = false
