#!/bin/bash
# Word Battle 開発起動スクリプト
# ・env.json から Supabase 接続情報を読み込む（→「サーバーに接続済み」になる）
# ・Chrome のプロファイルを固定（→ 同じ端末＝同じアカウント。ゲストが増えない）
# 使い方: ./run.sh   終了: ターミナルで q
#
# 素の `flutter run -d chrome` は毎回まっさらなプロファイルで開くため、匿名
# アカウント（ゲスト）が起動のたびに新規作成されてしまう。このスクリプトは
# プロファイル用ディレクトリを固定することで、前回のログインを再利用する。

PROFILE_DIR="$HOME/.word_battle_chrome_profile"

# すでに起動中の flutter/Chrome があるとプロファイルを奪い合って
# ページが再読み込みされ、余計なゲストが増える。先に閉じておく。
pkill -f "word_battle_chrome_profile" 2>/dev/null
pkill -f "flutter_tools.*chrome" 2>/dev/null
sleep 1

echo "▶ 固定プロファイルで起動します: $PROFILE_DIR"
echo "  （同じアカウントが再利用され、ゲストは増えません。終了は q）"

flutter run -d chrome \
  --dart-define-from-file=env.json \
  --web-browser-flag="--user-data-dir=$PROFILE_DIR"
