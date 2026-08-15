extends LevelRoot

## 冒頭カットシーン未実装中の暫定開始幕。カットシーン実装時は、ここからの
## advance_to() を削除し、カットシーン終了時の notify_prologue_finished() に置き換える。
## インスペクタで PROLOGUE（0）へ戻すと、客が伏せず犯人も撃たない状態になり、
## 格闘だけの手応えを確認できる。
@export var start_act: int = GameTypes.Act.INFILTRATION


func _ready() -> void:
	super._ready()
	if start_act != GameTypes.Act.PROLOGUE:
		GameDirector.advance_to(start_act)
