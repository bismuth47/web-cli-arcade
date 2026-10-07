# syntax=docker/dockerfile:1
# =============================================
# web-cli-arcade : 超軽量 Web CLI レトロゲーム
# Alpine multi-stage build / target 30-40MB
# =============================================

# ---------- Stage 1: builder ----------
FROM alpine:latest AS builder

# 2048.c / ninvaders / tint は gcc+cmake のみ、
# moon-buggy / nudoku は autotools、pacman4console は tarball+make が必要
RUN apk add --no-cache \
    git \
    curl \
    build-base \
    ncurses-dev \
    cmake \
    autoconf \
    automake \
    gettext-dev \
    sed \
    patch

WORKDIR /build

# pacman用中央化パッチ (迷路+ステータス窓を端末中央に寄せる)
COPY pacman-center.patch /build/pacman-center.patch

# --- 2048 (mevdschee/2048.c) ---
# 単一ファイル構成なので gcc 一発でビルドできる
RUN git clone --depth 1 https://github.com/mevdschee/2048.c.git 2048c \
 && gcc -O2 -o /tmp/2048 2048c/2048.c \
 && strip /tmp/2048

# --- nInvaders (doctorfree/ninvaders) ---
# cmake ベース: README 通りに cmake -B / cmake --build する
RUN git clone --depth 1 https://github.com/doctorfree/ninvaders.git ninvaders \
 && cmake -B /build/ninvaders/cmake_build \
           -S /build/ninvaders \
           -DCMAKE_BUILD_TYPE=Release \
 && cmake --build /build/ninvaders/cmake_build -j$(nproc) \
 && BIN=$(find /build/ninvaders/cmake_build -maxdepth 1 -type f -name "ninvaders" | head -n 1) \
 && echo "ninvaders binary: $BIN" && ls -lh "$BIN" \
 && cp "$BIN" /tmp/ninvaders \
 && strip /tmp/ninvaders

# --- tint (DavidGriffith/tint: テトリス) ---
# NOTE: Alpine公式apkに `tint` は存在しないため (Debian系のみ提供)、
# 上流ソースからビルドする。make 一発で 75KB程度のバイナリになる。
RUN git clone --depth 1 https://github.com/DavidGriffith/tint.git tint-src \
 && make -C tint-src \
 && ls -lh tint-src/tint \
 && cp tint-src/tint /tmp/tint \
 && strip /tmp/tint

# --- pacman4console (パックマン) ---
# NOTE: Alpineの `pacman` はArchのパッケージマネージャでありゲームではないため、
# Debian正規ソースtarballからビルドする。生成物は `pacman` という名前なので
# `pacman4console` に改名して配置する (紛らわしさ回避)。
RUN curl -sL -o /tmp/pacman4console.tar.gz \
      http://deb.debian.org/debian/pool/main/p/pacman4console/pacman4console_1.3.orig.tar.gz \
 && tar xzf /tmp/pacman4console.tar.gz -C /build \
 && patch -p1 -d /build/pacman-1.3 < /build/pacman-center.patch \
 && make -C /build/pacman-1.3 \
 && ls -lh /build/pacman-1.3/pacman \
 && cp /build/pacman-1.3/pacman /tmp/pacman4console \
 && strip /tmp/pacman4console \
 && mkdir -p /tmp/pacman-levels \
 && cp /build/pacman-1.3/Levels/level*.dat /tmp/pacman-levels/ \
 && ls /tmp/pacman-levels/ \
 && rm -f /tmp/pacman4console.tar.gz

# --- moon-buggy (横スクロール buggy) ---
# NOTE: 1.1.0はautotools構成。Alpineのbusybox sedではimg.sedが動かないため
# GNU sedを使い、欠品のmakeinfoは MAKEINFO=true で回避する。
RUN git clone --depth 1 https://github.com/seehuhn/moon-buggy.git moon-buggy-src \
 && cd moon-buggy-src \
 && autoreconf -fi \
 && ./configure --prefix=/usr \
 && make MAKEINFO=true \
 && ls -lh moon-buggy \
 && cp moon-buggy /tmp/moon-buggy \
 && strip /tmp/moon-buggy \
 && cd /build

# --- nsnake (高機能スネーク) ---
RUN git clone --depth 1 https://github.com/alexdantas/nSnake.git nsnake-src \
 && make -C nsnake-src \
 && ls -lh nsnake-src/bin/nsnake \
 && cp nsnake-src/bin/nsnake /tmp/nsnake \
 && strip /tmp/nsnake

# --- nudoku (数独) ---
RUN git clone --depth 1 https://github.com/jubalh/nudoku.git nudoku-src \
 && cd nudoku-src \
 && autoreconf -fi \
 && ./configure --prefix=/usr \
 && make \
 && ls -lh src/nudoku \
 && cp src/nudoku /tmp/nudoku \
 && strip /tmp/nudoku \
 && cd /build

# --- vitetris (テトリス variant) ---
# NOTE: 生成物は `tetris` という名前なので `vitetris` に改名して配置する。
RUN git clone --depth 1 https://github.com/vicgeralds/vitetris.git vitetris-src \
 && make -C vitetris-src \
 && ls -lh vitetris-src/tetris \
 && cp vitetris-src/tetris /tmp/vitetris \
 && strip /tmp/vitetris

