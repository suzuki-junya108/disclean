# ディスクリン / disclean — macOS Safe Disk Cleanup

**Document version**: 1.0
**Last updated**: 2026-08-20
**Status**: Draft
**Owner**: suzuki.junya

## 0. TL;DR (3 sentences max)

ディスクリン（英名・実行ファイル名 `disclean`）は macOS のディスク空き容量を回復するための OSS ツールで、「スキャン（読むだけ）→ 計画（選ぶ）→ 実行（隔離庫へ移動）」の 3 段を分離し、削除は 7 日間 undo 可能な隔離を経由する。共有コア `DiscleanKit` の上に CLI (`disclean`) と SwiftUI アプリ (`Disclean.app` / 表示名「ディスクリン」) を載せ、v1.0 では両方を提供する。既存の `mac_cleanup.sh`（無確認・無ログ・サイレント失敗）を置き換える。UI は「ギガバイトを物理的な塊として見せる」デザイン言語 HEAVY CANDY（`docs/design-system.md`）で統一し、同じ言語で作った LP から配布する。 ルール定義は署名付きカタログとして自動更新し（OS 更新でキャッシュの置き場所が変わっても本体を入れ直さずに追随できる）、取得は自動・**削除対象を拡大する変更の適用は利用者の承認を必須**とする（F-17〜F-19）。

## ファイルマップ (File Map)

> このドキュメントは複数ファイルに分割されている。各ファイルの責務は下表の通り。
> §4.0 / §6.5 / §10.5 は本ファイル（`docs/REQUIREMENTS.md`）内に残してある（onegai 互換性のため）。

| ファイル | スコープ | 含むセクション |
|---|---|---|
| `docs/REQUIREMENTS.md`（本ファイル） | エントリ + 画面 / 起動前提 / WS | §0, §4.0, §6.5, §10.5 |
| `requirements/01_background.md` | 背景・問題 | §1 |
| `requirements/02_goals.md` | ゴール・ノンゴール | §2 |
| `requirements/03_personas.md` | ユーザー・ペルソナ | §3 |
| `requirements/04_features.md` | 機能定義 | §4.1, §4.2 |
| `requirements/05_data_model.md` | データモデル | §5 |
| `requirements/06_dependencies.md` | 外部依存 | §6（§6.5 を除く） |
| `requirements/07_constraints.md` | 技術制約 | §7 |
| `requirements/08_nfr.md` | 非機能要件 | §8 |
| `requirements/09_architecture.md` | アーキテクチャ | §9 |
| `requirements/10_test_strategy.md` | テスト戦略 | §10（§10.5 を除く） |
| `requirements/11_operations.md` | 運用・DoD | §11 |
| `requirements/12_risks.md` | リスク・前提 | §12, §13 |
| `requirements/14_impl_hints.md` | 実装ヒント | §14 |
| `requirements/15_glossary.md` | 用語集 | §15 |
| `docs/design-system.md` | デザイン言語 HEAVY CANDY（トークン / シグネチャー / LP 構成 / 受入基準 D-01〜D-08）。**作成済み** | §4.0・§7・§8.8 から参照 |
| `docs/rule-schema.md` | ルール JSON のスキーマ定義。**未作成 — 実装時に作る（§11.1 の DoD 項目）** | §5 から参照 |
| `docs/update-protocol.md` | 更新 manifest の形式・署名手順・鍵ローテーション・緊急 revocation の手順。**未作成 — 実装時に作る（§11.1 の DoD 項目）** | §4.2 F-17 / §11 から参照 |

## 4.0 画面一覧 (Screen Inventory)

> CLI は「画面 ≒ 出力モード」として列挙する。GUI は SwiftUI View 単位。
> 「主要要素」は、その画面に必ず存在しなければならない表示物・操作要素。

