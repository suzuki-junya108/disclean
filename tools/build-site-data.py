#!/usr/bin/env python3
"""LP に載せるデータを、同梱ルールそのものから作る。

LP を手書きすると、ルールが増えたときに古い内容が残る。ここで生成することで、
「サイトに書いてあること」と「実際に見る場所」が必ず一致する。

出力: site/rules.js（window.DISCLEAN_DATA を定義するだけの静的ファイル）
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RULES_DIR = ROOT / "Sources/DiscleanKit/Resources/rules"
OUT = ROOT / "site/rules.js"

# ルール ID から「どの道具を使う人向けか」を決める。
# ここに載らないものは "everyone"（誰の Mac にもあるもの）として扱う。
GROUPS = [
    ("xcode", "Xcode / iOS", r"xcode|simulator|coresimulator|simctl|cocoapods|carthage|swiftpm"),
    ("docker", "Docker / インフラ", r"docker|colima|container-tool|kube|terraform|minikube"),
    ("node", "Web / Node.js", r"npm|pnpm|yarn|bun|deno|node-build|js-build|playwright|cypress|puppeteer|electron"),
    ("python", "Python / データ", r"pip|uv|conda|python-|poetry|pipenv"),
    ("jvm", "Android / JVM", r"gradle|maven|android|scala|nuget|jetbrains|unity"),
    ("otherlang", "そのほかの言語", r"cargo|go-|go_|ruby|composer|pub-cache|conan|compiler-caches|version-manager"),
    ("browser", "ブラウザ", r"chrome|edge|brave|firefox|arc-|chromium|safari|browser-on-device"),
    ("chat", "チャット / 会議", r"slack|discord|zoom|teams|telegram|whatsapp"),
    ("design", "デザイン / 制作", r"figma|sketch|adobe|final-cut|logic-pro|unity"),
    ("cloud", "クラウド同期", r"drive|dropbox"),
    ("ai", "AI / モデル", r"ollama|huggingface|local-model|claude-vm|lm-studio"),
    ("media", "音楽 / 動画 / ゲーム", r"spotify|music|steam|podcast"),
]

# 「よくある目安」の幅（GB）。実測ではなく、一般に語られる範囲。
# 出典は各ツールの掃除ガイドと、ルールが見る場所の性質から置いた保守的な幅。
PROFILE_ESTIMATES = {
    "xcode": (6, 70),
    "docker": (4, 40),
    "node": (1, 12),
    "python": (2, 40),
    "jvm": (3, 30),
    "otherlang": (1, 10),
    "browser": (1, 6),
    "chat": (1, 8),
    "design": (2, 25),
    "cloud": (1, 20),
    "ai": (3, 60),
    "media": (1, 20),
    "everyone": (1, 6),
}


def group_of(rule_id: str) -> str:
    for key, _label, pattern in GROUPS:
        if re.search(pattern, rule_id):
            return key
    return "everyone"


def main() -> int:
    rules = []
    for path in sorted(RULES_DIR.glob("*.json")):
        for rule in json.loads(path.read_text()):
            rules.append(
                {
                    "id": rule["id"],
                    "title": rule.get("titleJa") or rule["title"],
                    "tier": rule["tier"],
                    "lost": rule.get("whatIsLostJa") or rule["whatIsLost"],
                    "undoable": rule["kind"] == "directory",
                    "group": group_of(rule["id"]),
                }
            )

    groups = [{"id": "everyone", "label": "どの Mac にもあるもの"}] + [
        {"id": key, "label": label} for key, _label, _p in GROUPS for _k, label, _pp in [(key, _label, _p)]
    ]
    counts = {g["id"]: sum(1 for r in rules if r["group"] == g["id"]) for g in groups}
    groups = [g for g in groups if counts[g["id"]] > 0]

    data = {
        "rules": sorted(rules, key=lambda r: (r["tier"], r["id"])),
        "groups": groups,
        "estimates": {k: list(v) for k, v in PROFILE_ESTIMATES.items() if k in counts},
        "totals": {
            "rules": len(rules),
            "a": sum(1 for r in rules if r["tier"] == "A"),
            "b": sum(1 for r in rules if r["tier"] == "B"),
            "c": sum(1 for r in rules if r["tier"] == "C"),
        },
    }

    OUT.write_text(
        "// このファイルは tools/build-site-data.py が同梱ルールから作ります。手で直さないでください。\n"
        "window.DISCLEAN_DATA = " + json.dumps(data, ensure_ascii=False, separators=(",", ":")) + ";\n"
    )
    print(f"{OUT.relative_to(ROOT)}: {data['totals']['rules']} 本 / {len(groups)} グループ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
