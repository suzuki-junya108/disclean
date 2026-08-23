> 責務: 機能インベントリ (§4.1) と機能ごとの詳細仕様 (§4.2)。画面一覧 (§4.0) は ../REQUIREMENTS.md 参照。
> 親: ../REQUIREMENTS.md

## 4. Functional Requirements

### 4.1 Feature Inventory

| ID | Feature | Priority | Phase | フェーズ完了ゲート |
|---|---|---|---|---|
| F-01 | ルールカタログの読込・検証（同梱 JSON + ユーザー上書き） | Must | MVP | `swift test --filter RuleCatalog` 全 PASS, AT-001 PASS |
| F-02 | スキャン（読み取り専用・並列・dataless 非展開） | Must | MVP | `swift test --filter Scanner` 全 PASS, AT-002 PASS, WS-k PASS |
| F-03 | 空き容量の計測と回収量の帰属 | Must | MVP | `swift test --filter Capacity` 全 PASS, AT-003 PASS |
| F-04 | プラン生成と選択（Tier A 既定選択） | Must | MVP | `swift test --filter Planner` 全 PASS, AT-004 PASS |
| F-05 | 実行（隔離庫への移動）と安全ガード | Must | MVP | `swift test --filter Quarantine` 全 PASS, AT-005 PASS |
| F-06 | 隔離庫の失効処理（TTL 経過分の実削除） | Must | MVP | `swift test --filter Purge` 全 PASS, AT-006 PASS |
| F-07 | 復元（undo） | Must | MVP | `swift test --filter Restore` 全 PASS, AT-005 PASS |
| F-08 | 監査ログ（JSONL）と履歴表示 | Must | MVP | `swift test --filter Audit` 全 PASS, AT-007 PASS |
| F-09 | 環境診断（doctor: FDA 判定・外部ツール検出・状態確認） | Must | MVP | `swift test --filter Doctor` 全 PASS, AT-008 PASS |
| F-10 | コマンド型ルールの実行（brew/npm/simctl/docker 等） | Must | MVP | `swift test --filter CommandRule` 全 PASS, AT-009 PASS |
| F-11 | Tier C レポート（削除せず提示のみ） | Must | MVP | `swift test --filter Report` 全 PASS, AT-010 PASS |
| F-12 | GUI: スキャン → 選択 → 実行フロー | Must | v1.0 | `xcodebuild test -scheme DiscleanUITests` 全 PASS, AT-011 PASS |
| F-13 | GUI: 隔離庫と履歴 | Must | v1.0 | `xcodebuild test -scheme DiscleanUITests` 全 PASS, AT-012 PASS |
| F-14 | GUI: 権限案内と設定 | Must | v1.0 | `xcodebuild test -scheme DiscleanUITests` 全 PASS, AT-013 PASS |
| F-15 | デザイン言語 HEAVY CANDY の実装（トークン / チャンク / レバー / 瓶） | Must | v1.0 | `swift test --filter DesignTokens` 全 PASS, AT-014 PASS, D-01〜D-06 PASS |
| F-16 | 配布 LP（GitHub Pages, 静的） | Must | v1.0 | AT-015 PASS, D-01/D-03/D-07/D-08 PASS, WS-m / WS-n PASS |
| F-17 | ルールカタログの自動更新（署名検証 + 差分の承認適用） | Must | v1.0 | `swift test --filter CatalogUpdate` 全 PASS, AT-016 PASS |
| F-18 | 本体バージョンの更新検知とインストール導線 | Should | v1.0 | `swift test --filter AppUpdate` 全 PASS, AT-017 PASS |
| F-19 | OS 変化の検知とルールの OS 条件評価 | Must | MVP | `swift test --filter OSDrift` 全 PASS, AT-018 PASS |
| F-20 | 対象と隔離物の中身をファイル単位で見る（なかみ） | Must | v0.3 | `swift test --filter FileInventory`・`--filter InventoryBrowser` 全 PASS, AT-019 PASS |
| F-21 | ルールが見ていない大きな場所を知らせる（取りこぼしの可視化） | Must | v0.8 | `swift test --filter Uncovered` 全 PASS, AT-021 PASS |

**共通の終了コード規約**（全 CLI サブコマンド）

| Code | 意味 |
|---|---|
| 0 | 成功（スキップ項目があっても、失敗が 0 件なら 0） |
| 1 | 一般エラー（想定外の例外） |
| 2 | 引数エラー（ArgumentParser 既定） |
| 3 | 権限不足（TCC / フルディスクアクセス未付与により対象を読めない） |
| 4 | 部分的失敗（1 件以上の項目が failed） |
| 5 | ルールカタログ不正（JSON パース失敗 / スキーマ違反 / 禁止パス） |
| 6 | 隔離庫の整合性エラー（index.json と実体の不一致） |
| 7 | 更新の検証失敗（署名不一致 / ハッシュ不一致 / 巻き戻し検出 / manifest 期限切れ）。更新を適用せず、既存カタログで動作を継続する |
| 130 | SIGINT による中断（中断時点までの状態は整合を保つ） |

### 4.2 Feature Detail (one subsection per feature)

#### F-01: ルールカタログの読込・検証

- **Trigger**: すべてのサブコマンド起動時（`disclean rules list` では結果を表示する）
- **Actor**: CLI / GUI プロセス自身
- **Preconditions**: 実行ファイルに公式カタログ（SwiftPM resource `Resources/rules/*.json`）が同梱されている
- **Main flow**:
  1. 同梱カタログ（`Bundle.module`）から全 `*.json` を読み、`Rule` 配列にデコードする
  2. `$DISCLEAN_CONFIG_DIR/rules.d/*.json`（既定 `~/.config/disclean/rules.d/`）をファイル名昇順で読み、同一 `id` があればユーザー定義で置換、`enabled: false` なら無効化、新規 `id` なら追加する
  3. 各ルールに対しスキーマ検証（§5.1）と禁止パス検証（F-05 の SG-01〜SG-04 と同じ規則）を行う
  4. 検証を通ったルールのみを有効カタログとして返す
- **Alternate flows**:
  - ユーザールールが JSON として不正 → そのファイルのみ拒否し、ファイル名と行番号を stderr に出して exit 5
  - ユーザールールが禁止パスを含む → そのルールを拒否し、`id` と違反理由を出して exit 5
