> 責務: 実装ヒント（§14）— Bootstrap / Verify / ディレクトリ構成 / NOT to do の 4 要素。
> 親: ../REQUIREMENTS.md

## 14. Implementation Hints for Claude Code (onegai-ready)

### 14.1 Bootstrap Commands（最初に実行する）

```bash
cd ~/Sync/disclean

# 0. Syncthing の設定は 2026-08-20 に対応済み（R-07）。確認だけ行う。
#    ~/Sync/.stignore の「1) 同期対象内でも除外したい〜」節に .build / .swiftpm /
#    DerivedData / dist があり、「2) ホワイトリスト」節に !disclean / !disclean/** がある。
#    ※ .stignore は「上から評価して最初にマッチしたもの」が採用され、末尾は全除外の `*`。
#      除外パターンを末尾に追記しても `*` より後ろになり無効。必ず 1) 節に置くこと。
grep -nE '^(\.build|\.swiftpm|DerivedData|dist|!disclean(/\*\*)?)$' ~/Sync/.stignore

# 1. リポジトリ初期化（R-08: リモート設定と push を早期に行う）
git init
printf '.build/\nbuild/\ndist/\n.swiftpm/\nDerivedData/\n*.p12\n*.p8\n*.mobileprovision\n.DS_Store\n' > .gitignore

# 2. SwiftPM パッケージを作る（Package.swift は下記 14.3 の構成に手で書き換える）
swift package init --type empty --name Disclean

# 3. 検査ツールをバージョン要件に合わせる（実測: 導入済みは 0.63.2、要件は 0.65.0）
brew upgrade swiftlint || brew install swiftlint
swiftlint version   # 0.65.0 以上であること

# 4. ビルドとテスト（この時点で WS-a / WS-d / WS-h / WS-i が通ること）
swift build -c release
./.build/release/disclean --help
swift test
```

**最初のタスク（Walking Skeleton）**: `DiscleanKit` に `PathGuard`（SG-01〜SG-09）と `CapacityProbe`（`volumeAvailableCapacityKey` / `volumeAvailableCapacityForImportantUsageKey`）だけを実装し、`disclean doctor` と `disclean --version` が動く状態にする。削除系は一切書かない。この時点で WS-a / WS-d / WS-h / WS-i / WS-l を PASS させる。

次に `Scanner` と同梱ルール 3 件（`npm-cache` / `xcode-deriveddata` / `simctl-unavailable`）だけで `disclean scan --json` を成立させ、WS-k（スキャンが書き込まない）を PASS させる。`Executor` はその後。

更新機構（F-17 / F-18）は `Executor` の完成後に着手する。順序は **`ManifestVerifier`（署名・ハッシュ・巻き戻し・期限の拒否経路）→ `CatalogStore`（staged / active / previous）→ `CatalogDiff`（拡大・縮小・中立の分類）→ `Updater`（通信）**。通信を最後に書くこと（検証が無い状態でネットワークから物を取ってくるコードを、一時的にも存在させない）。

### 14.2 Verify Commands（変更のたびに実行する）

```bash
swiftlint lint --strict                       # 0 violations 期待
xcrun swift-format lint --recursive --strict Sources Tests   # 0 diagnostics 期待
swift build -c release                        # "Build complete!" 期待
swift test --enable-code-coverage             # 全 PASS + DiscleanKit 行カバレッジ 80% 以上
tests/acceptance/run-all.sh                   # AT-001〜AT-010 全 PASS
xcodebuild -project Disclean.xcodeproj -scheme Disclean -destination 'platform=macOS' build   # BUILD SUCCEEDED
xcodebuild test -project Disclean.xcodeproj -scheme DiscleanUITests -destination 'platform=macOS'  # AT-011〜AT-013
tests/acceptance/AT-014-design-parity.sh      # Swift と CSS のトークン一致 + 禁則（ぼかし影 / グラデーション）
tests/acceptance/AT-015-lp.sh                 # LP の 7 セクション / 無横スクロール / JS 無効 / axe / 外部ホスト
tests/acceptance/AT-016-update.sh             # 署名不一致 / 巻き戻し / 承認前の非適用 / 無効化時に通信 0
tests/acceptance/AT-018-os-drift.sh           # OS 変化の検知 / minMacOS・maxMacOS の評価
```

### 14.3 ディレクトリ構成

