extends Control
class_name InputLog

## 押したキーとコンボの進み具合を画面に出す。
##
## 「コンボが成功しているのか分からない」への対処。3つを同時に見せる。
##   1. 入力履歴  — 直近に押したボタンを左から順に並べる
##   2. いま出た技 — 何段目の何が出たか、当たったか（HIT / MISS）
##   3. 次の派生   — このノードから J / K で何へ繋がるか
##
## 表示だけを担い、入力の解釈や戦闘ロジックは持たない。入力は
## `Input.is_action_just_pressed()` を直接読む（消費しないので本体と競合しない）。

const ComboTree := preload("res://actors/player/combo_tree.gd")

## 技の表示名。ComboTree の TECHNIQUE_* と対応させる。
const TECHNIQUE_NAMES: Dictionary = {
	&"jab": "左ジャブ",
	&"straight": "右ストレート",
	&"hook": "左フック",
	&"knee": "右膝",
	&"middle": "右ミドル",
	&"high": "右ハイ",
}

## 履歴に出す入力。アクション名 → 表示ラベル。移動は数が多すぎるので出さない。
const LOGGED_ACTIONS: Dictionary = {
	&"attack": "J",
	&"kick": "K",
	&"dodge": "回避",
	&"lock_on": "LOCK",
}

@export_group("Connections")
@export var melee_path: NodePath
@export var hitbox_path: NodePath

@export_group("Behaviour")
## 履歴に残す個数。
@export var history_max: int = 8
## 履歴のチップが消えるまでの秒数。
@export var history_lifetime: float = 2.5
## コンボが終わってから表示を消すまでの秒数。
@export var result_linger: float = 1.2

@export_group("Colors")
@export var text_color: Color = Color(0.94, 0.95, 1.0, 1.0)
@export var accent_color: Color = Color("5A4C97")
@export var hit_color: Color = Color(0.42, 0.85, 0.72, 1.0)
@export var miss_color: Color = Color(0.72, 0.68, 0.78, 1.0)
@export var blocked_color: Color = Color(0.95, 0.72, 0.30, 1.0)

@export_group("Node Paths")
@export var history_label_path: NodePath = ^"Rows/HistoryLabel"
@export var stage_label_path: NodePath = ^"Rows/StageLabel"
@export var next_label_path: NodePath = ^"Rows/NextLabel"
@export_group("")

const RESULT_PENDING: int = 0
const RESULT_HIT: int = 1
const RESULT_BLOCKED: int = 2
const RESULT_MISS: int = 3

var _melee: Node = null
var _hitbox: Hitbox = null
var _history_label: Label = null
var _stage_label: Label = null
var _next_label: Label = null

## [ラベル, 残り秒数] の並び。
var _history: Array = []
var _stage_text: String = ""
## 0=未確定 / 1=命中 / 2=ガードされた / 3=空振り。
var _stage_result: int = RESULT_PENDING
var _stage_resolved: bool = false
var _linger_left: float = 0.0


func _ready() -> void:
	_history_label = get_node_or_null(history_label_path) as Label
	_stage_label = get_node_or_null(stage_label_path) as Label
	_next_label = get_node_or_null(next_label_path) as Label
	for label: Label in [_history_label, _stage_label, _next_label]:
		if label != null:
			label.add_theme_color_override(&"font_color", text_color)

	_melee = get_node_or_null(melee_path)
	if _melee != null:
		_melee.connect("stage_started", _on_stage_started)
		_melee.connect("combo_finished", _on_combo_finished)
	_hitbox = get_node_or_null(hitbox_path) as Hitbox
	if _hitbox != null:
		_hitbox.hit_landed.connect(_on_hit_landed)
		_hitbox.hit_blocked.connect(_on_hit_blocked)
	_refresh()


func _process(delta: float) -> void:
	_poll_inputs()
	_age_history(delta)
	if _linger_left > 0.0:
		_linger_left = maxf(_linger_left - delta, 0.0)
		if _linger_left <= 0.0:
			_stage_text = ""
			_stage_resolved = false
	_refresh()


func _poll_inputs() -> void:
	for action: StringName in LOGGED_ACTIONS:
		if not InputMap.has_action(action):
			continue
		if Input.is_action_just_pressed(action):
			_history.append([String(LOGGED_ACTIONS[action]), history_lifetime])
	while _history.size() > history_max:
		_history.pop_front()


func _age_history(delta: float) -> void:
	var index: int = 0
	while index < _history.size():
		_history[index][1] -= delta
		if _history[index][1] <= 0.0:
			_history.remove_at(index)
		else:
			index += 1


## 技が出た瞬間。当たったかどうかはこの時点ではまだ分からない。
func _on_stage_started(technique: StringName, stage: int) -> void:
	_stage_result = RESULT_PENDING
	_stage_resolved = false
	_linger_left = 0.0
	_stage_text = "%d段目  %s" % [stage, _technique_name(technique)]


func _on_hit_landed(_target: Node3D) -> void:
	_stage_result = RESULT_HIT
	_stage_resolved = true


## ガードで弾かれた。空振りと区別して出す。回り込めば通る、と読めるように。
func _on_hit_blocked(_target: Node3D) -> void:
	if _stage_result == RESULT_HIT:
		return
	_stage_result = RESULT_BLOCKED
	_stage_resolved = true


func _on_combo_finished() -> void:
	if _stage_result == RESULT_PENDING:
		_stage_result = RESULT_MISS
	_stage_resolved = true
	_linger_left = result_linger


func _refresh() -> void:
	if _history_label != null:
		var chips: PackedStringArray = []
		for entry in _history:
			chips.append("[%s]" % entry[0])
		_history_label.text = " ".join(chips)

	if _stage_label != null:
		if _stage_text.is_empty():
			_stage_label.text = ""
		elif not _stage_resolved:
			_stage_label.text = "%s  …" % _stage_text
			_stage_label.add_theme_color_override(&"font_color", text_color)
		elif _stage_result == RESULT_HIT:
			_stage_label.text = "%s  HIT" % _stage_text
			_stage_label.add_theme_color_override(&"font_color", hit_color)
		elif _stage_result == RESULT_BLOCKED:
			_stage_label.text = "%s  ガードされた" % _stage_text
			_stage_label.add_theme_color_override(&"font_color", blocked_color)
		else:
			_stage_label.text = "%s  MISS" % _stage_text
			_stage_label.add_theme_color_override(&"font_color", miss_color)

	if _next_label != null:
		_next_label.text = _next_text()


## いまのノードから J / K で何へ繋がるかを出す。繋がりが無ければコンボの終端。
func _next_text() -> String:
	if _melee == null or not _melee.has_method("combo_node"):
		return ""
	var node_id: StringName = _melee.call("combo_node")
	if String(node_id).is_empty():
		return "J パンチ / K キック で開始"
	var parts: PackedStringArray = []
	for pair in [[ComboTree.INPUT_PUNCH, "J"], [ComboTree.INPUT_KICK, "K"]]:
		var next_id: StringName = ComboTree.next_node(node_id, pair[0])
		if String(next_id).is_empty():
			continue
		parts.append("%s→%s" % [pair[1], _technique_name(ComboTree.technique_for(next_id))])
	if parts.is_empty():
		return "つぎ：無し（ここで締め）"
	return "つぎ：" + "   ".join(parts)


func _technique_name(technique: StringName) -> String:
	return String(TECHNIQUE_NAMES.get(technique, String(technique)))