- **Postconditions**: 有効カタログがメモリ上に構築され、ファイルシステムは変更されていない
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean rules list` | `[--tier A\|B\|C] [--json]` | `{"schemaVersion":1,"rules":[{"id","title","tier","kind","enabled","source":"builtin\|user"}]}` | 0, 5 |
  | `disclean rules validate` | `[<path>]` | `{"schemaVersion":1,"valid":bool,"errors":[{"file","ruleId","reason"}]}` | 0, 5 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | JSON パース失敗 | `JSONDecoder` の throw | stderr に `rules: <file>: <message>`、exit 5 |
  | 必須フィールド欠落 | デコード時の keyNotFound | stderr に `rules: <file>: missing field "<name>" in rule "<id>"`、exit 5 |
  | 禁止パス（`/`, `/System`, `$HOME` 直下, 深さ 2 未満） | `PathGuard.validate` | stderr に `rules: <id>: forbidden path "<path>"`、exit 5 |
  | 重複 id（同一ファイル内） | 読み込み時の Set 判定 | stderr に `rules: <file>: duplicate id "<id>"`、exit 5 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN 追加のユーザールールを置いていない状態
    - WHEN `disclean rules list --json` を実行する
    - THEN stdout の `.rules \| length` が 1 以上、すべての要素が `source == "builtin"`
    - 検証コマンド: `acceptance/AT-001-rules.sh`
    - 期待結果: exit 0, 出力に `"valid": true` を含む
  - AC2:
    - GIVEN `$DISCLEAN_CONFIG_DIR/rules.d/99-bad.json` に `{"id":"evil","tier":"A","kind":"directory","paths":["/"]}` を置く
    - WHEN `disclean rules validate` を実行する
    - THEN stderr に `forbidden path "/"` を含み、有効カタログにこのルールが含まれない
    - 検証コマンド: `acceptance/AT-001-rules.sh`
    - 期待結果: exit 5

#### F-02: スキャン（読み取り専用）

- **Trigger**: `disclean scan` の実行、または GUI 起動時の自動スキャン（S-13）
- **Actor**: P1 / P2（CLI）、P3（GUI）
- **Preconditions**: 有効カタログが構築済み（F-01）
- **Main flow**:
  1. プロセス起動直後に `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)` を発行し、クラウド未ダウンロードファイルの実体化を抑止する
  2. Tier A / B の各ルールについて、対象パスを解決し（`*` のひな形は 1 階層ずつ広げ、リンクは辿らない。`pathsFrom` があればツールに聞く）、存在と前提条件（対象アプリが未起動か、外部ツールが検出できるか）を評価する。**ツールが答えたパスにも F-01 と同じ禁止パス検証を必ず通す**（通らなければ `skipped(reason: "forbidden-root")`）
  3. 各パスを最大 `DISCLEAN_CONCURRENCY` 並列で列挙し、`lstat` の `st_blocks * 512`（実割当サイズ）を合算する。
     **実行時と同じ条件で数える**こと: `minAgeDays` があれば条件を満たす項目だけを、`requiresQuitApps` の
     アプリが起動中ならそのルール自体を `skipped` にする（表示した量と実際に移る量を一致させるため）。`st_flags & SF_DATALESS`（0x40000000）が立つ項目は中身を開かず、サイズ 0 かつ `dataless: true` として記録する
  4. ディレクトリ単位の結果を `$DISCLEAN_STATE_DIR/cache/scan-cache.json` に保存する（キー: 絶対パス、値: バイト数・ファイル数・ディレクトリの mtime・計測時刻）
  5. Tier 別にグループ化し、サイズ降順で `ScanResult` を返す
- **Alternate flows**:
  - キャッシュに同一パスの記録があり、ディレクトリの mtime が一致し、計測から 24 時間以内 → 再走査せずキャッシュ値を使う（`--no-cache` で無効化）
  - 対象パスが読めない（TCC / 権限） → その項目を `blocked(reason: "permission-denied", path:)` として記録し、成功項目には数えない
  - SIGINT 受信 → 走査を中断し、それまでの結果を出力して exit 130
- **Postconditions**: ファイルシステムへの変更はスキャンキャッシュの書き込みのみ。対象ディレクトリは一切変更されない
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean scan` | `[--tier A\|B\|C] [--json] [--no-cache] [--rule <id>]...` | `{"schemaVersion":1,"command":"scan","items":[{"ruleId","tier","title","bytes","fileCount","paths":[],"state":"ready\|blocked\|skipped","reason"}],"totals":{"bytes","itemCount"},"capacity":{"strictBytes","importantBytes","snapshotCount"},"errors":[]}` | 0, 3, 5, 130 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | TCC による読み取り拒否 | `errno == EPERM \|\| EACCES` | 当該項目を `blocked` にし、末尾に「フルディスクアクセスを付与すると測定できます」を表示。全項目が blocked なら exit 3 |
  | 対象パス不存在 | `lstat` の ENOENT | `skipped(reason: "not-found")`。エラー扱いにしない |
  | キャッシュ JSON 破損 | デコード失敗 | キャッシュを破棄して全走査し、stderr に警告 1 行。exit 0 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN 一時ディレクトリに 1MiB のファイルを 3 個作り、それを対象にするユーザールールを置く
    - WHEN `disclean scan --rule test-fixture --json` を実行する
    - THEN `.items[0].bytes` が 3145728 以上 3670016 以下（ブロック丸め許容）、`.items[0].state == "ready"`
    - 検証コマンド: `acceptance/AT-002-scan.sh`
    - 期待結果: exit 0
  - AC2:
    - GIVEN 直前に同じスキャンを実行済み（キャッシュあり）
    - WHEN `time disclean scan --rule test-fixture --json` を実行する
    - THEN 実時間が 5.0 秒未満
    - 検証コマンド: `acceptance/AT-002-scan.sh`
    - 期待結果: exit 0, 出力に `"cacheHit": true` を含む
  - AC3:
    - GIVEN `DISCLEAN_STATE_DIR` を空の一時ディレクトリに設定する
    - WHEN `disclean scan --json` を実行する
    - THEN `$DISCLEAN_STATE_DIR/quarantine` 配下のエントリ数が 0 のまま
    - 検証コマンド: `acceptance/AT-002-scan.sh`
    - 期待結果: exit 0, `find "$DISCLEAN_STATE_DIR/quarantine" -mindepth 1 \| wc -l` が `0`

#### F-03: 空き容量の計測と回収量の帰属

- **Trigger**: `disclean scan` / `disclean apply` の開始時と完了時
- **Actor**: CLI / GUI プロセス自身
- **Preconditions**: なし
- **Main flow**:
  1. `URL(fileURLWithPath: NSHomeDirectory())` に対し `volumeAvailableCapacityKey`（即時利用可能な空き）と `volumeAvailableCapacityForImportantUsageKey`（purgeable を含む空き）を取得する
  2. `tmutil listlocalsnapshots /` を実行し、ローカルスナップショット数を取得する（コマンドが無い・失敗した場合は `nil`）
  3. `apply` 完了時、**回収量は隔離した項目のバイト数合計として報告する**（決定的な値）
  4. 空き容量の前後差は「参考値」として別行に表示し、`snapshotCount > 0` のときは「ローカルスナップショットが残っているため、空き容量には即時反映されない場合があります」を併記する
- **Alternate flows**: `tmutil` が存在しない → スナップショット行を省略し、警告は出さない
- **Postconditions**: 計測値が `CapacitySample` として監査ログに記録される
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | （全コマンド共通の出力ブロック） | — | `{"capacity":{"strictBytes":int,"importantBytes":int,"snapshotCount":int\|null}}` | — |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | resourceValues の throw | `try` の catch | `strictBytes: null` として出力を継続し、stderr に 1 行警告。exit は変えない |
- **Acceptance criteria**:
  - AC1:
    - GIVEN 任意の状態
    - WHEN `disclean scan --json` を実行する
    - THEN `.capacity.strictBytes > 0` かつ `.capacity.importantBytes >= .capacity.strictBytes`
    - 検証コマンド: `acceptance/AT-003-capacity.sh`
    - 期待結果: exit 0
  - AC2:
    - GIVEN 隔離対象が 1 件以上ある状態で `disclean apply --yes` を実行した直後
    - WHEN 出力を読む
    - THEN 「回収量」は隔離バイト合計として表示され、空き容量差分は `参考` ラベル付きの別行として表示される
    - 検証コマンド: `acceptance/AT-003-capacity.sh`
    - 期待結果: exit 0, 出力に `reclaimedBytes` と `freeSpaceDeltaBytes` の両キーを含む

#### F-04: プラン生成と選択

- **Trigger**: `disclean plan` の実行、または `disclean apply` の内部呼び出し、GUI のチェックボックス操作（S-14）
- **Actor**: P1 / P2 / P3
- **Preconditions**: F-02 のスキャン結果が存在する
- **Main flow**:
  1. スキャン結果のうち `state == "ready"` の項目を候補にする
  2. Tier A を既定で選択済み、Tier B を既定で未選択にする
  3. `--select <ruleId>` / `--deselect <ruleId>` / `--tier` の指定で選択集合を上書きする
  4. 選択集合・合計バイト数・生成時刻・隔離先 run ID を含む `Plan` を返す
- **Alternate flows**:
  - 候補が 0 件 → S-04（空状態）を表示して exit 0
  - `--select` に存在しない `ruleId` を指定 → stderr に `unknown rule id` を出して exit 2
