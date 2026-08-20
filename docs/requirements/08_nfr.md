> 責務: 非機能要件（§8）— 8 カテゴリ全てを埋めるか `N/A — reason` を残す。
> 親: ../REQUIREMENTS.md

## 8. Non-Functional Requirements

### 8.1 Performance

| 指標 | 目標値 | 計測方法 |
|---|---|---|
| 初回スキャン（Tier A+B 全ルール、実測環境: ホーム約 300GB / 約 200 万ファイル） | 90 秒以内 | `time disclean scan --no-cache`（AT-002） |
| キャッシュ有効時のスキャン | 5 秒以内 | `time disclean scan`（AT-002 AC2） |
| `disclean --help` の表示 | 1 秒以内 | `time disclean --help`（WS-d） |
| `disclean apply` の隔離処理（1,000 エントリ） | 10 秒以内（同一ボリューム `rename` のため対象サイズに依存しない） | AT-005 の計測行 |
| GUI 起動から結果一覧表示まで（キャッシュ有効時） | 5 秒以内 | XCUITest の測定（F-12 AC1） |
| ピークメモリ（CLI, 200 万ファイル走査時） | 500MB 以内 | `/usr/bin/time -l` の maximum resident set size |
| GUI のチャンク描画（500 項目のタワー） | 60fps を維持（フレーム落ち 1% 未満） | Instruments の Animation Hitches |
| LP の初回表示（キャッシュなし, 4G 相当） | LCP 2.0 秒以内。フォント読み込み中も `font-display: swap` でフォールバック書体により本文が読める | Playwright の Performance API で計測（AT-015） |
| LP の総転送量（初回・フォント込み） | 700KB 以内（実測 679KB。うち 663KB が日本語 Web フォントの CJK サブセット 49 ファイル） | Playwright の `performance.getEntriesByType('resource')` の `encodedBodySize` 合計（AT-015） |
| LP の総転送量（2 回目以降・フォントはキャッシュ） | 20KB 以内（実測 16KB） | 同上 |
| 更新チェックがコマンド実行に与える遅延 | 0 秒（並行実行し、完了を待たない）。`disclean scan` の実測時間が更新チェックの有無で 5% 以上変化しないこと | AT-016 の計測行 |
| 更新チェックのネットワーク待ち | 接続 5 秒 / 全体 20 秒でタイムアウト（明示実行時は 60 秒）。超過時は静かに諦める | AT-016 |
| カタログ差分の算出（ルール 60 件） | 100ms 以内 | `swift test --filter CatalogUpdate` の計測 |

- スキャンの並列度は既定 `min(8, activeProcessorCount)`。列挙は `FileManager.enumerator` ではなく `fts(3)` 相当の低レベル走査を使い、`stat` を 1 エントリ 1 回に抑える。
- ディレクトリ単位でサイズをキャッシュし、ディレクトリの `mtime` が一致し 24 時間以内なら再走査しない。

### 8.2 Scalability

- スケール次元はファイル数とルール数。launch 時点でルール約 30 件、ホーム配下 200 万ファイルを想定。
- 12 ヶ月後もルール数は 60 件程度、ファイル数は同オーダーを想定する。水平分散は不要（単一マシンのローカルツール）。
- スケール戦略: 並列度を `DISCLEAN_CONCURRENCY` で上げる（垂直）。ルール数の増加は線形コストで、キャッシュにより実効コストは変化分に比例する。
- 隔離庫は run 単位のディレクトリで、`index.json` は run 数に比例。1,000 run（数年分）でも 1MB 未満。

### 8.3 Availability

