# CLAUDE.md

このリポジトリで作業する AI エージェントと、新しくコードを触る人向けの前提情報です。

## 現在の状態

> **状態: 未ビルド（2026-10-04 時点）** — ビルドと実機確認が取れたらこの節を書き換えてください。

macOS SDK の無い環境で書いたため、**コンパイルも実機確認もしていません**。確認済みなのは次だけです。

- tree-sitter-swift による構文チェック（型チェックではない）
- メニューファイルの解析とマクロ展開のロジック（同じ処理を Python で書き起こし、同梱の `.menu` を
  スペース・`'` を含むパスで展開して、`sh` が意図どおりの引数に分けることを確認）
- `dcmenu-zip` の zip 経路（Linux の Info-ZIP で、日本語・スペース入りのフォルダ、同名フォルダの中への圧縮）。
  7zz 経路・`-e`（osascript）・`dcmenu-unzip` は未確認
- DC の `cm_UniversalSingleDirectSort` が受け取るパラメータ（DC のソース `src/umaincommands.pas` で確認）

ポップアップメニューと 1 文字アクセラレータの仕組みは、実運用している姉妹プロジェクト
[pochi](https://github.com/moridonut/pochi) と同じコード（`NSMenu.popUp` + 修飾キーなしの `keyEquivalent`）です。

## これは何か

Double Commander（DC）から外部コマンドとして呼ばれ、あふの `.mnu` のようなメニューを出す。
1 文字で選ぶと、シェルのコマンドを実行するか、DC にキーを送って DC の内部コマンドを実行させる。

```
DC のホットキー（Files Panel 限定）
  → 非表示ツールバーの Program ボタン  dcmenu copy -o %Dt -k %p0 %p
  → dcmenu がメニュー表示 → 1 文字
  → シェル実行 / クリップボード / 別メニュー / DC へキー送信
```

あふ → DC 移行の経緯（Karabiner の変数レイヤーでやっていたこと、その限界）は
README の「なぜ作ったか」を参照。

## 構成

```
Sources/MenuFile.swift   メニュー解析・@コマンド判定・マクロ展開・キー名表（Foundation のみ）
Sources/Platform.swift   AppKit 側: メニュー表示、表示位置、フォーカス、キー送信、クリップボード、実行、ログ
Sources/main.swift       引数解析とメインループ（トップレベルコードはこのファイルだけ）
menus/*.menu             あふのメニューを移植した既定のメニュー
bin/dcmenu-copy-image    画像を PNG にしてクリップボードへ
bin/dcmenu-zip / -unzip  圧縮・解凍（7zz があれば優先、無ければ zip / ditto / tar）
build.sh                 swiftc で build/Dcmenu.app を作る（Xcode プロジェクトは使わない）
```

- テストは必ず `build/Dcmenu.app/Contents/MacOS/dcmenu` 経由で（バンドルでないとメニューがフォーカスを取れない可能性）
- `runCommand()` の `LANG` / `LC_CTYPE` 注入は消さないこと。DC は LANG 無しで外部コマンドを起動し、
  pbcopy が日本語を化けさせる。ターミナルからでは再現しない

## 想定される壊れどころ（優先度順）

### ★★★ 1. `@key` のキーが DC に届くか

`giveFocusBack()` で DC を前面に戻してから `CGEvent` を `.cghidEventTap` に投げている。

- 修飾キーは `CGEvent.flags` だけで付けており、修飾キー自体の押下イベント（flagsChanged）は送っていない。
  DC（Lazarus/Cocoa）が修飾を無視する場合は、修飾キーの down/up も送る必要がある
- DC が前面になる前にキーが届くと取りこぼす。`giveFocusBack()` の待ち時間（現在 0.08 秒）を伸ばす
- macOS 14 以降の協調的アクティベーション: `NSApp.yieldActivation(to:)` → `activate(options: [])`。
  前面に戻らない場合は `NSApp.hide(nil)` にフォールバックしている
- 調べるときは `~/Library/Logs/dcmenu.log` の `sent:` 行と warning 行を見る

### ★★★ 2. アクセシビリティ許可がどのアプリに付くか

`CGEvent.post` にはアクセシビリティ許可が要る。DC から起動された子プロセスは、TCC 上
「責任プロセス」の DC として扱われる可能性が高い（その場合は DC を許可すれば済み、dcmenu を再ビルドしても外れない）。
dcmenu 自身に付く場合は、**ad-hoc 署名だと再ビルドのたびに許可が外れる**。
その場合は Apple Development 証明書で署名するよう `build.sh` を変える。

### ★★ 3. `@menu` で 2 つ目のメニューが出るか

同じプロセスで `NSMenu.popUp` を 2 回呼んでいる。2 回目が出ない・キーが効かない場合は、
間に `RunLoop.current.run(until:)` を少し挟む。

### ★★ 4. 表示位置

マウスが DC のウィンドウ内ならマウス位置、外なら DC の最前面ウィンドウの中央付近。
`CGWindowListCopyWindowInfo` の座標（左上原点）を、メインスクリーンの高さで Cocoa 座標（左下原点）に変換している。
マルチディスプレイでずれたらここ。

### ★ 5. コンパイル

型チェック未実施。疑わしい箇所:
- `promptForInput` を `(String, String) -> String?` のクロージャとして `Expander` に渡している
- `NSApp.yieldActivation(to:)` は macOS 14 SDK が必要（`#available` で分岐済み）
- `NSApp.activate(ignoringOtherApps:)` などの非推奨警告は出るがエラーではない

## 次にやること

1. `./build.sh`
2. ターミナルから `build/Dcmenu.app/Contents/MacOS/dcmenu menus/copy.menu ~/somefile` でメニューと 1 文字選択を確認
3. DC にボタンとホットキーを設定し（README）、`@clip` → シェル → `@menu` → `@key` の順に確認
4. この節を更新
