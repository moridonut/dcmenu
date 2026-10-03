# dcmenu

Double Commander（macOS）で、**あふ（afxw）の `.mnu` メニューと同じ操作感**を出すための小さなアプリ。

キー 1 つでメニューが出て、**1 文字押すだけで即実行**。サブメニューも 1 文字で開けます。

```
Ctrl+C
┌──────────────────────────────────────┐
│ コピー                                │
│ ──────────────────────────────────── │
│ 同一フォルダにコピー                2  │
│ カーソル位置のフォルダにコピー        C  │
│ 上の階層にコピー                    U  │
│ ──────────────────────────────────── │
│ パスをコピー…                      N  │  ← N でパスのメニューに切り替わる
│ ...                                  │
└──────────────────────────────────────┘
```

## なぜ作ったか

- DC のツールバーの Menu は「頭文字 + Enter」の 2 ストロークで、1 文字では確定できない
- Karabiner の変数レイヤーなら 1 文字で確定できるが、メニュー表示（通知）は画面右下に固定で、
  1 項目足すにも JSON の 3 か所を直す必要があった

dcmenu ではメニューを 1 項目 1 行のテキストファイルで書き、DC のウィンドウの上に出します。

## インストール

```bash
git clone https://github.com/moridonut/dcmenu.git
cd dcmenu
./build.sh

./install.sh
```

`install.sh` は `~/.config/dcmenu/*.menu` と `~/bin/dcmenu` を、このリポジトリへの**シンボリックリンク**として置きます。
メニューの「= Edit this」で開いて直すとリポジトリのファイルがそのまま変わるので、git で管理できます。
`.menu` を新しく足したときは `./install.sh` をもう一度実行してください（何度実行しても大丈夫です。`-n` で予行演習）。
同じ名前の普通のファイルが既にある場合は、中身が違えば `<名前>.bak-日時` に退避してからリンクにします。

必要なのは Xcode Command Line Tools（`xcode-select --install`）だけです。

## Double Commander の設定

### 1. メニューを開くボタン

ツールバーに「Program」ボタンを作ります（ツールバーは非表示のままで構いません）。

| メニュー | Command | Parameters |
|---|---|---|
| コピー | `/Users/あなた/bin/dcmenu` | `copy -o %Dt -k %p0 %p` |
| ソート | `/Users/あなた/bin/dcmenu` | `sort` |
| 圧縮／解凍 | `/Users/あなた/bin/dcmenu` | `archive -k %p0 %p` |

それぞれ `cm_ExecuteToolbarItem` でホットキーを割り当て、**Controls は Files Panel だけ**にします。
こうすると検索欄や名前変更の入力中には反応しないので、素の `C` のような文字キーにも割り当てられます。

> Karabiner で同じキー（`左Ctrl+C` など）にメニューを作っている場合は、そのルールを無効にしてください。
> 残っていると Karabiner が先にキーを取ってしまいます。

### 2. `@key` で呼ぶ DC コマンドのホットキー

DC の内部コマンド（`cm_*`）は外から直接呼べないので、メニューは DC に**キーを送って**実行させます。
DC 側で次のキーを割り当ててください（Files Panel）。キーを変えたいときは `.menu` の `@key` 行も合わせて直します。

| キー | コマンド | パラメータ | 使うメニュー |
|---|---|---|---|
| `Ctrl+Opt+Shift+2` | `cm_CopySamePanel` | | コピー 2 |
| `Ctrl+Opt+Shift+B` | `cm_Copy` | | コピー B |
| `Ctrl+Opt+Cmd+F` | `cm_UniversalSingleDirectSort` | （なし） | ソート F 名前昇順 |
| `Ctrl+Opt+Cmd+R` | `cm_UniversalSingleDirectSort` | `order=descending` | ソート R 名前降順 |
| `Ctrl+Opt+Cmd+D` | `cm_UniversalSingleDirectSort` | `column=datetime`<br>`order=descending` | ソート D 日付降順 |
| `Ctrl+Opt+Cmd+T` | `cm_UniversalSingleDirectSort` | `column=datetime` | ソート T 日付昇順 |
| `Ctrl+Opt+Cmd+E` | `cm_SortByExt` | | ソート E |
| `Ctrl+Opt+Cmd+S` | `cm_SortBySize` | | ソート S |
| `Ctrl+Opt+Cmd+A` | `cm_SortByAttr` | | ソート A |

`cm_SortByExt` / `Size` / `Attr` は、同じ列で並んでいるときに押すと昇順・降順が入れ替わります（あふの `!` と同じ）。

### 3. アクセシビリティの許可

`@key` の項目を初めて選んだとき、キーを送る許可を求められます。
「システム設定 → プライバシーとセキュリティ → アクセシビリティ」で、出てきたアプリ
（DC から起動した場合はたいてい Double Commander）をオンにしてください。

## メニューファイルの書き方

`~/.config/dcmenu/<名前>.menu`（`-m` か環境変数 `DCMENU_DIR` で変更可）。1 ファイル = 1 メニューです。