| ID | ファイル名 | タイトル | カテゴリ | 遷移先 | 主要要素 |
|----|----------|---------|---------|-------|---------|
| S-01 | Sources/disclean/UI/HelpRenderer.swift | CLI ヘルプ | オンボーディング | S-02, S-03, S-10 | USAGE 行, サブコマンド一覧 (scan/plan/apply/undo/purge/history/report/doctor/rules), 各オプション説明 |
| S-02 | Sources/disclean/UI/DoctorView.swift | 環境診断 (doctor) | 設定 | S-03, S-31 | フルディスクアクセス判定行, 検出済み外部CLI表, 状態ディレクトリのパスと書込可否, 隔離庫の使用量, 適用中の catalogVersion と最終チェック時刻, OS のバージョン・ビルドと前回からの変化, この OS で無効・未検出になったルール一覧, 終了コード |
| S-03 | Sources/disclean/UI/ScanTableView.swift | スキャン結果一覧 | メイン | S-04, S-05, S-06, S-10, S-11 | Tier別グループ見出し, ルールID列, サイズ列(降順), リスクバッジ列, 合計行, 空き容量(strict/purgeable込み) |
| S-04 | Sources/disclean/UI/ScanEmptyView.swift | 回収候補なし | 空状態 | S-10 | 「回収可能な項目はありません」文言, 現在の空き容量, Tier C レポートへの誘導文 |
| S-05 | Sources/disclean/UI/ProgressRenderer.swift | スキャン進捗 | ローディング | S-03, S-11 | 進捗率, 走査中ルールID, 経過秒数, Ctrl-C で安全に中断できる旨 |
| S-06 | Sources/disclean/UI/PlanConfirmView.swift | 実行確認プロンプト | 確認 | S-07, S-03 | 選択項目一覧, 合計サイズ, 隔離庫パス, 失効日時, `yes` 入力要求, `--yes` で省略可の注記 |
| S-07 | Sources/disclean/UI/ApplyResultView.swift | 実行結果サマリ | 成功確認 | S-08, S-09 | 隔離件数, 隔離バイト数, スキップ件数と理由, 空き容量の前後, undo コマンド例 |
| S-08 | Sources/disclean/UI/QuarantineListView.swift | 隔離庫一覧 | メイン CRUD | S-07, S-09 | run ID, 隔離日時, 失効日時, 項目数, サイズ, 復元コマンド例 |
| S-09 | Sources/disclean/UI/HistoryView.swift | 実行履歴 | メイン CRUD | S-08 | 日時, アクション, ルールID, バイト数, 結果(ok/skipped/failed) の表, 期間フィルタ |
| S-10 | Sources/disclean/UI/ReportView.swift | Tier C レポート | メイン | S-03 | 削除しない大容量項目の一覧, サイズ, 「disclean は削除しない」の明示, 各項目の手動手順 |
| S-11 | Sources/disclean/UI/ErrorRenderer.swift | エラー出力 | エラー状態 | (終了) | エラー種別, 対象パス, 原因(TCC/権限/ボリューム違い/ルール不正), 復旧手順, 終了コード |
| S-12 | Sources/disclean/UI/JSONOutput.swift | JSON 出力 | メイン | (終了) | `{"schemaVersion","command","items","totals","errors"}` の JSON 1 オブジェクト, stdout のみ |
| S-13 | Sources/DiscleanApp/Views/ScanningView.swift | GUI スキャン中 | ローディング | S-14, S-15, S-23 | 進捗バー, 走査中ルール名, キャンセルボタン |
| S-14 | Sources/DiscleanApp/Views/ResultListView.swift | GUI 結果一覧 | メイン | S-16, S-19, S-20, S-21, S-22 | Tier別セクション, 容量バー, チェックボックス(既定=Tier A のみ), リスクバッジ, 「何を失うか」説明, 合計サイズ, 実行ボタン |
| S-15 | Sources/DiscleanApp/Views/EmptyStateView.swift | GUI 空状態 | 空状態 | S-13, S-21 | 空状態イラスト, 「回収候補なし」文言, 再スキャンボタン |
| S-16 | Sources/DiscleanApp/Views/ConfirmSheet.swift | GUI 実行確認シート | 確認 | S-17, S-14 | 対象一覧, 合計サイズ, 失効日, 「隔離庫へ移動します」文言, 実行/キャンセル |
| S-17 | Sources/DiscleanApp/Views/ApplyProgressView.swift | GUI 実行進捗 | ローディング | S-18, S-23 | 進捗バー, 処理中項目, 中断ボタン |
| S-18 | Sources/DiscleanApp/Views/CompletionSummaryView.swift | GUI 完了サマリ | 成功確認 | S-14, S-19 | 隔離サイズ, 空き容量前後, スキップ理由一覧, 隔離庫を開くボタン |
| S-19 | Sources/DiscleanApp/Views/QuarantineView.swift | GUI 隔離庫 | メイン CRUD | S-14, S-18 | run 一覧, 失効までの残日数, 復元ボタン, 今すぐ完全削除ボタン |
| S-20 | Sources/DiscleanApp/Views/HistoryView.swift | GUI 履歴 | メイン | S-14 | 月別回収量グラフ, 実行ログ表 |
| S-21 | Sources/DiscleanApp/Views/SettingsView.swift | GUI 設定 | 設定 | S-14, S-32 | 隔離TTL日数, 同時実行数, 除外パス編集, ルール上書きディレクトリを開く, 自動更新のオン/オフ, チェック間隔, 適用中の catalogVersion と最終チェック時刻, 「今すぐ確認」, 送信される情報の説明 |
| S-22 | Sources/DiscleanApp/Views/PermissionGuideView.swift | GUI 権限案内 | オンボーディング | S-13, S-14 | フルディスクアクセス未付与の説明, 「システム設定を開く」ボタン, 未付与時に測定できない範囲の一覧 |
| S-23 | Sources/DiscleanApp/Views/ErrorBannerView.swift | GUI エラー | エラー状態 | S-14 | エラー文言, 対象パス, 再試行ボタン, ログを開くボタン |
| S-24 | site/index.html#hero | LP ヒーロー | オンボーディング | S-25, S-28, S-30 | 実測値のチャンクタワー, 実行レバー, 隔離庫の瓶, 「瓶に入れた量」メーター（字面の幅が量に比例）, 見出し, 「これはデモです」注記 |
| S-25 | site/index.html#numbers | LP 実測比較 | メイン | S-26, S-28 | 1 ブロック = 2GB の壁（1 個 対 59 個）, 内訳の凡例, 旧スクリプトとの比較表, 実測日と機種の明記 |
| S-26 | site/index.html#safety | LP 安全のしくみ | メイン | S-27, S-28 | 隔離庫 / 7日 / undo / 監査ログ の4カード, 各カードに「取り消せる範囲」 |
| S-27 | site/index.html#hands-off | LP 触らないもの | メイン | S-28 | Tier C 一覧, 「disclean は削除しません」の明示, 手動手順へのリンク |
| S-28 | site/index.html#install | LP 導入 | 成功確認 | S-29, S-30 | brew コマンドのコピーボタン, .dmg リンク, 対応 OS, 署名と公証の記載 |
| S-29 | site/index.html#faq | LP よくある質問 | 設定 | S-28, S-30 | 6問（復元可否 / sudo / 送信データと更新の通信 / 更新の届き方と止め方 / 空き容量 / アンインストール）。開閉は details/summary |
| S-30 | site/index.html#footer | LP フッタ | エラー状態 | S-24 | GitHub リンク, ライセンス, 旧 mac_cleanup.sh からの移行, JS 無効時の代替表示 |
| S-31 | Sources/disclean/UI/UpdateView.swift | 更新の状態と差分 (update) | 確認 | S-03, (終了) | 適用中の catalogVersion, 配信中の版数と発行日, 差分 3 分類（拡大 / 縮小 / 中立）, **新たに削除対象になるパスと実サイズ**（最上部）, 本体の新版とインストール方法別の案内, `yes` 入力要求, 無効化の方法 |
| S-35 | Sources/disclean/Commands/InfoCommands.swift | まだ見ていない場所 (report --unknown) | メイン | S-34 | 大きい順の場所, サイズ, ファイル数, 最終更新, 「消しません」の明示, 中身の見かた, 打ち切り・読めない場所の注意, `--json` |
| S-36 | Sources/DiscleanApp/Views/CleanViews.swift | まだ見ていない大きな場所（GUI） | メイン | S-33 | 説明（消さないこと）, さがすボタン, 進行表示, 場所ごとのサイズ・パス・ファイル数, 「なかを見る」, 見つからなかったときの文言 |
| S-37 | Sources/disclean/Commands/BigCommand.swift | 大きいもの (big) | メイン | S-34, S-08 | 見た場所, 大きい順の一覧, まとめかた（ひとかたまり/部品・ビルドの置き場/ファイル）, 目印, ファイル数, 最後にさわってからの期間, 「消すとどうなるか」の 1 文, 「消しません」の明示, 打ち切り・読めない場所・iCloud を飛ばした注意, ホーム直下は対象外の明示, `--json` |
| S-38 | Sources/DiscleanApp/Views/BigItemsView.swift | 大きいもの（GUI） | メイン | S-33, S-39, S-19 | 説明（探すだけでは消えない・作り直せるとは限らない）, しきい値の切替（200MB/500MB/1GB）, ~/Library を見るかの切替, さがすボタン, 進行表示（`BusyBoard`）, 件ごとのサイズ・まとめかたチップ（文字併記）・パス・ファイル数・最後にさわった期間・消すとどうなるか, 選択チェック（既定はすべて未選択）, なかを見る, Finder で見る, えらんだ量と件数, 隔離庫へうつす, 見つからなかったとき・途中でやめたときの文言 |
| S-39 | Sources/DiscleanApp/Views/BigItemsView.swift | 大きいものの実行確認シート | 確認 | S-38, S-19 | 対象一覧（サイズ・パス・消すとどうなるか）, 合計と件数, 「いまは消さない」の明示, 失効日時と「そのあとは戻せません」, 「あなたのファイルであることがあります」の注意, うつす / やめる |
| S-33 | Sources/DiscleanApp/Views/InspectSheet.swift | なかみ（GUI 詳細） | 確認 | S-13, S-19 | 対象名, 戻せる/戻せないバッジ, 「これは何？」「このあとどうなる？」の 2 枚, いま見ている場所（`~` 表記）, 合計サイズとファイル数, 種類の内訳帯と各種類の 1 文説明, ファイル一覧（大きい順・種類チップ・サイズ・最終更新・量の帯）, フォルダを開く/もどる, Finder で見る, 省略件数 |
| S-34 | Sources/disclean/Commands/InspectCommand.swift | なかみ (inspect) | メイン | S-03, S-19 | 対象の場所, 実行後の扱い（隔離庫へ移す/外部ツールが消す）, なくなるもの, 合計サイズとファイル数, 中身の一覧（サイズ・種類・名前・ファイル数・最終更新）, 省略件数, `--json` |
| S-32 | Sources/DiscleanApp/Views/UpdateSheet.swift | GUI 更新シート | 確認 | S-14, S-21 | 差分一覧（拡大差分を最上部・装飾なし）, 「承認するまで削除対象は増えません」の明示, 承認 / 後で / この更新を無視, 本体の新版の案内, 設定へのリンク |