- **Postconditions**: `Plan` が生成される。`--save <path>` 指定時のみ JSON として保存される
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean plan` | `[--tier A\|B] [--select <id>]... [--deselect <id>]... [--save <path>] [--json]` | `{"schemaVersion":1,"command":"plan","runId":"<ULID>","selected":[{"ruleId","bytes"}],"totals":{"bytes","itemCount"}}` | 0, 2, 3, 5 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | 未知の ruleId | カタログとの突合 | stderr に `plan: unknown rule id "<id>"`、exit 2 |
  | Tier C の明示選択 | ルールの tier 判定 | stderr に `plan: tier C rules cannot be selected (report only)`、exit 2 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN Tier A と Tier B のルールがそれぞれ 1 件以上「ready」である
    - WHEN `disclean plan --json` を実行する
    - THEN `.selected` の全要素の tier が `A` であり、Tier B の項目は含まれない
    - 検証コマンド: `acceptance/AT-004-plan.sh`
    - 期待結果: exit 0
  - AC2:
    - GIVEN Tier C のルール id `trash` が存在する
    - WHEN `disclean plan --select trash` を実行する
    - THEN stderr に `tier C rules cannot be selected` を含む
    - 検証コマンド: `acceptance/AT-004-plan.sh`
    - 期待結果: exit 2

#### F-05: 実行（隔離庫への移動）と安全ガード

- **Trigger**: `disclean apply` の実行、GUI の確認シートで「実行」押下（S-16）
- **Actor**: P1 / P2 / P3
- **Preconditions**: `Plan` が生成済み。`$DISCLEAN_STATE_DIR` が書き込み可能
- **Main flow**:
  1. 対話 TTY かつ `--yes` 未指定なら S-06 の確認プロンプトを表示し、`yes` の入力を要求する
  2. run ID（ULID）を採番し、`$DISCLEAN_STATE_DIR/quarantine/<runID>/` を 0700 で作成する
  3. 各対象パスに対して安全ガード SG-01〜SG-09（下表）を順に適用し、1 つでも違反すれば当該項目を `skipped(reason:)` として次へ進む
  4. `directory` 型ルールは対象ディレクトリ**の中身**を 1 エントリずつ、`rename(2)` で隔離庫へ移動する（ディレクトリ自体は残す）。
     移動する項目がディレクトリの場合、**その中身を含めた実サイズ**を記録する（`lstat` の `st_blocks` は入れ物自身の大きさしか返さない）
  5. `command` 型ルールは F-10 の手順で外部コマンドを実行する（隔離庫は経由しない）
  6. 移動のたびに監査ログへ 1 行追記し、`index.json` を更新する
  7. 完了後に F-03 の計測を行い、S-07 のサマリを表示する
- **安全ガード**:
  | ID | 規則 | 違反時 |
  |---|---|---|
  | SG-01 | 対象は `realpath` 解決後に `$HOME` 配下であること | `skipped(reason: "outside-home")` |
  | SG-02 | パス深さが `$HOME` から 2 階層以上であること（`$HOME/Library` 単体は不可） | `skipped(reason: "too-shallow")` |
  | SG-03 | パス文字列が空でなく、`/`・`/System`・`/Library`・`/private/var` で始まらないこと | `skipped(reason: "forbidden-root")` |
  | SG-04 | 対象自身がシンボリックリンクでないこと（`lstat` で判定、リンクは辿らない） | `skipped(reason: "symlink")` |
  | SG-05 | 対象が `$DISCLEAN_STATE_DIR` および `$DISCLEAN_CONFIG_DIR` の配下でないこと | `skipped(reason: "self-referential")` |
  | SG-06 | 対象が `~/Sync`（Syncthing 同期対象）配下でないこと。除外パスは設定で追加可能 | `skipped(reason: "excluded")` |
  | SG-07 | ルールが `requiresQuitApps` を持つ場合、該当バンドル ID のアプリが `NSWorkspace.shared.runningApplications` に存在しないこと | `skipped(reason: "app-running:<bundleId>")` |
  | SG-08 | 対象と隔離庫が同一ボリュームであること（`volumeIdentifierKey` の一致） | `skipped(reason: "cross-volume")` |
  | SG-09 | `minAgeDays` 指定時、対象の `contentModificationDate` が指定日数より古いこと | `skipped(reason: "too-recent")` |
- **Alternate flows**:
  - `--dry-run` 指定 → SG 判定までを行い、移動を実行せずに結果だけ表示する
  - SIGINT 受信 → 進行中の `rename` の完了を待ち、`index.json` を確定させてから exit 130
- **Postconditions**: 選択項目が隔離庫配下に存在し、元パスから消えている。`index.json` と監査ログが整合している
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean apply` | `[--tier A\|B] [--select <id>]... [--deselect <id>]... [--dry-run] [--yes] [--json]` | `{"schemaVersion":1,"command":"apply","runId","quarantined":[{"ruleId","originalPath","quarantinePath","bytes"}],"skipped":[{"ruleId","path","reason"}],"failed":[{"ruleId","path","error"}],"totals":{"reclaimedBytes","itemCount"},"capacity":{"freeSpaceDeltaBytes"},"expiresAt":"<ISO8601>"}` | 0, 1, 3, 4, 5, 6, 130 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | `rename` が EXDEV | errno 判定 | `skipped(reason: "cross-volume")`。コピー＋削除へのフォールバックは行わない |
  | `rename` が EACCES / EPERM | errno 判定 | `failed` に記録し、最終 exit を 4 にする |
  | 隔離庫の作成失敗 | mkdir の throw | 何も移動せず exit 6 |
  | 確認プロンプトで `yes` 以外の入力 | 標準入力の比較 | 何も移動せず「中止しました」を表示して exit 0 |
  | 非 TTY かつ `--yes` 未指定 | `isatty(0) == 0` | 何も移動せず stderr に `apply: --yes is required in non-interactive mode`、exit 2 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN 一時ディレクトリ配下に fixture を作り、それを対象とする Tier A ルールを置く
    - WHEN `disclean apply --rule test-fixture --yes --json` を実行する
    - THEN `.quarantined \| length == 3`、元パスにファイルが存在せず、`$DISCLEAN_STATE_DIR/quarantine/<runId>/` 配下に 3 件存在する
    - 検証コマンド: `acceptance/AT-005-apply-undo.sh`
    - 期待結果: exit 0
  - AC2:
    - GIVEN `paths` に `$HOME` 直下（`~/Library`）を指定したユーザールールを置く
    - WHEN `disclean apply --rule shallow-test --yes --json` を実行する
    - THEN `.skipped[0].reason == "too-shallow"` であり `.quarantined` が空
    - 検証コマンド: `acceptance/AT-005-apply-undo.sh`
    - 期待結果: exit 0, `~/Library` が変更されていない
  - AC3:
    - GIVEN 非対話環境（`< /dev/null`）
    - WHEN `disclean apply` を `--yes` なしで実行する
    - THEN stderr に `--yes is required in non-interactive mode` を含み、隔離庫が空のまま
    - 検証コマンド: `acceptance/AT-005-apply-undo.sh`
    - 期待結果: exit 2

#### F-06: 隔離庫の失効処理

- **Trigger**: 任意の `disclean` サブコマンド起動時（自動、1 回のみ）、または `disclean purge` の明示実行
- **Actor**: CLI / GUI プロセス自身、P1 / P2 / P3
- **Preconditions**: `index.json` が読める
- **Main flow**:
  1. `index.json` の各 run について `expiresAt <= 現在時刻` を判定する
  2. 失効した run のディレクトリを `FileManager.removeItem` で削除する
  3. 監査ログに `purge` を 1 件ずつ追記し、`index.json` から該当 run を除去する
  4. 自動実行時は削除件数とバイト数を 1 行で通知する（`--json` 時は `purged` キーに含める）
- **Alternate flows**:
  - `disclean purge --all --force` → 失効前の run も含めて全削除（確認プロンプトあり、`--force` で省略）
  - `disclean purge --run <runID>` → 指定 run のみ即時削除
- **Postconditions**: 失効 run が隔離庫から消え、`index.json` と実体が一致する
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean purge` | `[--all] [--run <runID>] [--force] [--json]` | `{"schemaVersion":1,"command":"purge","purged":[{"runId","bytes","itemCount"}],"totals":{"bytes"}}` | 0, 2, 6 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | index にあるが実体が無い run | `FileManager.fileExists` | index から除去し、監査ログに `reason: "orphan-index"` を記録。exit 0 |
  | 実体があるが index に無いディレクトリ | ディレクトリ列挙との差分 | 削除せず stderr に `purge: orphan directory <path>` を出し、exit 6 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN `DISCLEAN_QUARANTINE_TTL_DAYS=0` で `disclean apply --yes` を実行済み
    - WHEN 次に `disclean scan` を実行する
    - THEN 直前の run のディレクトリが削除され、`index.json` の `runs` が空になる
    - 検証コマンド: `acceptance/AT-006-purge.sh`
    - 期待結果: exit 0, 出力に `"purged"` を含む
  - AC2:
    - GIVEN 隔離庫に有効期限内の run が 1 件ある
    - WHEN `disclean purge --json` を実行する
    - THEN `.purged \| length == 0` であり run が残っている
    - 検証コマンド: `acceptance/AT-006-purge.sh`
    - 期待結果: exit 0

#### F-07: 復元（undo）

- **Trigger**: `disclean undo <runID>` の実行、GUI の復元ボタン押下（S-19）
- **Actor**: P1 / P2 / P3
- **Preconditions**: 対象 run が隔離庫に存在し、失効していない
- **Main flow**:
  1. `index.json` から対象 run のエントリ一覧を読む
  2. 各エントリについて、元パスの親ディレクトリが存在しなければ作成し、`rename` で元パスへ戻す
  3. 監査ログに `restore` を追記し、`index.json` から復元済みエントリを除去する
  4. 全件復元後、run ディレクトリを削除する
- **Alternate flows**:
  - 元パスに同名の実体が既に存在する → そのエントリを `skipped(reason: "destination-exists")` とし、隔離庫に残す
  - `disclean undo --last` → 最新の run を対象にする
- **Postconditions**: 復元されたエントリが元パスに存在し、隔離庫から消えている
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean undo` | `<runID> \| --last [--json]` | `{"schemaVersion":1,"command":"undo","runId","restored":[{"originalPath","bytes"}],"skipped":[{"originalPath","reason"}],"totals":{"bytes","itemCount"}}` | 0, 2, 4, 6 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | 未知の runID | index 突合 | stderr に `undo: unknown run id "<id>"`、exit 2 |
  | 復元先に既存実体 | `lstat` が成功 | `skipped(reason: "destination-exists")`、隔離庫に残す。全件スキップなら exit 4 |
  | rename 失敗 | errno | `failed` に記録し exit 4 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN AT-005 AC1 の直後（3 件が隔離済み）
    - WHEN `disclean undo --last --json` を実行する
    - THEN `.restored \| length == 3`、元の 3 ファイルが元パスに存在し、合計バイト数が隔離前と一致する
    - 検証コマンド: `acceptance/AT-005-apply-undo.sh`
    - 期待結果: exit 0
  - AC2:
    - GIVEN 復元先に同名ファイルを手動で作成した状態
    - WHEN `disclean undo --last --json` を実行する
    - THEN `.skipped[0].reason == "destination-exists"`
    - 検証コマンド: `acceptance/AT-005-apply-undo.sh`
    - 期待結果: exit 4

