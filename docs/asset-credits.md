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
