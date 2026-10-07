#!/usr/bin/env python3
# =====================================================
# das-bridge.py : vitetris 2P 同時長押し対応ブリッジ
#
# 背景:
#   通常の ttyd 経路では、長押しの連打はブラウザ/OS のキーリピート
#   (typamatic) に依存する。typamatic は「最後に押した1キー」しか
#   リピートしないため、1P が D を長押し中に 2P がキーを押すと
#   1P のリピートが止まる。同時長押しも同様に片方しか進まない。
#   コンテナ側に届くのは文字ストリームのみで「離した」情報が無いため、
#   コンテナ内だけでは同時DASは実現できない。
#
# 方式:
#   専用ページ (das-term.html) が keydown/keyup を e.code 単位で送信し、
#   本ブリッジがキーごとの押下状態を保持して、移動系キーに自前DAS
#   (初動即時 + DAS_DELAY後に DAS_RATE間隔でリピート) をかけて pty に
#   書き込む。各キーが独立した状態を持つため、1P/2P の同時長押しが
#   互いに干渉せずリピートする。
#
# 依存: Python3 標準ライブラリのみ (http/socket/pty/threading)。
# =====================================================
import argparse
import base64
import hashlib
import json
import os
import pty
import select
import signal
import struct
import termios
import fcntl
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
CTL_PREFIX = "\x01"  # サーバ→クライアント制御フレームの目印 (vitetrisは出さない)

# DAS パラメータ (秒)
DAS_DELAY = 0.17  # 初動後の待ち
DAS_RATE = 0.05   # リピート間隔
TICK = 0.01       # 状態tick

# e.code -> vitetrisのアクション名 ([stdin]セクションのキー名に対応)。
# 実際の送信文字は ~/.vitetris の [stdin] から引くため、
# Input Setup でキーを変えてもブリッジ側の改修は不要。
CODE_ACTION = {
    "KeyA": "p1left", "KeyD": "p1right", "KeyS": "p1down",
    "KeyW": "p1up", "KeyQ": "p1a", "KeyE": "p1b",
    "KeyJ": "p2left", "KeyL": "p2right", "KeyK": "p2down",
    "KeyI": "p2up", "Comma": "p2a", "Period": "p2b",
    "Space": "hdrop",
}
# 長押しリピート対象のアクション (移動/ソフトドロップ)。回転/ハードは単発。
REPEAT_ACTIONS = {"p1left", "p1right", "p1down",
                  "p2left", "p2right", "p2down"}
# 矢印/Enter/Esc/数字など、設定に依存しない固定キー: e.code -> (送信内容, リピート)
# 矢印は ESCシーケンスのまま送る (vitetris側がP1に割当て/メニュー操作用)。
FIXED_KEYS = {
    "ArrowLeft": ("\x1b[D", True), "ArrowRight": ("\x1b[C", True),
    "ArrowDown": ("\x1b[B", True), "ArrowUp": ("\x1b[A", False),
    "KeyP": ("p", False),
    "Enter": ("\r", False), "Escape": ("\x1b", False),
}
for _i in range(10):
    FIXED_KEYS["Digit%d" % _i] = (str(_i), False)

# vitetris-config のデフォルト ([stdin] が無い場合のフォールバック)
DEFAULT_STDIN = {
    "p1left": "a", "p1right": "d", "p1up": "w", "p1down": "s",
    "p1a": "q", "p1b": "e",
    "p2left": "j", "p2right": "l", "p2up": "i", "p2down": "k",
    "p2a": ",", "p2b": ".", "hdrop": " ",
}


def load_stdin_map(path):
    """~/.vitetris の [stdin] セクションを {アクション名: 1文字} で読む。
    値が整数の場合は vitetris の stdin_convertval 互換で文字化する。
    読めなければデフォルトを返す。"""
    m = dict(DEFAULT_STDIN)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return m
    in_stdin = False
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            in_stdin = line[1:].split("]")[0].strip() == "stdin"
            continue
        if not in_stdin or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        if not k or not v:
            continue
        if len(v) == 1:
            m[k] = v
            continue
        try:
            n = int(v)
        except ValueError:
            continue
        if n < 0:
            continue
        elif n < 10:
            m[k] = chr(ord("0") + n)
        elif n <= 32:
            m[k] = chr(n)  # 32=space 等
        elif n < 127:
            m[k] = chr(n)
    return m