#### F-08: 監査ログと履歴表示

- **Trigger**: 全ての破壊的操作（apply / purge / undo）、および `disclean history` の実行
- **Actor**: CLI / GUI プロセス自身、P1 / P2 / P3
- **Preconditions**: `$DISCLEAN_STATE_DIR/audit/` が書き込み可能
- **Main flow**:
  1. 操作 1 件につき 1 行の JSON を `$DISCLEAN_STATE_DIR/audit/YYYY-MM.jsonl` へ追記する（`O_APPEND` で開き、1 行を 1 回の `write` で書く）
  2. `disclean history` は指定期間のファイルを読み、時刻降順で表示する
- **Alternate flows**: 監査ログの書き込みに失敗 → 操作を中止し、既に移動済みの項目は隔離庫に残したまま exit 1（記録できない削除は行わない）
- **Postconditions**: 全ての破壊的操作が 1 行ずつ記録されている
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean history` | `[--since <ISO8601>] [--until <ISO8601>] [--action apply\|undo\|purge] [--json]` | `{"schemaVersion":1,"command":"history","records":[{"ts","action","runId","ruleId","path","bytes","result","reason"}],"totals":{"bytes","recordCount"}}` | 0, 2 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | 監査ログ書き込み失敗 | write の throw | 以後の破壊的操作を中止し stderr に `audit: cannot write log`、exit 1 |
  | 壊れた JSONL 行 | 行単位のデコード失敗 | その行を読み飛ばし、`errors` に行番号を記録して継続。exit 0 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN `disclean apply --yes` を 1 回実行済み
    - WHEN `disclean history --json` を実行する
    - THEN `.records` に `action == "apply"` の行が隔離件数と同数存在し、各行が `ts` `runId` `path` `bytes` を持つ
    - 検証コマンド: `acceptance/AT-007-history.sh`
    - 期待結果: exit 0
  - AC2:
    - GIVEN 監査ログディレクトリを 0500（書き込み不可）にする
    - WHEN `disclean apply --rule test-fixture --yes` を実行する
    - THEN 元パスのファイルが 1 件も消えていない
    - 検証コマンド: `acceptance/AT-007-history.sh`
    - 期待結果: exit 1, stderr に `audit: cannot write log` を含む

#### F-09: 環境診断（doctor）

- **Trigger**: `disclean doctor` の実行、GUI 起動時（S-22 の表示要否判定）
- **Actor**: P1 / P2 / P3
- **Preconditions**: なし
- **Main flow**:
  1. フルディスクアクセス判定: `~/Library/Application Support/com.apple.TCC/TCC.db` を読み取り専用で `open(2)` し、成功すれば付与済み、`EPERM` なら未付与とする（ファイルの内容は読まない）
  2. 外部 CLI の検出: 各ツールの `detect` コマンド（例 `brew --version`）を 5 秒タイムアウトで実行し、バージョン文字列を得る
  3. 状態ディレクトリの存在・権限・隔離庫の使用量を表示する
  4. `--init` 指定時は不足ディレクトリを作成する
- **Alternate flows**: FDA 未付与 → 影響範囲（`~/.Trash` `~/Downloads` `~/Documents` `~/Desktop` が測定不能）と、システム設定を開く手順を表示する
- **Postconditions**: 診断結果が表示される。`--init` 時のみディレクトリが作成される
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean doctor` | `[--init] [--json]` | `{"schemaVersion":1,"command":"doctor","fullDiskAccess":bool,"tools":[{"name","found","version"}],"state":{"configDir","stateDir","writable","quarantineBytes","runCount"},"warnings":[]}` | 0, 3, 6 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | 状態ディレクトリが書き込み不可 | `access(W_OK)` | `writable: false` と修正コマンドを表示、exit 6 |
  | detect コマンドのタイムアウト | 5 秒経過 | `found: false, version: null` として継続、exit は変えない |
- **Acceptance criteria**:
  - AC1:
    - GIVEN 任意の環境
    - WHEN `disclean doctor --json` を実行する
    - THEN `.fullDiskAccess` が真偽値、`.tools` が 1 要素以上、`.state.stateDir` が絶対パス
    - 検証コマンド: `acceptance/AT-008-doctor.sh`
    - 期待結果: exit 0 または 3（FDA 未付与時は 3）
  - AC2:
    - GIVEN `DISCLEAN_STATE_DIR` を存在しない一時パスに設定する
    - WHEN `disclean doctor --init --json` を実行する
    - THEN `$DISCLEAN_STATE_DIR/quarantine` `audit` `cache` の 3 ディレクトリが 0700 で作成される
    - 検証コマンド: `acceptance/AT-008-doctor.sh`
    - 期待結果: exit 0

#### F-10: コマンド型ルールの実行

- **Trigger**: `disclean apply` が `kind == "command"` のルールを処理するとき
- **Actor**: CLI / GUI プロセス自身
- **Preconditions**: ルールの `detect` コマンドが成功している（ツールが存在する）
- **Main flow**:
  1. 実行前に `measure`（§5.1 の `MeasureSpec`）で対象量を測り、スキャン結果として提示する。測れないルールだけを「実行後に判明」として区別する。測った結果が 0 バイトなら `skipped(reason: "empty")` とし、実行しない
  2. 実行は `Process` に**絶対パスの実行ファイルと引数配列**を与えて行う。シェル（`/bin/sh -c`）は経由しない
  3. ルールごとの `timeoutSeconds`（既定 180、最大 900）を超えたら `SIGTERM` → 5 秒後に `SIGKILL` を送る
  4. 実行後に同じ `measure` で測り直し、前後の差を「実際に空けた量」として報告する（測れない場合は nil とし、0 と混同しない）
  5. 終了コードと stdout/stderr の先頭 4KiB、および解放できた量を監査ログに記録する
- **Alternate flows**:
  - 対象デーモンが起動していない（例: `docker info` が失敗） → `skipped(reason: "daemon-not-running")`
  - タイムアウト → `failed(reason: "timeout")` とし、最終 exit を 4 にする
- **Postconditions**: 外部ツールのキャッシュが削除されている。隔離庫は経由しないため undo できない旨が実行前の確認画面に表示される
- **コマンド仕様（v1.0 同梱の command 型ルール）**:
  | ruleId | 実行コマンド | Tier | undo 可否 |
  |---|---|---|---|
  | `brew-cleanup` | `/opt/homebrew/bin/brew cleanup --prune=all -s` | A | 不可（再ダウンロード可能） |
  | `npm-cache` | `<npm> cache clean --force` | A | 不可 |
  | `pnpm-store` | `<pnpm> store prune` | A | 不可 |
  | `yarn-cache` | `<yarn> cache clean` | A | 不可 |
  | `uv-cache` | `<uv> cache prune` | A | 不可 |
  | `pip-cache` | `<pip3> cache purge` | A | 不可 |
  | `simctl-unavailable` | `/usr/bin/xcrun simctl delete unavailable` | A | 不可 |
  | `docker-prune` | `<docker> system prune -f`（`-a` と `--volumes` は付けない） | B | 不可 |
  | `docker-builder-prune` | `<docker> builder prune -f` | B | 不可 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | 実行ファイルが見つからない | `detect` の失敗 | `skipped(reason: "tool-not-found")`、exit は変えない |
  | 非 0 終了 | `terminationStatus != 0` | `failed` に記録し stderr の先頭 4KiB を保存、exit 4 |
  | タイムアウト | 経過時間判定 | SIGTERM → SIGKILL、`failed(reason: "timeout")`、exit 4 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN `docker` が PATH に存在するがデーモンが停止している
    - WHEN `disclean apply --rule docker-prune --yes --json` を実行する
    - THEN `.skipped[0].reason == "daemon-not-running"` であり `.failed` が空
    - 検証コマンド: `acceptance/AT-009-command-rule.sh`
    - 期待結果: exit 0
  - AC2:
    - GIVEN テスト用に `sleep 30` を実行し `timeoutSeconds: 1` としたユーザールールを置く
    - WHEN `disclean apply --rule slow-test --yes --json` を実行する
    - THEN `.failed[0].error` に `timeout` を含み、`sleep` プロセスが残っていない（`pgrep -f "sleep 30"` が 1）
    - 検証コマンド: `acceptance/AT-009-command-rule.sh`
    - 期待結果: exit 4

#### F-11: Tier C レポート（削除せず提示のみ）

