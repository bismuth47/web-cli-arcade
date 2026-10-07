# web-cli-arcade 👾

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/bismuth47/web-cli-arcade)

Mac (Docker Desktop / Colima) で動く、Webブラウザ上で CLIレトロゲームを遊べる超軽量 Docker コンテナ。

`ttyd` + `Alpine Linux` + マルチステージビルドによる Web CLI ゲーム集。
全20本を収録し、ブラウザ上で ←→ 矢印キーによるカルーセル選択で遊べます。

```
 ____  ___  ____________  ____     ___    ____  ___________    ____  ____
/ __ \/ _ \/ ___/_  __/  / __ \   /   |  / __ \/ ____/   |  / __ \/ __ \
...
★☆★  WEB CLI ARCADE - RETRO TERMINAL PARK  ★☆★
```

## 収録ゲーム (全20本)

| # | ゲーム | ジャンル | 由来 | 起動コマンド |
|---|--------|---------|------|--------------|
| 1 | 2048 | PUZZLE | C言語製 [`mevdschee/2048.c`](https://github.com/mevdschee/2048.c.git) をコンパイル | `/usr/local/bin/2048` |
| 2 | nInvaders | ACTION | C言語製 [`doctorfree/ninvaders`](https://github.com/doctorfree/ninvaders.git) をコンパイル | `/usr/local/bin/ninvaders` |
| 3 | tint (テトリス) | PUZZLE | [`DavidGriffith/tint`](https://github.com/DavidGriffith/tint.git) をソースビルド ※ | `/usr/local/bin/tint` |
| 4 | snake | ACTION | Alpine apk `bsd-games` | `snake` |
| 5 | rogue系 (nethack) | ROGUE | Alpine apk `nethack` (bsd-gamesにrogue本体が無いため) | `nethack` |
| 6 | PAC-MAN | ACTION | `pacman4console` Debian正規ソースtarballをビルド ※※ | `/usr/local/bin/pacman4console` |
| 7 | moon-buggy | ACTION | [`seehuhn/moon-buggy`](https://github.com/seehuhn/moon-buggy) をソースビルド | `/usr/local/bin/moon-buggy` |
| 8 | nsnake | ACTION | [`alexdantas/nSnake`](https://github.com/alexdantas/nSnake) をソースビルド | `/usr/local/bin/nsnake` |
| 9 | nudoku | PUZZLE | [`jubalh/nudoku`](https://github.com/jubalh/nudoku) をソースビルド | `/usr/local/bin/nudoku` |
| 10 | vitetris | PUZZLE | [`vicgeralds/vitetris`](https://github.com/vicgeralds/vitetris) をソースビルド | `/usr/local/bin/vitetris` |
| 11 | micro-tetris | PUZZLE | Alpine apk `micro-tetris` | `micro-tetris` |
| 12 | gnuchess | BOARD | Alpine apk `gnuchess` | `gnuchess` |
| 13 | zangband | ROGUE | Alpine apk `zangband` | `zangband` |
| 14 | adventure | ADVENTURE | Alpine apk `bsd-games` | `adventure` |
| 15 | robots | ACTION | Alpine apk `bsd-games` | `robots` |
| 16 | worm | ACTION | Alpine apk `bsd-games` | `worm` |
| 17 | sail | STRATEGY | Alpine apk `bsd-games` | `sail` |
| 18 | battlestar | ADVENTURE | Alpine apk `bsd-games` | `battlestar` |
| 19 | hangman | WORD | Alpine apk `bsd-games` | `hangman` |
| 20 | hunt the wumpus | ADVENTURE | Alpine apk `bsd-games` | `wump` |

> ※ Alpine公式apkに `tint` が存在しないため (Debian/Ubuntu系のみ提供)、上流ソースから `builder` ステージでコンパイルしています。
> ※ Alpineの `pacman` はArchのパッケージマネージャでありゲームではないため、パックマンゲーム (`pacman4console`) はDebian正規ソースtarballからビルドしています (バイナリ名 `pacman` → `pacman4console` に改名して配置)。
> ※ `pacman4console` はビルド時に `pacman-center.patch` を適用し、迷路＋ステータス窓を端末中央に描画するようにしています (素のままだと左上固定)。
> ※ Alpineの `bsd-games` に `rogue` 本体は含まれず、`brogue` はSDL/GUI版でttydのターミナルでは動作しないため、ターミナル対応のrogue系として `nethack` をapk導入しています。

UI は `ttyd` + `game_menu.sh` (bash カルーセルメニュー)。
←→ 矢印キーでゲームを選び `Enter` で起動、各ゲーム終了後は `Press Enter to return to menu...` でメニューに復帰する無限ループです。

## プロジェクト構成

```
web-cli-arcade/
├── Dockerfile           # マルチステージビルド
├── game_menu.sh         # ASCIIアート付きゲーム選択メニュー
├── pacman-center.patch  # pacman4consoleの中央化パッチ
├── words                # hangman用英単語辞書
├── vitetris-config      # vitetris用プリセットキー設定 (~/.vitetris)
├── das-bridge.py        # vitetris 2P同時長押し対応ブリッジ (Python3標準庫のみ)
├── das-term.html        # DASブリッジ用ブラウザ端末ページ
├── das-proxy.py         # ttyd透過プロキシ (:8080にDASキー注入)
├── das-keys.js          # プロキシが差し込むキー別DASスクリプト
├── start-all.sh         # ttyd(:8080裏) + プロキシ(:8080) + DASブリッジ(:8081) 同居起動
└── README.md            # 本ファイル
```

## GitHub Codespaces で遊ぶ (Public公開)

1. 上の `Open in GitHub Codespaces` から Codespace を作成 (自動で `Dockerfile` をビルド)。
2. 下部の `PORTS` タブで `8080` / `8081` が Forward されていることを確認。
3. 各ポートを右クリック → `Visibility` → `Public` に変更 (友達と共有する場合)。
4. Globe アイコン / URL から開く:
   * `https://<codespace>-8080.app.github.dev` … 20本メニュー
   * `https://<codespace>-8081.app.github.dev` … vitetris 2P専用DAS端末

> `visibility: public` は devcontainer.json では強制できないため、手動で Public 化してください (Org ポリシーで禁止されている場合は Private のまま Preview で遊べます)。

## 必要環境

* macOS + Docker Desktop または Colima
* Webブラウザ (Chrome / Safari / Edge 等)

Colima の場合:

```bash
colima start
docker version
```

## ビルド手順

```bash
docker build -t web-cli-arcade .
```

マルチステージビルド構成:

* `builder` ステージ: `git + curl + build-base + ncurses-dev + cmake + autoconf/automake` で 2048 / ninvaders / tint / pacman4console / moon-buggy / nsnake / nudoku / vitetris をコンパイル (`strip` 済み)
* `runtime` ステージ: `bash + ncurses + bsd-games + nethack + micro-tetris + gnuchess + zangband + ttyd` のみ、`apk cache / man / doc` 削除

サイズ確認:

```bash
docker images | grep web-cli-arcade
# 機能優先のため 100MB前後になる想定 (Alpine素体 ~7MB + ttyd + games + python3/xterm.js同梱)
```

## 起動手順

```bash
docker run -d -p 8080:8080 -p 8081:8081 --name arcade web-cli-arcade
```

ブラウザでアクセス:

```
http://localhost:8080  (20本メニュー)
http://localhost:8081  (vitetris 2P同時長押しDAS対応端末)
```

停止・削除:

```bash
docker stop arcade
docker rm arcade
# イメージ削除する場合
docker rmi web-cli-arcade
```

## 使い方

1. `http://localhost:8080` を開くと自動でゲームカルーセルが表示される (各ゲームのテキストアイコンが画面全体に表示)
2. `←` `→` 矢印キー (または `h`/`l`、`a`/`d`) でゲームを選び、`Enter` で起動
3. ゲーム終了後は `Press Enter to return to menu...` と表示されるので `Enter` でメニューに戻る
4. `q` で終了メッセージを表示してメニューを抜ける (ttyd再接続で復帰)

> `ttyd` は `-W` (ブラウザからの入力許可) 付きで起動しています。
> `-W` が無いとキー入力がゲームに届かないため必須です:
> `CMD ["ttyd", "-p", "8080", "-W", "bash", "/usr/local/bin/game_menu.sh"]`

## vitetris 2人プレイ (同一キーボード)

同じブラウザ画面を見ながら2人で同時対戦できます。P2のデフォルトは全キー未設定のため、初期設定 (`vitetris-config` を `~/.vitetris` として同梱) でキーを割り当て済みです。

 1. メニューで `vitetris` を起動 → `2-Player Game` → `this terminal` → `Enter` → `Space` で対戦開始
 2. キー配置 (プリセット):
    * 1P (左手): `A`左 `D`右 `W`回転 `S`落下 `Q`/`E`回転 `Space`ハードドロップ (矢印キーも1Pで使えます)
    * 2P (右手): `J`左 `L`右 `I`回転 `K`落下 `,`/`.`回転 `Space`ハードドロップ (共通)
 3. 注意:
    * P2に矢印キーは割り当て不可です (vitetrisの矢印入力にはプレイヤー区別がなく、必ずP1側に届く仕様のため)。右手クラスタ `I/J/K/L` が矢印の代替です。
    * ゲーム内の `Options` → `Input Setup` (player1/player2) で自由に変更可。変更はその場で `~/.vitetris` に保存されます。

### vitetris 2P 同時長押し対応 (DAS)

通常のキーリピートは「最後に押した1キー」しか連打しない仕様のため、
対策なしでは以下の制限があります。

* 1Pが `D` を長押し中に2Pがキーを押すと、1Pの連打が止まる
* 1Pと2Pが同時に長押ししても、後から押した方しか進まない

本コンテナでは2経路ともキー別DAS (初動即時＋170ms後に50ms間隔リピート) 対応済みです。
各キーが独立した押下状態を持つため、1P/2Pの同時長押しが干渉しません。
回転・ハードドロップは単発送信のため、長押ししても暴走しません。

```
http://localhost:8080  … 20本メニュー (DASキー注入付きttydプロキシ経由)
http://localhost:8081  … vitetris 2P専用・同時長押しDAS対応端末
```

* `:8080`: 透過プロキシ (`das-proxy.py`) がttydページに `das-keys.js` を差し込み、
  ブラウザ側でキーごとにDASリピートします。`/ws` 等の通信は無加工で中継します。
  右下の `DAS:ON/OFF` バッジまたは `F9` でON/OFF切替可 (既定ON)。
  他の19本も同じDASで動作します (単発入力のゲームは従来通り1文字ずつ送られます)。
* `:8081`: vitetris専用端末 (`das-bridge.py`)。キー押下/解放をサーバ側で管理する方式。
  こちらもキー配置はプリセット (`vitetris-config`) と同じです。

起動後は通常通り `2-Player Game` → `this terminal` → `Enter` → `Space` で対戦開始してください。

起動 (2ポート公開):

```bash
docker run -d -p 8080:8080 -p 8081:8081 --name arcade web-cli-arcade
```

> `:8081` はvitetris専用セッションです (複数タブで開くと同一画面を共有します)。
> イメージサイズは `python3` 同梱のため従来の41MB前後から増加します。

### vitetris設定 (Input Setup) のイメージへの埋め込み

できます。ゲーム内の `Options` → `Input Setup` で変えた内容は
コンテナ内の `~/.vitetris` (`/root/.vitetris`) に保存されるので、
それを取り出してリポジトリの `vitetris-config` に反映し、rebuildします。
旧コンテナを消す前に取り出してください。

```bash
docker cp arcade:/root/.vitetris ./vitetris-config.new
# 末尾に [hiscore] セクションがあれば削除 (ハイスコアまで焼く必要はないため)
cp ./vitetris-config.new vitetris-config
docker build -t web-cli-arcade .
docker stop arcade && docker rm arcade
docker run -d -p 8080:8080 -p 8081:8081 --name arcade web-cli-arcade
```

注意:

* `:8081` のDASブリッジは起動時に同じ `~/.vitetris` の `[stdin]` を読むため、
  キー配置を変えてもブリッジ側の改修は不要です (移動系は自動でリピート対象になります)。
  矢印/Enter/Esc/数字は固定です。
* コンテナ起動後の `Input Setup` 変更は、次に起動したvitetris(`:8080`側)には即反映、
  `:8081`側のDASにはコンテナ再起動後に反映されます。

## トラブルシュート

* **PAC-MANがすぐ終わる**: `pacman4console` は 29列×32行以上の画面が必要です (ソース上の `getmaxyx` 判定。エラーメッセージの「32x29」表記は紛らわしいですが、行数が32要ります)。80x24のままだと起動できません。メニュー側でサイズ不足を検知して警告を出すようにしています。ブラウザのウィンドウを広げるか、ttydの文字サイズを小さくして行数を増やしてください。
* **hangmanが辞書エラーになる**: 旧版では `/usr/share/dict/words` が無く即終了しました。現版では英単語リスト (約480語) を同梱済みです。

* **文字化けする**: `TERM=xterm-256color` を Dockerfile で設定済み。ttydのターミナル設定が `xterm` 系か確認してください。
* **キーが効かない**: `ttyd -W` が付いているか `docker ps --no-trunc` で CMD を確認してください。
* **snake / rogue が無いと言われる**: Alpine の `bsd-games` のパス差異を `game_menu.sh` 内 `resolve_cmd()` で吸収しています (`/usr/bin`, `/usr/games` を探索)。それでも無い場合は `docker exec -it arcade apk info -L bsd-games | grep -E "snake|rogue"` で実体を確認してください。
* **Colimaでポートに繋がらない**: `colima stop && colima start` 後、再度 `docker run -p 8080:8080` してください。
