extends RefCounted

## 近接コンボの構造データ。
## 各ノードは再生する技と、入力から次ノードへの遷移だけを持つ。
## ルートを変更するときは ROOTS / NODES のみを編集する。

const INPUT_PUNCH: StringName = &"punch"
const INPUT_KICK: StringName = &"kick"

const TECHNIQUE_JAB: StringName = &"jab"
const TECHNIQUE_STRAIGHT: StringName = &"straight"
const TECHNIQUE_HOOK: StringName = &"hook"
const TECHNIQUE_KNEE: StringName = &"knee"
const TECHNIQUE_MIDDLE: StringName = &"middle"
const TECHNIQUE_HIGH: StringName = &"high"

const TECHNIQUES: Array[StringName] = [
	TECHNIQUE_JAB,
	TECHNIQUE_STRAIGHT,
	TECHNIQUE_HOOK,
	TECHNIQUE_KNEE,
	TECHNIQUE_MIDDLE,
	TECHNIQUE_HIGH,
]

const TECHNIQUE_STATES: Dictionary = {
	TECHNIQUE_JAB: &"melee_1",
	TECHNIQUE_STRAIGHT: &"melee_2",
	TECHNIQUE_HOOK: &"melee_3",
	TECHNIQUE_KNEE: &"kick_1",
	TECHNIQUE_MIDDLE: &"kick_2",
	TECHNIQUE_HIGH: &"kick_3",
}

const ROOTS: Dictionary = {
	INPUT_PUNCH: &"p_jab",
	INPUT_KICK: &"k_knee",
}

const NODES: Dictionary = {
	# P → 左ジャブ
	&"p_jab": {
		&"technique": TECHNIQUE_JAB,
		&"next": {INPUT_PUNCH: &"pp_straight", INPUT_KICK: &"pk_knee"},
	},
	&"pp_straight": {
		&"technique": TECHNIQUE_STRAIGHT,
		&"next": {INPUT_PUNCH: &"ppp_hook", INPUT_KICK: &"ppk_knee"},
	},
	&"ppp_hook": {&"technique": TECHNIQUE_HOOK, &"next": {}},
	&"ppk_knee": {
		&"technique": TECHNIQUE_KNEE,
		&"next": {INPUT_PUNCH: &"ppkp_hook"},
	},
	&"ppkp_hook": {
		&"technique": TECHNIQUE_HOOK,
		&"next": {INPUT_KICK: &"ppkpk_high"},
	},
	&"ppkpk_high": {&"technique": TECHNIQUE_HIGH, &"next": {}},
	&"pk_knee": {
		&"technique": TECHNIQUE_KNEE,
		&"next": {INPUT_PUNCH: &"pkp_jab", INPUT_KICK: &"pkk_middle"},
	},
	&"pkp_jab": {
		&"technique": TECHNIQUE_JAB,
		&"next": {INPUT_PUNCH: &"pkpp_straight"},
	},
	&"pkpp_straight": {&"technique": TECHNIQUE_STRAIGHT, &"next": {}},
	&"pkk_middle": {
		&"technique": TECHNIQUE_MIDDLE,
		&"next": {INPUT_PUNCH: &"pkkp_hook"},
	},
	&"pkkp_hook": {&"technique": TECHNIQUE_HOOK, &"next": {}},

	# K → 右膝
	&"k_knee": {
		&"technique": TECHNIQUE_KNEE,
		&"next": {INPUT_KICK: &"kk_middle", INPUT_PUNCH: &"kp_hook"},
	},
	&"kk_middle": {
		&"technique": TECHNIQUE_MIDDLE,
		&"next": {INPUT_KICK: &"kkk_high"},
	},
	&"kkk_high": {&"technique": TECHNIQUE_HIGH, &"next": {}},
	&"kp_hook": {
		&"technique": TECHNIQUE_HOOK,
		&"next": {INPUT_PUNCH: &"kpp_straight"},
	},
	&"kpp_straight": {
		&"technique": TECHNIQUE_STRAIGHT,
		&"next": {INPUT_PUNCH: &"kppp_jab"},
	},
	&"kppp_jab": {
		&"technique": TECHNIQUE_JAB,
		&"next": {INPUT_KICK: &"kpppk_knee"},
	},
	&"kpppk_knee": {
		&"technique": TECHNIQUE_KNEE,
		&"next": {INPUT_PUNCH: &"kpppkp_hook"},
	},
	&"kpppkp_hook": {
		&"technique": TECHNIQUE_HOOK,
		&"next": {INPUT_KICK: &"kpppkpk_high"},
	},
	&"kpppkpk_high": {&"technique": TECHNIQUE_HIGH, &"next": {}},
}


static func root_for(input_kind: StringName) -> StringName:
	return StringName(ROOTS.get(input_kind, &""))


static func technique_for(node_id: StringName) -> StringName:
	var node_value: Variant = NODES.get(node_id)
	if not node_value is Dictionary:
		return &""
	var node: Dictionary = node_value
	return StringName(node.get(&"technique", &""))


static func state_for_technique(technique: StringName) -> StringName:
	return StringName(TECHNIQUE_STATES.get(technique, &""))


static func state_for_node(node_id: StringName) -> StringName:
	return state_for_technique(technique_for(node_id))


static func next_node(node_id: StringName, input_kind: StringName) -> StringName:
	var node_value: Variant = NODES.get(node_id)
	if not node_value is Dictionary:
		return &""
	var node: Dictionary = node_value
	var next_value: Variant = node.get(&"next")
	if not next_value is Dictionary:
		return &""
	var transitions: Dictionary = next_value
	return StringName(transitions.get(input_kind, &""))