## 6.5 ローカル起動前提情報 (Local Startup Prerequisites)

### 6.5.1 ローカル起動コマンド（想定）
```bash
swift build -c release && ./.build/release/disclean doctor && ./.build/release/disclean scan
```

LP（`site/`）はビルド工程を持たない静的ファイルのため、確認は下記 1 行で行う。

```bash
python3 -m http.server 4173 --directory site
```

### 6.5.2 必須環境変数（required — 欠如時アプリ起動失敗）
| 変数名 | 用途 | 例値 / 取得方法 | 紐づく機能 |
|-------|-----|---------------|----------|
| （なし） | 必須環境変数は存在しない。全設定は既定値を持ち、環境変数なしで全機能が動作する | — | — |

### 6.5.3 任意環境変数（optional — 欠如時は既定値で動作）
| 変数名 | 用途 | デフォルト挙動 | 紐づく機能 |
|-------|-----|--------------|----------|
| DISCLEAN_CONFIG_DIR | 設定・ユーザールールの読込先 | `~/.config/disclean` を使用 | F-01 |
| DISCLEAN_STATE_DIR | 隔離庫・監査ログ・スキャンキャッシュの保存先 | `~/.local/state/disclean` を使用 | F-05, F-06, F-07, F-08 |
| DISCLEAN_QUARANTINE_TTL_DAYS | 隔離庫の保持日数（整数, 1〜90） | `7` を使用 | F-06 |
| DISCLEAN_CONCURRENCY | スキャン同時実行数（整数, 1〜32） | `min(8, ProcessInfo.activeProcessorCount)` を使用 | F-02 |
| DISCLEAN_AUTO_UPDATE | `0` で更新チェックを完全に無効化（通信が一切発生しない） | 有効（既定オン）。24 時間に 1 回、コマンド実行時のみチェック | F-17, F-18 |
| DISCLEAN_UPDATE_INTERVAL_HOURS | 更新チェックの間隔（整数, 1〜168） | `24` を使用 | F-17 |
| DISCLEAN_UPDATE_ENDPOINT | 更新の配信元 URL（テスト・ミラー用）。**署名検証は無効化できない** | `https://github.com/suzuki-junya108/disclean/releases/latest/download/` を使用 | F-17, F-18 |
| DISCLEAN_UPDATE_TRUSTED_KEYS_FILE | テスト用の信頼公開鍵ファイル。**debug ビルドでのみ有効**（release ビルドは無視する） | 埋め込みの `release-keys.json` のみを信頼 | F-17 |
| NO_COLOR | 値の有無のみ判定。設定時は ANSI 色を出力しない | TTY のときのみ色付き出力 | S-03, S-07, S-11 |

