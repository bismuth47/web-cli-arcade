#!/usr/bin/env bash
# =====================================================
# web-cli-arcade : GAME CAROUSEL MENU (20 games)
# ttyd 経由で自動実行される無限ループメニュー
# ←→矢印キーで選択 / Enterで起動 / 終了後は Enter で復帰
# =====================================================

# カラー定義 ($'' で実ESCバイトにする。echo -e / printf '%s' のどちらでも発色する)
RST=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
C_CYAN=$'\033[96m'
C_YELLOW=$'\033[93m'
C_GREEN=$'\033[92m'
C_MAGENTA=$'\033[95m'
C_RED=$'\033[91m'
C_BLUE=$'\033[94m'
C_WHITE=$'\033[97m'
BG_BLUE=$'\033[44m'

# ゲーム一覧: id|タイトル|ジャンル|説明|操作
GAMES=(
  "2048|2048|PUZZLE|数字を合体させて2048を作れ|矢印キーで移動"
  "ninvaders|nInvaders|ACTION|迫り来る侵略者を撃ち落とせ|←→移動 Space発射"
  "tint|tint TETRIS|PUZZLE|定番ブロック落とし|←→移動 ↓落下"
  "snake|snake|ACTION|餌を食べて伸びろ、壁に当たるな|矢印キーで移動"
  "rogue|rogue (nethack)|ROGUE|ダンジョン潜りの元祖ローグライク|hjkl移動 (vi風)"
  "pacman|PAC-MAN|ACTION|ドットを全部食べてゴーストをかわせ|矢印キー/wasd移動"
  "buggy|moon-buggy|ACTION|月のクレーターをジャンプで越えろ|Spaceジャンプ"
  "nsnake|nsnake|ACTION|多機能スネーク、障害物を避けろ|矢印キーで移動"
  "nudoku|nudoku|PUZZLE|ターミナルで遊ぶ数独|数字キー+矢印で入力"
  "vitetris|vitetris|PUZZLE|2人対戦テトリス(同一画面・同時プレイ)|1P:A/D/W/S/Q/E 2P:I/J/K/L/,/. (落下共通Space) 同時長押しDAS対応"
  "microtetris|micro-tetris|PUZZLE|IOCCC生まれの極小テトリス|j/k/l等で操作"
  "chess|gnuchess|BOARD|本格チェスエンジンと対局|英字で指し手入力"
  "zangband|zangband|ROGUE|Angband系ローグライクの深淵|hjkl移動"
  "adventure|adventure|ADVENTURE|伝説の洞窟探検テキスト冒険|英単語コマンド入力"
  "robots|robots|ACTION|殺人ロボットから逃げ切れ|hjkl/yubn移動"
  "worm|worm|ACTION|体が伸びるワームを操れ|矢印キーで移動"
  "sail|sail|STRATEGY|帆船同士の砲撃戦シミュレーション|コマンド入力"
  "battlestar|battlestar|ADVENTURE|宇宙要塞からの脱出冒険|英単語コマンド入力"
  "hangman|hangman|WORD|英単語当て・吊し人ゲーム|アルファベット入力"
  "wump|hunt the wumpus|ADVENTURE|暗い洞窟で怪物を狩れ|数字で移動先指定"
)

