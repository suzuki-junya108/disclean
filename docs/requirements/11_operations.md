> 責務: 運用（§11）— 配布・監視・ロールバック + プロジェクト全体の Definition of Done (§11.1)。
> 親: ../REQUIREMENTS.md

## 11. Operations

- **Deployment**:
  - CI: GitHub Actions（`runs-on: macos-latest` = macOS 26 Arm64、2026-08 時点）で push / PR ごとに `swiftlint lint --strict` → `swift build -c release` → `swift test --enable-code-coverage` → `acceptance/run-all.sh` → `xcodebuild test`（GUI）を実行する。
  - リリース: `v*` タグの push で、ユニバーサルバイナリ（arm64 + x86_64）と `Disclean.app` をビルドし、Developer ID Application 証明書で `codesign --options runtime` 署名、`xcrun notarytool submit --wait` で公証、`xcrun stapler staple` で添付する。成果物（`.tar.gz` と `.dmg`）を GitHub Release に添付する。
  - 配布: Homebrew tap `suzuki-junya108/homebrew-disclean` の Formula を Release の SHA256 で更新する（`brew install suzuki-junya108/disclean/disclean`）。
  - **配布物には SwiftPM のリソースバンドル（`Disclean_DiscleanKit.bundle`）を必ず同梱する**。実行ファイル単体では同梱ルールを読めず、起動直後に落ちる（2026-08-20 の実インストールで発生）。`tools/make-dist.sh` が tar.gz を作り、展開した状態で `rules list` が通ることを毎回確認する。Formula は `libexec` に両方を置き、`bin.write_exec_script` で呼ぶ。
  - **カタログ配信（F-17）**: リリースワークフローが `Sources/DiscleanKit/Resources/rules/*.json` から `catalog-<catalogVersion>.tar.gz` を作り、`catalog-manifest.json`（`catalogVersion` / `publishedAt` / `expiresAt` = 発行 +90 日 / `minDiscleanVersion` / 各ファイルの sha256 / `revocations` / `latestApp`）を生成し、Ed25519 秘密鍵で detached 署名（`catalog-manifest.json.sig`）を付けて同じ Release に添付する。`catalogVersion` は単調増加を CI で検証し、前回以下なら公開を中止する。
  - **ルールだけの更新**（OS 更新でパスが変わった場合など）: 本体を再ビルドせず、ルール JSON の修正 → `catalogVersion` を +1 → manifest の再署名 → Release 更新、だけで全利用者に届く。到達は「利用者の次回実行時（24 時間間隔）＋拡大差分なら承認後」。
  - **緊急のルール停止（revocation）**: 誤ったルールを配ってしまった場合、`revocations: ["<ruleId>"]` を含む manifest を公開する。無効化は削除対象が減る方向のため、利用者の承認を待たずに次回実行時へ自動適用される。
  - **署名鍵の管理**: Ed25519 秘密鍵は GitHub Actions の Encrypted Secrets のみに置く。公開鍵は `release-keys.json` としてバイナリに埋め込む。ローテーションは「新鍵を `validFrom` 付きで追加した本体を先にリリース → 旧鍵での署名を止める → 十分に普及したら旧鍵を削除」の順に行う（新鍵だけを配ると旧バージョンが更新を受け取れなくなる）。
  - LP: `site/` を GitHub Pages（`gh-pages` ブランチ）へ公開する。ビルド工程を持たないため、`main` の `site/` をそのまま同期する。公開前に `acceptance/AT-015-lp.sh` を CI で実行し、失敗した場合は公開しない。LP に記載するバージョン番号とチェックサムは Release の値をワークフローが差し込む。
  - 秘密情報: 署名証明書（`.p12`）と App Store Connect API キー（`.p8`）、それらのパスワードは GitHub Actions の Encrypted Secrets に置く。リポジトリ・チャット・コミットメッセージには一切含めない。
- **Monitoring**: `N/A — reason: ローカル CLI / GUI であり、監視対象のサーバーが存在しないため。` 利用者側の診断は `disclean doctor` と `disclean history` が担う。
- **Alerting**: `N/A — reason: 常駐せず通知先を持たないため。` 失敗は終了コード（4 = 部分的失敗、3 = 権限不足、6 = 隔離庫不整合）と stderr で即時に伝える。
- **Rollback**:
  - 利用者のデータに対するロールバック = `disclean undo <runID>`（既定 7 日以内）。
  - カタログのロールバック = 利用者側は `disclean update --rollback`（1 世代前へ）、配信側は「修正した内容で `catalogVersion` を +1 して再公開」する。**古い manifest を再公開しても巻き戻し防止により適用されない**ため、版数を戻す運用は取れない。
  - リリースのロールバック = Homebrew Formula を直前のバージョンに戻し、問題のある GitHub Release を pre-release に落とす。バイナリは各バージョンが独立しており、状態ファイルは `schemaVersion` で後方互換を判定する（上位版数の状態を読んだら書き込みを拒否して exit 6）。
