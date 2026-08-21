/* HEAVY CANDY hero — チャンクタワー / レバー / 瓶
   実測データ（2026-08-20, MacBook Apple M4 / 460GB SSD）を静的に持つ。
   ユーザーのマシンは読まない（読めない）。 */
(function () {
  "use strict";

  var ITEMS = [
    { id: "sim",    gb: 71.5, tier: "A", name: "使っていない iOS シミュレータ", lost: "次に使うとき再ダウンロード" },
    { id: "docker", gb: 26.6, tier: "B", name: "Docker のイメージとキャッシュ", lost: "次のビルドが遅くなる" },
    { id: "colima", gb: 10.0, tier: "B", name: "Colima の仮想ディスク", lost: "VM の作り直しが必要" },
    { id: "ollama", gb: 6.5,  tier: "C", name: "ollama のモデル", lost: "ディスクリンは触りません" },
    { id: "uv",     gb: 3.2,  tier: "A", name: "uv のキャッシュ", lost: "次の install で取り直し" }
  ];

  var SCALE = 0.48;           // ヒーロー表示用の縮尺（比例関係は保つ）。瓶まで画面に入る高さに収める
  var MIN_PX = 68;            // 文字が 2 行入る下限。これ未満は高さを揃え、大小の逆転を作らない
  var PULL_THRESHOLD = 120;   // design-system.md §5.2

  var tower = document.getElementById("tower");
  var jarBody = document.getElementById("jar-body");
  var jarEmpty = document.getElementById("jar-empty");
  var jarCount = document.getElementById("jar-count");
  var grip = document.getElementById("lever-grip");
  var track = document.getElementById("lever-track");
  var status = document.getElementById("stage-status");
  var meter = document.getElementById("meter-value");
  if (!tower || !grip) return;

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  var state = {};

  function height(gb) {
    return Math.max(MIN_PX, Math.min(320, Math.max(48, 48 + gb * 3.2)) * SCALE);
  }

  function render() {
    tower.textContent = "";
    var index = -1;
    ITEMS.forEach(function (item) {
      if (state[item.id] === "jar") return;
      index += 1;
      var b = document.createElement("button");
      b.type = "button";
      b.className = "chunk";
      b.dataset.tier = item.tier;
      b.dataset.id = item.id;
      b.style.minHeight = height(item.gb) + "px";
      b.style.setProperty("--i", String(index));
      if (item.tier === "C") {
        b.disabled = true;
        b.setAttribute("aria-disabled", "true");
      } else {
        b.setAttribute("aria-pressed", state[item.id] === "on" ? "true" : "false");
      }
      b.setAttribute("aria-label",
        item.gb + " ギガバイト、" + item.name + "、区分 " +
        (item.tier === "C" ? "見るだけ" : item.tier) + "、" +
        (item.tier === "C" ? "選べません" : (state[item.id] === "on" ? "選択中" : "未選択")) +
        "、失うもの: " + item.lost);
      b.innerHTML =
        '<span class="chunk__row" aria-hidden="true">' +
          '<span class="chunk__gb data">' + item.gb + '<small>GB</small></span>' +
          '<span class="chunk__name">' + item.name + '</span>' +
        '</span>' +
        '<span class="chunk__lost" aria-hidden="true">' + item.lost + '</span>';
      if (item.tier !== "C") {
        b.addEventListener("click", function () {
          state[item.id] = state[item.id] === "on" ? "off" : "on";
          render();
          // 選び直した塊だけを揺らす。押した手応えを返す。
          jiggle(tower.querySelector('[data-id="' + item.id + '"]'));
          say(item.name + "を" + (state[item.id] === "on" ? "選びました" : "外しました"));
        });
      }
      tower.appendChild(b);
    });
    renderJar();
  }

  function renderJar() {
    Array.prototype.slice.call(jarBody.querySelectorAll(".pebble")).forEach(function (n) { n.remove(); });
    var inJar = ITEMS.filter(function (i) { return state[i.id] === "jar"; });
    jarEmpty.hidden = inJar.length > 0;
    var total = inJar.reduce(function (a, i) { return a + i.gb; }, 0);
    jarCount.textContent = inJar.length === 0 ? "からっぽ" : inJar.length + "件 / " + total.toFixed(1) + " GB";
    setMeter(total);
    inJar.forEach(function (item, index) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "pebble";
      b.style.setProperty("--i", String(index));
      b.dataset.tier = item.tier;
      b.textContent = item.gb + " GB";
      b.setAttribute("aria-label", item.name + " を元に戻す（" + item.gb + " ギガバイト）");
      b.addEventListener("click", function () {
        state[item.id] = "on";
        render();
        // 戻した塊が、タワーの中で跳ねる
        jiggle(tower.querySelector('[data-id="' + item.id + '"]'));
        animateOnce(document.querySelector(".jar"), "is-wobbling");
        say(item.name + "を元に戻しました");
      });
      jarBody.appendChild(b);
    });
  }

  function say(msg) { if (status) status.textContent = msg; }

  /* 要素を 1 回だけ揺らす。アニメーションは付け直さないと再生されないため、
     クラスを外して強制的に再計算してから付け直す。 */
  function animateOnce(el, className) {
    if (!el || reduce.matches) return;
    el.classList.remove(className);
    void el.offsetWidth;
    el.classList.add(className);
    el.addEventListener("animationend", function handler() {
      el.classList.remove(className);
      el.removeEventListener("animationend", handler);
    });
  }

  function jiggle(el) { animateOnce(el, "is-jelly"); }

  /* 数字そのものを重くする: 量が増えるほど字面を広げる（Martian Mono の wdth 軸）。 */
  function setMeter(gb) {
    if (!meter) return;
    var width = Math.round(82 + Math.min(1, gb / 100) * 30);   // 82 → 112
    meter.style.setProperty("--w", width);
    meter.innerHTML = gb.toFixed(1) + "<small>GB</small>";
  }

  function pull() {
    var picked = ITEMS.filter(function (i) { return state[i.id] === "on"; });
    if (picked.length === 0) { say("選ばれているものがありません"); return; }
    picked.forEach(function (i) { state[i.id] = "jar"; });
    render();
    // 落ちた衝撃を、置き場と瓶の両方に伝える
    animateOnce(document.querySelector(".frame"), "is-shuddering");
    animateOnce(document.querySelector(".jar"), "is-wobbling");
    var total = picked.reduce(function (a, i) { return a + i.gb; }, 0);
    say(picked.length + "件 " + total.toFixed(1) + " ギガバイトを瓶に入れました。7日以内なら掴んで戻せます");
  }

  /* --- レバー: 引き下ろしで発火。reduced-motion ならクリックで発火 --- */
  var dragging = false, startY = 0, offset = 0;
  var maxPull = 150;

  function setGrip(px) {
    var pull = Math.min(1, px / PULL_THRESHOLD);
    // 引くほど握りが縦に伸びる（ゴムを引く手応え）
    grip.style.transform = "translateY(" + px + "px) scale(" + (1 - pull * 0.06) + "," + (1 + pull * 0.1) + ")";
    if (track) track.style.setProperty("--pull", pull.toFixed(3));
  }

  function down(e) {
    if (reduce.matches) return;
    dragging = true;
    startY = (e.touches ? e.touches[0].clientY : e.clientY);
    grip.setPointerCapture && e.pointerId !== undefined && grip.setPointerCapture(e.pointerId);
    e.preventDefault();
  }
  function move(e) {
    if (!dragging) return;
    var y = (e.touches ? e.touches[0].clientY : e.clientY);
    offset = Math.max(0, Math.min(maxPull, y - startY));
    setGrip(offset);
  }
  function up() {
    if (!dragging) return;
    dragging = false;
    var fired = offset >= PULL_THRESHOLD;
    offset = 0;
    grip.style.transition = "transform 300ms var(--spring)";
    setGrip(0);
    window.setTimeout(function () { grip.style.transition = ""; }, 320);
    if (fired) pull();
  }

  grip.addEventListener("pointerdown", down);
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", up);
  window.addEventListener("pointercancel", up);

  /* キーボード: Enter で実行、Space 長押し 800ms でも実行（D-05） */
  var holdTimer = null;
  grip.addEventListener("keydown", function (e) {
    if (e.key === "Enter") { e.preventDefault(); pull(); return; }
    if (e.key === " " && holdTimer === null) {
      e.preventDefault();
      setGrip(PULL_THRESHOLD);
      holdTimer = window.setTimeout(function () { setGrip(0); pull(); holdTimer = null; }, 800);
    }
  });
  grip.addEventListener("keyup", function (e) {
    if (e.key === " " && holdTimer !== null) {
      window.clearTimeout(holdTimer); holdTimer = null; setGrip(0);
      say("引ききる前に離しました。実行していません");
    }
  });
  grip.addEventListener("click", function () { if (reduce.matches) pull(); });

  function applyMotionMode() {
    grip.textContent = reduce.matches ? "おす" : "ひく";
    var label = document.getElementById("lever-label");
    if (label) {
      label.textContent = reduce.matches
        ? "押すと実行します"
        : "つまんで下まで引くと実行します";
    }
  }
  reduce.addEventListener ? reduce.addEventListener("change", applyMotionMode) : reduce.addListener(applyMotionMode);

  /* ブロックの壁は、画面に入ったときに下から順に積み上がる。
     読み込み時にまとめて動かすと、スクロールして来たときには終わっている。 */
  (function revealWalls() {
    var walls = document.querySelectorAll(".wall");
    if (!walls.length) return;
    walls.forEach(function (wall) {
      wall.querySelectorAll(".brick").forEach(function (brick, index) {
        brick.style.setProperty("--i", String(index));
      });
    });
    if (reduce.matches || !("IntersectionObserver" in window)) {
      walls.forEach(function (wall) { wall.classList.add("is-visible"); });
      return;
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.2 });
    walls.forEach(function (wall) { observer.observe(wall); });
  })();

  ITEMS.forEach(function (i) { state[i.id] = i.tier === "A" ? "on" : "off"; });
  applyMotionMode();
  render();
})();
