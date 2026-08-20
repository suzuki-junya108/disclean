> 責務: テスト戦略（§10）— レイヤー別方針。Walking Skeleton 完了条件 (§10.5) は ../REQUIREMENTS.md 参照。
> 親: ../REQUIREMENTS.md

## 10. Test Strategy

#### 10.1 レイヤー別方針

| レイヤー | 対象 | フレームワーク | 実行コマンド |
|---|---|---|---|
| Unit | `PathGuard` の SG-01〜SG-09、`RuleCatalog` のスキーマ検証・上書き解決、`Planner` の既定選択、サイズ集計、ULID 生成、JSON エンコード/デコード | swift-testing (Testing Library 1902) | `swift test --filter DiscleanKitTests` |
| Integration | 一時ディレクトリ上の fixture に対する scan → plan → apply → undo → purge の一巡、`index.json` と実体の整合、監査ログの追記 | swift-testing | `swift test --filter IntegrationTests` |
| E2E (CLI) | ビルド済みバイナリを実行し、stdout の JSON を jq で検証（AT-001〜AT-010） | bash + jq 1.7 | `tests/acceptance/run-all.sh` |
| E2E (更新) | ローカル HTTP サーバー（テスト鍵で署名した manifest を配信）に対する取得・検証・差分分類・承認適用・巻き戻し拒否（AT-016〜AT-017） | bash + jq + python3 `http.server` | `tests/acceptance/AT-016-update.sh` / `AT-017-app-update.sh` |
| E2E (OS ドリフト) | `env.json` の書き換えによる OS 変化検知、`minMacOS` / `maxMacOS` の評価（AT-018） | bash + jq | `tests/acceptance/AT-018-os-drift.sh` |
| E2E (GUI) | 起動 → スキャン → 選択 → 実行 → 隔離庫 → 復元 → 設定、レバーのキーボード操作（AT-011〜AT-013, AT-014 AC3） | XCUITest (Xcode 26.6) | `xcodebuild test -project Disclean.xcodeproj -scheme DiscleanUITests -destination 'platform=macOS'` |
| Design parity | Swift と CSS のトークン値の一致、ぼかし影・グラデーションの禁則（AT-014） | bash + grep | `tests/acceptance/AT-014-design-parity.sh` |
| E2E (LP) | 7 セクションの存在、360px 無横スクロール、JS 無効時の可読性、axe-core、外部ホスト数、reduced-motion（AT-015） | Playwright 1.56 + axe-core 4.10 | `tests/acceptance/AT-015-lp.sh` |
| Manual QA | 実機での回収量確認、FDA 未付与時の表示、Time Machine スナップショット有無での容量表示 | 手動 | §10.4 |

#### 10.2 テスト用の隔離環境

- すべての自動テストは `DISCLEAN_STATE_DIR` と `DISCLEAN_CONFIG_DIR` を `mktemp -d` で作った一時ディレクトリに向ける。実ユーザーの隔離庫・監査ログ・設定を読み書きしない。
- 対象パスは fixture 専用のユーザールール（`$DISCLEAN_CONFIG_DIR/rules.d/00-test-fixture.json`）で一時ディレクトリを指す。**実在の `~/Library` や `~/.cache` をテストの削除対象にしない。**
- `command` 型ルールのテストは、実在ツールではなくテスト用の `/bin/echo` `/bin/sleep` を `executable` に指定して挙動（成功・失敗・タイムアウト）を検証する。
- 更新のテストは `DISCLEAN_UPDATE_ENDPOINT` を `http://127.0.0.1:<port>/` に向け、テスト専用の Ed25519 鍵ペアで署名した manifest を配信する。テスト鍵は debug ビルド限定の `DISCLEAN_UPDATE_TRUSTED_KEYS_FILE` で注入し、**release ビルドでは無視されること自体もテストする**（テストの都合で本番の信頼起点を緩めない）。
- 更新テストは実在の GitHub へ接続しない。ネットワーク遮断下でも全テストが通ること（更新失敗が他のテストを壊さないことの検証を兼ねる）。
- テストは並列実行しても互いに干渉しない（環境変数でディレクトリが分離されるため）。

#### 10.3 分岐カバレッジの必達点

