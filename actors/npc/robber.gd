extends CharacterBody3D
class_name Robber

## 犯人の共通挙動（technical-spec §9 / tasks.md 8/17）。
## 役割差（leader / gunner / erratic）は後日 `roles/` で注入する。ここは3体共通の骨格。
##
## 見た目は `Model` の下へ差し込む Mixamo キャラクター（With Skin）。差し替えは
## `model_scene` 1か所で完結する。役割はシルエット（服装）で見分ける前提とし、
## 色でステートを塗り分けない（重なると読めなくなる）。見た目に出す色は
## 被弾フラッシュだけで、ModelTint が overlay に白を短く重ねる。
##
## 攻撃判定の窓はこのスクリプトのタイマーで開閉し、クリップ長をそのタイマーに
## 合わせて再生する（速度スケール）。主人公（§6.3）の Call Method Track 方式へ
## 揃えるのは、犯人の攻撃クリップを専用にベイクしてからにする。
##
## 向きの規約: 犯人は本体（CharacterBody3D）を回し、前方は Godot 標準の -Z。
## 主人公は VRM の都合で Model ノードの +Z が前方であり、そちらとは規約が異なる。

## GUARD は DOWNED の手前に足す。役割スクリプトが `State.DOWNED + 1` を
## 自分専用ステート（SHIELD / COVER）の番号として使っているため、末尾に足すと衝突する。
enum State { PATROL, ALERT, CHASE, ATTACK, STAGGERED, GUARD, DOWNED }

## 追跡対象を探すグループ名。プレイヤーが自分を登録している。
@export var target_group: StringName = &"player"

@export_group("Movement")
## 巡回時の移動速度（m/s）。
@export var patrol_speed: float = 1.4
## 追跡時の移動速度（m/s）。プレイヤー（4.5）より遅くし、逃げれば振り切れるようにする。
@export var chase_speed: float = 3.2
## 向き直りの補間速さ（lerp 係数）。
@export var rotation_speed: float = 8.0
## 巡回する地点。空なら初期位置で待機する。`Marker3D` を並べて指定する。
@export var patrol_points: Array[NodePath] = []
## 巡回地点に到達したとみなす距離（m）。
@export var patrol_arrive_distance: float = 0.6
## 巡回地点で立ち止まる秒数。
@export var patrol_wait: float = 1.5

@export_group("Perception")
## 視認距離（m）。
@export var sight_range: float = 12.0
## 視野角（度、全角）。この外は見えない。
@export var sight_fov_deg: float = 110.0
## 視野角に関係なく気づく距離（m）。背後に張り付かれても反応する。
@export var close_notice_range: float = 2.5
## 見失ってから巡回へ戻るまでの秒数。
@export var lose_sight_duration: float = 4.0
## 目の高さ（m）。視線判定の始点。
@export var eye_height: float = 1.5

@export_group("Combat")
## 攻撃を始める距離（m）。
@export var attack_range: float = 1.7
## 攻撃を中断せず追撃を続ける距離（m）。attack_range より少し広く取る。
@export var attack_keep_range: float = 2.4
## 予備動作の秒数（プレイヤーが見てから避けられる長さ）。
@export var attack_telegraph: float = 0.45
## 判定を開いている秒数。
@export var attack_active: float = 0.18
## 硬直の秒数。
@export var attack_recovery: float = 0.35
## 次の攻撃までの間隔（秒）。
@export var attack_cooldown: float = 0.8
## 攻撃の踏み込み初速（m/s）。
@export var attack_lunge_speed: float = 2.2
## 与ダメージ。
@export var attack_damage: float = 12.0
## 与ノックバック強度。
@export var attack_knockback: float = 3.0

