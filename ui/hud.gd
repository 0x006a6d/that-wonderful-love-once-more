extends CanvasLayer
class_name Hud

## AIニケ自身の状態表示として、戦闘中に必要な最小情報だけを画面へ重ねる。
## 監視カメラ風フィルタや走査線などの演出は持たず、現段階では可読性を優先する。

@export_group("Connections")
@export var health_path: NodePath
@export var camera_path: NodePath
@export var lock_on_path: NodePath

@export_group("Layout")
@export var status_position: Vector2 = Vector2(24.0, 24.0)
@export var status_size: Vector2 = Vector2(310.0, 174.0)
@export var hp_bar_size: Vector2 = Vector2(274.0, 18.0)
## 相手のHPゲージ。格闘の的として、いま殴っている相手の残りが常に見えるようにする。
@export var enemy_bar_size: Vector2 = Vector2(488.0, 16.0)
## ロックオンしていないとき、この距離以内で最も近い生存中の犯人をゲージに出す（m）。
@export var enemy_gauge_range: float = 14.0
@export var marker_size: Vector2 = Vector2(160.0, 38.0)
@export var marker_world_height: float = 2.1

@export_group("Colors")
@export var panel_color: Color = Color(0.035, 0.04, 0.07, 0.86)
@export var text_color: Color = Color(0.94, 0.95, 1.0, 1.0)
@export var accent_color: Color = Color("5A4C97")
@export var hp_background_color: Color = Color(0.11, 0.12, 0.17, 0.95)
@export var hp_fill_color: Color = Color(0.42, 0.85, 0.72, 1.0)
@export var enemy_fill_color: Color = Color(0.92, 0.36, 0.32, 1.0)
@export var live_robber_color: Color = Color(1.0, 0.78, 0.16, 1.0)
@export var civilian_warning_color: Color = Color(1.0, 0.20, 0.32, 1.0)
@export var downed_robber_color: Color = Color(0.72, 0.66, 0.95, 1.0)

@export_group("Typography")
@export var status_font_size: int = 20
@export var hp_font_size: int = 22
@export var marker_font_size: int = 20

@export_group("Node Paths")
@export var status_panel_path: NodePath = ^"Screen/StatusPanel"
@export var hp_label_path: NodePath = ^"Screen/StatusPanel/Margin/Rows/HpLabel"
@export var hp_bar_path: NodePath = ^"Screen/StatusPanel/Margin/Rows/HpBar"
@export var robber_label_path: NodePath = ^"Screen/StatusPanel/Margin/Rows/RobberLabel"
@export var civilian_label_path: NodePath = ^"Screen/StatusPanel/Margin/Rows/CivilianLabel"
@export var marker_path: NodePath = ^"Screen/LockMarker"
@export var enemy_panel_path: NodePath = ^"Screen/EnemyPanel"
@export var enemy_name_path: NodePath = ^"Screen/EnemyPanel/Margin/Rows/NameLabel"
@export var enemy_bar_path: NodePath = ^"Screen/EnemyPanel/Margin/Rows/HpBar"
@export_group("")

var _health: Health = null
var _camera: Camera3D = null
var _lock_on: Node = null
var _status_panel: Panel = null
var _hp_label: Label = null
var _hp_bar: ProgressBar = null
var _robber_label: Label = null
var _civilian_label: Label = null
var _marker: Label = null
var _enemy_panel: Panel = null
var _enemy_name: Label = null
var _enemy_bar: ProgressBar = null
## ゲージに出している相手。切り替わったときだけ購読し直す。
var _enemy_body: Node3D = null
var _enemy_health: Health = null
var _last_robbers_downed: int = -1
var _last_robbers_total: int = -1
var _last_civilians_downed: int = -1
var _last_civilians_total: int = -1
var _marker_kind: int = LockOn.TargetKind.NONE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_status_panel = get_node_or_null(status_panel_path) as Panel
	_hp_label = get_node_or_null(hp_label_path) as Label
	_hp_bar = get_node_or_null(hp_bar_path) as ProgressBar
	_robber_label = get_node_or_null(robber_label_path) as Label
	_civilian_label = get_node_or_null(civilian_label_path) as Label
	_marker = get_node_or_null(marker_path) as Label
	_enemy_panel = get_node_or_null(enemy_panel_path) as Panel
	_enemy_name = get_node_or_null(enemy_name_path) as Label
	_enemy_bar = get_node_or_null(enemy_bar_path) as ProgressBar
	_health = get_node_or_null(health_path) as Health
	_camera = get_node_or_null(camera_path) as Camera3D
	_lock_on = get_node_or_null(lock_on_path)
	_apply_visual_settings()
	_connect_sources()
	_update_initial_hp()
	_update_population(true)
	_update_marker()
	GameDirector.act_changed.connect(_on_act_changed)
	_on_act_changed(GameDirector.current_act)