```
mac_cleanup/
├── Package.swift                  # swift-tools-version: 6.2, platforms: [.macOS(.v14)]
├── .swiftlint.yml                 # force_unwrapping / force_try を error に
├── .swift-format
├── Sources/
│   ├── DiscleanKit/                # 共有コア（UI 非依存・stdout に書かない）
│   │   ├── Rules/                 # Rule, RuleKind, Tier, CommandSpec, RuleCatalog
│   │   ├── Scan/                  # Scanner, SizeCache, DatalessPolicy(setiopolicy_np)
│   │   ├── Capacity/              # CapacityProbe, SnapshotProbe(tmutil)
│   │   ├── Plan/                  # Planner, Plan
│   │   ├── Safety/                # PathGuard(SG-01〜SG-09), ExcludedPaths
│   │   ├── Execute/               # Executor, CommandRunner(Process + timeout)
│   │   ├── Quarantine/            # QuarantineStore, QuarantineRun, index.json 更新
│   │   ├── Audit/                 # AuditLog(JSONL 追記), AuditRecord
│   │   ├── Update/                # Updater(URLSession), ManifestVerifier(Ed25519 + sha256),
│   │   │                          #   CatalogStore(staged/active/previous), CatalogDiff
│   │   │   └── Resources/         # release-keys.json（公開鍵のみ。秘密鍵は置かない）
│   │   ├── Env/                   # OSDrift(env.json), OSVersionRange(minMacOS/maxMacOS 判定)
│   │   └── Resources/rules/       # 同梱ルール JSON（.process リソース）
│   ├── disclean/                      # CLI（ArgumentParser）
│   │   ├── Commands/              # Scan, Plan, Apply, Undo, Purge, History, Report, Doctor, Rules, Update
│   │   └── UI/                    # S-01〜S-12 のレンダラ（TTY 判定・NO_COLOR 対応）
│   └── DiscleanApp/             # SwiftUI（S-13〜S-23）
│       ├── DesignTokens.swift     # HEAVY CANDY のトークン（色 / 書体 / 角丸 / 影 / モーション）
│       ├── Components/            # Chunk, Lever, Jar, TierChip, ConfirmSheet
│       ├── Views/
│       ├── ViewModels/
│       └── Resources/Fonts/       # Bricolage Grotesque / Zen Maru Gothic / Martian Mono（OFL 同梱）
├── site/                          # 配布 LP（S-24〜S-30・ビルド工程なし）
│   ├── index.html                 # 日本語版
│   ├── en/index.html              # 英語版
│   ├── tokens.css                 # :root のトークン（DesignTokens.swift と同値）
│   ├── style.css
│   ├── hero.js                    # チャンクタワー / レバー / 瓶
│   └── og.png                     # 1200x630
├── Tests/
│   ├── DiscleanKitTests/           # swift-testing（Unit）
│   ├── IntegrationTests/          # swift-testing（一時ディレクトリ上の一巡）
│   └── DiscleanUITests/         # XCUITest
├── tests/acceptance/              # AT-001〜AT-013 の bash + jq
│   └── run-all.sh
├── docs/
│   ├── REQUIREMENTS.md
│   ├── requirements/
│   ├── design-system.md           # HEAVY CANDY（UI / LP の唯一の出典）
│   ├── rule-schema.md
│   └── update-protocol.md         # manifest 形式 / 署名手順 / 鍵ローテーション / revocation
├── Disclean.xcodeproj           # GUI ビルド用（SwiftPM パッケージを参照）
└── mac_cleanup.sh                 # 旧スクリプト（非推奨の注記を追加、v1.0 まで残す）
```

### 14.4 NOT to do（推測で変えてはいけない選択）