@export_group("Reaction")
## 被弾でよろけている秒数。
@export var stagger_duration: float = 0.45
## のけぞり耐性。1回の被弾ごとに必ずのけぞると、殴り始めた側が一方的に固め続けられ、
## 攻防が成立しない（実測: 1対1で犯人がのけぞりに費やす時間が全体の 58%）。
## 短時間に受けた累計ダメージがこの値を超えたときだけ STAGGERED へ落とす。
## 0 以下にすると従来どおり毎回のけぞる。
@export var poise: float = 35.0
## のけぞり耐性の回復量（毎秒）。殴る手を止めれば体勢が立て直る。
@export var poise_recovery: float = 25.0
## 足を止めるときの減速度（m/s²）。攻撃の予備動作・硬直・よろけで使う。
@export var stop_decel: float = 20.0
## ノックバックの初速（m/s）。
@export var knockback_speed: float = 3.0
## ノックバックが減衰しきるまでの秒数。
@export var knockback_decay: float = 0.25
## 被弾フラッシュの色と持続秒数。
@export var flash_color: Color = Color(1, 1, 1, 1)
@export var flash_duration: float = 0.08
## ダウン時に倒れる角度（度）と所要秒数。ラグドールは使わない（tasks.md）。
@export var fall_angle_deg: float = 85.0
@export var fall_duration: float = 0.4

@export_group("Guard")
## ガードと反撃。殴られっぱなしだと格闘にならないので、耐えた直後に構えて、
## 受け止めたら反撃する。回り込めば正面扇形の外から通る。
@export var guard_enabled: bool = true
## 近接を防ぐ正面扇形の全角（度）。これより外から殴られたガードは成立しない。
@export var guard_arc_deg: float = 140.0
## 構えている秒数。
@export var guard_duration: float = 1.1
## ガードを解いてから次に構えるまでの秒数。
@export var guard_cooldown: float = 1.8
## のけぞらずに耐えた被弾1回につき、構えに入る確率。
@export_range(0.0, 1.0) var guard_chance: float = 0.7
## この回数を受け止めたら、時間を待たずに反撃へ移る。
@export var counter_after_blocks: int = 2
## 受け止めたあとに反撃する確率。
@export_range(0.0, 1.0) var counter_chance: float = 0.8
## 反撃の予備動作（秒）。通常の attack_telegraph より短く、割り込みにくい。
@export var counter_telegraph: float = 0.18
## ガード中の向き直りの速さ。遅くして側面へ回り込む余地を残す。
@export var guard_face_speed: float = 2.5

@export_group("Appearance")
## 見た目。`Model` の下へ差し込むキャラクターのシーン（Mixamo の FBX）。
## 差し替えはここ1か所で完結させる（technical-spec §9）。
@export var model_scene: PackedScene
## 主人公の VRM（MToon）へ寄せるため、写真テクスチャの陰影をトゥーンへ置き換える。
## 切ると Mixamo 本来の見た目に戻る。
@export var toon_skin: bool = true
## ステートの記録用の色。**描画には使わない**（_refresh_tint 参照）。
## 役割スクリプトが `color_idle` を上書きして役割を識別する慣習も残している。
@export var color_idle: Color = Color(0.42, 0.24, 0.26)
@export var color_alert: Color = Color(0.72, 0.52, 0.18)
@export var color_telegraph: Color = Color(0.85, 0.18, 0.16)
## 被弾フラッシュのピーク時の濃さ。
@export_range(0.0, 1.0) var flash_tint_alpha: float = 0.85

@export_group("Nodes")
@export var model_path: NodePath = ^"Model"
@export var animator_path: NodePath = ^"Animator"
@export var health_path: NodePath = ^"Health"
@export var hurtbox_path: NodePath = ^"Hurtbox"
@export var hitbox_path: NodePath = ^"MeleeHitbox"
@export var agent_path: NodePath = ^"NavigationAgent3D"
@export var state_machine_path: NodePath = ^"StateMachine"
@export_group("")

## 現在ステートが変わった（デバッグ表示・テスト用）。
signal state_entered(state: int)

var _model: Node3D = null
var _animator: NpcAnimator = null
var _tint: ModelTint = ModelTint.new()
var _health: Health = null
var _hurtbox: Area3D = null
var _hitbox: Hitbox = null
var _agent: NavigationAgent3D = null
var _sm: StateMachine = null