func _process(_delta: float) -> void:
	# RunState は犯人側の変更通知を持たない。int 4個の比較は軽量で、片側だけ
	# シグナル方式にして経路を二重化するより単純なため、人数だけ毎フレーム読む。
	_update_population(false)
	# 3D対象は動くため、画面座標への射影は表示フレームごとに更新する。
	_update_marker()
	_update_enemy_gauge()


func _connect_sources() -> void:
	if _health != null:
		_health.hp_changed.connect(_on_hp_changed)


func _update_initial_hp() -> void:
	if _health == null:
		_on_hp_changed(0.0, 0.0)
		return
	_on_hp_changed(_health.current_hp(), _health.max_hp)


func _on_hp_changed(current: float, maximum: float) -> void:
	if _hp_label != null:
		_hp_label.text = "SELF HP   %d / %d" % [roundi(current), roundi(maximum)]
	if _hp_bar != null:
		_hp_bar.max_value = maxf(maximum, 1.0)
		_hp_bar.value = clampf(current, 0.0, _hp_bar.max_value)


func _update_population(force: bool) -> void:
	if force or RunState.robbers_downed != _last_robbers_downed \
			or RunState.robbers_total != _last_robbers_total:
		_last_robbers_downed = RunState.robbers_downed
		_last_robbers_total = RunState.robbers_total
		var robbers_alive := maxi(RunState.robbers_total - RunState.robbers_downed, 0)
		if _robber_label != null:
			# 残りの時間圧と、制圧した数 / 総数の進捗を同じ1行で読めるようにする。
			_robber_label.text = "犯人 残り %d / %d  制圧 %d / %d" % [
				robbers_alive, RunState.robbers_total,
				RunState.robbers_downed, RunState.robbers_total]
	if force or RunState.civilians_downed != _last_civilians_downed \
			or RunState.civilians_total != _last_civilians_total:
		_last_civilians_downed = RunState.civilians_downed
		_last_civilians_total = RunState.civilians_total
		var civilians_alive := maxi(RunState.civilians_total - RunState.civilians_downed, 0)
		if _civilian_label != null:
			_civilian_label.text = "客 生存     %d / %d" % [
				civilians_alive, RunState.civilians_total]


func _update_marker() -> void:
	if _marker == null:
		return
	if not visible or _camera == null or _lock_on == null \
			or not _lock_on.has_method("current_target") \
			or not _lock_on.has_method("current_target_kind"):
		_hide_marker()
		return
	var target := _lock_on.call("current_target") as Node3D
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		_hide_marker()
		return
	var world_position := target.global_position + Vector3.UP * marker_world_height
	# 背後や画面外では隠す。画面端へ寄せると、背後の対象まで同じ方向指示に見えて
	# 攻撃意図を誤認しやすいため、実際に画面内へ入った対象だけを明示する。
	if _camera.is_position_behind(world_position):
		_hide_marker()
		return
	var screen_position := _camera.unproject_position(world_position)
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	if not viewport_rect.has_point(screen_position):
		_hide_marker()
		return
	var kind := int(_lock_on.call("current_target_kind"))
	_apply_marker_kind(kind)
	_marker.position = screen_position - marker_size * 0.5
	_marker.visible = true


## 相手のHPゲージ。ロックオン中はその相手、していなければ手近な生存中の犯人。
func _update_enemy_gauge() -> void:
	if _enemy_panel == null:
		return
	var target: Node3D = _resolve_enemy_target()
	if target != _enemy_body:
		_bind_enemy(target)
	if _enemy_health == null or _enemy_health.is_downed():
		_enemy_panel.visible = false
		return
	_enemy_panel.visible = visible
	if _enemy_bar != null:
		_enemy_bar.max_value = maxf(_enemy_health.max_hp, 1.0)
		_enemy_bar.value = clampf(_enemy_health.current_hp(), 0.0, _enemy_bar.max_value)


