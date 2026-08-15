extends Node

## すべての行動記録と判定の単一の置き場所。
## 他のノードはグローバルな可変状態を持たない。

## ダウンした相手の記録。エンディング時の死体配置（aftermath）に使う。
class DownedRecord:
	var body: Node3D = null
	var faction: int = GameTypes.Faction.CIVILIAN
	var position: Vector3 = Vector3.ZERO
	var basis: Basis = Basis.IDENTITY
	var lethal: bool = false
	var attacker: Node3D = null

signal civilian_downed(total: int)
signal deviation_changed(level: float)

var civilians_total: int = 0
var civilians_downed: int = 0
var civilians_killed: int = 0
var civilians_downed_by_player: int = 0
var civilians_killed_by_player: int = 0
var civilians_rescued: int = 0
var robbers_total: int = 0
var robbers_downed: int = 0
var robbers_killed: int = 0
var robbers_downed_by_player: int = 0
var robbers_killed_by_player: int = 0
var player_fired_gun: bool = false
var elapsed: float = 0.0

var downed: Array[DownedRecord] = []


func record_down(body: Node3D, faction: int, lethal: bool,
		attacker: Node3D = null) -> void:
	var r := DownedRecord.new()
	r.body = body
	r.faction = faction
	r.position = body.global_position
	r.basis = body.global_transform.basis
	r.lethal = lethal
	r.attacker = attacker
	downed.append(r)
	var by_player := _is_player_attacker(attacker)

	match faction:
		GameTypes.Faction.CIVILIAN:
			civilians_downed += 1
			if by_player:
				civilians_downed_by_player += 1
			if lethal:
				civilians_killed += 1
				if by_player:
					civilians_killed_by_player += 1
			civilian_downed.emit(civilians_downed)
			deviation_changed.emit(deviation_level())
		GameTypes.Faction.ROBBER:
			robbers_downed += 1
			if by_player:
				robbers_downed_by_player += 1
			if lethal:
				robbers_killed += 1
				if by_player:
					robbers_killed_by_player += 1


## 既に記録済みのダウンを、後から致死として更新する。
## 進行判断は持たず、同じ本体の集計を二重に増やさない。
func mark_down_lethal(body: Node3D, attacker: Node3D = null) -> void:
	for r: DownedRecord in downed:
		if r.body != body:
			continue
		if r.lethal:
			return
		r.lethal = true
		r.attacker = attacker
		var by_player := _is_player_attacker(attacker)
		match r.faction:
			GameTypes.Faction.CIVILIAN:
				civilians_killed += 1
				if by_player:
					civilians_killed_by_player += 1
				deviation_changed.emit(deviation_level())
			GameTypes.Faction.ROBBER:
				robbers_killed += 1
				if by_player:
					robbers_killed_by_player += 1
		return


func _is_player_attacker(attacker: Node3D) -> bool:
	return attacker != null and attacker.is_in_group(&"player")


## 0 = 正常, 1 = 警戒, 2 = 敵性。警察AIとHUD配色の両方がこれを参照する。
func police_threat_level() -> int:
	if civilians_killed > 0:
		return 2
	if civilians_downed > 0:
		return 1
	return 0


## HUDの色相シフト量（0.0 - 1.0）。
func deviation_level() -> float:
	if civilians_total == 0:
		return 0.0
	var lethal_weight := float(civilians_killed) * 2.0
	return clampf((float(civilians_downed) + lethal_weight) / float(civilians_total), 0.0, 1.0)


## 上から順に評価する。重み付き合計にしないこと。
func resolve_ending() -> int:
	if civilians_killed > 0:
		return GameTypes.Ending.FAILURE
	if civilians_downed >= 3:
		return GameTypes.Ending.DRIFT
	if robbers_killed == 0 and civilians_downed == 0:
		return GameTypes.Ending.IDEAL
	return GameTypes.Ending.NORMAL


## 全フィールドを初期状態へ戻す。プレイのやり直し時に呼ぶ。
func reset() -> void:
	civilians_total = 0
	civilians_downed = 0
	civilians_killed = 0
	civilians_downed_by_player = 0
	civilians_killed_by_player = 0
	civilians_rescued = 0
	robbers_total = 0
	robbers_downed = 0
	robbers_killed = 0
	robbers_downed_by_player = 0
	robbers_killed_by_player = 0
	player_fired_gun = false
	elapsed = 0.0
	downed = []
