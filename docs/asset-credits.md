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

## モーション: Mixamo (Adobe Mixamo)

- 出典: Mixamo (https://www.mixamo.com、Adobe 提供)
- ライセンス: Adobe General Terms of Use に基づく。自分の制作物への組み込み利用は可（ゲーム・映像等）。一方で、モーションを Mixamo 由来のスタンドアロンなアセットとして単体再配布（素材ファイルそのものの配布・転売）することは不可。このため `assets/motions/mixamo_*.fbx` はリポジトリに含めていない
- 取得日: 2026-08-13（Hip Hop Dancing のみ 2026-08-16）
- 形式: 各 FBX に 1 アニメ（Godot の ufbx が sanitize して `mixamo_com` 名になる）

### 実行時に必要（3本）

ゲームを動かすだけならこの3本でよい。攻撃モーションは `actors/player/anim/*.res` にベイク済みで、リポジトリに含まれている。

| Mixamo 検索名 | 配置ファイル名 | 用途 |
| --- | --- | --- |
| Walking | `mixamo_walk.fbx` | 歩行 |
| Running | `mixamo_run.fbx` | 走行 |
| Hip Hop Dancing | `mixamo_dance_hiphop.fbx` | `interact` 長押し中の回復ダンス（15.77s / 53 トラック） |

待機モーションは Quaternius の glTF（上記）を使うため、Mixamo 側には無い。

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

Hip Hop Dancing 以外は **FBX for Unity / Without Skin**、Hip Hop Dancing だけ **FBX for Unity / With Skin**（取得ファイル `Ch45_nonPBR@Hip Hop Dancing.fbx`。ただしインポート結果は `Skeleton3D` + `AnimationPlayer` のみでメッシュは入っていない）。

### スケルトン命名と BoneMap

Mixamo 元来の命名は `mixamorig:Hips` だが、Godot 4.7 の ufbx インポータがコロンを `_` に sanitize する。さらに **接頭辞の数字はダウンロードごとに変わりうる**。

| 命名 | 対象 | BoneMap |
| --- | --- | --- |
| `mixamorig4_*` | Hip Hop Dancing 以外 | `assets/motions/mixamo_bone_map.tres` |
| `mixamorig1_*` | Hip Hop Dancing | `assets/motions/mixamo_bone_map_rig1.tres` |

接頭辞が一致しない BoneMap を流用するとリターゲットが通らず、ボーン名が `mixamorig1_*` のまま残る。新しい素材を足す際は `tools/generate_mixamo_bone_map.gd --prefix=<接頭辞> --output=<保存先>` で BoneMap を生成する。

## 取得予定（未取得）

方針は `docs/game-design.md` §7.1。着手は 8/24 以降のため、以下はまだ取得していない。**取得した時点で、上記と同じ粒度（ファイル名・取得元・ライセンス根拠・取得日・内容）で本ファイルに追記すること。**

- 犯人3体・客2〜3種のキャラクターモデル: Mixamo（With Skin）。ライセンスの扱いは上記モーションと同じ（組み込み配布可・単体再配布不可）。
- 什器モデル: Kenney Furniture Kit（Kenney、CC0、glTF）。