# --- DASブリッジ用 xterm.js 資材 (2P同時長押し対応端末の描画に使用) ---
# NOTE: バージョン固定。200応答・実体サイズを確認してから採用すること。
# ランタイムは完全オフラインで動くよう、ビルド時に同梱する (CDN参照なし)。
RUN mkdir -p /tmp/das-static \
 && curl -sSL -o /tmp/das-static/xterm.js \
      https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js \
 && curl -sSL -o /tmp/das-static/xterm.css \
      https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css \
 && curl -sSL -o /tmp/das-static/addon-fit.js \
      https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.js \
 && ls -lh /tmp/das-static/ \
 && test -s /tmp/das-static/xterm.js \
 && test -s /tmp/das-static/xterm.css \
 && test -s /tmp/das-static/addon-fit.js

# ---------- Stage 2: runtime ----------
FROM alpine:latest

# bsd-games / nethack(rogue系) / ttyd は apk から取得
# 追加: micro-tetris(軽量テトリス) / gnuchess(チェス) / zangband(ローグライク)
# bash: メニュー実行用 / ncurses: 各ゲームの描画用
# python3: vitetris 2P同時長押し対応のDASブリッジ (das-bridge.py) 実行用 (stdlibのみ使用)
# NOTE: Alpineの bsd-games には `rogue` 本体が含まれないため、
# ターミナル対応のrogue系として `nethack` を追加。
# (brogueはSDL/GUI版でttydのターミナルでは動作しないため不採用)
# tint / pacman4console / moon-buggy / nsnake / nudoku / vitetris は上記でソースビルド。
# (Alpine公式apkに存在しないため)
RUN apk add --no-cache \
    bash \
    ncurses \
    ncurses-terminfo-base \
    python3 \
    bsd-games \
    nethack \
    micro-tetris \
    gnuchess \
    zangband \
    ttyd \
 && rm -rf /var/cache/apk/* \
            /usr/share/man/* \
            /usr/share/doc/*

# 自前ビルドの8本を配置
COPY --from=builder /tmp/2048 /usr/local/bin/2048
COPY --from=builder /tmp/ninvaders /usr/local/bin/ninvaders
COPY --from=builder /tmp/tint /usr/local/bin/tint
COPY --from=builder /tmp/pacman4console /usr/local/bin/pacman4console
COPY --from=builder /tmp/moon-buggy /usr/local/bin/moon-buggy
COPY --from=builder /tmp/nsnake /usr/local/bin/nsnake
COPY --from=builder /tmp/nudoku /usr/local/bin/nudoku
COPY --from=builder /tmp/vitetris /usr/local/bin/vitetris

# pacman4console のレベルデータ (バイナリは /usr/local/share/pacman/Levels/ を参照する)
COPY --from=builder /tmp/pacman-levels/ /usr/local/share/pacman/Levels/

# hangman (bsd-games) 用の英単語辞書 (Alpineにwordsパッケージが無いため同梱)
COPY words /usr/share/dict/words

# vitetris 用プリセットキー設定 (P1=WASD / P2=IJKL、ハードドロップ共通Space)
# P2デフォルトは全キー未設定のため、初期 ~/.vitetris として同梱する
COPY vitetris-config /root/.vitetris

# vitetris 2P同時長押し対応: DASブリッジ + 専用端末ページ + 同居起動スクリプト
# das-proxy/das-keys.js: :8080(ttyd)経路にもキー別DASを注入する透過プロキシ用
COPY --from=builder /tmp/das-static/ /opt/das-static/
COPY das-term.html /opt/das-static/das-term.html
COPY das-keys.js /opt/das-static/das-keys.js
COPY das-bridge.py /usr/local/bin/das-bridge.py
COPY das-proxy.py /usr/local/bin/das-proxy.py
COPY start-all.sh /usr/local/bin/start-all.sh

# メニュースクリプト
COPY game_menu.sh /usr/local/bin/game_menu.sh

RUN chmod +x /usr/local/bin/game_menu.sh \
              /usr/local/bin/das-bridge.py \
              /usr/local/bin/das-proxy.py \
              /usr/local/bin/start-all.sh \
              /usr/local/bin/2048 \
              /usr/local/bin/ninvaders \
              /usr/local/bin/tint \
              /usr/local/bin/pacman4console \
              /usr/local/bin/moon-buggy \
              /usr/local/bin/nsnake \
              /usr/local/bin/nudoku \
              /usr/local/bin/vitetris \
 && ls -lh /usr/local/bin/ \
 && command -v tint && command -v ttyd && command -v snake \
 && command -v nethack && command -v gnuchess && echo "runtime OK"

EXPOSE 8080 8081

ENV TERM=xterm-256color

# -W はブラウザからの入力許可に必須
# :8080=20本メニュー(ttyd) / :8081=vitetris 2P同時長押し対応DAS端末
CMD ["bash", "/usr/local/bin/start-all.sh"]