var _target: Node3D = null
## 現在のステート色。描画には使わず、テストとデバッグの識別に使う。
var _state_color: Color = Color.WHITE
var _flash_tween: Tween = null
var _patrol_index: int = 0
var _patrol_wait_left: float = 0.0
var _lost_sight_for: float = 0.0
var _cooldown_left: float = 0.0
var _hitbox_open: bool = false
var _engaged_notified: bool = false

var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0
## 直近に蓄積した被弾ダメージ。poise を超えるとのけぞる。
var _poise_damage: float = 0.0
## ガードの再使用待ち（秒）。
var _guard_cooldown_left: float = 0.0
## 現在の構えで受け止めた回数。
var _guard_blocks: int = 0
## 次の ATTACK を反撃（短い予備動作）にする。
var _counter_pending: bool = false
## のけぞり判定に使う、前回の被弾時点の HP。
var _hp_before_hit: float = 0.0
## Hurtbox から通知された、最後に自分へ攻撃を成立させた本体。
var _last_attacker: Node3D = null


func _ready() -> void:
	_model = get_node_or_null(model_path) as Node3D
	_health = get_node_or_null(health_path) as Health
	_hurtbox = get_node_or_null(hurtbox_path) as Area3D
	_hitbox = get_node_or_null(hitbox_path) as Hitbox
	_agent = get_node_or_null(agent_path) as NavigationAgent3D
	_sm = get_node_or_null(state_machine_path) as StateMachine
	RunState.robbers_total += 1

	if _model != null and model_scene != null:
		_model.add_child(model_scene.instantiate())
	if toon_skin:
		ToonSkin.apply(_model)
	_tint.setup(_model)
	_state_color = color_idle
	_refresh_tint(0.0)
	# Animator は Model を読むので、キャラクターを差し込んだ後に初期化させる。
	_animator = get_node_or_null(animator_path) as NpcAnimator
	if _animator != null:
		_animator.setup()

	if _health != null:
		_hp_before_hit = _health.max_hp
		_health.staggered.connect(_on_staggered)
		_health.downed.connect(_on_downed)
		_health.finished.connect(_on_finished)

	if _sm == null:
		push_warning("robber: StateMachine が無い")
		return
	_sm.add_state(State.PATROL, &"patrol", _enter_patrol, _physics_patrol)
	_sm.add_state(State.ALERT, &"alert", _enter_alert, _physics_alert)
	_sm.add_state(State.CHASE, &"chase", _enter_chase, _physics_chase)
	_sm.add_state(State.ATTACK, &"attack", _enter_attack, _physics_attack, _exit_attack)
	_sm.add_state(State.STAGGERED, &"staggered", _enter_staggered, _physics_staggered)
	_sm.add_state(State.GUARD, &"guard", _enter_guard, _physics_guard, _exit_guard)
	_sm.add_state(State.DOWNED, &"downed", _enter_downed)
	_sm.state_changed.connect(func(_from: int, to: int) -> void: state_entered.emit(to))
	# ナビゲーションマップの初期化は次フレーム以降のため、1 フレーム待ってから開始する。
	call_deferred("_start_state_machine")


func _start_state_machine() -> void:
	_resolve_target()
	_sm.start(State.PATROL)


func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _poise_damage > 0.0:
		_poise_damage = maxf(_poise_damage - poise_recovery * delta, 0.0)
	if _guard_cooldown_left > 0.0:
		_guard_cooldown_left = maxf(_guard_cooldown_left - delta, 0.0)

	if _sm != null:
		_sm.physics_update(delta)

	# ノックバックは全ステートに優先して水平速度を上書きする。
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
		_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO,
			(knockback_speed / knockback_decay) * delta)

	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_update_locomotion_animation()