**設計上の禁止**
- `docker system prune` に `-a` や `--volumes` を付けない（F-10 の表のコマンドを 1 文字も変えない）
- Tier C のルールに削除機能を実装しない。`report` 型は計測と表示だけを行う
- sudo / `AuthorizationExecuteWithPrivileges` / SMJobBless を使わない。特権昇格の経路を作らない
- `FileManager.removeItem` を `QuarantineStore.purge` 以外の場所で呼ばない
- `rename` が EXDEV で失敗したとき、コピー＋削除にフォールバックしない（`skipped` にする）
- `Process` に `/bin/sh -c` を渡さない。実行ファイルと引数配列を直接指定する
- 標準エラーを握り潰さない（`2>/dev/null` 相当のコードを書かない）。失敗は必ず `failed` / `blocked` として記録し、成功件数に数えない
- `df` の前後差を「回収量」として報告しない。回収量は隔離バイト数、空き容量差分は参考値として別に出す（F-03）
- ルール定義をコード内にハードコードしない（JSON リソースとして持つ）
- launchd プラグインや常駐プロセスを追加しない（NG3）
- ネットワーク通信を `DiscleanKit/Update/` 以外の場所に書かない。テレメトリ・クラッシュレポート送信・利用統計・マシン識別子の生成を実装しない（NG6）。更新のリクエストに本文を持たせない（GET のみ）
- 署名検証を省略できる経路・環境変数・ビルド設定を作らない。テスト鍵の注入は debug ビルド限定にする
- 取得した配信物を、検証を通す前に `staged` の外へ置かない。`active` の切り替えは `CatalogStore` の 1 経路のみにする
- 更新カタログのルールに、同梱ルールより緩い検証を適用しない（F-01 と同じスキーマ検証・禁止パス検証を通す）
- 削除対象を拡大する差分（ルール追加 / paths 追加 / Tier 引き上げ / command 変更）を承認なしに適用しない（NG13）
- 本体バイナリ・アプリを自分で置き換えない。ダウンロードと検証までで止め、インストールは brew か利用者に委ねる（NG12）
- 更新チェックの完了をコマンド本体の処理が待たない。ネットワーク失敗を終了コードに反映しない

**デザイン上の禁止（`docs/design-system.md` §1.1 が出典）**
- 塗りにグラデーションを使わない（背景・ボタン・テキストすべて）
- ぼかしのある影を使わない。影は `Npx Npx 0` のハードオフセットのみ。SwiftUI の `.shadow(` を使わない
- グラスモーフィズム・半透明ブラーを使わない
- マスコットキャラクター・紙吹雪・キラキラの成功演出を足さない
- 「何を失うか」「取り消せるか」「触らないもの」の記述を装飾しない。本文サイズ・最高コントラストで書く
- 破壊的操作をワンクリックにしない（レバーのドラッグ、またはキーボードの明示操作を要求する）。ただし `prefers-reduced-motion` 有効時は単一クリックに切り替える
- Tier を色だけで表現しない。必ず文字ラベル（`A` / `B` / `見るだけ`）を併記する
- 色の組み合わせを `docs/design-system.md` §2.2 の 8 通りから増やさない
- 角丸を 22px / 999px / 14px の 3 値以外にしない
- View に色や寸法のリテラル値を直接書かない（`DesignTokens` / CSS カスタムプロパティ経由）

**LP 上の禁止**
- フレームワーク・バンドラ・npm 依存・CSS プリプロセッサを導入しない（素の HTML/CSS/JS）
- Google Fonts（`fonts.googleapis.com` / `fonts.gstatic.com`）以外の外部ホストを参照しない
- アクセス解析・Cookie・フォーム・メールアドレス収集を置かない
- LP からバイナリを直接配信しない（GitHub Releases と Homebrew tap への外部リンクのみ）
- LP 上で訪問者のマシンを診断する機能・そう見える表現を作らない
- JavaScript 無効時に本文とインストール手順が読めなくなる構造にしない

**技術選択の固定**
- 第三者ライブラリを swift-argument-parser 1.8.2 以外に追加しない（JSON は Codable、並列は Swift Concurrency、署名検証は CryptoKit、通信は URLSession）。Sparkle 等の更新フレームワークを導入しない
- 書体を Bricolage Grotesque / Zen Maru Gothic / Martian Mono から変更しない。同梱時は OFL 全文を同梱する
- テストは swift-testing（DiscleanKit）と XCUITest（GUI）から変更しない
- `platforms: [.macOS(.v14)]` を下げない・上げない
- 状態ディレクトリの既定を `~/Library/Application Support` に変えない（A-02 の通り XDG パスを使う）
- CLI サブコマンド名（`scan` / `plan` / `apply` / `undo` / `purge` / `history` / `report` / `doctor` / `rules` / `update`）と終了コード規約（§4.1 の表、7 = 更新の検証失敗を含む）を変えない
- `--json` 出力の `schemaVersion` を省略しない

**テスト上の禁止**
- 実在の `~/Library` `~/.cache` `~/.Trash` をテストの削除対象にしない。必ず `mktemp -d` の fixture を使う
- テストで実ユーザーの `$DISCLEAN_STATE_DIR` / `$DISCLEAN_CONFIG_DIR` を読み書きしない（環境変数で一時ディレクトリへ向ける）