def build_keymap(stdin_map):
    """e.code -> (送信文字, リピート対象か) を構成する。"""
    km = dict(FIXED_KEYS)
    for code, action in CODE_ACTION.items():
        ch = stdin_map.get(action, DEFAULT_STDIN.get(action))
        if not ch:
            continue
        km[code] = (ch, action in REPEAT_ACTIONS)
    return km


KEYMAP = build_keymap(DEFAULT_STDIN)


class Bridge:
    def __init__(self, cmd, static_dir, index_file, cfg_path=None):
        self.cmd = cmd
        self.static_dir = static_dir
        self.index_file = index_file
        cfg = cfg_path or os.environ.get("VITETRIS_CFG", "/root/.vitetris")
        self.keymap = build_keymap(load_stdin_map(cfg))
        print("keymap from %s: %s" % (cfg, sorted(
            "%s=%r%s" % (c, ch, "*" if rep else "")
            for c, (ch, rep) in self.keymap.items()
            if c in CODE_ACTION or c == "Space")), flush=True)
        self.lock = threading.Lock()
        self.clients = set()          # 接続中ソケット
        self.send_lock = threading.Lock()
        self.held = {}                # code -> {ch, repeat, next_emit}
        self.cols = 96
        self.rows = 30
        self.master_fd = None
        self.child_pid = None
        self.alive = False
        with open(index_file, "rb") as f:
            self.index_bytes = f.read()
        self.static_cache = {}
        for name, ctype in (("xterm.js", "text/javascript"),
                            ("xterm.css", "text/css"),
                            ("addon-fit.js", "text/javascript")):
            p = os.path.join(static_dir, name)
            if os.path.exists(p):
                with open(p, "rb") as f:
                    self.static_cache[name] = (ctype, f.read())
        self.decoder = __import__("codecs").getincrementaldecoder("utf-8")(errors="replace")

    # ---------- pty / child ----------
    def spawn(self):
        with self.lock:
            if self.alive:
                return False
            try:
                pid, fd = pty.fork()
            except OSError:
                return False
            if pid == 0:
                # child
                try:
                    self._set_winsize(0)
                except OSError:
                    pass
                env = dict(os.environ)
                env["TERM"] = "xterm-256color"
                try:
                    os.execvpe(self.cmd[0], self.cmd, env)
                except Exception:
                    os._exit(127)
            # parent
            self.child_pid = pid
            self.master_fd = fd
            self.alive = True
            try:
                fl = fcntl.fcntl(fd, fcntl.F_GETFL)
                fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
            except OSError:
                pass
            threading.Thread(target=self._reader, daemon=True).start()
            self._broadcast_ctl({"sys": "running"})
            return True

    def _set_winsize(self, fd):
        s = struct.pack("HHHH", self.rows, self.cols, 0, 0)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, s)

    def resize(self, cols, rows):
        cols = max(20, min(400, int(cols)))
        rows = max(10, min(120, int(rows)))
        with self.lock:
            self.cols, self.rows = cols, rows
            if self.alive and self.master_fd is not None:
                try:
                    self._set_winsize(self.master_fd)
                    os.kill(self.child_pid, signal.SIGWINCH)
                except OSError:
                    pass

    def _write_pty(self, data: bytes):
        with self.lock:
            if not self.alive or self.master_fd is None:
                return
            try:
                os.write(self.master_fd, data)
            except OSError:
                pass

    def _reader(self):
        fd = self.master_fd
        buf = b""
        while True:
            try:
                r, _, _ = select.select([fd], [], [], 0.2)
            except (OSError, ValueError):
                break
            if r:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                text = self.decoder.decode(chunk)
                if text:
                    self._broadcast_text(text)
        # child 終了
        with self.lock:
            self.alive = False
            try:
                os.close(fd)
            except OSError:
                pass
            if self.master_fd == fd:
                self.master_fd = None
        self.held.clear()
        self._broadcast_ctl({"sys": "exit"})

    # ---------- DAS ----------
    def key_down(self, code):
        m = self.keymap.get(code)
        if not m:
            return
        ch, repeat = m
        now = time.monotonic()
        with self.lock:
            if code in self.held:
                return  # OSリピート等の重複downは無視
            if not self.alive:
                self._spawn_locked()
                if not self.alive:
                    return
            self.held[code] = {"ch": ch, "repeat": repeat,
                               "next_emit": now + DAS_DELAY}
        self._write_pty(ch.encode("utf-8", "replace"))

    def _spawn_locked(self):
        # lock保持中のspawn (spawn()と同等、再帰ロック回避のため内製)
        try:
            pid, fd = pty.fork()
        except OSError:
            return
        if pid == 0:
            try:
                self._set_winsize(0)
            except OSError:
                pass
            env = dict(os.environ)
            env["TERM"] = "xterm-256color"
            try:
                os.execvpe(self.cmd[0], self.cmd, env)
            except Exception:
                os._exit(127)
        self.child_pid = pid
        self.master_fd = fd
        self.alive = True
        try:
            fl = fcntl.fcntl(fd, fcntl.F_GETFL)
            fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
        except OSError:
            pass
        threading.Thread(target=self._reader, daemon=True).start()

    def key_up(self, code):
        with self.lock:
            self.held.pop(code, None)

    def clear_held(self):
        with self.lock:
            self.held.clear()

    def ticker(self):
        while True:
            time.sleep(TICK)
            now = time.monotonic()
            due = []
            with self.lock:
                for code, st in self.held.items():
                    if st["repeat"] and now >= st["next_emit"]:
                        due.append((code, st))
                        # 長時間stall後のバースト抑止: 最大1回分に畳む
                        if now - st["next_emit"] > 3 * DAS_RATE:
                            st["next_emit"] = now + DAS_RATE
                        else:
                            st["next_emit"] += DAS_RATE
            for _, st in due:
                self._write_pty(st["ch"].encode("utf-8", "replace"))

    # ---------- websocket ----------
    def _broadcast_text(self, text):
        self._broadcast_raw(text.encode("utf-8"))

    def _broadcast_ctl(self, obj):
        self._broadcast_raw((CTL_PREFIX + json.dumps(obj)).encode("utf-8"))

    def _broadcast_raw(self, payload: bytes):
        frame = b"\x81" + self._len_bytes(len(payload)) + payload
        dead = []
        with self.send_lock:
            for c in list(self.clients):
                try:
                    c.sendall(frame)
                except OSError:
                    dead.append(c)
            for c in dead:
                self.clients.discard(c)

    @staticmethod
    def _len_bytes(n):
        if n < 126:
            return bytes([n])
        if n < 65536:
            return bytes([126]) + struct.pack(">H", n)
        return bytes([127]) + struct.pack(">Q", n)

    def ws_send(self, conn, payload: bytes):
        with self.send_lock:
            try:
                conn.sendall(b"\x81" + self._len_bytes(len(payload)) + payload)
            except OSError:
                pass

    def ws_loop(self, conn):
        conn.settimeout(60)
        buf = b""
        try:
            while True:
                try:
                    data = conn.recv(65536)
                except socket.timeout:
                    # keepalive ping
                    with self.send_lock:
                        try:
                            conn.sendall(b"\x89\x00")
                        except OSError:
                            break
                    continue
                if not data:
                    break
                buf += data
                while True:
                    msg, buf = self._parse_frame(buf)
                    if msg is None:
                        break
                    self._on_ws_msg(conn, msg)
                    if msg == "CLOSE":
                        return
        finally:
            with self.send_lock:
                self.clients.discard(conn)
                nobody = not self.clients
            if nobody:
                # 誰も見ていない間のリピート残留(スタックキー)を防ぐ
                self.clear_held()
            try:
                conn.close()
            except OSError:
                pass

    def _parse_frame(self, buf):
        # -> (msg|None, rest). msg は str(close時は"CLOSE") / None=継続待ち
        if len(buf) < 2:
            return None, buf
        fin_op = buf[0]
        op = fin_op & 0x0F
        masked = buf[1] & 0x80
        ln = buf[1] & 0x7F
        idx = 2
        if ln == 126:
            if len(buf) < 4:
                return None, buf
            ln = struct.unpack(">H", buf[2:4])[0]
            idx = 4
        elif ln == 127:
            if len(buf) < 10:
                return None, buf
            ln = struct.unpack(">Q", buf[2:10])[0]
            idx = 10
        if masked:
            if len(buf) < idx + 4:
                return None, buf
            mask = buf[idx:idx + 4]
            idx += 4
        if len(buf) < idx + ln:
            return None, buf
        payload = buf[idx:idx + ln]
        rest = buf[idx + ln:]
        if masked:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if op == 0x8:
            return "CLOSE", rest
        if op == 0x9:  # ping -> pong (payloadそのまま)
            return ("PONG", payload), rest
        if op == 0xA:  # pong
            return ("IGN", b""), rest
        if op in (0x1, 0x2):
            try:
                return payload.decode("utf-8"), rest
            except UnicodeDecodeError:
                return ("IGN", b""), rest
        return ("IGN", b""), rest

    def _on_ws_msg(self, conn, msg):
        if msg == "CLOSE":
            try:
                with self.send_lock:
                    conn.sendall(b"\x88\x00")
            except OSError:
                pass
            return
        if isinstance(msg, tuple):
            if msg[0] == "PONG":
                with self.send_lock:
                    try:
                        conn.sendall(b"\x8A" + self._len_bytes(len(msg[1])) + msg[1])
                    except OSError:
                        pass
            return
        if msg == "IGN":
            return
        try:
            obj = json.loads(msg)
        except (ValueError, TypeError):
            return
        t = obj.get("t")
        if t == "down":
            self.key_down(str(obj.get("code", "")))
        elif t == "up":
            self.key_up(str(obj.get("code", "")))
        elif t == "resize":
            try:
                self.resize(obj.get("cols", 96), obj.get("rows", 30))
            except (ValueError, TypeError):
                pass
        elif t == "start":
            if self.spawn():
                pass
            else:
                with self.lock:
                    running = self.alive
                self.ws_send(conn, (CTL_PREFIX + json.dumps(
                    {"sys": "running" if running else "exit"})).encode())

    # ---------- http ----------
    def make_handler(self):
        bridge = self

        class H(BaseHTTPRequestHandler):
            server_version = "das-bridge/1.0"

            def log_message(self, fmt, *args):
                pass

            def do_GET(self):
                if self.headers.get("Upgrade", "").lower() == "websocket":
                    self._ws_handshake()
                    return
                if self.path in ("/", "/index.html"):
                    body = bridge.index_bytes
                    ctype = "text/html; charset=utf-8"
                elif self.path.startswith("/static/"):
                    name = self.path[len("/static/"):]
                    if name in bridge.static_cache:
                        ctype, body = bridge.static_cache[name]
                    else:
                        self.send_error(404)
                        return
                else:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                try:
                    self.wfile.write(body)
                except OSError:
                    pass

            def _ws_handshake(self):
                key = self.headers.get("Sec-WebSocket-Key", "")
                if not key:
                    self.send_error(400)
                    return
                acc = base64.b64encode(hashlib.sha1(
                    (key + WS_GUID).encode()).digest()).decode()
                self.send_response(101, "Switching Protocols")
                self.send_header("Upgrade", "websocket")
                self.send_header("Connection", "Upgrade")
                self.send_header("Sec-WebSocket-Accept", acc)
                self.end_headers()
                conn = self.connection
                with bridge.send_lock:
                    bridge.clients.add(conn)
                # 既存の画面を新規クライアントに再送できないため状態通知のみ
                with bridge.lock:
                    running = bridge.alive
                bridge.ws_send(conn, (CTL_PREFIX + json.dumps(
                    {"sys": "running" if running else "exit",
                     "cols": bridge.cols, "rows": bridge.rows})).encode())
                self.close_connection = True
                bridge.ws_loop(conn)

        return H


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8081)
    ap.add_argument("--cmd", nargs=argparse.REMAINDER, default=["/usr/local/bin/vitetris"])
    ap.add_argument("--static", default="/opt/das-static")
    ap.add_argument("--index", default="/opt/das-static/das-term.html")
    ap.add_argument("--cols", type=int, default=96)
    ap.add_argument("--rows", type=int, default=30)
    ap.add_argument("--cfg", default=None,
                    help="vitetris設定ファイル (~/.vitetris)。未指定時は "
                         "VITETRIS_CFG か /root/.vitetris")
    a = ap.parse_args()
    if not a.cmd:
        a.cmd = ["/usr/local/bin/vitetris"]

    bridge = Bridge(a.cmd, a.static, a.index, a.cfg)
    bridge.cols = a.cols
    bridge.rows = a.rows
    bridge.spawn()
    threading.Thread(target=bridge.ticker, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", a.port), bridge.make_handler())
    srv.daemon_threads = True
    print("das-bridge listening on :%d cmd=%s" % (a.port, a.cmd), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
