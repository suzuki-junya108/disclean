> 責務: 技術制約（§7）— 言語・ランタイム・FW・テストfwk 等を **正確なバージョン** で固定。
> 親: ../REQUIREMENTS.md

## 7. Technical Constraints

> すべて **正確なバージョン** で指定する。バージョンは 2026-08-20 に対象マシン上で実測したもの、または GitHub Releases API で確認したもの。

- **Language**: Swift 6.3.3 (swiftlang-6.3.3.1.3, clang-2100.1.1.101) / strict concurrency（`swift-tools-version: 6.2`, `StrictConcurrency` 既定有効）
- **Runtime**: macOS 14.0 以降（`platforms: [.macOS(.v14)]`）。開発機は macOS 26.5.2 (25F84) / Apple M4 / 10 コア
- **Package manager**: Swift Package Manager（Swift 6.3.3 同梱）。CocoaPods / Carthage は使用しない
- **Framework**: なし（Foundation + AppKit + SwiftUI のみ）。CLI 引数解析に swift-argument-parser 1.8.2
- **Test framework**: swift-testing（Swift 6.3 ツールチェーン同梱, Testing Library Version 1902）を DiscleanKit の単体・結合テストに使用。GUI は XCTest + XCUITest（Xcode 26.6 同梱）。受入テストは bash スクリプト（`tests/acceptance/AT-*.sh`）+ jq 1.7
- **Lint / Format**: SwiftLint 0.65.0（`.swiftlint.yml` をリポジトリ直下に配置、`--strict` で 0 violations が CI ゲート）+ swift-format 6.3.0（Xcode 26.6 同梱の `xcrun swift-format`、`.swift-format` をリポジトリ直下に配置）
- **Build target**: ユニバーサルバイナリ（arm64 + x86_64）。CLI は `swift build -c release --arch arm64 --arch x86_64`、GUI は Xcode プロジェクトで `Disclean.app` を生成
- **Build output**:
  - CLI: `./.build/apple/Products/Release/disclean`（ユニバーサル）/ 単一アーキ時は `./.build/release/disclean`
  - GUI: `./build/Release/Disclean.app`（`xcodebuild -derivedDataPath ./build` 指定時）
  - 配布物: `dist/disclean-<version>-macos-universal.tar.gz` と `dist/Disclean-<version>.dmg`
- **Naming**: 日本語表示名は「ディスクリン」、英名・識別子は `disclean` の 2 本立てに固定する。**機械が読むものは例外なく `disclean`**（実行ファイル / SwiftPM パッケージ / GitHub リポジトリ `suzuki-junya108/disclean` / Homebrew tap `suzuki-junya108/homebrew-disclean` / `~/.config/disclean` / `~/.local/state/disclean` / 環境変数 `DISCLEAN_*`）。**人間が読む日本語の文章と GUI の表示は「ディスクリン」**。英語の文面では `disclean` を使い、カタカナ表記を混ぜない。GUI バンドルは `Disclean.app`、`CFBundleDisplayName` は「ディスクリン」、コアライブラリは `DiscleanKit`
- **Design language**: HEAVY CANDY（`docs/design-system.md` v1.0）。GUI と LP はこのトークン定義から逸脱しない。色は 9 トークン、角丸は 3 値（22px / 999px / 14px）、影はぼかし 0 のオフセットのみ、塗りにグラデーションを使わない
- **Fonts**: Bricolage Grotesque（Display）/ Zen Maru Gothic（Body, 日本語・英語共用）/ Martian Mono（Data）。いずれも OFL 1.1。GUI は同梱、LP は Google Fonts から読み込む
- **LP stack**: 素の HTML5 + CSS（カスタムプロパティ）+ ES2022 の DOM スクリプト。フレームワーク・バンドラ・npm 依存・CSS プリプロセッサを使わない。配信は GitHub Pages（`site/` ディレクトリ）
- **Browser support**: LP のみ対象。Safari 17+ / Chrome 120+ / Firefox 128+ の各最新 2 バージョン。JavaScript 無効時も全文とインストール手順が読める（F-16）
- **OS support (CLI/Native)**: macOS 14.0 (Sonoma) 以降、arm64 と x86_64 の両方。macOS 13 以前は非対応
- **Repo structure**: 単一 Git リポジトリ。`~/Sync/disclean` で `git init` し、GitHub のリモートを設定して公開する（monorepo にはしない）。SwiftPM の 1 パッケージに 3 ターゲット（`DiscleanKit` / `disclean` / `DiscleanApp`）+ 2 テストターゲット
- **Network**: 通信は更新機構（F-17 / F-18）のみが行う。`URLSession` を使うのは `DiscleanKit/Update/` の 1 コンポーネントに限定し、他のコンポーネントは import しない。接続先は `github.com` と `objects.githubusercontent.com` の 2 ホスト、HTTPS のみ（ATS 既定のまま、`NSAllowsArbitraryLoads` を設定しない）。既定オン、`DISCLEAN_AUTO_UPDATE=0` で完全に無効化できる
- **Update signing**: カタログ manifest は Ed25519（CryptoKit `Curve25519.Signing`）の detached 署名を必須とし、公開鍵はバイナリに埋め込む。検証を省略する経路・環境変数を実装しない。テスト用の信頼鍵注入（`DISCLEAN_UPDATE_TRUSTED_KEYS_FILE`）は **debug ビルドでのみ**有効とし、release ビルドでは値を無視する
- **Signing / Distribution**: Developer ID Application 証明書で署名し、`notarytool` で公証、`stapler` で添付する。Homebrew tap（`homebrew-disclean`）で `disclean` を、GitHub Releases で `.dmg` を配布する
- **Existing systems to respect**:
  - `~/Sync` は Syncthing のホワイトリスト同期対象。`.stignore` に `.build` / `build` / `dist` / `.swiftpm` / `DerivedData` の除外を追加してから開発する（追加しない限り全ビルド成果物が全台へ同期される）
  - 既存の `mac_cleanup.sh` は v1.0 リリースまでリポジトリに残し、README に「非推奨・disclean へ移行」と明記する
  - `~/Sync` 配下は SG-06 により既定で削除対象から除外する