## ロコモーションだけを毎フレーム更新する。攻撃・のけぞり・ダウンの単発クリップは
## 各ステートの進入時に一度だけ再生する。
func _update_locomotion_animation() -> void:
	if _animator == null or not _animator.is_active() or _sm == null:
		return
	match _sm.current():
		State.PATROL, State.ALERT, State.CHASE:
			_animator.drive_locomotion(Vector2(velocity.x, velocity.z).length())
		State.GUARD:
			# 待機クリップはボクシングの構え。そのままガードの絵になる。
			_animator.play(NpcAnimator.Clip.IDLE)


## HUD のゲージに出す表示名。役割スクリプトが上書きする。
## HUD がクラス名で分岐すると役割を増やすたびに UI を触ることになるため、
## 名乗るのは本体側の責任にする。
func display_name() -> String:
	return "犯人"


## 現在のステート（テスト・デバッグ用）。
func current_state() -> int:
	return _sm.current() if _sm != null else State.PATROL


# --- PATROL ---------------------------------------------------------------

func _enter_patrol() -> void:
	_set_color(color_idle)
	_lost_sight_for = 0.0
	_patrol_wait_left = 0.0
	_on_patrol_entered()


func _physics_patrol(delta: float) -> void:
	if _sees_target():
		_sm.transition_to(State.ALERT)
		return

	if patrol_points.is_empty():
		# 巡回地点が無ければ初期位置で待機する。
		_stop_horizontal(delta)
		return

	var point := _patrol_point(_patrol_index)
	if point == null:
		_stop_horizontal(delta)
		return

	if _patrol_wait_left > 0.0:
		_patrol_wait_left -= delta
		_stop_horizontal(delta)
		return

	var flat_distance := _flat_distance_to(point.global_position)
	if flat_distance <= patrol_arrive_distance:
		_patrol_wait_left = _next_patrol_wait()
		_patrol_index = _next_patrol_index(_patrol_index)
		_stop_horizontal(delta)
		return

	_navigate_toward(point.global_position, patrol_speed, delta)


# --- ALERT ----------------------------------------------------------------

func _enter_alert() -> void:
	_set_color(color_alert)
	# 幕の進行を促す（INFILTRATION -> ENGAGEMENT）。1体が気づけば十分。
	if not _engaged_notified:
		_engaged_notified = true
		GameDirector.notify_robber_engaged()


func _physics_alert(delta: float) -> void:
	_stop_horizontal(delta)
	if _target != null:
		_face_position(_target.global_position, delta)
	# 気づいてから飛びかかるまでの一拍。予備動作として見せる。
	if _sm.time_in_state() >= 0.4:
		_transition_after_alert()


# --- CHASE ----------------------------------------------------------------

func _enter_chase() -> void:
	_set_color(color_alert)
	_lost_sight_for = 0.0
	_on_chase_entered()


func _physics_chase(delta: float) -> void:
	if _target == null:
		_resolve_target()
		if _target == null:
			_sm.transition_to(State.PATROL)
			return

	if _sees_target():
		_lost_sight_for = 0.0
	else:
		_lost_sight_for += delta
		if _lost_sight_for >= lose_sight_duration:
			_sm.transition_to(State.PATROL)
			return

	var distance := _flat_distance_to(_target.global_position)
	if distance <= attack_range and _cooldown_left <= 0.0:
		_sm.transition_to(State.ATTACK)
		return

	if _cooldown_left > 0.0 and distance <= attack_keep_range:
		# 射程付近でクールダウン中。これ以上踏み込まず間合いを保つ。
		# クールダウン明けは踏み込ませる（ここで距離を見ないと attack_range まで
		# 詰めずに attack_keep_range で足を止め、永久に殴ってこなくなる）。
		_stop_horizontal(delta)
		_face_position(_target.global_position, delta)
		return

	_navigate_toward(_target.global_position, chase_speed, delta)


# --- ATTACK ---------------------------------------------------------------