- `N/A — reason: 常駐サービスではなくオンデマンド実行の CLI / GUI のため、稼働率目標を持たない。`
- 信頼性要件は以下に読み替える:
  | 項目 | 要件 |
  |---|---|
  | 中断耐性 | SIGINT / SIGTERM 受信時、進行中の `rename` を完了させてから `index.json` を確定し exit 130。中断後も `index.json` と実体が一致する |
  | クラッシュ耐性 | `index.json` / `config.json` は tmp → fsync → rename で置換。プロセス強制終了時も旧版が残る |
  | 孤児検出 | 実体があるのに index に無い run を `disclean purge` が検出し、削除せず exit 6 で報告する |
  | 再試行 | 外部コマンドの自動リトライは行わない（副作用の二重適用を避けるため）。失敗は記録して次の項目へ進む |
  | データ耐久性 | 隔離庫は同一ボリューム上の rename のみを使い、コピーによる複製・EXDEV フォールバックを行わない |

### 8.4 Security

- **Authentication method**: `N/A — reason: 自前のネットワークサービスを持たず、ログイン中ユーザーのローカル権限のみで動作するため。` 更新の取得は公開アセットへの匿名 GET であり、認証情報を持たない。
- **Authorization model**: 実行ユーザーの POSIX 権限のみ。sudo による特権昇格を行わない（NG2）。システム領域（`/System`, `/Library`, `/private/var`）は SG-03 で削除対象から機械的に排除する。
- **Secret management**: `N/A — reason: API キー・トークン・パスワードを扱わないため。`
- **Encryption at rest / in transit**: 保存データは FileVault（OS 機能）に委ね、隔離庫と監査ログはファイル権限 0700 / 0600 で保護する。通信は更新の取得のみで、HTTPS（ATS 既定、TLS 1.2 以上）に限定する。加えて**通信路の信頼に依存しない**: 配信物は Ed25519 の detached 署名と sha256 で検証し、検証を通らないものは適用しない（F-17）。
- **Update trust model**: 信頼の起点はバイナリに埋め込んだ公開鍵のみ。TLS・GitHub・ミラーのいずれが侵害されても、鍵を持たない配信物は適用されない。巻き戻し（古い版の再配信）は `catalogVersion` の単調増加で、差し止め（更新を止めて古い版に留める攻撃）は manifest の `expiresAt`（90 日）で検知する。
- **Threat model（対処する上位 3 脅威）**:
  | # | 脅威 | 対策 |
  |---|---|---|
  | T-1 | 不正なルール定義（悪意ある、または誤った `paths` / `command`）による意図しない削除・任意コマンド実行 | ルールは読み込み時に禁止パス検証（F-01）を通す。`command` 型はシェルを経由せず `Process` に実行ファイルと引数配列を直接渡す（シェルインジェクション不成立）。ユーザールールの配置場所は 0700 のディレクトリに限定 |
  | T-2 | シンボリックリンク / パス置換による対象外領域の削除（TOCTOU） | 対象は `lstat` で判定しシンボリックリンクを辿らない（SG-04）。`realpath` 解決後に `$HOME` 配下と深さ 2 以上を再検証（SG-01, SG-02）。移動は `renameat` 相当で親ディレクトリを固定して行う |
  | T-3 | 監査ログ・ファイルパスの外部漏洩 | 送信経路を持つコードは更新の取得（GET）のみに限定し、リクエストボディを持たせない。スキャン結果・パス・識別子を送信するコードを書かない（NG6）。ログはローカルのみ、権限 0600。クラッシュレポート・テレメトリを組み込まない |
  | T-4 | 配信元（GitHub アカウント・リリース）の侵害、または中間者による差し替えで、悪意あるルールが配られ削除対象が拡大する | 署名検証（Ed25519）を必須にし、鍵はバイナリ埋め込み。さらに**削除対象を拡大する差分は利用者の承認なしに適用しない**（F-17 の分類表）。承認画面には「新たに削除対象になるパス」を最上部に実サイズ付きで表示する。禁止パス検証（SG-01〜SG-04）は更新カタログにも同一に適用する |
  | T-5 | 巻き戻し攻撃（脆弱な旧カタログの再配信）・差し止め攻撃（更新を止めて古い版に留める） | `catalogVersion` の単調増加を強制し、`publishedAt` の逆行を拒否。manifest に `expiresAt`（90 日）を持たせ、期限切れを「配信が止まっている」警告として表示する |
  | T-6 | 状態ディレクトリ（`updates/active/`）を書き換えて任意ルールを注入する（同一マシンの他ユーザー・別プロセス） | `updates/` を 0700 / 0600 で作成し、権限が緩い場合は適用しない。`active` のカタログも読み込み時に manifest のハッシュと突合し、不一致なら同梱カタログにフォールバックする |