### 6.5.4 必須プロセス／エミュレータ
- なし。DB・サーバー・エミュレータのいずれも不要。
- 外部 CLI（brew / npm / pnpm / yarn / uv / pip3 / xcrun simctl / docker / colima）は **任意**。実行時に `detect` コマンドで検出し、無ければ該当ルールを `skipped(reason: "tool-not-found")` として報告する。
- ネットワーク接続は **任意**。オフラインでも全機能が動作する（更新チェックが静かに失敗するのみ。WS-o / MQ-15）。
- 更新機構の自動テストにはローカル HTTP サーバー（`python3 -m http.server`）とテスト用 Ed25519 鍵を使う。実在の GitHub へは接続しない。
- LP の確認には Python 3.9 以降（macOS 標準搭載）が必要。Node.js・バンドラ・パッケージインストールは不要。

### 6.5.5 シード／マイグレーション初期化
- DB を使わないため migration は存在しない（`N/A — reason: 永続化は JSON/JSONL ファイルのみ`）。
- 状態ディレクトリ初期化: `disclean doctor --init` が `$DISCLEAN_STATE_DIR/{quarantine,audit,cache}` と `$DISCLEAN_CONFIG_DIR/rules.d` を作成する（既存なら何もしない、冪等）。
- シードデータ: 公式ルールカタログは実行ファイルに同梱（SwiftPM resource）。ユーザー投入は不要。
- リセット手順: `disclean purge --all --force` で隔離庫を空にし、`rm -rf "$DISCLEAN_STATE_DIR"` で状態を初期化する。