- **Trigger**: `disclean report` の実行、`disclean scan --tier C` の実行
- **Actor**: P1 / P2 / P3
- **Preconditions**: なし
- **Main flow**:
  1. Tier C ルール（§5.1 のカタログ）の対象サイズを F-02 と同じ方法で計測する
  2. 各項目について「サイズ」「失うもの」「ユーザーが手で実行する手順」を表示する
  3. 出力の先頭に「disclean はこれらを削除しません」を必ず表示する
- **Alternate flows**: TCC により測定できない項目 → `blocked` として理由と FDA 付与手順を併記する
- **Postconditions**: ファイルシステムは変更されない
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean report` | `[--json]` | `{"schemaVersion":1,"command":"report","items":[{"ruleId","title","bytes","state","whatIsLost","manualSteps"}],"totals":{"bytes"}}` | 0, 3 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | TCC による読み取り拒否 | errno EPERM | `state: "blocked"` として理由を表示。全件 blocked なら exit 3 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN 任意の環境
    - WHEN `disclean report --json` を実行する
    - THEN 全要素が `whatIsLost` と `manualSteps` を非空で持ち、`apply` 対象に Tier C が一切含まれない
    - 検証コマンド: `acceptance/AT-010-report.sh`
    - 期待結果: exit 0 または 3
  - AC2:
    - GIVEN 任意の環境
    - WHEN `disclean apply --tier C --yes` を実行する
    - THEN stderr に `tier C rules cannot be selected` を含む
    - 検証コマンド: `acceptance/AT-010-report.sh`
    - 期待結果: exit 2

#### F-12: GUI スキャン → 選択 → 実行フロー

- **Trigger**: `Disclean.app` の起動、または「再スキャン」ボタン押下
- **Actor**: P1 / P3
- **Preconditions**: アプリが非サンドボックスでビルドされている
- **Main flow**:
  1. 起動時に F-09 を実行し、FDA 未付与なら S-22 を表示する
  2. F-02 のスキャンを実行し、進捗を S-13 に表示する
  3. 結果を S-14 に Tier 別セクションで表示する。各項目は `docs/design-system.md` §5.1 のチャンク（高さが容量に比例する塊）として描画し、Tier A のみ選択済み、Tier B は未選択、Tier C は「見るだけ」チップ付きで選択不可とする
  4. 各行に「何が消えるか」「何を失うか」を 1 文で表示する
  5. 実行はレバー（§5.2）を 120px 以上引き下ろすことで発火する。単一クリックでは発火しない（`prefers-reduced-motion` 有効時のみクリックに切り替わる）。発火後に S-16 の確認シートを表示し、承認後に F-05 を実行して S-17 → S-18 と遷移する
- **Alternate flows**: 候補 0 件 → S-15、実行中エラー → S-23
- **Postconditions**: CLI と同一の隔離庫・監査ログが更新される
- **コマンド仕様（GUI サーフェス）**:
  | 操作 | 入力 | 出力 | 失敗時 |
  |---|---|---|---|
  | 再スキャン | ボタン押下 | S-14 の一覧更新 | S-23 にエラー表示 |
  | 項目選択 | チェックボックス | 合計サイズの再計算 | — |
  | 実行 | ボタン押下 → シート承認 | S-18 のサマリ | S-23 にエラー表示 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | スキャン中の例外 | Task の throw | S-23 にエラー種別とパスを表示し、再試行ボタンを出す |
  | 全項目 blocked | 結果判定 | S-22 の権限案内へ誘導する |
- **Acceptance criteria**:
  - AC1:
    - GIVEN テスト用の `DISCLEAN_STATE_DIR` と fixture ルールを環境変数で注入した状態でアプリを起動する
    - WHEN スキャン完了を待ち、Tier A 行のチェック状態を読む
    - THEN Tier A の全行が checked、Tier B の全行が unchecked、Tier C 行にチェックボックスが存在しない
    - 検証コマンド: `xcodebuild test -project Disclean.xcodeproj -scheme DiscleanUITests -destination 'platform=macOS' -only-testing:DiscleanUITests/ScanFlowTests/testDefaultSelection`
    - 期待結果: exit 0, `TEST SUCCEEDED` を含む
  - AC2:
    - GIVEN スキャン結果が 1 件以上ある
    - WHEN 実行ボタンを押し、確認シートで「実行」を選ぶ
    - THEN S-18 に隔離サイズと「7 日以内なら元に戻せます」の文言が表示される
    - 検証コマンド: `xcodebuild test -project Disclean.xcodeproj -scheme DiscleanUITests -destination 'platform=macOS' -only-testing:DiscleanUITests/ScanFlowTests/testApplyShowsUndoNotice`
    - 期待結果: exit 0, `TEST SUCCEEDED` を含む

#### F-13: GUI 隔離庫と履歴

- **Trigger**: サイドバーの「隔離庫」「履歴」選択
- **Actor**: P1 / P3
- **Preconditions**: 状態ディレクトリが読める
- **Main flow**:
  1. S-19 に run 一覧（隔離日時・失効までの残日数・項目数・サイズ）を表示する
  2. 「復元」で F-07 を、「今すぐ完全削除」で F-06 の `--run` を実行する
  3. S-20 に月別回収量の棒グラフと監査ログ表を表示する
- **Alternate flows**: run が 0 件 → 「隔離中の項目はありません」を表示する
- **Postconditions**: 操作結果が index.json と監査ログに反映される
- **コマンド仕様（GUI サーフェス）**:
  | 操作 | 入力 | 出力 | 失敗時 |
  |---|---|---|---|
  | 復元 | run 選択 → ボタン | 一覧から当該 run が消える | S-23 に理由表示（destination-exists 等） |
  | 完全削除 | run 選択 → ボタン → 確認 | 一覧から当該 run が消える | S-23 に理由表示 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | 復元先に既存実体 | F-07 の skipped | S-23 に対象パスと「元の場所に同名の項目があります」を表示 |
  | index 不整合 | F-06 の exit 6 相当 | S-23 に `disclean doctor` の実行を促す文言を表示 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN テスト用隔離庫に run を 1 件作った状態でアプリを起動する
    - WHEN 「隔離庫」を開き、その run の「復元」を押す
    - THEN 一覧が 0 件になり、元パスに項目が戻っている
    - 検証コマンド: `xcodebuild test -project Disclean.xcodeproj -scheme DiscleanUITests -destination 'platform=macOS' -only-testing:DiscleanUITests/QuarantineTests/testRestore`
    - 期待結果: exit 0, `TEST SUCCEEDED` を含む

#### F-14: GUI 権限案内と設定

- **Trigger**: 起動時の FDA 未付与検出、または「設定」選択
- **Actor**: P1 / P3
- **Preconditions**: なし
- **Main flow**:
  1. FDA 未付与時に S-22 を表示し、「測定できない場所」の一覧と、`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` を開くボタンを出す
  2. S-21 で隔離 TTL 日数（1〜90）、同時実行数（1〜32）、除外パス一覧を編集し、`$DISCLEAN_CONFIG_DIR/config.json` に保存する
  3. 「ルール上書きフォルダを開く」で `$DISCLEAN_CONFIG_DIR/rules.d` を Finder で開く
- **Alternate flows**: 設定値が範囲外 → 保存せずフィールド脇に許容範囲を表示する
- **Postconditions**: `config.json` が更新され、CLI 側の次回実行にも反映される
- **コマンド仕様（GUI サーフェス）**:
  | 操作 | 入力 | 出力 | 失敗時 |
  |---|---|---|---|
  | 設定保存 | 各フィールド | `config.json` 更新 | 範囲外の値はフィールド脇にエラー表示 |
  | システム設定を開く | ボタン | プライバシー設定画面が前面に出る | 開けない場合は手順テキストを表示 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | config.json 書き込み失敗 | write の throw | S-23 にパスと権限修正コマンドを表示 |
  | 範囲外の TTL / 同時実行数 | 入力検証 | 保存ボタンを無効化し許容範囲を表示 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN 設定画面を開く
    - WHEN TTL に `0` を入力する
    - THEN 保存ボタンが無効になり、`1〜90` の範囲表示が出る
    - 検証コマンド: `xcodebuild test -project Disclean.xcodeproj -scheme DiscleanUITests -destination 'platform=macOS' -only-testing:DiscleanUITests/SettingsTests/testTTLValidation`
    - 期待結果: exit 0, `TEST SUCCEEDED` を含む

#### F-15: デザイン言語 HEAVY CANDY の実装

- **Trigger**: GUI（S-13〜S-23）および LP（S-24〜S-30）の全描画
- **Actor**: 実装者（ビルド時）／全ペルソナ（閲覧時）
- **Preconditions**: `docs/design-system.md` のトークン定義が確定している
- **Main flow**:
  1. GUI は `Sources/DiscleanApp/DesignTokens.swift` に色・書体・角丸・影・モーションの定数を定義し、View から直接リテラル値を書かない
  2. LP は `site/tokens.css` の `:root` カスタムプロパティに同じ値を定義する。両者の値は `acceptance/AT-014-design-parity.sh` が突合する
  3. 容量はチャンク（高さ = `clamp(48, 48 + GB * 3.2, 320)` pt/px）として描画する
  4. 破壊的操作はレバー（§5.2）経由でのみ発火する。キーボード操作の代替経路を必ず持つ
  5. Tier は色に加えて文字ラベル（`A` / `B` / `見るだけ`）を必ず併記する
  6. 影はぼかし 0 のオフセット矩形、塗りにグラデーションを使わない
- **Alternate flows**:
  - `prefers-reduced-motion: reduce` / `accessibilityReduceMotion` → 全アニメーションを 0ms にし、レバーのドラッグ要件を単一クリック＋確認シートに置換する
  - ダークモード → §2.3 の反転規則を適用し、キャンディ 6 色の値は変えない
- **Postconditions**: GUI と LP が同一トークンで描画され、D-01〜D-08 を満たす
- **検証サーフェス**:
  | 対象 | 検査 | 期待 |
  |---|---|---|
  | 色の組み合わせ | §2.2 の 8 通り以外が使われていないこと | `DesignTokensTests` が全ペアのコントラスト比 4.5 以上を検証 |
  | 影 | ぼかしを含む影が 0 件 | `grep` で 0 ヒット（D-02） |
  | 塗り | グラデーションが 0 件 | `grep` で 0 ヒット（D-03） |
  | Tier | 色のみで表現していない | ラベル文字の存在を DOM / XCUITest で確認（D-04） |
  | トークン一致 | Swift と CSS の値が同一 | AT-014 が hex / 数値を突合 |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | 同梱フォントの読み込み失敗 | `NSFont(name:)` が nil | §3.1 のフォールバック書体で描画を継続し、機能は損なわない |
  | トークン不一致（Swift と CSS） | AT-014 の突合 | CI を失敗させる（exit 1）。実行時の挙動は変えない |
- **Acceptance criteria**:
  - AC1:
    - GIVEN `site/tokens.css` と `Sources/DiscleanApp/DesignTokens.swift` が存在する
    - WHEN `acceptance/AT-014-design-parity.sh` を実行する
    - THEN 9 個のカラートークンと 7 個のタイプスケール値が完全一致する
    - 検証コマンド: `acceptance/AT-014-design-parity.sh`
    - 期待結果: exit 0, 出力に `parity: 16/16` を含む
  - AC2:
    - GIVEN LP をローカル配信している
    - WHEN `acceptance/AT-015-lp.sh` の禁則検査を実行する
    - THEN ぼかし影 0 件・グラデーション 0 件
    - 検証コマンド: `acceptance/AT-015-lp.sh`
    - 期待結果: exit 0, 出力に `blur-shadow: 0` と `gradient: 0` を含む
  - AC3:
    - GIVEN GUI をテスト用データで起動する
    - WHEN レバーをキーボードのみ（Tab → Space 長押し 800ms）で操作する
    - THEN 確認シートが表示され、マウス操作なしで実行を完了できる
    - 検証コマンド: `xcodebuild test -project Disclean.xcodeproj -scheme DiscleanUITests -destination 'platform=macOS' -only-testing:DiscleanUITests/LeverTests/testKeyboardOnlyExecution`
    - 期待結果: exit 0, `TEST SUCCEEDED` を含む

#### F-16: 配布 LP

- **Trigger**: 訪問者（P4）が LP の URL を開く
- **Actor**: P4（LP 訪問者）
- **Preconditions**: GitHub Pages に `site/` が公開されている
- **Main flow**:
  1. S-24 のヒーローで、実測データ（CoreSimulator 71.5GB / Docker 26.6GB / `~/.cache` 9.7GB、2026-08-20 計測）を積んだチャンクタワーとレバーと瓶を表示する
  2. 訪問者がレバーを引くと、チャンクが瓶へ落ち、瓶から掴んで引き戻せる（undo の説明を操作で示す）
  3. S-25 で旧 `mac_cleanup.sh` との回収量の対比を、計測日と機種を明記した表で示す
  4. S-26 で隔離庫 / 7 日 / undo / 監査ログを 4 カードで説明する
  5. S-27 で Tier C（disclean が触らないもの）を列挙する。この節のみ装飾を落とす
  6. S-28 で `brew install suzuki-junya108/disclean/disclean` のコピーボタンと GitHub Releases へのリンクを置く
  7. S-29 の FAQ、S-30 のフッタで終わる
- **Alternate flows**:
  - JavaScript 無効 → ヒーローはタワーの静止画（インライン SVG）として表示され、全セクションの本文とインストール手順が読める。コピーボタンはコマンドの選択可能なテキストに退化する
  - `prefers-reduced-motion` → 落下アニメーションを行わず、レバーはクリックで状態が切り替わる
- **Postconditions**: 訪問者が「何が消えるか」「取り消せるか」「何を触らないか」を理解し、GitHub Releases か Homebrew へ遷移する。訪問者のデータは一切記録されない
- **ページ仕様**:
  | 項目 | 値 |
  |---|---|
  | 公開先 | GitHub Pages（`site/` を `gh-pages` として配信） |
  | ファイル構成 | `site/index.html` / `site/tokens.css` / `site/style.css` / `site/hero.js` / `site/og.png` |
  | ビルド工程 | なし（バンドラ・npm 依存を持たない） |
  | 外部通信 | `fonts.googleapis.com` と `fonts.gstatic.com` のみ |
  | 配布物へのリンク | GitHub Releases の `.dmg` と `.tar.gz`、Homebrew tap。LP 自身はバイナリを配信しない |
  | メタ | `<title>` / `og:title` / `og:description` / `og:image`（1200x630）/ `lang="ja"` |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | Google Fonts が読めない | `document.fonts.ready` のタイムアウト（3 秒） | §3.1 のフォールバック書体で表示を続ける。レイアウトの破綻を起こさないため `font-display: swap` と `size-adjust` を指定する |
  | JS の実行に失敗 | `<noscript>` および未初期化状態 | 静止 SVG のタワーを表示し、本文とインストール手順を全て読める状態にする |
- **Acceptance criteria**:
  - AC1:
    - GIVEN `python3 -m http.server 4173 --directory site` で配信している
    - WHEN `acceptance/AT-015-lp.sh` を実行する
    - THEN 7 セクション（`#hero` `#numbers` `#safety` `#hands-off` `#install` `#faq` `#footer`）が全て存在し、360px 幅で横スクロールが発生しない
    - 検証コマンド: `acceptance/AT-015-lp.sh`
    - 期待結果: exit 0, 出力に `sections: 7/7` と `overflow: none` を含む
  - AC2:
    - GIVEN LP を配信している
    - WHEN Playwright で JavaScript を無効化して読み込む
    - THEN インストールコマンド文字列 `brew install suzuki-junya108/disclean/disclean` が本文に存在し、可視である
    - 検証コマンド: `acceptance/AT-015-lp.sh`
    - 期待結果: exit 0, 出力に `nojs: ok` を含む
  - AC3:
    - GIVEN LP を配信している
    - WHEN axe-core を実行する
    - THEN critical と serious の違反が 0 件
    - 検証コマンド: `acceptance/AT-015-lp.sh`
    - 期待結果: exit 0, 出力に `axe: 0 critical, 0 serious` を含む
  - AC4:
    - GIVEN LP を配信している
    - WHEN Playwright でネットワークリクエストを記録して読み込む
    - THEN 外部ホストが `fonts.googleapis.com` と `fonts.gstatic.com` の 2 つのみ
    - 検証コマンド: `acceptance/AT-015-lp.sh`
    - 期待結果: exit 0, 出力に `external-hosts: 2` を含む