- **Audit log requirements**: apply / undo / purge / commandRun / catalogUpdate / appUpdate の全操作を JSONL に追記する。更新の適用・自動適用・拒否（署名不一致・巻き戻し等）も 1 行ずつ記録し、各行に `osVersion` / `osBuild` / `catalogVersion` を含める。監査ログに書けない場合は破壊的操作を実行しない（F-08）。ログは追記専用で、既存行を書き換えない。

### 8.5 Privacy & Compliance

- **PII handling**: 監査ログにユーザーのファイルパス（ユーザー名を含む）が記録される。これはローカルのホームディレクトリ配下にのみ保存し、外部送信しない。
- **更新機構が外部に渡す情報**（F-17 / F-18。ここに書いていないものは送らない）:
  | 渡るもの | 内容 | 備考 |
  |---|---|---|
  | HTTP リクエスト | 取得対象の URL | 固定パス。利用者ごとに変化しない |
  | User-Agent | `disclean/<version> (macOS <ver>; <arch>)` | 本体バージョン・OS バージョン・アーキテクチャのみ。ランダム ID を生成しない |
  | IP アドレスと接続時刻 | 配信元（GitHub）のログに残る | 本ツールが送るのではなく、HTTPS 接続に伴って不可避に残るもの。README と LP の FAQ に明記する |
- **更新機構が渡さないもの**: スキャン結果・ファイルパス・回収量・ルールの選択内容・インストール ID・マシン識別子・実行回数。リクエストボディを持たない（GET のみ）。
- **Data retention**: 隔離庫は既定 7 日。監査ログは自動削除しない（月別ファイルで手動削除可能。README に削除方法を記載）。 更新関連の一時データ（staged / downloads）は §5.3 の Retention に従い自動削除する。
- **Regional restrictions**: `N/A — reason: データがローカルマシンから出ないため、データ所在地の制約が発生しない。`
- **Applicable regulations**: `N/A — reason: 個人のローカルツールであり、第三者の個人データを処理しない。`
- **User consent flows**: 破壊的操作の前に必ず対象一覧と合計サイズを提示し、対話 TTY では `yes` の明示入力を要求する（非対話では `--yes` 必須）。Tier B の実行時は「何を失うか」を項目ごとに表示する。 自動更新は既定で有効だが、**削除対象を拡大する差分は同じ承認フローを通す**（F-17）。初回実行時に「更新の取得が有効であること・送信される情報・止め方」を 3 行で表示し、`disclean update --off` と GUI 設定で無効化できることを案内する。

### 8.6 Observability

| 項目 | 内容 |
|---|---|
| Logging（LP） | `N/A — reason: 訪問者のデータを一切記録しないため（NG9）。ダウンロード数は GitHub Releases 側の統計で代替する。` |
| Logging | 監査ログ = `$DISCLEAN_STATE_DIR/audit/YYYY-MM.jsonl`（JSONL, 追記専用, 0600, 自動削除なし）。診断ログ = stderr（`--verbose` 指定時のみ、ルール評価とスキップ理由を出力） |
| Metrics | `disclean history --json` の集計値（期間内の回収バイト数・操作件数・失敗件数）。GUI の S-20 で月別回収量を棒グラフ表示 |
| Tracing | `N/A — reason: 単一プロセス・単一マシンで完結し、分散トレースの対象がないため。` |
| Alerting | `N/A — reason: 常駐せず、通知先も持たないため。` 失敗は実行時の終了コード（4 = 部分的失敗）と stderr で通知する |
| Health check | `disclean doctor`（FDA 判定 / 外部ツール検出 / 状態ディレクトリの書込可否 / 隔離庫の整合 / 適用中カタログ版数と最終チェック時刻 / OS 変化の検知 — F-19） |
| 出力の機械可読性 | 全サブコマンドが `--json` を持ち、`schemaVersion` 付きの 1 オブジェクトを stdout に出す。人間向け出力は stdout、警告・エラーは stderr に分離する |

