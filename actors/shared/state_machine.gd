extends Node
class_name StateMachine

## NPC 共通のステートマシン基盤（technical-spec §7.2）。
## 各 NPC は「ステート集合」だけを差し替える。犯人・客・警官がこれを共有する。
##
## 方式:
## - ステートは int（各 NPC が定義する enum）で識別する
## - 1 ステートにつき 進入 / 毎物理フレーム / 退出 の Callable を登録する
## - 「1 ステート 1 ノード」方式は採らない。.tscn の階層が膨らみ、
##   エディタ操作の負担が増えるため（開発者が Godot 未経験である前提）
##
## 駆動は所有者側が `physics_update(delta)` を明示的に呼ぶ。ノードの
## `_physics_process` に任せると、本体の移動処理との実行順が読めなくなるため。

## ステートが切り替わった。from_state は初回のみ NO_STATE。
signal state_changed(from_state: int, to_state: int)

## 未開始・無効を表すステートID。
const NO_STATE: int = -1

var _enter_callbacks: Dictionary[int, Callable] = {}
var _physics_callbacks: Dictionary[int, Callable] = {}
var _exit_callbacks: Dictionary[int, Callable] = {}
var _state_names: Dictionary[int, StringName] = {}

var _current: int = NO_STATE
var _time_in_state: float = 0.0
## 進入コールバックの中でさらに transition_to() が呼ばれた場合の再入防止。
var _transitioning: bool = false
## 遷移中に届いた要求の待ち行列。force も一緒に運ばないと、退避経路を通った
## 同ステート再進入（STAGGERED の滞在時間延長）が握り潰される。
var _pending: Array[int] = []
var _pending_force: Array[bool] = []


## ステートを登録する。未使用のフックは空の Callable のままでよい。
func add_state(id: int, state_name: StringName, on_enter: Callable = Callable(),
		on_physics: Callable = Callable(), on_exit: Callable = Callable()) -> void:
	_state_names[id] = state_name
	if on_enter.is_valid():
		_enter_callbacks[id] = on_enter
	if on_physics.is_valid():
		_physics_callbacks[id] = on_physics
	if on_exit.is_valid():
		_exit_callbacks[id] = on_exit


## 初期ステートへ入る。退出コールバックは呼ばれない。
func start(id: int) -> void:
	_current = NO_STATE
	transition_to(id, true)


## ステートを切り替える。同じステートへの遷移は force=true のときだけ再進入する
## （被弾の連続で STAGGERED の滞在時間を延ばす、といった用途）。
func transition_to(id: int, force: bool = false) -> void:
	if not _state_names.has(id):
		push_warning("StateMachine: 未登録のステート %d へ遷移しようとした" % id)
		return
	if id == _current and not force:
		return
	if _transitioning:
		# 進入処理の途中から呼ばれた。現在の遷移を終えてから順に適用する。
		_pending.append(id)
		_pending_force.append(force)
		return

	_transitioning = true
	var from := _current
	if from != NO_STATE and _exit_callbacks.has(from):
		_exit_callbacks[from].call()
	_current = id
	_time_in_state = 0.0
	if _enter_callbacks.has(id):
		_enter_callbacks[id].call()
	_transitioning = false
	state_changed.emit(from, id)

	if not _pending.is_empty():
		var next := _pending.pop_front() as int
		var next_force := _pending_force.pop_front() as bool
		transition_to(next, next_force)


## 所有者の _physics_process から呼ぶ。
func physics_update(delta: float) -> void:
	if _current == NO_STATE:
		return
	_time_in_state += delta
	if _physics_callbacks.has(_current):
		_physics_callbacks[_current].call(delta)


func current() -> int:
	return _current


func current_name() -> StringName:
	return _state_names.get(_current, &"none")


## 現在ステートに入ってからの経過秒。遷移のたびに 0 に戻る。
func time_in_state() -> float:
	return _time_in_state