| 対象 | 目標 | 検証 |
|---|---|---|
| `PathGuard`（SG-01〜SG-09 の全違反経路） | 分岐 100% | `swift test --enable-code-coverage` + `llvm-cov report` |
| `RuleCatalog` の検証エラー経路（不正 JSON / 欠落フィールド / 禁止パス / 重複 id） | 分岐 100% | 同上 |
| `Updater` の拒否経路（署名不一致 / ハッシュ不一致 / 巻き戻し / 期限切れ / minDiscleanVersion 不足 / スキーマ違反 / リダイレクト先不許可） | 分岐 100% | 同上 |
| `CatalogDiff` の分類（拡大 / 縮小 / 中立の全 `ChangeKind`） | 分岐 100% | 同上 |
| `DiscleanKit` 全体 | 行 80% 以上 | 同上（CI ゲート） |

#### 10.4 Manual QA シナリオ（v1.0 リリース前に実施し、結果を PR に記載する）

| # | シナリオ | 期待 |
|---|---|---|
| MQ-1 | 実機で `disclean scan` を実行し、Tier A 合計が実測値（CoreSimulator 未使用分 + 各種キャッシュ）と ±10% で一致するか | 一致 |
| MQ-2 | Tier A のみで `disclean apply` を実行し、隔離サイズ ≥ 60GB を確認（M4） | 達成 |
| MQ-3 | `disclean undo --last` で全件復元し、対象ディレクトリのファイル数とバイト数が実行前と一致するか | 一致 |
| MQ-4 | フルディスクアクセスを外した状態で `disclean doctor` / `disclean report` を実行 | 未付与と表示され、測定不能な場所が列挙され、成功を装わない |
| MQ-5 | iCloud Drive にダウンロード未実施のファイルがある状態で `disclean scan` を実行 | 実体化が発生しない（実行後も当該ファイルが dataless のまま、`ls -lO` で `dataless` フラグを確認） |
| MQ-6 | GUI を起動し、キーボードのみで スキャン → 選択 → 実行 → 復元 を完了できるか | 完了できる |
| MQ-7 | VoiceOver を有効にして GUI の結果一覧を読み上げる | 各行のルール名・サイズ・Tier が読み上げられる |
| MQ-8 | Time Machine ローカルスナップショットがある状態で `disclean apply` を実行 | 「空き容量に即時反映されない場合がある」旨が表示される |
| MQ-9 | GUI と LP を並べてスクリーンショットを撮り、同一のデザイン言語に見えるかを目視する | 色・角丸・影・書体が一致し、別々の製品に見えない |
| MQ-10 | LP のヒーローでレバーを引き、瓶からチャンクを引き戻す | 落下と復元が意図通りに動き、「これはデモです」の注記が読める |
| MQ-11 | macOS のシステム設定で「視差効果を減らす」を有効にして GUI と LP を操作 | アニメーションが止まり、レバーが単一クリックで動作する |
| MQ-12 | ダークモードで GUI と LP を表示し、全テキストの可読性を目視する | キャンディ 6 色の値が変わらず、地とキーラインのみ反転している |
| MQ-13 | 生成した LP のスクリーンショットと OG 画像（1200x630）を開いて目視する | 要素の重なり・文字の切れがない |
| MQ-14 | 実機で新しいカタログ（新ルールを 1 件追加）を配信し、`disclean scan` → `disclean update` → 承認 → `disclean scan` の順に実行する | 承認前は新ルールが現れず、承認後に現れる。差分画面に「新たに削除対象になるパス」が実サイズ付きで出る |
| MQ-15 | 機内モード（オフライン）で全サブコマンドを実行する | 遅延・エラー表示がなく、すべて通常どおり完了する |
| MQ-16 | `disclean update --off` を実行後、`nettop` / `lsof -i` でプロセスの通信を観察する | 外向き接続が発生しない |
| MQ-17 | macOS のアップデート適用後（またはビルド番号を書き換えた `env.json` で）`disclean doctor` を実行する | OS が変わった旨と、この OS で見つからなくなったルールが一覧表示される |


#### 10.6 Coverage target

- `DiscleanKit` 行カバレッジ 80% 以上。CI で下回った場合はマージをブロックする。
- UI 層（`disclean` のレンダラ、SwiftUI View）はカバレッジ目標の対象外とし、E2E で担保する。
