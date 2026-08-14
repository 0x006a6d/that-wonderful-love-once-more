extends Node

## 客の最小実装をヘッドレス検証するシーンハーネス。
##   godot --path . --headless res://tools/test_civilian.tscn

const CIVILIAN_SCENE: PackedScene = preload("res://actors/npc/civilian.tscn")
const CIVILIAN_SCRIPT: Script = preload("res://actors/npc/civilian.gd")
const PLAYER_SCENE: PackedScene = preload("res://actors/player/player.tscn")
const SETTLE_FRAMES: int = 8

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 客 検証開始 ===")
	RunState.reset()
	GameDirector.reset()

	var first: Node3D = _spawn_civilian()
	_assert("_ready() で RunState.civilians_total が増える", RunState.civilians_total == 1)
	_assert("Act.PROLOGUE では IDLE",
		int(first.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.IDLE)

	GameDirector.advance_to(GameTypes.Act.INFILTRATION)
	_assert("INFILTRATION への進行で PRONE に入る",
		int(first.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.PRONE)

	var late: Node3D = _spawn_civilian()
	_assert("INFILTRATION 以降に生成した客は最初から PRONE",
		int(late.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.PRONE)

	var first_health := first.get_node("Health") as Health
	first_health.take_hit(first_health.max_hp)
	var first_hit_staggered: bool = (
		int(first.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.STAGGERED
		and not first_health.is_downed()
	)
	first_health.take_hit(first_health.max_hp)
	var second_hit_staggered: bool = (
		int(first.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.STAGGERED
		and not first_health.is_downed()
	)
	first_health.take_hit(first_health.max_hp)
	_assert("stagger_threshold=3 により1・2回目は STAGGERED、3回目で DOWNED",
		first_hit_staggered and second_hit_staggered
		and int(first.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.DOWNED
		and first_health.is_downed())
	_assert("非致死ダウンで civilians_downed のみ増える",
		RunState.civilians_downed == 1 and RunState.civilians_killed == 0)

	var downed_before := RunState.civilians_downed
	first_health.take_hit(first_health.max_hp, true)
	_assert("ダウン済みの客は追加ダメージを受けず二重記録されない",
		RunState.civilians_downed == downed_before)

	var late_health := late.get_node("Health") as Health
	late_health.take_hit(late_health.max_hp, true)
	late_health.take_hit(late_health.max_hp, true)
	late_health.take_hit(late_health.max_hp, true)
	_assert("lethal=true のダウンで civilians_killed も増える",
		int(late.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.DOWNED
		and RunState.civilians_downed == 2 and RunState.civilians_killed == 1)

	await _clear_test_nodes()
	RunState.reset()
	GameDirector.reset()

	var nonlethal: Node3D = _spawn_civilian()
	var nonlethal_health := nonlethal.get_node("Health") as Health
	var nonlethal_hitbox := _spawn_test_hitbox(nonlethal)
	await _hit_three_times(nonlethal_hitbox, nonlethal, nonlethal_health.max_hp, false)
	_assert("Hitbox 経由の非致死3回で civilians_downed のみ増える",
		int(nonlethal.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.DOWNED
		and nonlethal_health.is_downed()
		and RunState.civilians_downed == 1 and RunState.civilians_killed == 0)

	await _clear_test_nodes()
	RunState.reset()
	GameDirector.reset()

	var lethal: Node3D = _spawn_civilian()
	var lethal_health := lethal.get_node("Health") as Health
	var lethal_hitbox := _spawn_test_hitbox(lethal)
	await _hit_three_times(lethal_hitbox, lethal, lethal_health.max_hp, true)
	_assert("Hitbox 経由の lethal=true 3回で civilians_killed も増える",
		int(lethal.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.DOWNED
		and lethal_health.is_downed()
		and RunState.civilians_downed == 1 and RunState.civilians_killed == 1)

	await _clear_test_nodes()
	RunState.reset()
	GameDirector.reset()

	var player := PLAYER_SCENE.instantiate() as Node3D
	var standing: Node3D = _spawn_civilian()
	add_child(player)
	player.global_position = Vector3.ZERO
	standing.global_position = Vector3(0.0, 0.0, 0.5)
	for _frame: int in range(SETTLE_FRAMES):
		await get_tree().physics_frame

	var standing_health := standing.get_node("Health") as Health
	var melee_hitbox := player.get_node("Model/MeleeHitbox") as Hitbox
	var original_ignore_groups: Array[StringName] = melee_hitbox.ignore_groups.duplicate()
	var melee_damage: float = standing_health.max_hp * 0.25
	var control_hp_before := standing_health.current_hp()
	melee_hitbox.ignore_groups.clear()
	melee_hitbox.configure(melee_damage, 0.0, false)
	melee_hitbox.activate()
	for _frame: int in range(SETTLE_FRAMES):
		await get_tree().physics_frame
	melee_hitbox.deactivate()
	var control_hp_after := standing_health.current_hp()
	print("[positive control] ignore_groups=[]: 客 HP %.1f → %.1f" %
		[control_hp_before, control_hp_after])
	_assert("対照: ignore_groups が空なら客に判定が届き HP が減る（減らなければ配置不正）",
		control_hp_after < control_hp_before)

	melee_hitbox.ignore_groups = original_ignore_groups
	var filtered_hp_before := standing_health.current_hp()
	melee_hitbox.configure(melee_damage, 0.0, false)
	melee_hitbox.activate()
	for _frame: int in range(SETTLE_FRAMES):
		await get_tree().physics_frame
	melee_hitbox.deactivate()
	var filtered_hp_after := standing_health.current_hp()
	_assert("プレイヤーの MeleeHitbox は立っている客を ignore_groups で除外する",
		is_equal_approx(filtered_hp_after, filtered_hp_before))
	# テスト中に変更した設定は、テスト用インスタンスでも終了時に明示的に元へ戻す。
	melee_hitbox.ignore_groups = original_ignore_groups

	GameDirector.advance_to(GameTypes.Act.INFILTRATION)
	# positive control の被弾で入った STAGGERED が終わり、PRONE へ戻るまで待つ。
	for _frame: int in range(SETTLE_FRAMES * 4):
		await get_tree().physics_frame
	var civilian_shape := standing.get_node("Hurtbox/CollisionShape3D") as CollisionShape3D
	var melee_shape := player.get_node("Model/MeleeHitbox/CollisionShape3D") as CollisionShape3D
	var hurtbox_top := _capsule_top_relative(civilian_shape, standing)
	var melee_bottom := _sphere_bottom_relative(melee_shape, player)
	print("[height] PRONE Hurtbox 上端=%.3f m / MeleeHitbox 下端=%.3f m（各本体原点基準）" %
		[hurtbox_top, melee_bottom])
	_assert("PRONE の Hurtbox 上端は MeleeHitbox 下端より低い",
		int(standing.call("current_state")) == CIVILIAN_SCRIPT.CivilianState.PRONE
		and hurtbox_top < melee_bottom)

	await _clear_test_nodes()
	RunState.reset()
	GameDirector.reset()
	_finish()


func _spawn_civilian() -> Node3D:
	var civilian := CIVILIAN_SCENE.instantiate() as Node3D
	add_child(civilian)
	return civilian


func _spawn_test_hitbox(target: Node3D) -> Hitbox:
	var source_body := Node3D.new()
	source_body.name = "TestHitboxSource"
	var hitbox := Hitbox.new()
	hitbox.name = "TestHitbox"
	# 既定の civilian 除外を明示的に外し、将来の銃撃が客へ通る経路を模す。
	hitbox.ignore_groups.clear()
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	collision_shape.shape = sphere
	hitbox.add_child(collision_shape)
	source_body.add_child(hitbox)
	add_child(source_body)
	hitbox.global_position = _hurtbox_center(target)
	return hitbox


func _hit_three_times(hitbox: Hitbox, target: Node3D, damage: float, lethal: bool) -> void:
	for _hit: int in range(3):
		hitbox.global_position = _hurtbox_center(target)
		hitbox.configure(damage, 0.0, lethal)
		hitbox.activate()
		for _frame: int in range(SETTLE_FRAMES):
			await get_tree().physics_frame
		hitbox.deactivate()
		await get_tree().physics_frame


func _hurtbox_center(target: Node3D) -> Vector3:
	var shape := target.get_node("Hurtbox/CollisionShape3D") as CollisionShape3D
	return shape.global_position


func _clear_test_nodes() -> void:
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame


## 水平化した CapsuleShape3D の上端を、本体原点からの相対値で求める。
func _capsule_top_relative(collision_shape: CollisionShape3D, body: Node3D) -> float:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return INF
	var shape_basis := collision_shape.global_transform.basis
	var axis_scale := shape_basis.y.length()
	var radial_scale := maxf(shape_basis.x.length(), shape_basis.z.length())
	var axis := shape_basis.y.normalized()
	var half_line := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
	var world_top := (collision_shape.global_position.y
		+ absf(axis.y) * half_line * axis_scale
		+ capsule.radius * radial_scale)
	return world_top - body.global_position.y


## SphereShape3D の下端を、本体原点からの相対値で求める。
func _sphere_bottom_relative(collision_shape: CollisionShape3D, body: Node3D) -> float:
	var sphere := collision_shape.shape as SphereShape3D
	if sphere == null:
		return -INF
	var shape_scale := collision_shape.global_transform.basis.get_scale()
	var radius_scale := maxf(absf(shape_scale.x), maxf(absf(shape_scale.y), absf(shape_scale.z)))
	var world_bottom := collision_shape.global_position.y - sphere.radius * radius_scale
	return world_bottom - body.global_position.y


func _assert(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[PASS] %s" % label)
	else:
		_fail += 1
		print("[FAIL] %s" % label)


func _finish() -> void:
	print("=== 結果: PASS=%d FAIL=%d ===" % [_pass, _fail])
	print("ALL PASS" if _fail == 0 else "FAILED")
	get_tree().quit(0 if _fail == 0 else 1)