#### F-17: ルールカタログの自動更新

- **Trigger**: 任意の `disclean` サブコマンド起動時（前回チェックから `updateIntervalHours` 経過している場合のみ、非同期で 1 回）、`disclean update` の明示実行、GUI 起動時
- **Actor**: CLI / GUI プロセス自身、P1 / P2 / P3
- **Preconditions**: `autoUpdate` が有効（既定 true）。無効なら明示実行時のみ動作する
- **設計方針（なぜこの形か）**:
  - OS のメジャー更新でキャッシュの置き場所が変わったとき、**本体をリリースし直さずにルール定義だけを配れる**ようにする。これが自動更新を持つ第一の理由（§12 R-19）。
  - 削除ツールである以上、**遠隔の変更がそのまま削除対象の拡大にならない**こと。取得は自動、適用は分類に応じて承認を要求する。
- **Main flow**:
  1. `updateIntervalHours`（既定 24）が経過していれば、コマンド本体の処理と並行して更新チェックを開始する。**コマンドの完了を待たせない**（結果が間に合わなければ次回起動時に通知する）
  2. `<updateEndpoint>/catalog-manifest.json` と `<updateEndpoint>/catalog-manifest.json.sig` を HTTPS GET する（接続 5 秒 / 全体 20 秒のタイムアウト、リダイレクトは `github.com` と `objects.githubusercontent.com` のみ許可）
  3. manifest の署名を、バイナリに埋め込んだ公開鍵（`releaseKeys` の `keyId` 一致分）で Ed25519 検証する。失敗したら**その時点で破棄**し、以後の取得を行わない
  4. `catalogVersion` が適用済みの値より大きいこと、`publishedAt` が適用済み manifest より新しいこと、`expiresAt` が未来であること、`minDiscleanVersion` が自分のバージョン以下であることを検証する（1 つでも満たさなければ exit 7 相当の記録を残して中止）
  5. manifest が指すカタログアーカイブを取得し、`sha256` と展開後の各ファイルのハッシュを照合したうえで `$DISCLEAN_STATE_DIR/updates/staged/<catalogVersion>/` に置く（この時点では**まだ有効化しない**）
  6. staged と現行カタログの差分を `CatalogDiff` として算出し、下表の分類に振り分ける
  7. **縮小変更・中立変更のみ**なら自動適用し、監査ログ（`action: "catalogUpdate"`）に記録して次回の出力で 1 行通知する
  8. **拡大変更が 1 つでも含まれる**場合は適用せず、「更新があります（`disclean update` で内容を確認）」を表示するに留める
  9. `disclean update` の実行時に S-31 で差分を提示し、承認（`yes` 入力または `--yes`）を得てから `active` へ切り替える