func _enter_attack() -> void:
	_set_color(color_telegraph)
	_hitbox_open = false
	_stop_horizontal_immediate()
	# クリップ長を予備動作＋判定＋硬直に合わせ、当たる瞬間と絵をずらさない。
	if _animator != null and _animator.is_active():
		var total: float = _current_telegraph() + attack_active + attack_recovery
		var length: float = _animator.clip_length(NpcAnimator.Clip.ATTACK)
		var scale: float = length / total if total > 0.0 and length > 0.0 else 1.0
		_animator.play(NpcAnimator.Clip.ATTACK, 0.05, scale, true)


## 反撃中は予備動作を短くする。ガードで受け止めた直後の一撃なので、
## 通常の振りかぶりだと殴り返される前に潰される。
func _current_telegraph() -> float:
	return counter_telegraph if _counter_pending else attack_telegraph


func _physics_attack(delta: float) -> void:
	var t := _sm.time_in_state()
	# export の attack_telegraph を隠さないよう別名にする（反撃では短くなる）。
	var telegraph := _current_telegraph()
	var active_end := telegraph + attack_active
	var recovery_end := active_end + attack_recovery

	if t < telegraph:
		# 予備動作。向きだけ合わせて踏みとどまる。
		_stop_horizontal(delta)
		if _target != null:
			_face_position(_target.global_position, delta)
		return

	if t < active_end:
		# 判定窓。開くのは1回だけ（Hitbox 側が二重ヒットを防ぐ）。
		if not _hitbox_open:
			_hitbox_open = true
			_set_color(color_alert)
			_open_hitbox()
			_lunge_forward()
		return

	if _hitbox_open:
		_close_hitbox()

	if t < recovery_end:
		# 硬直。次の攻撃までここで足を止める。
		_stop_horizontal(delta)
		return

	_cooldown_left = attack_cooldown
	_sm.transition_to(State.CHASE)


func _exit_attack() -> void:
	_close_hitbox()
	_counter_pending = false


# --- STAGGERED ------------------------------------------------------------

func _enter_staggered() -> void:
	_close_hitbox()
	_set_color(color_alert)
	if _animator != null and _animator.is_active():
		# ノックバックを伴う被弾は大きくのけぞらせる。連続被弾では頭から出し直す。
		var clip: int = NpcAnimator.Clip.HIT
		if _knockback_timer > 0.0 and _animator.has_clip(NpcAnimator.Clip.KNOCKBACK):
			clip = NpcAnimator.Clip.KNOCKBACK
		_animator.play(clip, 0.05, 1.0, true)


func _physics_staggered(delta: float) -> void:
	# のけぞり中は自走しない（ノックバックは _physics_process 側が上書きする）。
	_stop_horizontal(delta)
	if _sm.time_in_state() >= stagger_duration:
		# 殴られた時点でプレイヤーの位置は分かっている。追跡へ戻す。
		_resolve_target()
		_sm.transition_to(State.CHASE)


# --- GUARD ----------------------------------------------------------------

## Hitbox の汎用方向防御フック。構えている間だけ、正面扇形からの近接を弾く。
## 役割スクリプト（リーダーの盾）は override して super() と OR で合成する。
func blocks_hit_from(attacker_position: Vector3) -> bool:
	if _sm == null or _sm.current() != State.GUARD:
		return false
	if not _is_in_front_arc(attacker_position, guard_arc_deg):
		return false
	_guard_blocks += 1
	# 受け止めた手応え。ダメージは通っていないので Hurtbox は呼ばれない。
	flash_hit()
	if _guard_blocks >= counter_after_blocks:
		# 待たずに反撃へ。ガードで固まり続けると、今度は殴れないだけの置物になる。
		_leave_guard_to_counter()
	return true


func _enter_guard() -> void:
	_close_hitbox()
	_guard_blocks = 0
	_stop_horizontal_immediate()


func _physics_guard(delta: float) -> void:
	_stop_horizontal(delta)
	if _target != null:
		_face_position_at_speed(_target.global_position, delta, guard_face_speed)
	if _sm.time_in_state() < guard_duration:
		return
	if _guard_blocks > 0:
		_leave_guard_to_counter()
		return
	# 空振りのガード。追跡へ戻す。
	_sm.transition_to(State.CHASE)


