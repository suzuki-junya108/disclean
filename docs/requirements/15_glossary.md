> 責務: 用語集（§15）— ドメイン用語・略語・プロダクト固有名を 1 表に集約。
> 親: ../REQUIREMENTS.md

## 15. Glossary

| Term | Definition |
|---|---|
| ディスクリン | 本プロダクトの日本語表示名。日本語の文章・GUI の表示・LP の本文ではこの表記を使う |
| disclean | 本プロダクトの英名であり、機械が扱う唯一の識別子。実行バイナリ名・パッケージ名・リポジトリ名・Homebrew tap 名・設定/状態ディレクトリ名・環境変数の接頭辞（`DISCLEAN_`）に使う |
| DiscleanKit | CLI と GUI が共有する Swift ライブラリターゲット。ルール評価・走査・安全検証・実行・記録を担う |
| Disclean.app | SwiftUI で実装する GUI アプリ。DiscleanKit を通じて CLI と同じ隔離庫・監査ログを扱う |
| Tier（リスク階層） | ルールの危険度分類。A = 既定選択、B = 要確認（既定未選択）、C = 提示のみ（選択不可） |
| 隔離庫 (Quarantine) | `$DISCLEAN_STATE_DIR/quarantine/<runID>/`。削除対象を同一ボリューム内の `rename` で移す一時領域。既定 7 日後に実削除される |
| run ID | 隔離 1 回分の識別子。ULID（26 文字、時刻順にソート可能）で採番する |
| TTL | 隔離庫の保持期間。既定 7 日、`DISCLEAN_QUARANTINE_TTL_DAYS` で 1〜90 日に変更可能 |
| purge | 隔離庫から実削除すること。TTL 満了分の自動処理と `disclean purge` の明示実行がある |
| undo | 隔離した項目を元のパスへ戻すこと（`disclean undo <runID>`） |
| 安全ガード (SG-01〜SG-09) | 削除実行の直前に適用するパス検証規則。1 つでも違反すればその項目をスキップする |
| PathGuard | SG-01〜SG-09 を実装する DiscleanKit のコンポーネント。すべての破壊的操作がここを通る |
| TCC | Transparency, Consent, and Control。macOS のプライバシー許可機構。`~/Downloads` 等へのアクセスを制御する |
| FDA（フルディスクアクセス） | TCC の `kTCCServiceSystemPolicyAllFiles`。付与されないと `~/.Trash` `~/Downloads` `~/Documents` `~/Desktop` を読めない |
| dataless file | クラウド（iCloud Drive 等）に実体があり、ローカルにはメタデータのみを持つファイル。`stat.st_flags` の `SF_DATALESS`(0x40000000) で判定する |
| materialize（実体化） | dataless file の中身をクラウドからダウンロードすること。スキャンで意図せず発生すると逆に容量を消費する |
| purgeable space | macOS の CacheDelete が必要時に自動解放できる領域。`volumeAvailableCapacityForImportantUsageKey` に含まれ、`volumeAvailableCapacityKey` には含まれない |
| ローカルスナップショット | Time Machine が APFS 上に保持する世代。存在すると削除しても空き容量が即時に増えないことがある |
| 実割当サイズ | `stat.st_blocks * 512`。スパースファイル（`Docker.raw` 等）で見かけのサイズと大きく異なるため、本ツールはこちらを使う |
| directory 型ルール | 対象ディレクトリの中身を隔離庫へ移動するルール。undo 可能 |
| command 型ルール | 外部 CLI（brew / npm / docker 等）を実行するルール。隔離庫を経由しないため undo 不可 |
| report 型ルール | 計測と表示のみを行うルール。Tier C はすべてこの型 |
| 監査ログ | `$DISCLEAN_STATE_DIR/audit/YYYY-MM.jsonl`。破壊的操作を 1 行 1 JSON で追記する。追記専用 |
| サイレント失敗 | 権限不足などで実際には何もできていないのに、成功したかのように報告すること。既存 `mac_cleanup.sh` の主要な欠陥であり、本ツールが排除する対象 |
| DiscleanKit | CLI と GUI が共有するコアライブラリのターゲット名 |
| Disclean.app | GUI アプリのバンドル名。Finder 上の表示名は「ディスクリン」 |
| HEAVY CANDY | 本プロダクトのデザイン言語の名称。「ギガバイトには重さがある」を主張とし、キャンディ色・黒キーライン・ぼかし 0 の影・物理的な塊で構成する（`docs/design-system.md`） |
| チャンク | 容量 1 件を表す塊。高さが GB に比例する（`clamp(48, 48 + GB * 3.2, 320)`）。Tier 色の面に黒キーラインと影を持つ |
| レバー | 実行操作の入力装置。クリックでは発火せず、120px 以上引き下ろすか、キーボードで明示操作したときのみ実行に進む |
| 瓶 (Jar) | 隔離庫の視覚表現。隔離中のチャンクが溜まり、残り日数のリングを持つ。掴んで外へ出すと復元 |
| キーライン | 全要素に引く 3px の輪郭線。ステッカーの型抜き感を作る。線幅は 3px 固定 |
| ハードオフセット影 | ぼかし 0 の影（`Npx Npx 0`）。刷り物の浮きを表現する。ぼかしのある影は使わない |
| LP | 配布用のランディングページ（`site/`）。GitHub Pages で配信する静的ファイルのみで構成され、バイナリは配信しない |
| D-01〜D-08 | デザインの受入基準。コントラスト・禁則・キーボード操作・レスポンシブ・外部通信を機械的に検証する（`docs/design-system.md` §10） |
| カタログ (catalog) | 同梱・自動更新・ユーザー定義の 3 系統からなるルール定義の集合。優先順位は 同梱 < 自動更新 < ユーザー |
| catalogVersion | 配信されるカタログの版数。単調増加する整数で、これ以下の版は巻き戻しとして拒否する |
| manifest | 配信物のメタデータ（`catalogVersion` / 各ファイルの sha256 / 有効期限 / 本体の最新版）。Ed25519 の detached 署名の対象 |
| detached 署名 | 署名対象のファイルとは別ファイルとして配る署名（`catalog-manifest.json.sig`）。本プロジェクトでは Ed25519（CryptoKit `Curve25519.Signing`）を使う |
| staged / active / previous | 更新カタログの 3 世代。`staged` = 検証済みだが未承認、`active` = 現在有効、`previous` = 1 世代前（`disclean update --rollback` の戻し先） |
| 拡大差分 (expanding) | 削除対象が増える方向の変更（ルール追加 / paths 追加 / Tier 引き上げ / command 変更 / OS 条件の緩和）。利用者の承認なしに適用しない |
| 縮小差分 (shrinking) | 削除対象が減る方向の変更（ルール削除・無効化 / paths 削除 / Tier 引き下げ / OS 条件の厳格化）。自動適用する |
| revocation | 配信済みルールの緊急停止。manifest の `revocations` に `Rule.id` を載せると、承認を待たずに無効化される |
| 巻き戻し攻撃 (rollback) | 古い（脆弱な）カタログを再配信して適用させる攻撃。`catalogVersion` の単調増加で防ぐ |
| 差し止め攻撃 (freeze) | 更新の配信を止めて古い版に留める攻撃。manifest の `expiresAt`（発行 +90 日）で検知する |
| OS ドリフト | OS の更新によって、ルールが指すパスが移動・消滅・新設され、掃除が静かに空振りする現象。`env.json` の比較と `minMacOS` / `maxMacOS` で検知・制御する（F-19） |
| installMethod | 本体の導入経路（`brew` / `app` / `manual`）。更新の案内先を分けるために判定する |
| Walking Skeleton | 主要経路を最小構成で貫通させた実装。§10.5 の WS-* が完了条件 |
| onegai | 本要件定義書を消費する自律 TDD 実装エージェント。§4.0 / §6.5 / §10.5 を厳密なセクション名で参照する |
