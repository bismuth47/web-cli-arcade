#!/usr/bin/env python3
# =====================================================
# das-proxy.py : ttyd透過プロキシ + DASキー注入
#
# :8080 で待ち受け、背後の ttyd (127.0.0.1:18080) に中継する。
# ttydトップページ (/) に <script src="/das-keys.js"> を差し込み、
# ブラウザ側でキーごとの押下状態+DASリピートを行わせる。
# (/ws のWebSocket等はバイナリ透過で一切触らない)
#
# 背景: ttyd経路の長押し連打はOS/ブラウザのキーリピート依存で、
# リピートは「最後に押した1キー」にしか効かない。1P/2Pの同時長押しを
# 両立させるには、キーup/downを個別に扱う必要がある。
# =====================================================
import argparse
import os
import socket
import threading

BUF = 65536
JS_PATH_DEFAULT = "/opt/das-static/das-keys.js"


def recv_head(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        try:
            chunk = conn.recv(BUF)
        except OSError:
            return None
        if not chunk:
            return None if not data else data
        data += chunk
        if len(data) > 65536:
            return None
    i = data.find(b"\r\n\r\n") + 4
    return data[:i], data[i:]


def parse_head(head):
    try:
        text = head.decode("latin-1")
    except UnicodeDecodeError:
        return None, None, {}
    lines = text.split("\r\n")
    first = lines[0].split(" ", 2)
    if len(first) < 2:
        return None, None, {}
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    return first[0], first[1], headers


def read_body(conn, headers, initial):
    body = initial
    if headers.get("transfer-encoding", "").lower() == "chunked":
        raw = body
        out = b""

        def more(n):
            nonlocal raw
            while len(raw) < n:
                try:
                    c = conn.recv(BUF)
                except OSError:
                    return False
                if not c:
                    return False
                raw += c
            return True

        while True:
            if not more(1):
                break
            j = raw.find(b"\r\n")
            while j < 0:
                if not more(len(raw) + 1):
                    break
                j = raw.find(b"\r\n")
            if j < 0:
                break
            try:
                size = int(raw[:j].split(b";")[0].strip(), 16)
            except ValueError:
                break
            raw = raw[j + 2:]
            if size == 0:
                break
            if not more(size + 2):
                break
            out += raw[:size]
            raw = raw[size + 2:]
        return out
    try:
        n = int(headers.get("content-length", "-1"))
    except ValueError:
        n = -1
    if n < 0:
        # 長さ不明はEOFまで
        chunks = [body]
        while True:
            try:
                c = conn.recv(BUF)
            except OSError:
                break
            if not c:
                break
            chunks.append(c)
        return b"".join(chunks)
    while len(body) < n:
        try:
            c = conn.recv(BUF)
        except OSError:
            break
        if not c:
            break
        body += c
    return body[:n]


def relay(a, b):
    try:
        while True:
            d = a.recv(BUF)
            if not d:
                break
            b.sendall(d)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                s.close()
            except OSError:
                pass


def blind_relay(client, upstream_host, upstream_port):
    try:
        up = socket.create_connection((upstream_host, upstream_port), timeout=10)
    except OSError:
        try:
            client.close()
        except OSError:
            pass
        return
    t = threading.Thread(target=relay, args=(up, client), daemon=True)
    t.start()
    relay(client, up)


INJECT_TAG = b'<script src="/das-keys.js"></script>'


def handle(client, up_host, up_port, js_bytes):
    try:
        up = socket.create_connection((up_host, up_port), timeout=10)
    except OSError:
        try:
            client.close()
        except OSError:
            pass
        return
    try:
        got = recv_head(client)
        if got is None:
            up.close()
            client.close()
            return
        req_head, req_extra = got
        method, path, headers = parse_head(req_head)
        if method is None:
            up.close()
            client.close()
            return
        clean_path = path.split("?", 1)[0]

        # 自前JSの配信
        if method == "GET" and clean_path == "/das-keys.js" and \
                "upgrade" not in headers:
            resp = (b"HTTP/1.1 200 OK\r\nContent-Type: text/javascript\r\n" +
                    b"Content-Length: " + str(len(js_bytes)).encode() +
                    b"\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" +
                    js_bytes)
            try:
                client.sendall(resp)
            except OSError:
                pass
            up.close()
            client.close()
            return

        inject = (method == "GET" and clean_path in ("/", "/index.html")
                  and "upgrade" not in headers)
        if inject:
            # ブラウザは gzip/br を要求するが、圧縮応答には注入できないため
            # 上流への要求を identity に書き換えて必ず平文で受け取る。
            # (stdlibにbrotliが無いため、受側での解凍はしない)
            lines = req_head.decode("latin-1").split("\r\n")
            lines = [l if not l.lower().startswith("accept-encoding:")
                     else "Accept-Encoding: identity" for l in lines]
            req_head = ("\r\n".join(lines)).encode("latin-1")
        try:
            up.sendall(req_head + req_extra)
        except OSError:
            up.close()
            client.close()
            return
        if not inject:
            # WebSocket等は完全透過
            t = threading.Thread(target=relay, args=(up, client), daemon=True)
            t.start()
            relay(client, up)
            return

        # トップページ応答を横取りして注入を試みる
        rhead = recv_head(up)
        if rhead is None:
            up.close()
            client.close()
            return
        resp_head, resp_extra = rhead
        _m, status, rheaders = parse_head(resp_head)
        ctype = rheaders.get("content-type", "")
        cenc = rheaders.get("content-encoding", "identity")
        if status != "200" or "html" not in ctype or \
                cenc.lower() not in ("identity", ""):
            try:
                client.sendall(resp_head + resp_extra)
            except OSError:
                up.close()
                client.close()
                return
            t = threading.Thread(target=relay, args=(up, client), daemon=True)
            t.start()
            relay(client, up)
            return
        body = read_body(up, rheaders, resp_extra)
        up.close()
        low = body.lower()
        idx = low.rfind(b"</body>")
        if idx >= 0:
            body = body[:idx] + INJECT_TAG + body[idx:]
        else:
            body = body + INJECT_TAG
        out_lines = []
        for line in resp_head.decode("latin-1").split("\r\n"):
            kl = line.split(":", 1)[0].strip().lower()
            if kl in ("content-length", "transfer-encoding", "connection",
                      "content-encoding"):
                continue
            out_lines.append(line)
        out_lines.append("Content-Length: %d" % len(body))
        out_lines.append("Connection: close")
        out_lines.append("Cache-Control: no-store")
        try:
            client.sendall(("\r\n".join(out_lines) + "\r\n\r\n").encode("latin-1")
                           + body)
        except OSError:
            pass
        try:
            client.close()
        except OSError:
            pass
    except Exception:
        for s in (client, up):
            try:
                s.close()
            except OSError:
                pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--upstream", default="127.0.0.1")
    ap.add_argument("--upstream-port", type=int, default=18080)
    ap.add_argument("--js", default=JS_PATH_DEFAULT)
    a = ap.parse_args()
    with open(a.js, "rb") as f:
        js_bytes = f.read()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((a.listen, a.port))
    srv.listen(64)
    print("das-proxy :%d -> %s:%d" % (a.port, a.upstream, a.upstream_port),
          flush=True)
    while True:
        try:
            conn, _ = srv.accept()
        except OSError:
            break
        threading.Thread(target=handle,
                         args=(conn, a.upstream, a.upstream_port, js_bytes),
                         daemon=True).start()


if __name__ == "__main__":
    main()
