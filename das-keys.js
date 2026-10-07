"use strict";
/* =====================================================
 * das-keys.js : ttydページ用・キー別DAS注入
 * (das-proxy.py が ttydトップページに差し込む)
 *
 * 背景: ttyd経路の長押し連打はOS/ブラウザのキーリピート依存で、
 * リピートは「最後に押した1キー」にしか効かない。1P/2Pの同時長押しを
 * 両立させるため、本スクリプトが keydown/keyup をキーごとに管理し、
 * 自前DAS (初動即時 + 170ms後に50ms間隔) で合成keydownを xterm に送る。
 * ブラウザ本来のリピート(e.repeat)は抑止する。
 * F9または右下バッジで ON/OFF 切替 (既定ON)。
 * ===================================================== */
(function () {
  var DAS_DELAY = 170, DAS_RATE = 50;
  var enabled = true;
  var held = {}; // code -> {evt, timer}
  var stats = { seen: 0, repeats: 0, taken: 0, synthetic: 0 };

  function isGameKey(e) {
    if (e.ctrlKey || e.metaKey || e.altKey) return false;
    if (e.isComposing || e.key === "Process" || e.keyCode === 229) return false;
    if (!e.key) return false;
    if (e.key.length === 1) return true;
    return e.key === "ArrowUp" || e.key === "ArrowDown" ||
      e.key === "ArrowLeft" || e.key === "ArrowRight" ||
      e.key === "Enter" || e.key === "Escape" || e.key === "Backspace";
  }

  function target() {
    var t = document.querySelector("textarea.xterm-helper-textarea");
    if (t) return t;
    t = document.querySelector("#terminal textarea");
    if (t) return t;
    return document.activeElement;
  }

  // xtermは keyCode で判定するキーがある (矢印/Enter/Esc等) ため、
  // 合成イベントにも keyCode/which を付与する (init辞書では入らないので後付け)。
  var CODEKEYS = {
    ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40,
    Enter: 13, Escape: 27, Backspace: 8, Space: 32,
    Comma: 188, Period: 190, Slash: 191, Semicolon: 186, Quote: 222,
    BracketLeft: 219, BracketRight: 221, Backquote: 192, Minus: 189,
    Equal: 187, Tab: 9
  };
  function keyCodeFor(st) {
    if (CODEKEYS[st.code]) return CODEKEYS[st.code];
    var k = st.key || "";
    if (k.length === 1) {
      var c = k.toUpperCase().charCodeAt(0);
      if (c >= 65 && c <= 90) return c; // A-Z
      if (c >= 48 && c <= 57) return c; // 0-9
      var m = { ",": 188, ".": 190, "/": 191, ";": 186, "'": 222,
        "[": 219, "]": 221, "`": 192, "-": 189, "=": 187, "\\": 220,
        " ": 32 };
      if (m[k]) return m[k];
    }
    return 0;
  }

  function press(st) {
    var t = target();
    if (!t) return;
    var ev;
    try {
      ev = new KeyboardEvent("keydown", {
        key: st.key, code: st.code, location: st.location || 0,
        shiftKey: !!st.shiftKey,
        bubbles: true, cancelable: true, composed: true
      });
    } catch (err) { return; }
    var kc = keyCodeFor(st);
    try {
      Object.defineProperty(ev, "keyCode", { value: kc });
      Object.defineProperty(ev, "which", { value: kc });
    } catch (e) {}
    stats.synthetic++;
    t.dispatchEvent(ev);
  }

  function tick(code) {
    var st = held[code];
    if (!st) return;
    press(st);
    st.timer = setTimeout(function () { tick(code); }, DAS_RATE);
  }

  function down(e) {
    if (held[e.code]) return; // 重複down無視
    press({ key: e.key, code: e.code, location: e.location || 0, shiftKey: !!e.shiftKey });
    if (e.key === "Escape") return; // Escは単発
    var st = { key: e.key, code: e.code, location: e.location || 0, shiftKey: !!e.shiftKey, timer: 0 };
    held[e.code] = st;
    st.timer = setTimeout(function () { tick(e.code); }, DAS_DELAY);
  }

  function up(code) {
    var st = held[code];
    if (st) { clearTimeout(st.timer); delete held[code]; }
  }

  function clearAll() {
    for (var c in held) { try { clearTimeout(held[c].timer); } catch (e) {} }
    held = {};
  }

  // Ctrl+A: ゲーム⇔裏シェル(tmux window)トグル用。素通しさせる
  // (tmux側で bind-key -n C-a last-window)。ブラウザの全選択は抑止。
  // DASのheld登録対象外・リピート不要のためe.repeatは無視する。
  function isShellToggle(e) {
    return e.code === "KeyA" && e.ctrlKey && !e.metaKey && !e.altKey;
  }

  window.addEventListener("keydown", function (e) {
    if (e.code === "F9" && !e.ctrlKey && !e.metaKey && !e.altKey) {
      e.preventDefault(); e.stopPropagation();
      setEnabled(!enabled);
      return;
    }
    if (isShellToggle(e)) {
      if (e.isTrusted === false) return;
      // ブラウザの全選択だけ抑止し、trustedイベント自体はxtermへ届ける
      // (xtermがCtrl+Aを\x01に変換してpty→tmuxの-n C-aバインドに渡す)。
      // stopPropagationはしない。DAS登録・リピート対象外。
      e.preventDefault();
      if (e.repeat) { e.stopPropagation(); return; }
      return;
    }
    if (!enabled) return;
    if (e.isTrusted === false) return; // 自分の合成イベントは無視
    if (!isGameKey(e)) return;
    stats.seen++;
    e.preventDefault(); e.stopPropagation();
    if (e.repeat) { stats.repeats++; return; }
    stats.taken++;
    down(e);
  }, true);

  window.addEventListener("keyup", function (e) {
    if (e.isTrusted === false) return;
    up(e.code);
  }, true);
  window.addEventListener("blur", clearAll);
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) clearAll();
  });

  // ON/OFFバッジ
  var badge = null;
  function setEnabled(on) {
    enabled = on;
    clearAll();
    if (badge) {
      badge.textContent = "DAS:" + (on ? "ON" : "OFF");
      badge.style.opacity = on ? "0.85" : "0.45";
    }
  }
  function mountBadge() {
    if (!document.body || document.getElementById("das-badge")) return;
    badge = document.createElement("div");
    badge.id = "das-badge";
    badge.textContent = "DAS:ON";
    badge.title = "クリック/F9で同時長押しDASのON/OFF";
    badge.style.cssText = "position:fixed;right:8px;bottom:8px;z-index:9999;" +
      "font:11px monospace;background:#0a1226;color:#7df9ff;" +
      "border:1px solid #2a5a8a;border-radius:6px;padding:3px 8px;" +
      "cursor:pointer;opacity:0.85;user-select:none;";
    badge.addEventListener("click", function () { setEnabled(!enabled); });
    document.body.appendChild(badge);
    setEnabled(true);
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mountBadge);
  } else {
    mountBadge();
  }
  window.__dasKeys = { setEnabled: setEnabled, clearAll: clearAll, stats: stats };
})();
