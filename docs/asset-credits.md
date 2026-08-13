# アセットクレジット

外部から取得したアセットの出典とライセンスを記録する。

## モーション: Universal Animation Library (Quaternius)

- ファイル: `assets/motions/universal_animation_library.gltf` (+ `.bin`)
- 作者: Quaternius (https://quaternius.com)
- ライセンス: CC0 1.0 Universal (パブリックドメイン。帰属義務なし・商用可)
- 取得元: https://github.com/J-Ponzo/gltf-universal-animation-library
  - このリポジトリは Quaternius の Universal Animation Library (Standard/無料版) を itch.io (https://quaternius.itch.io/universal-animation-library) から 2025-06-10 に取得し、glTF ファイルのみを再配布したもの。
- ライセンス根拠:
  - リポジトリ同梱の `LICENSE` が Creative Commons Zero 1.0 Universal (CC0 1.0) の全文。
  - README にも "This pack is licensed under CC0 1.0. Full details in LICENSE" と明記。
  - Quaternius 公式ページ (https://quaternius.com/packs/universalanimationlibrary.html) でも "Free to use in personal, educational and commercial projects" / CC0 と表記。
- 取得日: 2026-08-13
- 内容: 46 アニメーションを含む単一 glTF。攻撃系として `Punch_Jab` / `Punch_Cross` / `Punch_Enter` / `Sword_Attack` を含む。
- 検証で使用した攻撃モーション: `Punch_Cross` (クロスパンチ)。
- スケルトン命名: Blender Rigify の DEF- 命名 (例 `DEF-hips`, `DEF-spine.001`, `DEF-upper_arm.L`)。
  SkeletonProfileHumanoid へのリターゲットには BoneMap によるエイリアス解決が必要。

## モーション: Mixamo モーション一式 (Adobe Mixamo)

- ファイル: `assets/motions/mixamo_*.fbx` (計 42 本)
  - パンチ (11): `mixamo_jab_left` (Lead Jab) / `mixamo_cross_punch` / `mixamo_combo_punch` / `mixamo_punch_combo` / `mixamo_hook_1..4` / `mixamo_elbow_1..3`
  - キック・ひざ (11): `mixamo_knee` (Illegal Knee。kick_1) / `mixamo_kick_finish` (Kicking。kick_2) / `mixamo_kick_mma` (Mma Kick。kick_3) / `mixamo_kick_high_left` (Kicking2。未使用) / `mixamo_kick_roundhouse` (Roundhouse Kick。未使用) / `mixamo_kick_side` (Side Kick。未使用) / `mixamo_kick_soccer` (Kick Soccerball。未使用) / `mixamo_knee_jab` (Knee Jab) / `mixamo_kick_chapa` (Chapa-Giratoria) / `mixamo_kick_martelo` (Martelo 2) / `mixamo_kick_standing` (Standing Melee Kick)
  - 構え (1): `mixamo_boxing_idle` (Boxing)
  - 被弾リアクション (4): `mixamo_hit_react_1` (Hit Reaction) / `mixamo_hit_react_large_front` / `mixamo_hit_react_large_right` / `mixamo_hit_react_small` (Standing React Large From Front/Right, Small From Right)
  - 回避・移動 (4): `mixamo_dodge_backward` (Standing Dodge Backward) / `mixamo_dive_roll` (Running Dive Roll) / `mixamo_backslide` (Sprint To Backslide) / `mixamo_fall_land_idle` (Fall B Land To Standing Idle)
  - 歩行・走行 (4): `mixamo_walk` (Walking) / `mixamo_run` (Running) / `mixamo_walk_female` (Female Walk。逸脱時の歩行差し替え候補) / `mixamo_walk_catwalk` (Catwalk Walk Forward。同候補)
  - 銃 (1): `mixamo_rifle_fire` (Firing Rifle)
  - ダウン (6): `mixamo_death_dying` (Dying) / `mixamo_death_front_01` (Death From The Front) / `mixamo_death_back_01` (Death From Back Headshot。元名がプロジェクト制約に触れるため中立名で配置) / `mixamo_death_backward_01` / `mixamo_death_forward_01` / `mixamo_death_left_01` (Standing Death Backward/Forward/Left 01)
### ファイル名 ↔ Mixamo 検索名 対応表

Mixamo で各モーションを検索・ダウンロードする際の検索名（Mixamo 上のアニメーション名）と、`assets/motions/` へ配置する際のファイル名の対応。ダウンロードは全て **FBX for Unity / Without Skin**。Hook / Illegal Elbow Punch は Mixamo 上で同名の複数バリエーションがあり、ダウンロード時に `(1)` `(2)` 等の連番が付く。ここでは連番の若い順にファイル名を割り当てている。

| Mixamo 検索名 | 配置ファイル名 |
| --- | --- |
| Lead Jab | `mixamo_jab_left.fbx` |
| Cross Punch | `mixamo_cross_punch.fbx` |
| Combo Punch | `mixamo_combo_punch.fbx` |
| Punch Combo | `mixamo_punch_combo.fbx` |
| Hook | `mixamo_hook_1.fbx` |
| Hook (バリエーション 2) | `mixamo_hook_2.fbx` |
| Hook (バリエーション 3) | `mixamo_hook_3.fbx` |
| Hook (バリエーション 4) | `mixamo_hook_4.fbx` |
| Illegal Elbow Punch | `mixamo_elbow_1.fbx` |
| Illegal Elbow Punch (バリエーション 2) | `mixamo_elbow_2.fbx` |
| Illegal Elbow Punch (バリエーション 3) | `mixamo_elbow_3.fbx` |
| Boxing | `mixamo_boxing_idle.fbx` |
| Kicking2 | `mixamo_kick_high_left.fbx` |
| Roundhouse Kick | `mixamo_kick_roundhouse.fbx` |
| Side Kick | `mixamo_kick_side.fbx` |
| Mma Kick | `mixamo_kick_mma.fbx` |
| Kick Soccerball | `mixamo_kick_soccer.fbx` |
| Illegal Knee | `mixamo_knee.fbx` |
| Kicking | `mixamo_kick_finish.fbx` |
| Knee Jab | `mixamo_knee_jab.fbx` |
| Chapa-Giratoria | `mixamo_kick_chapa.fbx` |
| Martelo 2 | `mixamo_kick_martelo.fbx` |
| Standing Melee Kick | `mixamo_kick_standing.fbx` |
| Hit Reaction | `mixamo_hit_react_1.fbx` |
| Standing React Large From Front | `mixamo_hit_react_large_front.fbx` |
| Standing React Large From Right | `mixamo_hit_react_large_right.fbx` |
| Standing React Small From Right | `mixamo_hit_react_small.fbx` |
| Standing Dodge Backward | `mixamo_dodge_backward.fbx` |
| Running Dive Roll | `mixamo_dive_roll.fbx` |
| Sprint To Backslide | `mixamo_backslide.fbx` |
| Fall B Land To Standing Idle | `mixamo_fall_land_idle.fbx` |
| Walking | `mixamo_walk.fbx` |
| Running | `mixamo_run.fbx` |
| Female Walk | `mixamo_walk_female.fbx` |
| Catwalk Walk Forward | `mixamo_walk_catwalk.fbx` |
| Firing Rifle | `mixamo_rifle_fire.fbx` |
| Dying | `mixamo_death_dying.fbx` |
| Death From The Front | `mixamo_death_front_01.fbx` |
| Death From Back Headshot | `mixamo_death_back_01.fbx` |
| Standing Death Backward 01 | `mixamo_death_backward_01.fbx` |
| Standing Death Forward 01 | `mixamo_death_forward_01.fbx` |
| Standing Death Left 01 | `mixamo_death_left_01.fbx` |

- 出典: Mixamo (https://www.mixamo.com、Adobe 提供)
- キャラクター: Ch12_nonPBR。ダウンロードは Without Skin 相当 (メッシュ非同梱、スケルトン + アニメのみ。中身を確認済み。`Ch12_nonPBR` はファイル名の名残でメッシュは入っていない)。
- ライセンス: Adobe General Terms of Use に基づく。Mixamo のコンテンツは自分の制作物への組み込み利用が可 (ゲーム・映像等)。一方でモーション/キャラを Mixamo 由来のスタンドアロンなアセットとして単体再配布 (素材ファイルそのものの配布・転売) することは不可。
- 取得日: 2026-08-13
- 内容: 各 FBX に 1 アニメ (Godot ufbx が sanitize し `mixamo_com` 名)。長さは 0.60s (Hit Reaction) 〜 4.40s (Dying)。右ストレート用に Cross_Punch を採用 (数値 QC 済)、他は被弾・回避・ダウン・銃・キック・コンボ素材として導入。全 29 本が同一の 65 ボーンスケルトン (Without Skin) で、`mixamo_bone_map.tres` 1 つでリターゲットする。
- スケルトン命名: Mixamo 命名だが Godot 4.7 の ufbx インポータがコロンを sanitize するため、インポート後のボーン名は `mixamorig4_Hips` 等 (元は `mixamorig:Hips`)。BoneMap (`assets/motions/mixamo_bone_map.tres`) はこの sanitize 後の名前でエイリアスを張っている。
- 公開時の注意: 上記のとおり Mixamo 由来 FBX の生ファイルは単体再配布不可。**このリポジトリを一般公開する場合、`assets/motions/mixamo_*.fbx` の生ファイルをそのまま含めてよいかはライセンス上の要注意事項**であり、公開前に FBX を除外する / 別途権利処理する等の判断が要る。