- **差分の分類**:
  | 分類 | 該当する変更 | 適用 |
  |---|---|---|
  | 拡大 (expanding) | ルールの追加 / `paths` の追加・拡張 / Tier の C→B・B→A / `minAgeDays` の短縮・削除 / `command` の変更 / `minMacOS`・`maxMacOS` の変更により現在の OS で新たに有効になる | **承認必須**。承認までカタログは切り替わらない |
  | 縮小 (shrinking) | ルールの削除・`enabled: false` 化（revocation）/ `paths` の削除 / Tier の A→B・B→C / `minAgeDays` の延長 / 現在の OS で無効になる方向の OS 条件変更 | 自動適用（削除対象が減る方向のみ）。監査ログに記録し次回出力で通知 |
  | 中立 (neutral) | `title` / `titleJa` / `whatIsLost` / `manualSteps` / `verifiedOn` の変更 | 自動適用 |
- **カタログの優先順位**（F-01 の読込順を置き換える）: 同梱カタログ < 自動更新カタログ（`active`）< ユーザールール（`rules.d`）。**ユーザーの上書きが常に最優先**であり、自動更新がユーザー定義を書き換えることはない
- **Alternate flows**:
  - ネットワークに到達できない / DNS 失敗 / タイムアウト → 何も表示せず終了する（失敗は `--verbose` 時のみ stderr に 1 行）。終了コードに影響しない
  - `manifest.expiresAt` が過去 → 「更新の配信が 90 日以上止まっています」を警告表示する（更新の差し止め攻撃と配信停止の両方を検知する）
  - `autoUpdate: false`（`disclean update --off` または GUI 設定で設定）/ `DISCLEAN_AUTO_UPDATE=0` / `--no-update` → チェック自体を行わない（通信が発生しない）。環境変数は設定ファイルより優先する
  - `disclean update --rollback` → 1 世代前の `active` に戻す（`updates/previous/` に 1 世代だけ保持）
- **Postconditions**: 承認された場合のみ `active` カタログが切り替わる。承認していない差分は staged に留まり、対象ディレクトリには一切触れていない
- **コマンド仕様（CLI サーフェス）**:
  | Command | Arguments | stdout schema | Exit codes |
  |---|---|---|---|
  | `disclean update` | `[--check] [--apply] [--yes] [--rollback] [--off] [--on] [--json]`（`--off` / `--on` は `config.json` の `autoUpdate` を書き換える） | `{"schemaVersion":1,"command":"update","catalog":{"applied":int,"available":int\|null,"publishedAt","expiresAt"},"diff":{"expanding":[{"ruleId","change","newPaths":[]}],"shrinking":[],"neutral":[]},"app":{"current","latest"\|null,"installMethod"},"applied":bool,"errors":[]}` | 0, 2, 7 |
  | （全コマンド共通） | `--no-update` | — | 更新チェックを行わない |
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | 署名検証の失敗 | Ed25519 verify が false | staged を削除し、監査ログに `result: "failed", reason: "signature"` を記録。以後 24 時間は再取得しない。明示実行時は exit 7 |
  | ハッシュ不一致 | sha256 の照合 | 同上（`reason: "hash-mismatch"`）、exit 7 |
  | `catalogVersion` が適用済み以下 | 数値比較 | 適用せず `reason: "rollback-detected"` を記録、exit 7 |
  | `minDiscleanVersion` > 自分 | セマンティックバージョン比較 | 適用せず「本体の更新が必要です」を表示、exit 0（明示実行時も 0。異常ではない） |
  | 展開後のファイルがスキーマ違反 | F-01 と同一の検証 | 適用せず staged を削除、exit 7 |
  | ネットワークエラー | URLSession の error | 記録のみ。終了コードを変えない |
- **Acceptance criteria**:
  - AC1:
    - GIVEN テスト用のローカル HTTP サーバー（`DISCLEAN_UPDATE_ENDPOINT`）に、**署名を 1 バイト改竄した** manifest を置く
    - WHEN `disclean update --check --json` を実行する
    - THEN `active` カタログが変化せず、`.errors[0].reason == "signature"` を含む
    - 検証コマンド: `acceptance/AT-016-update.sh`
    - 期待結果: exit 7
  - AC2:
    - GIVEN 適用済み `catalogVersion: 5` の状態で、`catalogVersion: 4` の正しく署名された manifest を配信する
    - WHEN `disclean update --check --json` を実行する
    - THEN `.errors[0].reason == "rollback-detected"` であり `active` が version 5 のまま
    - 検証コマンド: `acceptance/AT-016-update.sh`
    - 期待結果: exit 7
  - AC3:
    - GIVEN 新しいルール（`paths` に一時ディレクトリを追加）を含む正当な manifest を配信する
    - WHEN `disclean scan --json` を実行する（自動チェックが走る）
    - THEN 新ルールは**有効化されておらず**、スキャン結果に現れない。`disclean update --json` の `.diff.expanding \| length >= 1` である
    - 検証コマンド: `acceptance/AT-016-update.sh`
    - 期待結果: exit 0
  - AC4:
    - GIVEN AC3 の状態
    - WHEN `disclean update --apply --yes --json` を実行する
    - THEN `.applied == true` となり、次の `disclean scan` に新ルールが現れる。監査ログに `action == "catalogUpdate"` の行がある
    - 検証コマンド: `acceptance/AT-016-update.sh`
    - 期待結果: exit 0
  - AC5:
    - GIVEN `DISCLEAN_AUTO_UPDATE=0` を設定する
    - WHEN `disclean scan` を実行し、プロセスの通信を記録する
    - THEN `updateEndpoint` への接続が 0 件
    - 検証コマンド: `acceptance/AT-016-update.sh`
    - 期待結果: exit 0, 出力に `network-requests: 0` を含む

#### F-20: 対象と隔離物の中身をファイル単位で見る（なかみ）

- **Trigger**: 一覧の項目または隔離庫の run で「なかを見る」を押す / `disclean inspect <ruleId>` `--run <runID>` `--path <path>`
- **Preconditions**: なし（読み取りだけを行う）
- **Postconditions**: ファイルシステムを変更しない。スキャンキャッシュも書かない
- **入力**: ルール ID / run ID / 場所（ホーム配下と隔離庫に限る）
- **出力**: その場所の合計サイズとファイル数、中身の一覧（大きい順）、各行の種類（フォルダ / 圧縮ファイル / ログ / データベース / キャッシュの中身 …）とその意味、最終更新日
- **手順**:
  1. ルールなら F-01 と同じ手順で対象パスを解決する（`pathsFrom` があればツールに聞き、同じ禁止パス検証を通す）
  2. 対象の 1 段下だけを読む。フォルダは中を数えて合計サイズとファイル数を出す（`st_blocks` ベースで、一覧・実行と一致させる）
  3. 大きい順に並べ、`limit` 件までを見せる。残りは件数だけ伝える
  4. リンクは辿らず、リンク自身の大きさで数える
  5. フォルダを選ぶと 1 段下がる。パンくずで戻れる
