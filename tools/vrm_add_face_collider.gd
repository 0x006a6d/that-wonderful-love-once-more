@tool
extends EditorScenePostImport

## 主人公 VRM のインポート後処理。前髪のスプリングボーンが走行中に顔（目）を
## 貫通する問題への対処。
##
## 原因: この VRM の Head コライダーグループは後頭部（offset.z が負）にしか球を
## 持たず、顔前面に当たり判定が無い。前髪 (HairMaegami*) スプリングは既にこの
## Head グループを参照しているため、グループに顔前面の球を1個足すだけで全前髪が
## 顔で跳ね返り、貫通しなくなる（揺れ自体は残す）。
##
## 座標は Head ボーンローカル（+Y 上, +Z 前方=顔）。実測: 目 (±0.04, 0.064, 0.035)、
## 前髪根元 Y≈0.14。球中心 (0, 0.06, 0.0) / 半径 0.08 は、生え際では球の極で
## 前方押し出しゼロ、目の高さで最大となり、根元を浮かせずに前髪を顔の外へ保つ。
##
## この .gd は nikechan_player.vrm.import の import_script/path から呼ばれる。
## モデル差し替えでも Head グループを bone 名で探すため頑健。再インポートで
## 二重追加しないよう既存チェックを入れる。

const FACE_OFFSET := Vector3(0.0, 0.06, 0.0)
const FACE_RADIUS := 0.08


func _post_import(scene: Node) -> Object:
	var secondary := _find_by_name(scene, "secondary")
	if secondary == null:
		push_warning("vrm_add_face_collider: secondary ノードが見つからない。スキップ")
		return scene
	# secondary.collider_groups は未使用（vrm_secondary.gd 参照）。実際のコライダー参照は
	# 各 spring_bone の collider_groups にある。そこから Head グループ（共有リソース）を
	# 見つけて球を1個足せば、それを参照する全前髪に効く。
	var springs: Variant = secondary.get("spring_bones")
	if not (springs is Array):
		push_warning("vrm_add_face_collider: spring_bones が無い。スキップ")
		return scene

	var head_group: Resource = null
	for s in springs:
		var cgs: Variant = s.get("collider_groups")
		if not (cgs is Array):
			continue
		for g in cgs:
			for c in g.colliders:
				if c.bone == "Head":
					head_group = g
					break
			if head_group != null:
				break
		if head_group != null:
			break
	if head_group == null:
		push_warning("vrm_add_face_collider: Head コライダーグループが見つからない。スキップ")
		return scene

	# 再インポート時の二重追加防止。
	# 判定はこのスクリプトが追加する球そのもの（bone / offset / radius / 球であること）
	# と照合する。以前は「offset.z が正」で見ていたが、FACE_OFFSET は z = 0 のため
	# 自分が追加した球に一度も一致せず、ガードとして機能していなかった。
	for c in head_group.colliders:
		if c.bone == "Head" and not c.is_capsule \
				and c.offset.is_equal_approx(FACE_OFFSET) \
				and is_equal_approx(c.radius, FACE_RADIUS):
			return scene

	var face := VRMCollider.new()
	face.bone = "Head"
	face.offset = FACE_OFFSET
	face.tail = FACE_OFFSET
	face.radius = FACE_RADIUS
	face.is_capsule = false
	head_group.colliders.append(face)
	print("vrm_add_face_collider: 顔前面コライダーを追加 (offset=%s r=%.3f)" % [FACE_OFFSET, FACE_RADIUS])
	return scene


func _find_by_name(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var found := _find_by_name(child, target)
		if found != null:
			return found
	return null