func _exit_guard() -> void:
	_guard_cooldown_left = guard_cooldown


## 受け止めたあとの行き先を決める。反撃するか、追跡へ戻るか。
func _leave_guard_to_counter() -> void:
	if _sm == null or _sm.current() != State.GUARD:
		return
	if randf() < counter_chance and _target != null \
			and _flat_distance_to(_target.global_position) <= attack_keep_range:
		_counter_pending = true
		_sm.transition_to(State.ATTACK)
		return
	_sm.transition_to(State.CHASE)


## 被弾を耐えたときに構えるか決める。
func _try_enter_guard() -> void:
	if not guard_enabled or _sm == null or _guard_cooldown_left > 0.0:
		return
	match _sm.current():
		State.ALERT, State.CHASE, State.ATTACK:
			pass
		_:
			return
	if _target == null or _flat_distance_to(_target.global_position) > attack_keep_range:
		return
	if randf() >= guard_chance:
		return
	_sm.transition_to(State.GUARD)


## 正面 arc_deg（全角）の扇形に相手がいるか。
func _is_in_front_arc(point: Vector3, arc_deg: float) -> bool:
	var toward := point - global_position
	toward.y = 0.0
	if toward.length_squared() <= 0.0:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var half_arc := deg_to_rad(clampf(arc_deg, 0.0, 360.0) * 0.5)
	return forward.dot(toward.normalized()) >= cos(half_arc)


# --- DOWNED ---------------------------------------------------------------

func _enter_downed() -> void:
	_close_hitbox()
	_stop_horizontal_immediate()
	# 予備動作の色のまま倒れないよう、ステート色を通常へ戻す。
	_set_color(color_idle)
	# Hurtbox 自身が他の Area を監視する必要はないため monitoring は切る一方、
	# プレイヤーの Hitbox 側から検出できるよう monitorable だけを残す。Health は
	# ダウン中の通常 take_hit() を弾き、Hurtbox も再ロック済みの追い打ちだけを
	# 振り分けるため、他人の通常攻撃がダメージへ戻ることはない。
	# ダウンは物理信号中に確定するため、変更は物理ステップ末尾へ遅延する。
	if _hurtbox != null:
		# 本体の固定ダウン回転に巻き込まれて判定まで床下へ倒れると、立ったままの
		# 近接 Hitbox が届かない。現在のワールド姿勢を保って本体から独立させ、
		# 追い打ち用の検出体積だけは従来の高さに残す。
		var hurtbox_transform: Transform3D = _hurtbox.global_transform
		_hurtbox.top_level = true
		_hurtbox.global_transform = hurtbox_transform
		_hurtbox.set_deferred("monitoring", false)
		_hurtbox.set_deferred("monitorable", true)
	# robber レイヤーは LockOnDetector が倒れた本体を狙い直すために残す。
	set_collision_layer_value(3, true)
	if _animator != null and _animator.is_active():
		# 倒れ込みはクリップが持つ。本体まで倒すと二重に倒れるので回さない。
		_animator.play(NpcAnimator.Clip.DOWN, 0.1, 1.0, true)
		return
	# プリミティブ表示のままの個体は従来どおり固定ポーズで倒す
	# （ラグドールはコンテスト版では扱わない）。
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", deg_to_rad(fall_angle_deg), fall_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# --- Health からの通知 -----------------------------------------------------