- **表示の原則**: 種類は色だけで示さず、必ず言葉のラベルと 1 文の説明を添える（例: 「ログ: 動いた記録です。消しても、これからの動作には影響しません。」）
- **受入基準**:
  | 状況 | 判定 | 結果 |
  |------|------|------|
  | フォルダとファイルが混在 | 大きい順 | フォルダは中身の合計で並ぶ（AT-019） |
  | ホームの外を指定 | パス検証 | exit 2 で拒否し、理由を出す（AT-019） |
  | 隔離済みの run | 索引参照 | 元の場所と、隔離庫にある実体の中身を出す（AT-019） |
  | 件数が limit を超える | 打ち切り | 上位のみ表示し、残り件数を明示する（`FileInventoryTests`） |
  | 対象が既に無い | lstat | 「この場所はもうありません」を出す（`FileInventoryTests`） |

#### F-21: ルールが見ていない大きな場所を知らせる

- **Trigger**: `disclean report --unknown` / GUI 一覧下部の「ほかに大きな場所をさがす」
- **Preconditions**: なし（読み取りだけを行う）
- **Postconditions**: ファイルシステムを変更しない。**この機能からは削除できない**
- **背景**: ルールをいくら足しても、世の中のアプリすべては網羅できない。網羅を数で追うのではなく、
  「見えていないこと」自体を見えるようにして、利用者が自分の Mac で取りこぼしを見つけられるようにする
- **手順**:
  1. キャッシュが置かれがちな親（`~/Library/Caches` / `Application Support` / `Containers` /
     `Group Containers` / `Logs` / `Developer` / `~/.cache` / ホーム直下の隠しフォルダ）の直下を見る
  2. 同梱・配信・利用者ルールが見ている場所（ひな形は広げる）を除く
  3. ルールが「一部だけ」見ている場所は 1 段下りて残りを見る（親ごと隠すと隣の大物が消える）
  4. 自分の保存先（隔離庫・設定）と、除外設定に入っている場所は対象にしない
  5. しきい値（既定 200MB）以上を大きい順に返す。上限で打ち切ったときはその旨を明示する
- **受入基準**:
  | 状況 | 判定 | 結果 |
  |------|------|------|
  | ルールが見ている場所 | 包含判定 | 報告しない（AT-021） |
  | しきい値未満 | サイズ | 報告しない（AT-021） |
  | 隔離庫・設定 | 自分の保存先 | 報告しない（AT-021・`UncoveredTests`） |
  | 除外設定に入っている場所 | `canInspect` | 報告しない（`UncoveredTests`） |
  | 一部だけ対象の親 | 1 段下降 | 親ではなく、対象外の子を報告する（`UncoveredTests`） |
  | 実行後 | ファイル数 | 1 つも消えていない（AT-021） |

#### F-18: 本体バージョンの更新検知とインストール導線

- **Trigger**: F-17 と同じチェック（manifest に本体バージョン情報を含めるため、**追加の通信を行わない**）
- **Actor**: P1 / P2 / P3
- **Preconditions**: F-17 のチェックが成功している
- **設計方針**: **本体バイナリを自分で置き換えない**（NG12）。数十 MB の成果物を既定で自動取得することもしない。カタログ（数十 KB）は自動取得、本体は「新版の存在を知らせ、要求されたときに取得して検証し、インストーラを開くところまで」を担当する
- **Main flow**:
  1. manifest の `latestApp`（`version` / `minMacOS` / `assets[]`）を読み、自分のバージョンと比較する
  2. インストール方法を判定する: 実行ファイルの `realpath` が Homebrew の prefix 配下なら `brew`、`/Applications/Disclean.app` 配下なら `app`、それ以外は `manual`
  3. `latestApp.minMacOS` が現在の OS より新しい場合は「この OS では受け取れない最新版があります」と表示し、導線を出さない
  4. 導線を表示する:
     - `brew` → `brew upgrade disclean` を提示する（自前でダウンロードしない。二重管理を避けるため）
     - `app` / `manual` → `disclean update --apply` / GUI の更新ボタンで `.dmg`（または `.tar.gz`）を `$DISCLEAN_STATE_DIR/updates/downloads/` に取得する
  5. 取得後、sha256 を照合し、`codesign --verify --deep --strict` と `spctl --assess --type open` 相当の検証を行う。いずれか失敗ならファイルを削除して exit 7
  6. 検証を通った成果物を Finder で表示する（`NSWorkspace.activateFileViewerSelecting`）。**インストールの実行はユーザーが行う**
- **Alternate flows**:
  - 最新版が自分と同じ → 何も表示しない
  - GUI が `/Applications` 以外（ダウンロードフォルダ等）から起動されている → 導線に「アプリケーションフォルダへ移動してください」を併記する
- **Postconditions**: 検証済みの成果物がダウンロードディレクトリに存在する。実行中のバイナリとアプリは変更されていない
- **コマンド仕様（CLI サーフェス）**: F-17 の `disclean update` に統合（`.app` キー）
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | ダウンロードの sha256 不一致 | ハッシュ照合 | ファイル削除、`reason: "hash-mismatch"`、exit 7 |
  | 署名・公証の検証失敗 | `codesign` / `spctl` の終了コード | ファイル削除、`reason: "codesign-failed"`、exit 7 |
  | ディスク空き容量不足 | 書き込みの ENOSPC | 部分ファイルを削除し「空き容量が足りません」を表示、exit 1 |
- **Acceptance criteria**:
  - AC1:
    - GIVEN テスト用エンドポイントが `latestApp.version` に自分より新しい値を返す
    - WHEN `disclean update --json` を実行する
    - THEN `.app.latest` が新バージョン、`.app.installMethod` が `brew` / `app` / `manual` のいずれか
    - 検証コマンド: `acceptance/AT-017-app-update.sh`
    - 期待結果: exit 0
  - AC2:
    - GIVEN 本体アセットの sha256 を改竄した manifest を配信する
    - WHEN `disclean update --apply --yes` を実行する
    - THEN ダウンロードディレクトリにファイルが残らず、stderr に `hash-mismatch` を含む
    - 検証コマンド: `acceptance/AT-017-app-update.sh`
    - 期待結果: exit 7

#### F-19: OS 変化の検知とルールの OS 条件評価

- **Trigger**: 任意のサブコマンド起動時（環境記録の比較）、`disclean doctor` の実行
- **Actor**: CLI / GUI プロセス自身
- **Preconditions**: なし
- **設計方針**: macOS のメジャー更新でキャッシュの置き場所が変わっても、**利用者が気づけない「静かな空振り」を作らない**。既存 `mac_cleanup.sh` の欠陥（対象が消えても成功したように見える）を構造的に排除する
- **Main flow**:
  1. 起動時に `ProcessInfo.processInfo.operatingSystemVersion` と `sysctl kern.osversion`（ビルド番号）を取得し、`$DISCLEAN_STATE_DIR/env.json` の前回値と比較する
  2. 各ルールの `minMacOS` / `maxMacOS` を評価し、現在の OS で有効なルールのみをカタログに残す（範囲外は `skipped(reason: "os-unsupported")` として一覧には出す）
  3. OS のメジャーまたはビルド番号が変化していた場合、スキャンキャッシュを全破棄し、`paths` の存在確認を全ルールで再実行する
  4. 「前回の OS では見つかっていたが、この OS では見つからないルール」を `disclean doctor` に一覧表示し、`disclean update` の実行を促す
  5. `env.json` を新しい値で更新し、監査ログの各行に `osVersion` / `osBuild` を記録する
- **Alternate flows**:
  - 初回実行（`env.json` が無い） → 比較を行わず記録のみ
  - OS が古くなった（ダウングレード・別マシンでの状態ディレクトリ共有） → 同じ手順で再評価する（方向は問わない）
- **Postconditions**: カタログが現在の OS に合わせて評価され、消えたパスが利用者に見える形で報告されている
- **コマンド仕様（CLI サーフェス）**: `disclean doctor --json` の出力に以下を追加する
  ```
  "os": {"version":"26.5.2","build":"25F84","changedSince":"25E52"|null,
         "rulesDisabledByOS":[{"ruleId","reason"}],
         "rulesMissingAfterOSChange":[{"ruleId","path"}]}
  ```
- **Error handling**:
  | Error | Detection | Response |
  |---|---|---|
  | `env.json` の破損 | デコード失敗 | 初回扱いにして再作成し、stderr に警告 1 行。exit 0 |
  | `minMacOS` の書式不正 | セマンティックバージョン解析の失敗 | そのルールを拒否（F-01 と同じく exit 5） |
- **Acceptance criteria**:
  - AC1:
    - GIVEN `env.json` に現在と異なる OS ビルドを書き込む
    - WHEN `disclean doctor --json` を実行する
    - THEN `.os.changedSince` が非 null であり、スキャンキャッシュが破棄されている
    - 検証コマンド: `acceptance/AT-018-os-drift.sh`
    - 期待結果: exit 0
  - AC2:
    - GIVEN `minMacOS: "99.0"` を持つ fixture ルールを置く
    - WHEN `disclean scan --json` を実行する
    - THEN そのルールが `state == "skipped"`, `reason == "os-unsupported"` として出力され、削除対象に含まれない
    - 検証コマンド: `acceptance/AT-018-os-drift.sh`
    - 期待結果: exit 0
