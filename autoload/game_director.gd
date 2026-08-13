extends Node

## 幕（Act）の進行を管理する。各幕への移行はシグナルで通知し、NPC側が購読する。
## 移行トリガはゲームロジック側（カットシーン終了・犯人ダウン等）から
## advance_to() / notify_* API を呼んで起こす。ここでは可変状態を持たない
## （current_act は進行位置であり、行動記録は RunState が持つ）。
##
## 移行条件（technical-spec.md §5）:
##   PROLOGUE      -> INFILTRATION : 冒頭カットシーン終了
##   INFILTRATION  -> ENGAGEMENT   : 犯人のいずれかが ALERT、または犯人1体がダウン
##   ENGAGEMENT    -> BREACH       : ENGAGEMENT 開始から breach_delay 秒経過。
##                                   RunState.player_fired_gun が true なら 40% 短縮
##   BREACH        -> EPILOGUE     : 犯人3体すべてがダウン
##
## 本日（8/14）実装するのは幕移行の骨組みと、時間系（ENGAGEMENT -> BREACH）の
## タイマー。犯人・警察の実体は未実装のため、犯人ダウン数などの条件は
## 外部からの notify_* 呼び出しで駆動する形にしてある。

signal act_changed(act: int)

## ENGAGEMENT 開始から BREACH までの基準待機秒数。
@export var breach_delay: float = 90.0
## player_fired_gun が true のときに breach_delay へ掛ける短縮係数（40% 短縮）。
@export var breach_gun_shorten: float = 0.6

var current_act: int = GameTypes.Act.PROLOGUE

var _breach_timer: SceneTreeTimer = null
## タイマーの世代番号。reset() や再タイマーで加算し、古いコールバックを無視する。
## SceneTreeTimer は null 代入では止まらず timeout を送出するため、世代で識別する。
var _breach_timer_generation: int = 0


## 任意の幕へ直接移行する。同じ幕への再移行は無視する。
func advance_to(act: int) -> void:
	if act == current_act:
		return
	current_act = act
	act_changed.emit(current_act)
	if act == GameTypes.Act.ENGAGEMENT:
		_start_breach_timer()


## 冒頭カットシーン終了。PROLOGUE のときのみ INFILTRATION へ進む。
func notify_prologue_finished() -> void:
	if current_act == GameTypes.Act.PROLOGUE:
		advance_to(GameTypes.Act.INFILTRATION)


## 犯人が ALERT になった、または犯人1体がダウンした。
## INFILTRATION のときのみ ENGAGEMENT へ進む。
func notify_robber_engaged() -> void:
	if current_act == GameTypes.Act.INFILTRATION:
		advance_to(GameTypes.Act.ENGAGEMENT)


## 犯人が全滅した。BREACH のときのみ EPILOGUE へ進む。
func notify_all_robbers_downed() -> void:
	if current_act == GameTypes.Act.BREACH:
		advance_to(GameTypes.Act.EPILOGUE)


## ENGAGEMENT 開始時に BREACH までのタイマーを張る。
## player_fired_gun が立っていれば待機時間を短縮する。
func _start_breach_timer() -> void:
	_breach_timer_generation += 1
	var generation := _breach_timer_generation
	var delay := breach_delay
	if RunState.player_fired_gun:
		delay *= breach_gun_shorten
	_breach_timer = get_tree().create_timer(delay)
	# SceneTreeTimer は停止できないため、発火時に世代が一致する場合のみ処理する。
	_breach_timer.timeout.connect(func() -> void:
		if generation == _breach_timer_generation:
			_on_breach_timer_timeout())


func _on_breach_timer_timeout() -> void:
	_breach_timer = null
	if current_act == GameTypes.Act.ENGAGEMENT:
		advance_to(GameTypes.Act.BREACH)


## 進行をやり直す。RunState.reset() と併せて呼ぶ。
## 世代番号を進めて、進行中の古い BREACH タイマーのコールバックを無効化する。
func reset() -> void:
	_breach_timer_generation += 1
	_breach_timer = null
	current_act = GameTypes.Act.PROLOGUE
	act_changed.emit(current_act)