# ゲーム実体の解決 (Alpineでパスが違う場合の吸収)
resolve_cmd() {
  case "$1" in
    2048)        echo "/usr/local/bin/2048" ;;
    ninvaders)   echo "/usr/local/bin/ninvaders" ;;
    pacman)      echo "/usr/local/bin/pacman4console" ;;
    buggy)       echo "/usr/local/bin/moon-buggy" ;;
    nsnake)      echo "/usr/local/bin/nsnake" ;;
    nudoku)      echo "/usr/local/bin/nudoku" ;;
    vitetris)    echo "/usr/local/bin/vitetris" ;;
    microtetris)
      # micro-tetrisパッケージの実体は /usr/bin/tetris
      for c in /usr/bin/tetris micro-tetris microtetris tetris; do command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }; [ -x "$c" ] && { echo "$c"; return; }; done
      echo "/usr/bin/tetris"
      ;;
    chess)
      for c in gnuchess /usr/bin/gnuchess; do command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }; [ -x "$c" ] && { echo "$c"; return; }; done
      echo "gnuchess"
      ;;
    zangband)
      for c in zangband /usr/bin/zangband angband; do command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }; [ -x "$c" ] && { echo "$c"; return; }; done
      echo "zangband"
      ;;
    tint)
      for c in /usr/local/bin/tint tint /usr/bin/tint; do command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }; [ -x "$c" ] && { echo "$c"; return; }; done
      echo "tint"
      ;;
    snake)
      for c in snake /usr/bin/snake /usr/games/snake; do command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }; [ -x "$c" ] && { echo "$c"; return; }; done
      echo "snake"
      ;;
    rogue)
      # Alpineのbsd-gamesにrogueは含まれず、brogueはGUI版でttyd不可のため
      # ターミナル対応のrogue系 nethackを優先、無ければadventureにフォールバック
      for c in nethack /usr/bin/nethack rogue /usr/bin/rogue adventure; do command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }; [ -x "$c" ] && { echo "$c"; return; }; done
      echo "nethack"
      ;;
    adventure|robots|worm|sail|battlestar|hangman|wump|atc|gomoku|gofish)
      local c="$1"
      command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }
      [ -x "/usr/bin/$c" ] && { echo "/usr/bin/$c"; return; }
      echo "$c"
      ;;
  esac
}

