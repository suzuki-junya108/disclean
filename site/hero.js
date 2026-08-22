/* HEAVY CANDY hero — 使っているものを選ぶと、塊が積み直る。

   ここに出る数字は「よくある目安の幅」で、実測ではありません。
   誰か 1 台の Mac の値でもありません。あなたの Mac も読み込みません（読めません）。
   幅の出どころは rules.js（同梱ルールから生成）です。 */
(function () {
  "use strict";

  var DATA = window.DISCLEAN_DATA;
  if (!DATA) return;

  var SCALE = 0.42;           // ヒーロー表示用の縮尺（比例関係は保つ）
  var MIN_PX = 74;            // 文字が 2 行入る下限
  var PULL_THRESHOLD = 120;   // design-system.md §5.2
  var MAX_CHUNKS = 6;         // 積みすぎると比較にならない

  var tower = document.getElementById("tower");
  var jarBody = document.getElementById("jar-body");
  var jarEmpty = document.getElementById("jar-empty");
  var jarCount = document.getElementById("jar-count");
  var grip = document.getElementById("lever-grip");
  var track = document.getElementById("lever-track");
  var status = document.getElementById("stage-status");
  var meter = document.getElementById("meter-value");
  var chipBox = document.getElementById("profile-chips");
  if (!tower || !grip) return;

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  var picked = {};    // group id -> true（使っているもの）
  var state = {};     // group id -> "on" | "off" | "jar"

  /* --- 目安の幅。数字は rules.js から来る --- */
  function estimate(groupId) {
    var range = DATA.estimates[groupId] || [1, 4];
    return { min: range[0], max: range[1], mid: (range[0] + range[1]) / 2 };
  }

  function tierOf(groupId) {
    var rules = DATA.rules.filter(function (r) { return r.group === groupId; });
    var a = rules.filter(function (r) { return r.tier === "A"; }).length;
    var b = rules.filter(function (r) { return r.tier === "B"; }).length;
    var c = rules.filter(function (r) { return r.tier === "C"; }).length;
    if (c > a + b) return "C";
    return a >= b ? "A" : "B";
  }

  function labelOf(groupId) {
    var group = DATA.groups.filter(function (g) { return g.id === groupId; })[0];
    return group ? group.label : groupId;
  }

  function ruleCount(groupId) {
    return DATA.rules.filter(function (r) { return r.group === groupId; }).length;
  }

  /* いま積むべき塊。「どの Mac にもあるもの」は常に一番下に置く。 */
  function items() {
    var ids = ["everyone"].concat(
      DATA.groups
        .map(function (g) { return g.id; })
        .filter(function (id) { return id !== "everyone" && picked[id]; })
    );
    return ids
      .map(function (id) {
        var range = estimate(id);
        return {
          id: id,
          name: labelOf(id),
          tier: tierOf(id),
          min: range.min,
          max: range.max,
          mid: range.mid,
          rules: ruleCount(id)
        };
      })
      .sort(function (a, b) { return b.mid - a.mid; })
      .slice(0, MAX_CHUNKS);
  }

  function height(gb) {
    return Math.max(MIN_PX, Math.min(320, 48 + gb * 3.4) * SCALE);
  }

  function rangeText(item) {
    return item.min + "〜" + item.max;
  }

  /* --- チップ: 何を使っているか --- */
  function renderChips() {
    if (!chipBox) return;
    chipBox.textContent = "";
    DATA.groups
      .filter(function (g) { return g.id !== "everyone"; })
      .forEach(function (group) {
        var b = document.createElement("button");
        b.type = "button";
        b.className = "pchip";
        b.dataset.on = picked[group.id] ? "1" : "0";
        b.setAttribute("aria-pressed", picked[group.id] ? "true" : "false");
        b.textContent = group.label;
        b.addEventListener("click", function () {
          picked[group.id] = !picked[group.id];
          if (!picked[group.id]) { delete state[group.id]; }
          else { state[group.id] = tierOf(group.id) === "C" ? "off" : "on"; }
          renderChips();
          render();
          if (window.Goo) {
            window.Goo.squish(b, 1.2);
            window.Goo.chain(tower.querySelectorAll(".chunk"), 0, 0.9);
          }
          say(group.label + "を" + (picked[group.id] ? "足しました" : "外しました"));
        });
        chipBox.appendChild(b);
      });
  }

  function render() {
    var list = items();
    tower.textContent = "";
    var index = -1;
    list.forEach(function (item) {
      if (state[item.id] === "jar") return;
      index += 1;
      var b = document.createElement("button");
      b.type = "button";
      b.className = "chunk";
      b.dataset.tier = item.tier;
      b.dataset.id = item.id;
      b.style.minHeight = height(item.mid) + "px";
      b.style.setProperty("--i", String(index));
      if (item.tier === "C") {
        b.disabled = true;
        b.setAttribute("aria-disabled", "true");
      } else {
        b.setAttribute("aria-pressed", state[item.id] === "on" ? "true" : "false");
      }
      b.setAttribute(
        "aria-label",
        item.name + "、よくある目安 " + rangeText(item) + " ギガバイト、区分 " +
        (item.tier === "C" ? "見るだけ" : item.tier) + "、" +
        (item.tier === "C" ? "選べません" : (state[item.id] === "on" ? "選択中" : "未選択")) +
        "、ルール " + item.rules + " 本"
      );

      var skin = document.createElement("span");
      skin.className = "chunk__skin";
      skin.setAttribute("aria-hidden", "true");
      var row = document.createElement("span");
      row.className = "chunk__row";
      var gb = document.createElement("span");
      gb.className = "chunk__gb data";
      gb.style.setProperty("--w", String(Math.round(82 + Math.min(1, item.mid / 70) * 30)));
      gb.textContent = rangeText(item);
      var unit = document.createElement("small");
      unit.textContent = "GB";
      gb.appendChild(unit);
      var name = document.createElement("span");
      name.className = "chunk__name";
      name.textContent = item.name;
      row.appendChild(gb);
      row.appendChild(name);
      var lost = document.createElement("span");
      lost.className = "chunk__lost";
      lost.textContent = "ルール " + item.rules + " 本 ・ よくある目安";
      skin.appendChild(row);
      skin.appendChild(lost);
      b.appendChild(skin);

      if (item.tier !== "C") {
        b.addEventListener("click", function () {
          state[item.id] = state[item.id] === "on" ? "off" : "on";
          var nodes = tower.querySelectorAll(".chunk");
          var position = Array.prototype.indexOf.call(nodes, b);
          render();
          if (window.Goo) {
            window.Goo.chain(tower.querySelectorAll(".chunk"), Math.max(0, position), 1.15);
          }
          say(item.name + "を" + (state[item.id] === "on" ? "選びました" : "外しました"));
        });
      }
      tower.appendChild(b);
      if (window.Goo) window.Goo.breathe(skin, 0.006);
    });
    renderJar(list);
  }

  function renderJar(list) {
    Array.prototype.slice.call(jarBody.querySelectorAll(".pebble")).forEach(function (n) { n.remove(); });
    var inJar = list.filter(function (i) { return state[i.id] === "jar"; });
    jarEmpty.hidden = inJar.length > 0;
    var min = inJar.reduce(function (a, i) { return a + i.min; }, 0);
    var max = inJar.reduce(function (a, i) { return a + i.max; }, 0);
    jarCount.textContent = inJar.length === 0 ? "からっぽ" : inJar.length + "件 / " + min + "〜" + max + " GB";
    setMeter(min, max);
    inJar.forEach(function (item, index) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "pebble";
      b.style.setProperty("--i", String(index));
      b.style.setProperty("--size", String(Math.round(46 + Math.min(1, item.mid / 60) * 44)));
      b.dataset.tier = item.tier;
      b.textContent = item.min + "〜" + item.max;
      b.setAttribute("aria-label", item.name + " を元に戻す（よくある目安 " + rangeText(item) + " ギガバイト）");
      b.addEventListener("click", function () {
        state[item.id] = "on";
        render();
        if (window.Goo) {
          window.Goo.chain(tower.querySelectorAll(".chunk"), 0, 1.2);
          window.Goo.squish(document.querySelector(".jar__body"), 0.7);
        }
        say(item.name + "を元に戻しました");
      });
      jarBody.appendChild(b);
    });
  }

  function say(msg) { if (status) status.textContent = msg; }

  /* 数字そのものを重くする: 量が増えるほど字面を広げる（Martian Mono の wdth 軸）。 */
  function setMeter(min, max) {
    if (!meter) return;
    var width = Math.round(82 + Math.min(1, max / 120) * 30);
    meter.style.setProperty("--w", width);
    meter.textContent = min + "〜" + max;
    var unit = document.createElement("small");
    unit.textContent = "GB";
    meter.appendChild(unit);
    if (window.Goo) window.Goo.squish(meter, 0.8);
  }

  function pull() {
    var list = items();
    var chosen = list.filter(function (i) { return state[i.id] === "on"; });
    if (chosen.length === 0) { say("選ばれているものがありません"); return; }
    chosen.forEach(function (i) { state[i.id] = "jar"; });
    render();
    if (window.Goo) {
      window.Goo.squish(document.querySelector(".frame"), 1.4);
      window.Goo.squish(document.querySelector(".jar__body"), 1.5);
      window.Goo.chain(jarBody.querySelectorAll(".pebble"), 0, 1.3);
    }
    var min = chosen.reduce(function (a, i) { return a + i.min; }, 0);
    var max = chosen.reduce(function (a, i) { return a + i.max; }, 0);
    say(chosen.length + "件、よくある目安 " + min + "〜" + max + " ギガバイトを瓶に入れました。7日以内なら掴んで戻せます");
  }

  /* --- レバー: 引き下ろしで発火。reduced-motion ならクリックで発火 --- */
  var dragging = false, startY = 0, offset = 0;
  var maxPull = 150;

  function setGrip(px) {
    var pulled = Math.min(1, px / PULL_THRESHOLD);
    // 引くほど握りが縦に伸びる（ゴムを引く手応え）
    grip.style.transform = "translateY(" + px + "px) scale(" + (1 - pulled * 0.09) + "," + (1 + pulled * 0.16) + ")";
    if (track) track.style.setProperty("--pull", pulled.toFixed(3));
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
      label.textContent = reduce.matches ? "押すと実行します" : "つまんで下まで引くと実行します";
    }
  }
  reduce.addEventListener ? reduce.addEventListener("change", applyMotionMode) : reduce.addListener(applyMotionMode);

  /* 積み上がりは、画面に入ってから始める（来たときには終わっている、を避ける） */
  (function revealWalls() {
    var walls = document.querySelectorAll(".wall");
    if (!walls.length) return;
    if (reduce.matches || !("IntersectionObserver" in window)) {
      Array.prototype.forEach.call(walls, function (wall) { wall.classList.add("is-visible"); });
      return;
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.2 });
    Array.prototype.forEach.call(walls, function (wall) { observer.observe(wall); });
  })();

  state.everyone = "on";
  applyMotionMode();
  renderChips();
  render();
  window.DISCLEAN_STAGE = {
    picked: picked,
    onChange: [],
    items: items
  };
})();