```conf
# コメント
title: コピー                                   ← 先頭に薄く表示される見出し

2 | 同一フォルダにコピー     | @key ctrl+opt+shift+2
c | カーソル位置のフォルダにコピー | /bin/cp -Rpn %M %C
-                                              ← 区切り線
n | パスをコピー…           | @menu clip
= | Edit this              | @edit
```

`キー | 表示名 | コマンド`。キーは 1 文字（英数字・記号）。同じメニューでキーが重なると先の項目が優先されます。

### コマンド

| 書き方 | 動作 | あふでいうと |
|---|---|---|
| シェルのコマンド | `/bin/sh -c` で実行。カレントは対象ファイルのフォルダ | 外部コマンド |
| `@menu <名前>` | 別のメニューファイルを同じ場所に開く | `&MENU` |
| `@key <キー>` | DC にキーを送る。`ctrl+opt+shift+2`、空白区切りで連続も可 | `&SORT` など内部コマンド |
| `@clip <文字列>` | クリップボードへ。マークしたファイルごとに 1 行 | `&CLIP` |
| `@edit [コマンド]` | このメニューファイルを開く（既定は `open -t`） | `&EDIT` |

`@key` で使えるキー名: 英数字・記号、`f1`〜`f12`、`return` `tab` `space` `esc` `delete` `fwddelete`
`left` `right` `up` `down` `home` `end` `pageup` `pagedown`。修飾キーは `ctrl` `opt` `shift` `cmd`。

`{ 名前` 〜 `}` で囲むと、横に開く普通のサブメニューも作れます（1 文字では開けません。あふ風にしたいときは `@menu`）。

### マクロ

| マクロ | 中身 | DC で渡すもの |
|---|---|---|
| `%P` | フルパス（マークの先頭） | `%p` |
| `%M` | マークしたファイル全部（無ければカーソル位置） | `%p` |
| `%C` | カーソル位置のファイル | `-k %p0` |
| `%O` | 反対側パネルのフォルダ（あふの `$O`） | `-o %Dt` |
| `%D` | `%P` の親フォルダ | |
| `%N` | ファイル名（拡張子つき） | |
| `%A` | ファイル名（拡張子なし） | |
| `%B` | フルパス（拡張子なし） | |
| `%E` | 拡張子 | |
| `%F` | 親フォルダ名 | |
| `%U` | `file://` 形式の URL | |
| `%X` | 実行時に入力ダイアログ。`%X"初期値"` で初期値つき | |
| `%%` | `%` そのもの | |

シェルのコマンドでは**自動でシェルクォートされる**ので、`"%P"` のように囲む必要はありません。
`@clip` ではクォートされず、そのままの文字列になります（`@clip "%P"` でダブルクォートつきのパス）。
`%P %D %N %F %E %A %B %M %X` の文字は [pochi](https://github.com/moridonut/pochi) と同じです。

## 同梱のメニュー

あふで使っていた `copymenu.txt` `ClipFilename.txt` `Shortcutmenu.txt` `Sortmenu.txt` `7zip.txt` を移植したものです
（`7zip.txt` には `Lhaplus.txt` の「暗号付き」も足しています）。
Mac に無いものは外したり置き換えたりしています。

| あふ | dcmenu |
|---|---|
| `H` 複写先をヒストリーから選ぶ | 削除（DC では `B` のコピーダイアログの宛先欄に履歴がある） |
| `M` メッセージをコピー | 削除（相当機能なし） |
| ショートカット（.lnk） | シンボリックリンク。スタートアップ・SendTo は削除 |
| パスをコピー `S` ショートファイルネーム | 削除（Mac に無い） |
| パスをコピー `\` 末尾に `\` | `/` 末尾に `/` |
| パスをコピー `U` Pathway の URL 形式 | `U` `file://` URL |
| パスをコピー `U` 拡張子も除く（キー重複） | `A` |
| ソート `F` ファイル名降順（キー重複） | `R` |
| ソート `B` 前に戻す | 削除（DC に相当コマンドなし） |
| 圧縮のパスワード（名前に `-pPW` を付ける） | `E` 暗号付き（パスワードは伏せ字のダイアログで聞く） |

### 圧縮／解凍について

`dcmenu-zip` / `dcmenu-unzip`（`bin/`、アプリに同梱）が実際の処理をします。

- **7-Zip があれば 7-Zip を使います**（`brew install sevenzip` で入る `7zz`）。日本語のファイル名を
  Windows で開いても化けにくいので、社外に送る zip を作るなら入れておくのがおすすめです。
  無ければ macOS 標準の `zip`（圧縮）と `ditto` / `tar`（解凍）を使います
- zip の中のパスはフォルダからの相対パスで入り、`.DS_Store` と `._*` は入れません
- 暗号は ZipCrypto（Windows 標準の展開機能でも開ける方式）。強度は高くありません
- 同じ名前の zip が既にあるときは作らずにエラーにします。解凍では既存のファイルを上書きしません

## ログ

実行したコマンドとエラー、送ったキーは `~/Library/Logs/dcmenu.log` に残ります（`DCMENU_LOG` で変更可）。

```bash
tail -f ~/Library/Logs/dcmenu.log
```

コマンドが 3 秒以内にエラーで終わったときは、内容をダイアログでも表示します。

## ライセンス

MIT
