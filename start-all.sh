#!/usr/bin/env bash
# =====================================================
# start-all.sh : 3サービス同居起動
# - :8080 … 20本メニュー (das-proxy → 背後のttyd。DASキー注入付き)
# - :8081 … vitetris 2P専用・同時長押しDAS対応端末 (das-bridge.py)
# ttyd本体は 127.0.0.1:18080 のみで待ち受け、外部公開はプロキシ経由のみ。
# :8080 の実体は tmux セッション (game ウィンドウ + shell ウィンドウ)。
#   Ctrl+A で ゲーム ⇔ 裏bash を同一画面トグル (状態維持)。
# =====================================================
TMUX_SOCK=/tmp/arcade.sock
# tmux が非UTF-8扱いになると罫線/●○◀▶★ が _ に化けるため UTF-8 を強制
export LC_ALL=C.UTF-8 LANG=C.UTF-8
TMUX="tmux -u -S $TMUX_SOCK"

# 古いセッション残骸があれば掃除
if $TMUX has-session -t arcade 2>/dev/null; then
  $TMUX kill-session -t arcade 2>/dev/null || true
fi
rm -f "$TMUX_SOCK"

# window 0: game (メニュー) / window 1: shell (裏Linux bash)
$TMUX new-session -d -s arcade -n game -x 120 -y 30 \
  'bash /usr/local/bin/game_menu.sh'
$TMUX new-window -t arcade -n shell bash
$TMUX select-window -t arcade:game
# メニュー表示を崩さないようステータスバーは消す
$TMUX set-option -g status off
# prefix不要で Ctrl+A → 直前のウィンドウにトグル
$TMUX bind-key -n C-a last-window
chmod 700 "$TMUX_SOCK" 2>/dev/null || true

python3 /usr/local/bin/das-bridge.py \
  --port 8081 \
  --static /opt/das-static \
  --index /opt/das-static/das-term.html \
  --cmd /usr/local/bin/vitetris &
python3 /usr/local/bin/das-proxy.py \
  --port 8080 \
  --upstream 127.0.0.1 \
  --upstream-port 18080 \
  --js /opt/das-static/das-keys.js &
exec ttyd -p 18080 -i 127.0.0.1 -W tmux -u -S "$TMUX_SOCK" attach -t arcade