## 10.5 Walking Skeleton 完了条件 (Bootstrap Smoke Test)

| ID | 条件 | 検証コマンド | 期待結果 |
|----|------|------------|---------|
| WS-a | プロセス起動 | `swift run disclean --version` | 5 秒以内に `disclean 0.1.0` 形式の 1 行を stdout に出力し exit 0 |
| WS-b | PORT変更可 | `N/A` | N/A — reason: ネットワークを待ち受けないローカル CLI/GUI のため |
| WS-c | ヘルスチェック | `N/A` | N/A — reason: 常駐サービスではないため /health は存在しない |
| WS-d | --help (CLI) | `swift run disclean --help` | exit 0 かつ stdout に `USAGE:` と `scan` `plan` `apply` `undo` `purge` `history` `report` `doctor` `rules` を含む |
| WS-e | iOS ビルド | `N/A` | N/A — reason: macOS 専用ツールのため iOS ターゲットなし |
| WS-f | Android ビルド | `N/A` | N/A — reason: macOS 専用ツールのため |
| WS-g | Flutter analyze | `N/A` | N/A — reason: Swift のみで Flutter を使用しない |
| WS-h | release ビルド成果物 | `swift build -c release && test -x ./.build/release/disclean` | exit 0（`Build complete!` を含み、実行可能ファイルが存在） |
| WS-i | 単体テスト起動 | `swift test` | exit 0 かつ stdout に `Test run with` と `passed` を含む |
| WS-j | GUI ビルド | `tools/make-app.sh`（SwiftPM の実行ファイルにバンドル構造を被せる方式。Xcode プロジェクトは持たない） | `build/Disclean.app` が生成され exit 0 |
| WS-k | scan が読み取り専用 | `DISCLEAN_STATE_DIR=$(mktemp -d) ./.build/release/disclean scan --json > /tmp/disclean-ws-k.json; jq -e '.items \| length >= 0' /tmp/disclean-ws-k.json` | exit 0 かつ `$DISCLEAN_STATE_DIR/quarantine` が空（`find "$DISCLEAN_STATE_DIR/quarantine" -mindepth 1 \| wc -l` が `0`） |
| WS-l | Lint clean | `swiftlint lint --strict` | exit 0 かつ `0 violations` を含む |
| WS-m | LP が単体で開ける | `python3 -m http.server 4173 --directory site & sleep 2; curl -sf -o /dev/null -w '%{http_code}' http://localhost:4173/index.html` | `200` を出力（ビルド工程なしで配信できる） |
| WS-n | LP のデザイン禁則 | `! grep -rnE 'box-shadow:[^;]*[0-9]+px +[0-9]+px +[1-9]' site/ && ! grep -rn 'linear-gradient\|radial-gradient' site/*.css` | exit 0（ぼかし影とグラデーションが 0 件。`docs/design-system.md` D-02 / D-03） |
| WS-o | オフラインでも動作する | `DISCLEAN_STATE_DIR=$(mktemp -d) DISCLEAN_UPDATE_ENDPOINT=http://127.0.0.1:1/ ./.build/release/disclean doctor --json` | 5 秒以内に exit 0（更新チェックの失敗が終了コードに影響せず、コマンド本体を待たせない） |
| WS-p | 更新の検証が働く | `acceptance/AT-016-update.sh --signature-only` | exit 7 かつ stderr に `signature` を含み、`$DISCLEAN_STATE_DIR/updates/active` が生成されない |