## Health からのよろけ通知。ここで「のけぞらせるか」を決める。
## Health は被弾のたびに発火するだけで、耐えるかどうかは受け手の判断にする。
func _on_staggered() -> void:
	if _sm == null or _sm.current() == State.DOWNED:
		return
	# Health は信号にダメージ量を載せないので、HP の差分から取る。
	var hp_now: float = _health.current_hp() if _health != null else 0.0
	var taken: float = maxf(_hp_before_hit - hp_now, 0.0)
	_hp_before_hit = hp_now

	if poise > 0.0:
		_poise_damage += taken
		if _poise_damage < poise:
			# 耐える。ノックバックと被弾フラッシュだけ出て、行動は中断されない。
			# 耐えた直後は構えに入る余地を作る（殴られっぱなしにしない）。
			_try_enter_guard()
			return
		_poise_damage = 0.0
	# 連続被弾で滞在時間を延ばす（force=true で再進入）。
	_sm.transition_to(State.STAGGERED, true)


func _on_downed(lethal: bool) -> void:
	if _sm == null or _sm.current() == State.DOWNED:
		return
	RunState.record_down(self, GameTypes.Faction.ROBBER, lethal, _last_attacker)
	# 犯人が1体ダウンしても幕は進む（technical-spec §5）。
	if not _engaged_notified:
		_engaged_notified = true
		GameDirector.notify_robber_engaged()
	# 全滅という事実は RunState の集計から判定するが、幕を進める判断と通知は
	# 犯人側が担う。RunState.record_down() に進行ロジックを持ち込まない。
	if RunState.robbers_total > 0 and RunState.robbers_downed >= RunState.robbers_total:
		GameDirector.notify_all_robbers_downed()
	_sm.transition_to(State.DOWNED)


func _on_finished(attacker: Node3D) -> void:
	_last_attacker = attacker
	RunState.mark_down_lethal(self, _last_attacker)


# --- Hurtbox からの呼び出し -------------------------------------------------

## LockOnDetector が役割型へ依存せず、追い打ち可能な対象か問い合わせるAPI。
func can_receive_finish_hit() -> bool:
	return _health != null and _health.is_downed()


## Hurtbox から具体的な攻撃種別に依存せず、最後の加害者を受け取る。
func record_attacker(attacker: Node3D) -> void:
	_last_attacker = attacker

## direction は攻撃者→自分の水平方向。
func receive_knockback(direction: Vector3, strength: float) -> void:
	if _sm != null and _sm.current() == State.DOWNED:
		return
	if strength <= 0.0:
		return
	var d := direction
	d.y = 0.0
	if d.length() < 0.001:
		return
	_knockback_vel = d.normalized() * knockback_speed * clampf(strength / 5.0, 0.5, 2.0)
	_knockback_timer = knockback_decay


## 被弾フラッシュ。白を重ねて 0 へ抜く。
func flash_hit() -> void:
	if not _tint.is_ready():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(_apply_flash_mix, 1.0, 0.0, flash_duration)


func _apply_flash_mix(amount: float) -> void:
	_refresh_tint(amount)


## 被せ色を更新する。**被弾フラッシュのときだけ**白を重ねる。
## ステートを色で塗り分けると、複数の色（役割・警戒・予備動作・ダウン）が
## 重なって何を示しているのか読めなくなるため、色による状態表示はやめた。
## 警戒と予備動作はアニメーション（振り向き・追跡・攻撃の振りかぶり）で伝える。
func _refresh_tint(flash_amount: float) -> void:
	if not _tint.is_ready():
		return
	_tint.apply(flash_color, flash_amount * flash_tint_alpha)


# --- 内部ヘルパ -------------------------------------------------------------

func _resolve_target() -> void:
	_target = get_tree().get_first_node_in_group(target_group) as Node3D


## 視界内にプレイヤーがいるか。距離・視野角・遮蔽の3段で判定する。
func _sees_target() -> bool:
	if _target == null:
		_resolve_target()
		if _target == null:
			return false
	var to := _target.global_position - global_position
	var flat := Vector2(to.x, to.z)
	var distance := flat.length()
	if distance > sight_range:
		return false
	if distance > close_notice_range:
		var forward := -global_transform.basis.z
		var angle := absf(rad_to_deg(Vector2(forward.x, forward.z).angle_to(flat)))
		if angle > sight_fov_deg * 0.5:
			return false
	return _has_line_of_sight()


