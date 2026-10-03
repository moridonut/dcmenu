#!/bin/bash
# install.sh — このリポジトリを自分の Mac で使えるようにする（シンボリックリンクで配置）
#
#   ./install.sh          リンクを張る（何度実行しても同じ結果）
#   ./install.sh -n       何をするかだけ表示して、実際には変更しない
#
# 張るリンク:
#   ~/.config/dcmenu/<名前>.menu  →  このリポジトリの menus/<名前>.menu
#   ~/bin/dcmenu                  →  build/Dcmenu.app/Contents/MacOS/dcmenu
#
# リンクなので、メニューの「= Edit this」で開いて直すとリポジトリのファイルが変わり、
# そのまま git で管理できます。新しい .menu を足したら、もう一度このスクリプトを実行してください。
#
# 既にリンクでない同名ファイルがある場合は、中身が同じならリンクに置き換え、
# 違えば <名前>.bak-日時 に退避してからリンクにします（消しはしません）。
# リポジトリから消えた .menu を指す、切れたリンクは片付けます。
set -euo pipefail

dry=0
[ "${1:-}" = "-n" ] && dry=1

repo="$(cd "$(dirname "$0")" && pwd -P)"
menudir="${DCMENU_DIR:-$HOME/.config/dcmenu}"
bindir="$HOME/bin"
stamp="$(date +%Y%m%d-%H%M%S)"

run() {
  if [ $dry = 1 ]; then echo "  (dry-run) $*"; else "$@"; fi
}

# link <source> <target>
link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then
      echo "  ok       $dst"
      return
    fi
    echo "  relink   $dst  (以前: $(readlink "$dst"))"
    run ln -sfn "$src" "$dst"
  elif [ -e "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      echo "  replace  $dst  (中身が同じなのでリンクに置き換え)"
    else
      echo "  backup   $dst  →  $dst.bak-$stamp  (中身が違うので退避)"
      run mv "$dst" "$dst.bak-$stamp"
    fi
    run ln -sfn "$src" "$dst"
  else
    echo "  link     $dst"
    run ln -s "$src" "$dst"
  fi
}

echo "==> メニュー: $menudir"
run mkdir -p "$menudir"
shopt -s nullglob
for src in "$repo"/menus/*.menu; do
  link "$src" "$menudir/$(basename "$src")"
done
# リポジトリから消えた .menu への切れたリンクを片付ける
for dst in "$menudir"/*.menu; do
  if [ -L "$dst" ] && [ ! -e "$dst" ]; then
    case "$(readlink "$dst")" in
      "$repo"/menus/*) echo "  remove   $dst  (リンク先が無い)"; run rm "$dst" ;;
    esac
  fi
done

echo "==> コマンド: $bindir/dcmenu"
exe="$repo/build/Dcmenu.app/Contents/MacOS/dcmenu"
run mkdir -p "$bindir"
link "$exe" "$bindir/dcmenu"
[ -x "$exe" ] || echo "  ※ まだビルドされていません。./build.sh を実行してください（リンクはビルド後にそのまま使えます）"

case ":$PATH:" in
  *":$bindir:"*) ;;
  *) echo "  ※ $bindir が PATH に入っていません（DC からはフルパスで呼ぶので動作には影響しません）" ;;
esac
echo "==> 完了"
