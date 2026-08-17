# アセットクレジット

外部から取得したアセットの出典とライセンスを記録する。

## モーション: Universal Animation Library (Quaternius、QC・計測ツール専用)

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
- 内容: 46 アニメーションを含む単一 glTF。現在は実行時には使用せず、QC・計測ツール専用。
- 参照ツール: `measure_punch.gd` / `measure_stride.gd` / `inspect_motion.gd` / `verify_retarget.gd` / `measure_combo_window.gd` / `probe_univ_names.gd` / `generate_bone_map.gd`
- 検証で使用した攻撃モーション: `Punch_Cross` (クロスパンチ)。
- スケルトン命名: Blender Rigify の DEF- 命名 (例 `DEF-hips`, `DEF-spine.001`, `DEF-upper_arm.L`)。
  SkeletonProfileHumanoid へのリターゲットには BoneMap によるエイリアス解決が必要。

## モーション: Mixamo (Adobe Mixamo)

- 出典: Mixamo (https://www.mixamo.com、Adobe 提供)
- ライセンス: Adobe General Terms of Use に基づく。自分の制作物への組み込み利用は可（ゲーム・映像等）。一方で、モーションを Mixamo 由来のスタンドアロンなアセットとして単体再配布（素材ファイルそのものの配布・転売）することは不可。このため `assets/motions/mixamo_*.fbx` はリポジトリに含めていない
- 取得日: 2026-08-13（Head Spinning / Idle は 2026-08-16、Medium Hit To Head / Dying / Medium Step Forward / Kip Up は 2026-08-17）
- 形式: 各 FBX に 1 アニメ（Godot の ufbx が sanitize して `mixamo_com` 名になる）

### 実行時に必要（11本）

ゲームを動かすだけならこの11本でよい。攻撃モーションは `actors/player/anim/*.res` にベイク済みで、リポジトリに含まれている。

| Mixamo 検索名 | 配置ファイル名 | 用途 |
| --- | --- | --- |
| Walking | `mixamo_walk.fbx` | 犯人の歩行 |
| Medium Step Forward | `mixamo_step_forward.fbx` | プレイヤーの歩行。構えたまま前へ出る。0.93 m 進むので `RootMotion.lock_horizontal()` で水平成分を潰してループさせる |
| Kip Up | `mixamo_kip_up.fbx` | プレイヤーの立ち上がり |
| Running | `mixamo_run.fbx` | 走行 |
| Idle | `mixamo_idle.fbx` | 待機（2.200s / 53 トラック） |
| Head Spinning | `mixamo_dance_headspin.fbx` | `interact` 長押し中の回復ダンス（0.833s / 53 トラック） |
| Standing Death Backward 01 | `mixamo_death_backward_01.fbx` | プレイヤーと客のダウン（仰向け。2.567s / 54 トラック）。立ち上がりは Kip Up に分離した |
| Medium Hit To Head | `mixamo_hit_head.fbx` | 犯人・客の被弾のけぞり |
| Dying | `mixamo_dying.fbx` | 犯人のダウン（うつ伏せ）と、客の伏せ（最終フレームで静止） |
| Walking | `mixamo_walk_female.fbx` | 客の立ち姿。先頭フレーム（直立）だけを静止させて使う |
| Cross Punch | `mixamo_cross_punch.fbx` | 犯人の近接攻撃 |

### 攻撃クリップを再ベイクする場合に必要（6本）

`tools/build_melee_anims.gd` が読む材料。`actors/player/anim/*.res` を作り直すときだけ要る。

| Mixamo 検索名 | 配置ファイル名 | ベイク先 | 技 |
| --- | --- | --- | --- |
| Lead Jab | `mixamo_jab_left.fbx` | `melee_1` | 左ジャブ |
| Cross Punch | `mixamo_cross_punch.fbx` | `melee_2` | 右ストレート |
| Hook（バリエーション 4） | `mixamo_hook_4.fbx` | `melee_3` | 左フック |
| Illegal Knee | `mixamo_knee.fbx` | `kick_1` | 右膝 |
| Kicking | `mixamo_kick_finish.fbx` | `kick_2` | 右ミドル |
| Mma Kick | `mixamo_kick_mma.fbx` | `kick_3` | 右ハイ |

Hook は Mixamo 上で同名の複数バリエーションがあり、ダウンロード時に `(1)` `(2)` 等の連番が付く。連番の若い順に `mixamo_hook_1..4` を割り当てており、採用したのは 4 番目。

### ダウンロード時の設定

Idle と Head Spinning 以外は **FBX for Unity / Without Skin**。Head Spinning の取得ファイルは `Ch45_nonPBR@Head Spinning.fbx`、Idle は `Ch45_nonPBR@Idle.fbx`、Medium Hit To Head と Dying は `Ch35_nonPBR@...`。Godot 4.7.1 でのインポート結果はいずれも `Skeleton3D` + `AnimationPlayer` のみで、`MeshInstance3D` は入っていない。

### スケルトン命名と BoneMap

Mixamo 元来の命名は `mixamorig:Hips` だが、Godot 4.7 の ufbx インポータがコロンを `_` に sanitize する。さらに **接頭辞の数字はダウンロードごとに変わりうる**。

| 命名 | 対象 | BoneMap |
| --- | --- | --- |
| `mixamorig4_*` | Walking / Running / Standing Death Backward 01 ほか | `assets/motions/mixamo_bone_map.tres` |
| `mixamorig1_*` | Head Spinning / Idle | `assets/motions/mixamo_bone_map_rig1.tres` |
| `mixamorig_*`（数字なし） | 2026-08-17 に取得した Ch35 由来の4本（Medium Hit To Head / Dying / Medium Step Forward / Kip Up） | `assets/motions/mixamo_bone_map_rig0.tres` |

接頭辞が一致しない BoneMap を流用するとリターゲットが通らず、ボーン名が `mixamorig1_*` のまま残る。新しい素材を足す際は `tools/generate_mixamo_bone_map.gd -- --prefix <接頭辞> --output <保存先>` で BoneMap を生成する（引数はスペース区切り。`--prefix=...` の形式は受け付けない）。

接頭辞が既知の BoneMap と同じなら、取り込みは `tools/add_mixamo_motion.sh` が一括で行う。

```
tools/add_mixamo_motion.sh "Ch35_nonPBR@Dying.fbx" mixamo_dying \
  res://assets/motions/mixamo_bone_map_rig0.tres
```

### ルートモーション

位置は `CharacterBody3D` が持つので、クリップが体を運ぶと見た目と当たり判定がずれる。
Mixamo の "In Place" で落とせなかったクリップは、読み込み後に
`RootMotion.lock_horizontal()`（`actors/shared/root_motion.gd`）で Hips の水平成分を潰す。
実測値は以下。NPC 側は `NpcAnimator.lock_root_motion`（既定 on）が全クリップに適用する。

| クリップ | 水平移動 |
| --- | ---: |
| `mixamo_walk` / `mixamo_run` | 0 m（In Place で取得済み） |
| `mixamo_dying` | 0.33 m |
| `mixamo_step_forward` | 0.93 m |
| `mixamo_death_backward_01` | 1.37 m |

## キャラクター: Mixamo (Adobe Mixamo)

- 出典・ライセンス: 上記モーションと同じ（Adobe General Terms of Use。制作物への組み込み利用は可、素材ファイル単体の再配布は不可）。このため `assets/characters/mixamo_*.fbx` と、インポータが同フォルダへ展開する `mixamo_*.png` はリポジトリに含めていない
- 取得日: 2026-08-16
- ダウンロード設定: **With Skin**。取得ファイル名は `ChNN_nonPBR@Flip Kick.fbx`。メッシュを得るためのダウンロードであり、同梱の Flip Kick アニメーションは使わない
- 配置: `assets/characters/mixamo_chNN.fbx`（`ChNN` は Mixamo のキャラクター番号）

| 役 | ファイル | 見た目 | メッシュ | 頂点数 | 身長 |
| --- | --- | --- | ---: | ---: | ---: |
| 犯人 | `mixamo_ch01.fbx` | 白ポロシャツ・青ジーンズ・スキンヘッド | 5 | 23,623 | 1.764 m |
| 犯人 | `mixamo_ch08.fbx` | 白パーカー・白スウェット・顎髭 | 7 | 35,568 | 1.781 m |
| 犯人 | `mixamo_ch28.fbx` | 黒の長袖・黒パンツ | 6 | 36,725 | 1.763 m |
| 客 | `mixamo_ch16.fbx` | 水色の術衣・サージカルマスク・キャップ | 7 | 31,886 | 1.774 m |

役割の割り当ては以下。顔の崩れている Ch28（後述）を、遮蔽から撃つだけで近寄らない銃持ちに当て、
プレイヤーが接近して顔を見るリーダーと不安定型には正常な個体を当てた。

| 役割 | ファイル | 割り当ての理由 |
| --- | --- | --- |
| リーダー | `mixamo_ch08.fbx` | 白パーカーで体積が最も大きく、人質を確保する側として見分けやすい |
| 銃持ち | `mixamo_ch28.fbx` | 全身黒。遮蔽越しの距離で戦うため、顔の崩れが目に入りにくい |
| 不安定型 | `mixamo_ch01.fbx` | 白ポロ＋青ジーンズ。一番「普通の客に見える」個体を、客を撃つ役に当てる |
| 客 | `mixamo_ch16.fbx` | 術衣＋マスクで犯人3体と明確に別系統 |

### スケルトンとリターゲット

4体とも 65 ボーンで、モーション側と同じ Mixamo リグ。ただし **sanitize 後の接頭辞はダウンロードごとに異なり、既存の 2 つの BoneMap はどれとも一致しない**。そこで各キャラクター専用の BoneMap を生成し、インポート時に `retarget/bone_map` を指定してある。設定内容は `assets/motions/mixamo_walk.fbx.import` と同じ（`apply_node_transforms` / `overwrite_axis` / `normalize_position_tracks` を有効、`fix_silhouette` は無効）。

| ファイル | 元の接頭辞 | BoneMap |
| --- | --- | --- |
| `mixamo_ch01.fbx` | `mixamorig12_` | `assets/characters/mixamo_bone_map_ch01.tres` |
| `mixamo_ch08.fbx` | `mixamorig7_` | `assets/characters/mixamo_bone_map_ch08.tres` |
| `mixamo_ch16.fbx` | `mixamorig_`（数字なし） | `assets/characters/mixamo_bone_map_ch16.tres` |
| `mixamo_ch28.fbx` | `mixamorig10_` | `assets/characters/mixamo_bone_map_ch28.tres` |

BoneMap は `tools/generate_mixamo_bone_map.gd` で生成した。4体とも 52 ボーンがマップされ、必須ボーンの欠落は無い。

リターゲット後はスケルトン名が `GeneralSkeleton`、ボーン名が `Hips` / `Head` などのプロファイル名になり、既存のモーション FBX がそのまま適用できる。検証は `tools/test_character_anim.gd`（4体 × 8モーションで、全トラック解決と姿勢変化、およびルートモーションを潰す処理を確認。76項目 PASS）。

### 既知の問題

- **Ch28 の顔が崩れている。** 眼球が瞼から突き出し、口が開いたままになる。髪・まつ毛メッシュを非表示にしても残るので Body メッシュ側の問題であり、リターゲット前のインポート直後から同じ状態。他の3体では起きていない。確認は `tools/capture_characters.gd`（`--only Ch28 --distance 0.8 --height 1.6`）
- Ch01 / Ch16 / Ch28 は FBX に埋め込まれたテクスチャが 1〜2 セットしか無く、髪・まつ毛のマテリアルに body の diffuse が割り当てられる。Ch08 だけは髪用テクスチャ（2048px）を持っている

## 取得予定（未取得）

方針は `docs/game-design.md` §7.1。着手は 8/24 以降のため、以下はまだ取得していない。**取得した時点で、上記と同じ粒度（ファイル名・取得元・ライセンス根拠・取得日・内容）で本ファイルに追記すること。**

- 什器モデル: Kenney Furniture Kit（Kenney、CC0、glTF）。