## 目の高さから相手の胸へレイを飛ばし、world レイヤー（1）に遮られていないか見る。
func _has_line_of_sight() -> bool:
	if _target == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * eye_height
	var to := _target.global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := space.intersect_ray(query)
	return hit.is_empty()


## NavigationAgent3D の経路に沿って進む。マップが未生成の場合は直線で寄る
## （ベイク前のステージでも動作確認できるようにするための保険）。
func _navigate_toward(destination: Vector3, speed: float, delta: float) -> void:
	var direction := Vector3.ZERO
	if _agent != null and _navigation_ready():
		_agent.target_position = destination
		var next := _agent.get_next_path_position()
		direction = next - global_position
	if direction.length() < 0.05:
		direction = destination - global_position
	direction.y = 0.0
	if direction.length() < 0.05:
		_stop_horizontal(delta)
		return
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_face_direction(direction, delta)


func _navigation_ready() -> bool:
	if _agent == null:
		return false
	var map := _agent.get_navigation_map()
	if not map.is_valid():
		return false
	return NavigationServer3D.map_get_iteration_id(map) > 0


func _flat_distance_to(point: Vector3) -> float:
	var d := point - global_position
	return Vector2(d.x, d.z).length()


func _patrol_point(index: int) -> Node3D:
	if index < 0 or index >= patrol_points.size():
		return null
	return get_node_or_null(patrol_points[index]) as Node3D


## 役割スクリプト向けの巡回拡張点。共通型は従来どおり順番に巡回する。
func _on_patrol_entered() -> void:
	pass


func _next_patrol_index(current_index: int) -> int:
	if patrol_points.is_empty():
		return 0
	return (current_index + 1) % patrol_points.size()


func _next_patrol_wait() -> float:
	return patrol_wait


## 役割スクリプト向けの ALERT 遷移先拡張点。共通型は従来どおり CHASE へ進む。
func _transition_after_alert() -> void:
	_sm.transition_to(State.CHASE)


## ATTACK / STAGGERED 後を含む CHASE 再進入時の役割拡張点。
func _on_chase_entered() -> void:
	pass


func _face_position(point: Vector3, delta: float) -> void:
	_face_position_at_speed(point, delta, rotation_speed)


## 役割ステートだけ向き直り速度を差し替えるための拡張点。
## 共通ステートは _face_position() を通して従来の rotation_speed を使う。
func _face_position_at_speed(point: Vector3, delta: float, face_speed: float) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	_face_direction_at_speed(d.normalized(), delta, face_speed)


## 前方は -Z。atan2(x, z) の結果に π を足すと -Z 向きのヨーになる。
func _face_direction(direction: Vector3, delta: float) -> void:
	_face_direction_at_speed(direction, delta, rotation_speed)


func _face_direction_at_speed(direction: Vector3, delta: float, face_speed: float) -> void:
	var target_yaw := atan2(direction.x, direction.z) + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, face_speed * delta)


func _stop_horizontal(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z)
	horizontal = horizontal.move_toward(Vector2.ZERO, stop_decel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


func _stop_horizontal_immediate() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _lunge_forward() -> void:
	var forward := -global_transform.basis.z
	velocity.x = forward.x * attack_lunge_speed
	velocity.z = forward.z * attack_lunge_speed


func _open_hitbox() -> void:
	if _hitbox == null:
		return
	_hitbox.configure(attack_damage, attack_knockback, false)
	_hitbox.activate()


## 判定を閉じる。よろけ・ダウンは被弾処理（信号）の最中に確定するため、
## 常に deferred 版を使う（判定自体は即座に閉じる）。
func _close_hitbox() -> void:
	_hitbox_open = false
	if _hitbox != null:
		_hitbox.deactivate_deferred()


## ステート色を記録する。描画には使わない（_refresh_tint 参照）。役割スクリプトと
## テストが現在ステートの識別に読むため、値の管理だけ従来どおり残している。
func _set_color(color: Color) -> void:
	_state_color = color
