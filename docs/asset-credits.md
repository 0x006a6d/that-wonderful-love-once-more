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

## モーション: Mixamo パンチ一式 (Adobe Mixamo)

- ファイル: `assets/motions/mixamo_cross_punch.fbx` / `mixamo_combo_punch.fbx` / `mixamo_punch_combo.fbx` / `mixamo_hook_1..4.fbx` / `mixamo_elbow_1..3.fbx` (計 10 本)
- 出典: Mixamo (https://www.mixamo.com、Adobe 提供)
- キャラクター: Ch12_nonPBR。ダウンロードは Without Skin 相当 (メッシュ非同梱、スケルトン + アニメのみ。中身を確認済み。`Ch12_nonPBR` はファイル名の名残でメッシュは入っていない)。
- ライセンス: Adobe General Terms of Use に基づく。Mixamo のコンテンツは自分の制作物への組み込み利用が可 (ゲーム・映像等)。一方でモーション/キャラを Mixamo 由来のスタンドアロンなアセットとして単体再配布 (素材ファイルそのものの配布・転売) することは不可。
- 取得日: 2026-08-13
- 内容: 各 FBX に 1 アニメ (Godot ufbx が sanitize し `mixamo_com` 名)。長さは Cross_Punch 2.00s / Combo_Punch 2.97s / Punch_Combo 2.20s / Hook 1.30〜2.93s / Elbow 2.03〜2.27s。右ストレート用に Cross_Punch を採用、Hook/Elbow はコンボ素材として導入のみ。
- スケルトン命名: Mixamo 命名だが Godot 4.7 の ufbx インポータがコロンを sanitize するため、インポート後のボーン名は `mixamorig4_Hips` 等 (元は `mixamorig:Hips`)。BoneMap (`assets/motions/mixamo_bone_map.tres`) はこの sanitize 後の名前でエイリアスを張っている。
- 公開時の注意: 上記のとおり Mixamo 由来 FBX の生ファイルは単体再配布不可。**このリポジトリを一般公開する場合、`assets/motions/mixamo_*.fbx` の生ファイルをそのまま含めてよいかはライセンス上の要注意事項**であり、公開前に FBX を除外する / 別途権利処理する等の判断が要る。