func _resolve_enemy_target() -> Node3D:
	if _lock_on != null and _lock_on.has_method("current_target"):
		var locked := _lock_on.call("current_target") as Node3D
		if locked != null and is_instance_valid(locked) \
				and locked.is_in_group(&"robber"):
			return locked
	if _camera == null:
		return null
	var nearest: Node3D = null
	var nearest_distance: float = enemy_gauge_range
	for node in get_tree().get_nodes_in_group(&"robber"):
		var body := node as Node3D
		if body == null or not is_instance_valid(body):
			continue
		var health := _find_health(body)
		if health == null or health.is_downed():
			continue
		var distance: float = _camera.global_position.distance_to(body.global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = body
	return nearest


func _bind_enemy(target: Node3D) -> void:
	_enemy_body = target
	_enemy_health = _find_health(target) if target != null else null
	if _enemy_name != null and target != null:
		# 表示名は本体が名乗る（HUD 側でクラス分岐しない）。
		_enemy_name.text = String(target.call("display_name")) \
			if target.has_method("display_name") else String(target.name)


func _find_health(body: Node3D) -> Health:
	if body == null:
		return null
	return body.get_node_or_null(^"Health") as Health


func _apply_marker_kind(kind: int) -> void:
	_marker_kind = kind
	match kind:
		LockOn.TargetKind.LIVE_CIVILIAN:
			_marker.text = "! CIVILIAN !"
			_marker.add_theme_color_override(&"font_color", civilian_warning_color)
		LockOn.TargetKind.DOWNED_ROBBER:
			_marker.text = "[ DOWN ]"
			_marker.add_theme_color_override(&"font_color", downed_robber_color)
		_:
			_marker.text = "[ TARGET ]"
			_marker.add_theme_color_override(&"font_color", live_robber_color)


func _hide_marker() -> void:
	if _marker != null:
		_marker.visible = false
	_marker_kind = LockOn.TargetKind.NONE


func _on_act_changed(act: int) -> void:
	visible = act != GameTypes.Act.EPILOGUE
	if not visible:
		_hide_marker()


func _apply_visual_settings() -> void:
	if _status_panel != null:
		_status_panel.position = status_position
		_status_panel.size = status_size
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = panel_color
		panel_style.border_color = accent_color
		panel_style.set_border_width_all(2)
		_status_panel.add_theme_stylebox_override(&"panel", panel_style)
	for label: Label in [_hp_label, _robber_label, _civilian_label]:
		if label != null:
			label.add_theme_color_override(&"font_color", text_color)
			label.add_theme_font_size_override(&"font_size", status_font_size)
	if _hp_label != null:
		_hp_label.add_theme_font_size_override(&"font_size", hp_font_size)
	if _enemy_panel != null:
		var enemy_style := StyleBoxFlat.new()
		enemy_style.bg_color = panel_color
		enemy_style.border_color = accent_color
		enemy_style.set_border_width_all(2)
		_enemy_panel.add_theme_stylebox_override(&"panel", enemy_style)
	if _enemy_name != null:
		_enemy_name.add_theme_color_override(&"font_color", text_color)
		_enemy_name.add_theme_font_size_override(&"font_size", status_font_size)
	if _enemy_bar != null:
		_enemy_bar.custom_minimum_size = enemy_bar_size
		var enemy_background := StyleBoxFlat.new()
		enemy_background.bg_color = hp_background_color
		_enemy_bar.add_theme_stylebox_override(&"background", enemy_background)
		var enemy_fill := StyleBoxFlat.new()
		enemy_fill.bg_color = enemy_fill_color
		_enemy_bar.add_theme_stylebox_override(&"fill", enemy_fill)
	if _hp_bar != null:
		_hp_bar.custom_minimum_size = hp_bar_size
		var background_style := StyleBoxFlat.new()
		background_style.bg_color = hp_background_color
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = hp_fill_color
		_hp_bar.add_theme_stylebox_override(&"background", background_style)
		_hp_bar.add_theme_stylebox_override(&"fill", fill_style)
	if _marker != null:
		_marker.size = marker_size
		_marker.add_theme_font_size_override(&"font_size", marker_font_size)


func hp_display_text() -> String:
	return _hp_label.text if _hp_label != null else ""


func hp_bar_value() -> float:
	return _hp_bar.value if _hp_bar != null else 0.0


func robber_display_text() -> String:
	return _robber_label.text if _robber_label != null else ""


func civilian_display_text() -> String:
	return _civilian_label.text if _civilian_label != null else ""


func marker_is_visible() -> bool:
	return _marker != null and _marker.visible


func displayed_marker_kind() -> int:
	return _marker_kind


func displayed_marker_text() -> String:
	return _marker.text if _marker != null else ""


func displayed_marker_color() -> Color:
	return _marker.get_theme_color(&"font_color") if _marker != null else Color.TRANSPARENT
