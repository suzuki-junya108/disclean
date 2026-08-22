/* ウニョウニョ担当。ページ全体の「粘り」をここ 1 か所で作る。

   方針:
   - rAF は 1 本だけ。要素ごとにタイマーを持たない（増えるほど重くなるため）
   - 動かすのは transform と filter だけ。レイアウトは動かさない
   - 押せるものの当たり判定は動かさない。常時の揺れは中の飾り層（pointer-events:none）に当てる
   - prefers-reduced-motion なら、何も動かさずに静止した見た目を返す
*/
(function () {
  "use strict";

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  var springs = [];       // 走っているバネ
  var running = false;
  var idle = [];          // 常時ゆらぐ飾り層
  var t0 = 0;

  /* --- バネ 1 本。行き過ぎて戻る（減衰振動）。 --- */
  function Spring(el, opts) {
    this.el = el;
    this.value = opts.from;     // いまの伸び（-1 潰れ 〜 +1 伸び）
    this.velocity = opts.kick;  // 初速。強く押すほど大きい
    this.stiffness = opts.stiffness || 190;
    this.damping = opts.damping || 13;
    this.apply = opts.apply;
    this.done = false;
  }

  Spring.prototype.step = function (dt) {
    // ばね：加速度 = -k * x - c * v
    var acceleration = -this.stiffness * this.value - this.damping * this.velocity;
    this.velocity += acceleration * dt;
    this.value += this.velocity * dt;
    if (Math.abs(this.value) < 0.0008 && Math.abs(this.velocity) < 0.008) {
      this.value = 0;
      this.done = true;
    }
    this.apply(this.el, this.value);
  };

  function loop(now) {
    if (!t0) t0 = now;
    var dt = Math.min(0.032, (now - t0) / 1000);   // 大きく飛ばさない（タブ復帰時の暴れ防止）
    t0 = now;

    for (var i = springs.length - 1; i >= 0; i -= 1) {
      springs[i].step(dt);
      if (springs[i].done) springs.splice(i, 1);
    }
    // 常時ゆらぐ層は、正弦波を 2 つ重ねただけ。位相を要素ごとにずらす
    for (var j = 0; j < idle.length; j += 1) {
      var item = idle[j];
      var time = now / 1000 + item.phase;
      var sx = 1 + Math.sin(time * 1.1) * item.amp;
      var sy = 1 + Math.sin(time * 1.37 + 1.2) * item.amp;
      var rotate = Math.sin(time * 0.83) * item.amp * 34;
      item.el.style.transform =
        "scale(" + sx.toFixed(4) + "," + sy.toFixed(4) + ") rotate(" + rotate.toFixed(2) + "deg)";
    }

    if (springs.length === 0 && idle.length === 0) {
      running = false;
      t0 = 0;
      return;
    }
    window.requestAnimationFrame(loop);
  }

  function start() {
    if (running) return;
    running = true;
    t0 = 0;
    window.requestAnimationFrame(loop);
  }

  /* 潰れて伸びる。押した強さ（0〜1）で初速を決める。 */
  function squish(el, strength) {
    if (!el || reduce.matches) return;
    var kick = Math.max(0.2, Math.min(1.6, strength === undefined ? 1 : strength)) * 7;
    springs.push(
      new Spring(el, {
        from: 0,
        kick: kick,
        apply: function (node, value) {
          var sx = 1 - value * 0.09;
          var sy = 1 + value * 0.13;
          node.style.transform = "scale(" + sx.toFixed(4) + "," + sy.toFixed(4) + ")";
        }
      })
    );
    start();
  }

  /* 隣へ波を伝える。1 つ押すと、周りも遅れて揺れる。 */
  function chain(elements, sourceIndex, strength) {
    if (reduce.matches) return;
    Array.prototype.forEach.call(elements, function (el, index) {
      var distance = Math.abs(index - sourceIndex);
      if (distance === 0) { squish(el, strength); return; }
      if (distance > 3) return;
      window.setTimeout(function () {
        squish(el, (strength || 1) * Math.pow(0.45, distance));
      }, distance * 55);
    });
  }

  /* 常時ゆらぐ飾り層を登録する（押せる要素そのものには絶対に付けない）。 */
  function breathe(el, amplitude) {
    if (!el || reduce.matches) return;
    idle.push({ el: el, phase: Math.random() * 6.28, amp: amplitude || 0.012 });
    start();
  }

  /* --- gooey フィルタ: ぼかしてコントラストを上げると、輪郭が溶けて融合する --- */
  function installGooFilter() {
    if (document.getElementById("goo-filter")) return;
    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    svg.style.cssText = "position:absolute;width:0;height:0;pointer-events:none";
    svg.innerHTML =
      '<defs><filter id="goo-filter" x="-30%" y="-30%" width="160%" height="160%">' +
      '<feGaussianBlur in="SourceGraphic" stdDeviation="9" result="blur"/>' +
      '<feColorMatrix in="blur" mode="matrix" ' +
      'values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 26 -12" result="goo"/>' +
      '<feBlend in="SourceGraphic" in2="goo"/>' +
      "</filter></defs>";
    document.body.appendChild(svg);
  }

  /* --- 見出しの文字を、可変フォントの軸で波打たせる --- */
  function waveHeading(heading) {
    if (!heading || reduce.matches) return;
    var lines = heading.querySelectorAll(".hero__line");
    Array.prototype.forEach.call(lines, function (line) {
      if (line.dataset.split === "1") return;
      var text = line.textContent;
      line.textContent = "";
      line.dataset.split = "1";
      for (var i = 0; i < text.length; i += 1) {
        var span = document.createElement("span");
        span.className = "glyph";
        span.textContent = text[i];
        span.style.setProperty("--g", String(i));
        line.appendChild(span);
      }
    });
    heading.classList.add("is-waving");
  }

  /* --- 粘るカーソル: 遅れて追い、進む向きに伸びる（細かい操作をする機器だけ） --- */
  function stickyCursor() {
    if (reduce.matches || !window.matchMedia("(pointer: fine)").matches) return;
    var blob = document.createElement("div");
    blob.className = "goo-cursor";
    blob.setAttribute("aria-hidden", "true");
    document.body.appendChild(blob);

    var target = { x: -100, y: -100 };
    var current = { x: -100, y: -100 };
    var visible = false;

    window.addEventListener("pointermove", function (event) {
      target.x = event.clientX;
      target.y = event.clientY;
      if (!visible) { visible = true; blob.classList.add("is-on"); }
    }, { passive: true });

    (function follow() {
      var dx = target.x - current.x;
      var dy = target.y - current.y;
      current.x += dx * 0.16;
      current.y += dy * 0.16;
      var speed = Math.min(1, Math.sqrt(dx * dx + dy * dy) / 90);
      var angle = Math.atan2(dy, dx) * (180 / Math.PI);
      blob.style.transform =
        "translate(" + current.x + "px," + current.y + "px) rotate(" + angle + "deg) " +
        "scale(" + (1 + speed * 0.85) + "," + (1 - speed * 0.4) + ")";
      window.requestAnimationFrame(follow);
    })();
  }

  /* --- スクロールでページ全体が少したわむ --- */
  function scrollElasticity() {
    if (reduce.matches) return;
    var last = window.scrollY;
    var skew = 0;
    var ticking = false;

    function update() {
      var now = window.scrollY;
      var delta = now - last;
      last = now;
      skew += (delta - skew) * 0.2;
      var amount = Math.max(-4.5, Math.min(4.5, skew * 0.22));
      document.body.style.setProperty("--scroll-skew", amount.toFixed(2) + "deg");
      if (Math.abs(skew) > 0.05) {
        window.requestAnimationFrame(update);
      } else {
        document.body.style.setProperty("--scroll-skew", "0deg");
        ticking = false;
      }
    }

    window.addEventListener("scroll", function () {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(update);
    }, { passive: true });
  }

  window.Goo = {
    squish: squish,
    chain: chain,
    breathe: breathe,
    reduced: function () { return reduce.matches; }
  };

  function boot() {
    installGooFilter();
    waveHeading(document.querySelector(".hero__h1"));
    stickyCursor();
    scrollElasticity();
    // 瓶とブランドマークは、押す対象ではないので常時ゆらしてよい
    Array.prototype.forEach.call(document.querySelectorAll("[data-breathe]"), function (el) {
      breathe(el, parseFloat(el.dataset.breathe) || 0.012);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
