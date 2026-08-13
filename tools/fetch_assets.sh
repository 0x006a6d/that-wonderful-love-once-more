#!/usr/bin/env bash
# 再配布不可アセットのうち、自動取得できるものを公式ソースから取得する。
#
# 対象:
#   - assets/vrm/nikechan_player.vrm  (AIニケちゃん公式 VRM)
#
# プロジェクトは主人公モデルを固定名 nikechan_player.vrm で参照する
# (モデル更新時に1ファイル差し替えで済ませるため)。再現ベースラインとして
# 公式リポジトリの nikechan_v2.vrm をこの固定名で取得する。作者は手元で
# より新しいモデルに差し替えてよい (スケルトンが GeneralSkeleton 準拠なら
# モーションはそのまま効く)。
#
# Mixamo (Adobe) 由来の FBX はライセンス上ここでは取得しない。
# README の「開発セットアップ」と docs/asset-credits.md の対応表に従い手動で取得すること。
set -euo pipefail

# リポジトリルート (このスクリプトの1つ上) を基準にする
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VRM_URL="https://raw.githubusercontent.com/tegnike/nikechan-assets/main/vrms/nikechan_v2.vrm"
VRM_DIR="$ROOT_DIR/assets/vrm"
VRM_PATH="$VRM_DIR/nikechan_player.vrm"

mkdir -p "$VRM_DIR"

if [ -f "$VRM_PATH" ]; then
  echo "[skip] $VRM_PATH は既に存在します"
else
  echo "[fetch] 公式 nikechan_v2.vrm を nikechan_player.vrm として取得します"
  echo "        $VRM_URL"
  # 途中失敗時に壊れたファイルを残さないよう一時ファイル経由で取得する
  tmp="$(mktemp "$VRM_DIR/.nikechan_player.vrm.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  curl -fSL "$VRM_URL" -o "$tmp"

  # 先頭4バイトが glTF (VRM は glTF バイナリ) であることを検証
  magic="$(head -c 4 "$tmp")"
  if [ "$magic" != "glTF" ]; then
    echo "[error] 取得したファイルの先頭4バイトが 'glTF' ではありません (実際: '$magic')" >&2
    echo "        取得元がHTMLエラーページ等を返した可能性があります。中断します。" >&2
    exit 1
  fi

  mv "$tmp" "$VRM_PATH"
  trap - EXIT
  echo "[ok] $VRM_PATH ($(wc -c < "$VRM_PATH") bytes)"
fi

echo
echo "VRM の取得は完了しました。"
echo "Mixamo モーション (assets/motions/mixamo_*.fbx) は自動取得できません。"
echo "README の「開発セットアップ」と docs/asset-credits.md の対応表に従って手動で配置してください。"
