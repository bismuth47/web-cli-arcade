#!/usr/bin/env bash
# =====================================================
# start-all.sh : 3サービス同居起動
# - :8080 … 20本メニュー (das-proxy → 背後のttyd。DASキー注入付き)
# - :8081 … vitetris 2P専用・同時長押しDAS対応端末 (das-bridge.py)
# ttyd本体は 127.0.0.1:18080 のみで待ち受け、外部公開はプロキシ経由のみ。
# =====================================================
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
exec ttyd -p 18080 -i 127.0.0.1 -W bash /usr/local/bin/game_menu.sh