### 8.7 Maintainability

- **Code style**: SwiftLint 0.65.0 `--strict` で 0 violations。swift-format 6.3.0 で整形（CI で `--lint` 差分ゼロを検証）。`.swiftlint.yml` は `force_unwrapping` / `force_try` を error として有効化する。
- **Test coverage target**: `DiscleanKit` の行カバレッジ 80% 以上（`swift test --enable-code-coverage` + `llvm-cov report` で検証）。安全ガード（SG-01〜SG-09）とパス検証は分岐カバレッジ 100%。
- **Documentation**: README に導入・使い方・アンインストール・ルール追加方法を記載。公開 API に DocC コメントを付ける。ルール JSON のスキーマを `docs/rule-schema.md` に記載する。
- **Deployment automation**: GitHub Actions（`macos-latest` = macOS 26 Arm64）で lint → build → test → 受入テストを実行。タグ push でユニバーサルバイナリと `.dmg` をビルドし、署名・公証して Release に添付する。
- **Onboarding time**: `git clone && swift build && swift test` が追加設定なしで通ること（外部ツール未導入の環境でも、該当ルールがスキップされるだけでテストは通る）。

### 8.8 Accessibility & i18n

- **Language support**: 日本語と英語。ルールの表示名・「何を失うか」は `title` / `titleJa` の 2 系統を持ち、`Locale.preferredLanguages` の先頭が `ja` なら日本語を選ぶ。CLI は `--lang ja|en` で上書き可能。LP は日本語版（`/`）と英語版（`/en/`）を同一デザインで持ち、`<html lang>` を正しく設定する。
- **WCAG conformance level**: GUI と LP の双方で WCAG 2.2 AA。デザイン言語側で担保する具体条件は `docs/design-system.md` §2.2（許可される文字色と地の組み合わせ 8 通りのみ、実測コントラスト比 5.50〜17.37）と D-01〜D-08。Tier は色だけでなくラベル文字（`A` / `B` / `見るだけ`）でも区別する。axe-core の critical + serious を 0 件にする。
- **Keyboard navigation**: GUI と LP の全操作をキーボードのみで完了できること。Tab 順序を視覚順序と一致させ、シートのキャンセルに Escape を割り当てる。**実行レバーはドラッグを要求するが、フォーカス時の `Space` 長押し 800ms または `Enter` で同じ確認シートに到達できる**（D-05）。フォーカスリングは `3px` の可視アウトライン（明色地では `--grape`、暗色地では `--sky`）。
- **Screen reader support**: 全 SwiftUI 要素に `accessibilityLabel` を設定する。チャンクには `accessibilityValue` として「12.4 ギガバイト、Tier A、選択済み、失うもの: npm の再ダウンロード」のように**サイズ・Tier・選択状態・失うもの**を含む読み上げ文字列を与える。LP では同じ情報を `aria-label` と視覚的に隠したテキストで提供し、装飾用の SVG に `aria-hidden="true"` を付ける。XCUITest / Playwright でラベル存在を検証する。
- **Time zone / locale handling**: 監査ログの `ts` はタイムゾーンオフセット付き ISO8601（例 `2026-08-20T18:37:11.482+09:00`）で保存し、表示時に `Locale.current` で整形する。バイト数は `ByteCountFormatter`（`.file` 単位、1000 進）で表示し、JSON には常に整数バイトを出す。