# ---------------- アイコン集 (各ゲームの大型テキストアート) ----------------
icon_2048() { cat <<'EOF'
   +------+------+------+------+
   |      |      | 1024 | 2048 |
   +------+------+------+------+
   |  128 | 256  | 512  | 1024 |
   +------+------+------+------+
   |   16 |  32  |  64  | 128  |
   +------+------+------+------+
   |    2 |   4  |   8  |  16  |
   +------+------+------+------+
EOF
}
icon_ninvaders() { cat <<'EOF'
      _      _      _      _
     /_\    /_\    /_\    /_\
    (o o)  (o o)  (o o)  (o o)
   /| V |\ /| V |\ /| V |\ /| V |\
     | |    | |    | |    | |
    _| |_  _| |_  _| |_  _| |_
         \_ A _/
          /|\
         / | \
        |  |  |
EOF
}
icon_tint() { cat <<'EOF'
          +----+----+----+----+
          |    |    |    |    |
          +----+----+----+----+
     +----+----+
     |[][]|[][]|
     +----+----+
   +----+----+----+
   | ## | ## | ## |
   +----+----+----+
        +----+----+
        | @@ | @@ |
        +----+----+
EOF
}
icon_snake() { cat <<'EOF'
      oooooooooo
               o
     @         o    *
     |         o
     +---------o
     ....................
     :  S N A K E       :
     ....................
EOF
}
icon_rogue() { cat <<'EOF'
   ##########  ########
   #........#  #......#
   #........####......#
   #...@.......+......#
   #........####......#
   #........#  #..!...#
   ##########  ########
      THE DUNGEON AWAITS
EOF
}
icon_pacman() { cat <<'EOF'
         . . . . . . .
       .   .-""""-.   .
         /  (o)(o)  \
        |   ____    |    (..) (..)
         \  --   . /     | || | ||
          '-....-'       |_||_|_|
       . . . .o. . . . . . . . .
EOF
}
icon_buggy() { cat <<'EOF'
                    ______
          _________/      \_____
         |  ___            ___  |
         | (___)          (___) |
          ‾‾‾‾‾‾‾‾|    |‾‾‾‾‾‾‾‾‾‾‾
                  |    |
              ____|    |____
             /              \
            (   C R A T E R   )
             ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
EOF
}
icon_nsnake() { cat <<'EOF'
     +------------------+
     | oooooooo         |
     |          ##      |
     |  *       ##   @  |
     |     ##           |
     |     ##    ooooo  |
     +------------------+
        N S N A K E +
EOF
}
icon_nudoku() { cat <<'EOF'
     +-------+-------+-------+
     | 5 3 . | . 7 . | . . . |
     | 6 . . | 1 9 5 | . . . |
     | . 9 8 | . . . | . 6 . |
     +-------+-------+-------+
     | 8 . . | . 6 . | . . 3 |
     | 4 . . | 8 . 3 | . . 1 |
     +-------+-------+-------+
EOF
}
icon_vitetris() { cat <<'EOF'
            ______
           |  ##  |
           |  ##  |
        ___|__##__|
       |  ##  ##  |
       |__##__##__|
       |  ##  ##  |
       |__##__##__|
          V S TETRIS
EOF
}
icon_microtetris() { cat <<'EOF'
       ||
       ||  ##
       ||  ##
       ||####
       ||####
       ||####  ##
       ‾‾‾‾‾‾‾‾‾‾‾‾‾
       MICRO 64x64
EOF
}
icon_chess() { cat <<'EOF'
         .--.
        |♞  |
        |  Knight
         '--'
      +--+--+--+--+--+
      |##|  |##|  |##|
      +--+--+--+--+--+
      |  |##|  |##|  |
      +--+--+--+--+--+
EOF
}
icon_zangband() { cat <<'EOF'
            /\  /\
           (  \/  )
          (  \/\/  )
         /|  (@)(@) |\
        / |    <>    | \
          |  \____/  |
           \  MORDOR /
            \______/
       Z A N G B A N D
EOF
}
icon_adventure() { cat <<'EOF'
               /\
              /  \
             / /\ \
            / /  \ \
           | |    | |
           | |    | |
           | |____| |
           |  CAVE  |
           |________|
EOF
}
icon_robots() { cat <<'EOF'
        +------------+
        | [o]    [o] |
        |            |
        |  \______/  |
        +-----+------+
              |
         _____|_____
        |  KILLER   |
        |  ROBOTS   |
        ‾‾‾‾‾‾‾‾‾‾‾
            \_@
EOF
}
icon_worm() { cat <<'EOF'
      ~~~~~~~~~~~~~~~~~~~~
      ~  (\_/)  worm!    ~
      ~  (o.o)           ~
      ~  (>_<)~~~~~~~~~~~
      ~~~~~~~~~~~~~~~~~~~~
EOF
}
icon_sail() { cat <<'EOF'
              | |
              | |
         _____| |_____
         \    | |    /
          \   | |   /
       ~~~~~~~~~~~~~~~~~
       ~  S A I L  war ~
       ~~~~~~~~~~~~~~~~~
EOF
}
icon_battlestar() { cat <<'EOF'
          \  |  /
        --  (*)  --
          /  |  \
        BATTLESTAR
       |==========|
       | // || \\ |
       |==========|
EOF
}
icon_hangman() { cat <<'EOF'
         +---+
         |   |
         O   |
        /|\  |
        / \  |
             |
        =========
        _ A _ _ M A N
EOF
}
icon_wump() { cat <<'EOF'
        .----------.
       /  DARK     /
      /   CAVE    /|
     +----------+  |
     | (o)  (o) |  |
     |    __    | /
     |   (oo)   |/
     +----------+
       W U M P U S
EOF
}

pause_return() {
  term_size
  center_prompt "  ${BOLD}${C_YELLOW}Press Enter to return to menu...${RST}"
}

run_game() {
  local label="$1"
  local bin="$2"
  local gid="$3"
  shift 3
  if ! command -v "$bin" >/dev/null 2>&1 && [ ! -x "$bin" ]; then
    echo ""
    echo -e "  ${C_RED}[ERROR] '$bin' が見つかりません。apk/ビルドを確認してください。${RST}"
    pause_return
    return
  fi
  # ゲームごとの最小端末サイズを満たさない場合は起動せず警告に戻す
  # (pacman4console は getmaxyx で cols>=29 && rows>=32 を要求するため)
  local need=""
  case "$gid" in
    pacman) need="29 32" ;;
  esac
  if [ -n "$need" ]; then
    term_size
    local nc=${need%% *} nr=${need##* }
    if (( T_COLS < nc || T_LINES < nr )); then
      clear
      term_size
      print_centered_block \
        "${C_RED}${BOLD}$label には ${nc}x${nr} 以上の画面が必要です${RST}" \
        "" \
        "${DIM}いま: ${T_COLS}x${T_LINES} → ブラウザを広げる/文字を小さくして再試行${RST}" \
        ""
      pause_return
      return
    fi
  fi
  clear
  term_size
  center_print "  ${BG_BLUE}${BOLD}  >>> $label を起動中... (終了はゲーム内の quit 操作)  ${RST}"
  sleep 0.7
  clear
  # ゲーム実行 (終了コードは無視して必ずメニューに戻す)
  "$bin" "$@" || true
  # curses系が画面を崩すのでリセット
  command -v reset >/dev/null 2>&1 && reset || clear
  term_size
  center_print "  ${DIM}--- $label 終了 ---${RST}"
  pause_return
}

# ---------------- 中央寄せ表示ヘルパー ----------------
# 端末サイズ取得 (COLUMNS/LINES環境変数があれば優先、ttydのリサイズに追従)
term_size() {
  T_COLS=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
  T_LINES=${LINES:-$(tput lines 2>/dev/null || echo 24)}
  [[ $T_COLS =~ ^[0-9]+$ ]] || T_COLS=80
  [[ $T_LINES =~ ^[0-9]+$ ]] || T_LINES=24
}

# ANSIカラー列を除いた見かけ幅で水平中央に1行表示
center_print() {
  local line="$1" clean w pad=0
  clean=$(printf '%s' "$line" | sed $'s/\033\[[0-9;]*m//g')
  w=${#clean}
  (( T_COLS > w )) && pad=$(( (T_COLS - w) / 2 ))
  printf '%*s%s\n' "$pad" '' "$line"
}

# 行配列を受け取り、垂直中央に配置して中央表示
print_centered_block() {
  local total=$# top=0 i line
  (( T_LINES > total )) && top=$(( (T_LINES - total) / 2 ))
  for ((i=0; i<top; i++)); do echo; done
  for line in "$@"; do center_print "$line"; done
}

# 中央にプロンプトを出して1行読み取り
center_prompt() {
  local prompt="$1" clean w pad=0 _ans
  clean=$(printf '%s' "$prompt" | sed $'s/\033\[[0-9;]*m//g')
  w=${#clean}
  (( T_COLS > w )) && pad=$(( (T_COLS - w) / 2 ))
  printf '%*s%s' "$pad" '' "$prompt"
  IFS= read -r _ans
}

# 簡易オープニングアニメーション (中央表示・4フレーム順次)
intro_animation() {
  term_size
  local frames=(
    "  [■          ] LOADING..."
    "  [■■■■      ] LOADING..."
    "  [■■■■■■■   ] LOADING..."
    "  [■■■■■■■■■■] READY! 20 GAMES"
  )
  local f
  for f in "${frames[@]}"; do
    center_print "  ${C_CYAN}${f}${RST}"
    sleep 0.12
  done
  sleep 0.15
}

# カルーセル画面の描画 (画面全体を中央寄せ)
draw_screen() {
  local idx="$1" total="$2"
  local entry="${GAMES[$idx]}"
  local id title genre desc controls
  IFS='|' read -r id title genre desc controls <<< "$entry"
  # 位置インジケータ
  local bar="" i
  for ((i=0; i<total; i++)); do
    if [ "$i" -eq "$idx" ]; then bar+="●"; else bar+="○"; fi
  done
  term_size
  clear
  local -a scr=()
  scr+=("${C_MAGENTA}${BOLD}★ WEB CLI ARCADE ★${RST}  ${DIM}$((idx+1)) / $total${RST}")
  scr+=("${DIM}────────────────────────────────${RST}")
  scr+=("")
  local iline
  while IFS= read -r iline || [[ -n $iline ]]; do
    scr+=("${C_CYAN}${iline}${RST}")
  done < <("icon_$id")
  scr+=("")
  scr+=("${BOLD}${C_WHITE}### $title ###${RST}  ${BG_BLUE}${BOLD} $genre ${RST}")
  scr+=("${C_GREEN}$desc${RST}")
  scr+=("${DIM}操作: $controls${RST}")
  scr+=("")
  scr+=("${C_YELLOW}◀ $bar ▶${RST}")
  scr+=("")
  scr+=("${DIM}← → : えらぶ   Enter : あそぶ   q : おわる${RST}")
  print_centered_block "${scr[@]}"
}

# キー入力 (矢印/Enter/q を判別)
read_key() {
  local k rest
  IFS= read -rsn1 k || { echo "QUIT"; return; }
  if [[ $k == $'\x1b' ]]; then
    IFS= read -rsn2 -t 0.3 rest || rest=""
    k+="$rest"
  fi
  case "$k" in
    $'\x1b[C') echo "RIGHT" ;;
    $'\x1b[D') echo "LEFT" ;;
    "") echo "ENTER" ;;
    $'\n'|$'\r') echo "ENTER" ;;
    q|Q|$'\x03') echo "QUIT" ;;
    h|H|a|A) echo "LEFT" ;;
    l|L|d|D) echo "RIGHT" ;;
    *) echo "OTHER" ;;
  esac
}

# ---- 起動直後の演出は1回だけ ----
term_size
clear
print_centered_block \
  "${C_CYAN}${BOLD}   ____  ___  ____________  ____     ___    ____  ___________    ____  ____${RST}" \
  "${C_CYAN}${BOLD}  / __ \/ _ \/ ___/_  __/  / __ \   /   |  / __ \/ ____/   |  / __ \/ __ \ ${RST}" \
  "${C_CYAN}${BOLD} / /_/ /  __/ /    / /    / /_/ /  / /| | / /_/ / /   / /| | / / / / / / /${RST}" \
  "${C_CYAN}${BOLD}/ _, _/\___/_/    /_/    \____/   /_/  |_|\____/_/   /_/  |_|/_/ /_/_/ /_/${RST}" \
  "" \
  "${C_MAGENTA}${BOLD}★☆★  WEB CLI ARCADE - 20 GAMES  ★☆★${RST}" \
  ""
intro_animation
sleep 0.2

# ---- 無限ループ・カルーセル ----
CUR=0
TOTAL=${#GAMES[@]}
while true; do
  draw_screen "$CUR" "$TOTAL"
  KEY=$(read_key)
  case "$KEY" in
    RIGHT) CUR=$(( (CUR + 1) % TOTAL )) ;;
    LEFT)  CUR=$(( (CUR - 1 + TOTAL) % TOTAL )) ;;
    ENTER)
      entry="${GAMES[$CUR]}"
      IFS='|' read -r gid gtitle _gg _gd _gc <<< "$entry"
      run_game "$gtitle" "$(resolve_cmd "$gid")" "$gid"
      ;;
    QUIT)
      term_size
      clear
      print_centered_block \
        "${C_CYAN}${BOLD}Thanks for playing! See you again... 👾${RST}" \
        "${DIM}(ttydセッションを切断して終了 / 再接続でメニュー復帰)${RST}"
      sleep 1
      exit 0
      ;;
  esac
done
