# セブンティーン

Godot 4.x 製の3Dサードパーソン・アクションゲーム。籠城中の「ぷにけ銀行」に AIニケちゃんが介入し、犯人を制圧する。プレイヤーの行動によってエンディングが4分岐する。

本作品は「AIニケちゃん」の非公式ファンメイド作品です。原作・公式とは関係ありません。
This is an unofficial fan-made work of AI Nike-chan. Not affiliated with or endorsed by the creator.

## 配布

- 無料配布のみ（BOOTH / itch.io、価格0円）
- 個人名義でのリリース

## 開発セットアップ

一部のアセットはライセンス上リポジトリに含めていない（`assets/vrm/*.vrm` と `assets/motions/mixamo_*.fbx`）。クローン後に以下の手順で取得・配置してから Godot で開く。

1. VRM を取得する。

   ```
   tools/fetch_assets.sh
   ```

   AIニケちゃん公式リポジトリの VRM を `assets/vrm/nikechan_player.vrm` としてダウンロードする（既にあればスキップ）。プロジェクトは主人公モデルをこの固定名で参照する。

2. Mixamo モーションを手動で取得する。Mixamo は自動ダウンロードできないため、[Mixamo](https://www.mixamo.com/) で `docs/asset-credits.md` の対応表にある各モーションを検索し、Hip Hop Dancing 以外は **FBX for Unity / Without Skin**、Hip Hop Dancing は **FBX for Unity / With Skin** でダウンロードする。対応表の `mixamo_*.fbx` 名にリネームして `assets/motions/` へ配置する（計 43 本）。ファイル名、検索名、専用 BoneMap の対応は同ドキュメントを参照。

3. Godot 4.7.1 でプロジェクトを開く。初回起動時に FBX / VRM がインポートされる。

## ドキュメント

- `CLAUDE.md` — 開発時の制約（IP・表現・コーディング規約）
- `docs/game-design.md` — 世界観、物語構造、ゲームデザイン
- `docs/technical-spec.md` — Godot 上の実装仕様
- `docs/tasks.md` — コンテスト版（8/29 提出）の実装計画
- `docs/tasks-full.md` — 提出後のフルスコープ版計画

## 使用アセット

- AIニケちゃん公式アセット: https://github.com/tegnike/nikechan-assets
- 二次創作ガイドライン: https://nikechan.com/guidelines/derivative