- **更新配信の監視**: `N/A — reason: 配信は GitHub Releases の静的アセットであり、監視対象のサービスを運用しないため。` 代わりに、CI の週次ジョブで公開中の manifest を取得し、署名検証・`expiresAt` の残日数（30 日を切ったら再署名して再公開）・`catalogVersion` の整合を検査する。
- **Backup / DR**:
  - 隔離庫は「削除の取り消し」のための一時領域であり、バックアップではない。README に「Time Machine 等の通常のバックアップを置き換えるものではない」と明記する。
  - 監査ログは自動削除しないため、`$DISCLEAN_STATE_DIR/audit/` を通常のバックアップ対象に含めれば履歴が保全される。
- **アンインストール手順**（README に記載）:
  1. `disclean purge --all --force`（隔離庫を空にする。復元したいものがあれば先に `disclean undo`）
  2. `brew uninstall disclean` または `rm ~/.local/bin/disclean`、および `/Applications/Disclean.app` の削除
  3. `rm -rf ~/.local/state/disclean ~/.config/disclean`（履歴を残したい場合は `audit/` を退避。`updates/` 配下のダウンロード済み成果物もここで消える）
  4. システム設定 → プライバシーとセキュリティ → フルディスクアクセス から `Disclean` を削除

### 11.1 Definition of Done (per project)

**Build & Code Quality**
- [ ] `swift build -c release --arch arm64 --arch x86_64` が 0 errors（成果物 `./.build/apple/Products/Release/disclean` が存在）
- [ ] `xcodebuild -project Disclean.xcodeproj -scheme Disclean -configuration Release build` が `BUILD SUCCEEDED`
- [ ] `swiftlint lint --strict` が 0 violations
- [ ] `xcrun swift-format lint --recursive --strict Sources Tests` が 0 diagnostics
- [ ] バンドルサイズ上限: `N/A — reason: Web バンドルを持たないネイティブアプリのため。` 代わりに CLI バイナリ 20MB 以内を目安とする
- [ ] 依存脆弱性スキャン: `N/A — reason: 第三者依存が swift-argument-parser 1.8.2 のみで、SwiftPM に監査コマンドが存在しないため。` 代替として GitHub Dependabot による SwiftPM 依存更新通知を有効化する

**Testing**
- [ ] `swift test --enable-code-coverage` 全 PASS、`DiscleanKit` 行カバレッジ 80% 以上
- [ ] `PathGuard` と `RuleCatalog` の検証経路が分岐カバレッジ 100%
- [ ] `acceptance/run-all.sh`（AT-001〜AT-010, AT-014〜AT-018）全 PASS
- [ ] `xcodebuild test -scheme DiscleanUITests`（AT-011〜AT-013）全 PASS

**Verification**
- [ ] §10.5 の WS-a / WS-d / WS-h / WS-i / WS-j / WS-k / WS-l / WS-o / WS-p が全 PASS（WS-b, c, e, f, g は N/A — reason: ネットワーク待受・iOS/Android/Flutter を持たないため。根拠は ../REQUIREMENTS.md §10.5 の各行）
- [ ] Manual QA MQ-1〜MQ-13（`10_test_strategy.md`）を実機で実施し、結果を PR に記載
- [ ] Tier A のみの実行で隔離サイズ 60GB 以上を実機で確認（M4）
- [ ] `disclean undo --last` による全件復元をバイト数一致で確認（M2）
- [ ] フルディスクアクセス未付与状態で「成功を装わない」ことを確認（MQ-4）
- [ ] 改竄 manifest 3 種（署名 / ハッシュ / 巻き戻し）をすべて拒否し `active` が不変（AT-016, M8）
- [ ] 拡大差分が承認前に有効化されないことを確認（AT-016 AC3, M9）
- [ ] `DISCLEAN_AUTO_UPDATE=0` で外向き接続が 0 件（AT-016 AC5, M10）
- [ ] オフライン環境で全サブコマンドが通常どおり完了（MQ-15, WS-o）
- [ ] Manual QA MQ-14〜MQ-17（更新と OS ドリフト）を実機で実施し、結果を PR に記載

**Documentation**
- [ ] README にインストール・使い方・ルール追加方法・アンインストール手順を記載
- [ ] README と LP の FAQ に、更新機構が**通信すること**・送信される情報・止め方（`disclean update --off` / `DISCLEAN_AUTO_UPDATE=0`）を記載し、旧来の「ネットワーク通信のコードがありません」という記述が残っていないこと
- [ ] `docs/update-protocol.md` に manifest の形式・署名手順・鍵ローテーション・緊急 revocation の手順を記載
- [ ] `docs/rule-schema.md` にルール JSON のスキーマと全フィールドの意味（`minMacOS` / `maxMacOS` / `verifiedOn` を含む）を記載
- [ ] `docs/design-system.md` の D-01〜D-08 が全て PASS し、GUI / LP のスクリーンショット（明・暗の 2 種）を PR に添付
- [ ] 同梱フォント 3 種の OFL 全文を `Disclean.app/Contents/Resources/LICENSES/` に含め、README にクレジットを記載
- [ ] `.env.local.template`: `N/A — reason: 必須環境変数が存在しないため（§6.5.2）。` 代わりに README に `DISCLEAN_*` 任意環境変数の一覧を記載する
- [ ] README の記述と §6.5 の内容に齟齬がないこと
- [ ] 既存 `mac_cleanup.sh` に非推奨の注記を追加し、README から `disclean` への移行手順を案内する
