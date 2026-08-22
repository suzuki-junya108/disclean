/* ルール図鑑・目安の壁・ベルトコンベア。すべて rules.js（同梱ルールから生成）が出典。
   ここに手書きの数字は置かない。ルールが増えれば、このページの中身も自動で増える。 */
(function () {
  "use strict";

  var DATA = window.DISCLEAN_DATA;
  if (!DATA) return;

  var TIER_LABEL = { A: "ふつうに消せる", B: "中身を見てから", C: "見るだけ" };

  /* --- ベルトコンベア: ルール名を流す（数字は出さない） --- */
  (function ticker() {
    var rail = document.getElementById("ticker-rail");
    if (!rail) return;
    var names = DATA.rules
      .filter(function (r) { return r.tier !== "C"; })
      .map(function (r) { return r.title; });
    // 同じ並びを 2 セット作って、途切れずに回す
    for (var pass = 0; pass < 2; pass += 1) {
      var set = document.createElement("span");
      set.className = "ticker__set";
      names.forEach(function (name) {
        var item = document.createElement("span");
        item.className = "ticker__item";
        item.textContent = name;
        set.appendChild(item);
        var dot = document.createElement("span");
        dot.className = "ticker__dot";
        dot.textContent = "●";
        set.appendChild(dot);
      });
      rail.appendChild(set);
    }
  })();

  /* --- ルール図鑑 --- */
  (function gallery() {
    var list = document.getElementById("rules-gallery");
    var filters = document.getElementById("rules-filters");
    var note = document.getElementById("rules-note");
    var total = document.getElementById("rules-total");
    if (!list || !filters) return;

    if (total) total.textContent = String(DATA.totals.rules);

    var active = { tier: "all", group: "all" };
    var showAll = false;
    var PREVIEW = 12;   // 最初は 12 本。全部出すとページが図鑑だけになる

    function chip(label, kind, value, count) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "gchip";
      b.dataset.kind = kind;
      b.dataset.value = value;
      b.textContent = count === undefined ? label : label + " " + count;
      b.setAttribute("aria-pressed", active[kind] === value ? "true" : "false");
      b.addEventListener("click", function () {
        active[kind] = active[kind] === value ? "all" : value;
        renderFilters();
        renderList();
        if (window.Goo) window.Goo.squish(b, 1.2);
      });
      return b;
    }

    function renderFilters() {
      filters.textContent = "";
      ["A", "B", "C"].forEach(function (tier) {
        var count = DATA.rules.filter(function (r) { return r.tier === tier; }).length;
        filters.appendChild(chip(TIER_LABEL[tier], "tier", tier, count));
      });
      DATA.groups.forEach(function (group) {
        var count = DATA.rules.filter(function (r) { return r.group === group.id; }).length;
        filters.appendChild(chip(group.label, "group", group.id, count));
      });
    }

    function renderList() {
      var rules = DATA.rules.filter(function (r) {
        return (active.tier === "all" || r.tier === active.tier)
          && (active.group === "all" || r.group === active.group);
      });
      list.textContent = "";
      var shown = showAll ? rules : rules.slice(0, PREVIEW);
      shown.forEach(function (rule, index) {
        var li = document.createElement("li");
        li.className = "gcard";
        li.dataset.tier = rule.tier;
        li.style.setProperty("--i", String(Math.min(index, 40)));

        var head = document.createElement("p");
        head.className = "gcard__head";
        var badge = document.createElement("span");
        badge.className = "gcard__tier";
        badge.textContent = TIER_LABEL[rule.tier];
        var name = document.createElement("span");
        name.className = "gcard__name";
        name.textContent = rule.title;
        head.appendChild(badge);
        head.appendChild(name);

        var lost = document.createElement("p");
        lost.className = "gcard__lost";
        lost.textContent = rule.lost;

        var foot = document.createElement("p");
        foot.className = "gcard__foot data";
        foot.textContent = rule.id + (rule.tier === "C" ? " ・ 消しません" : (rule.undoable ? " ・ 7日戻せます" : " ・ 戻せません"));

        li.appendChild(head);
        li.appendChild(lost);
        li.appendChild(foot);
        list.appendChild(li);
      });
      if (note) {
        note.textContent = "";
        var text = document.createElement("span");
        text.textContent = shown.length + " / " + rules.length + " 本を表示中（全 "
          + DATA.totals.rules + " 本）。端末では disclean rules list で同じ一覧が出ます。 ";
        note.appendChild(text);
        if (rules.length > PREVIEW) {
          var more = document.createElement("button");
          more.type = "button";
          more.className = "gchip";
          more.textContent = showAll ? "たたむ" : "ぜんぶ見る（" + rules.length + " 本）";
          more.addEventListener("click", function () {
            showAll = !showAll;
            renderList();
            if (window.Goo) window.Goo.squish(more, 1.2);
          });
          note.appendChild(more);
        }
      }
    }

    renderFilters();
    renderList();
  })();

  /* --- 目安の壁: ヒーローで選んだものに合わせて積み直す --- */
  (function estimate() {
    var wallMin = document.getElementById("wall-min");
    var wallMax = document.getElementById("wall-max");
    var numMin = document.getElementById("est-min");
    var numMax = document.getElementById("est-max");
    var rows = document.getElementById("est-rows");
    var key = document.getElementById("est-key");
    if (!wallMin || !wallMax) return;

    var MAX_BRICKS = 80;   // これ以上並べても読めない
    var brickGb = 2;       // 1 個あたりの大きさ。多い人向けに自動で粗くする

    function selected() {
      var stage = window.DISCLEAN_STAGE;
      var picked = stage ? stage.picked : {};
      return ["everyone"].concat(
        DATA.groups.map(function (g) { return g.id; })
          .filter(function (id) { return id !== "everyone" && picked[id]; })
      );
    }

    function fill(wall, gb, groups) {
      wall.textContent = "";
      // 上限で切り捨てるのではなく、1 個の大きさを粗くして全量を出す（黙って減らさない）
      var bricks = Math.max(1, Math.round(gb / brickGb));
      // グループごとに色を変えて、どこが太っているかを見せる
      var perGroup = groups.map(function (id) {
        var range = DATA.estimates[id] || [1, 2];
        return { id: id, share: (range[0] + range[1]) / 2 };
      });
      var sum = perGroup.reduce(function (a, g) { return a + g.share; }, 0) || 1;
      var placed = 0;
      perGroup.forEach(function (group, groupIndex) {
        var count = Math.max(1, Math.round(bricks * group.share / sum));
        for (var i = 0; i < count && placed < bricks; i += 1) {
          var brick = document.createElement("span");
          brick.className = "brick brick--" + "abcde"[groupIndex % 5];
          brick.style.setProperty("--i", String(placed));
          wall.appendChild(brick);
          placed += 1;
        }
      });
      wall.classList.add("is-visible");
      wall.setAttribute("aria-label", Math.round(gb) + " ギガバイト、ブロック " + placed + " 個分");
    }

    function render() {
      var groups = selected();
      var min = 0, max = 0;
      groups.forEach(function (id) {
        var range = DATA.estimates[id] || [1, 2];
        min += range[0];
        max += range[1];
      });
      // 多い人でも 1 枚に収まるよう、1 個あたりを 2GB 刻みで粗くする
      brickGb = 2;
      while (max / brickGb > MAX_BRICKS) { brickGb += 2; }

      if (numMin) { numMin.textContent = min; numMin.appendChild(unit()); }
      if (numMax) { numMax.textContent = max; numMax.appendChild(unit()); }
      fill(wallMin, min, groups);
      fill(wallMax, max, groups);

      if (key) {
        key.textContent = "ブロック 1 個 = " + brickGb + "GB。色は選んだものの内訳です。"
          + "幅があるのは、同じ道具でも使い方で 10 倍変わるためです。";
      }

      if (rows) {
        rows.textContent = "";
        groups.forEach(function (id) {
          var group = DATA.groups.filter(function (g) { return g.id === id; })[0];
          var range = DATA.estimates[id] || [1, 2];
          var inGroup = DATA.rules.filter(function (r) { return r.group === id; });
          var a = inGroup.filter(function (r) { return r.tier === "A"; }).length;
          var b = inGroup.filter(function (r) { return r.tier === "B"; }).length;
          var c = inGroup.filter(function (r) { return r.tier === "C"; }).length;
          var tr = document.createElement("tr");
          [
            group ? group.label : id,
            inGroup.length + " 本",
            "A " + a + " / B " + b + " / 見るだけ " + c,
            range[0] + "〜" + range[1] + " GB"
          ].forEach(function (text, index) {
            var td = document.createElement("td");
            if (index === 3) td.className = "num data";
            td.textContent = text;
            tr.appendChild(td);
          });
          rows.appendChild(tr);
        });
      }
    }

    function unit() {
      var small = document.createElement("small");
      small.textContent = "GB";
      return small;
    }

    render();
    // ヒーローのチップが押されたら積み直す（チップは hero.js が描く）
    var chips = document.getElementById("profile-chips");
    if (chips) chips.addEventListener("click", function () { window.setTimeout(render, 0); });
  })();
})();
