> 責務: 外部依存表（§6）— API / ライブラリ / サービスを 1 つの表で網羅。ローカル起動前提情報 (§6.5) は ../REQUIREMENTS.md 参照。
> 親: ../REQUIREMENTS.md

## 6. External Dependencies

#### 6.1 ビルド時依存（SwiftPM）

| Name | Type | Version | Auth方式 | 必須/任意 | 取得方法 | Source URL |
|---|---|---|---|---|---|---|
| swift-argument-parser | Lib | 1.8.2 | なし | 必須 | SwiftPM (`from: "1.8.2"`) | https://github.com/apple/swift-argument-parser |
| swift-testing | Lib | Swift 6.3 ツールチェーン同梱（1902） | なし | 必須 | Xcode 26.6 に同梱 | https://github.com/swiftlang/swift-testing |
| Foundation / AppKit / SwiftUI | Lib | macOS 14.0 SDK 以降 | なし | 必須 | OS 同梱 | https://developer.apple.com/documentation/foundation |
| CryptoKit（`Curve25519.Signing`）| Lib | macOS 14.0 SDK 以降 | なし | 必須 | OS 同梱 | https://developer.apple.com/documentation/cryptokit/curve25519/signing |
| Bricolage Grotesque | Font (OFL 1.1) | 可変（`wght` 200-800, `wdth` 75-100） | なし | 必須 | GUI はリポジトリに同梱 / LP は Google Fonts | https://fonts.google.com/specimen/Bricolage+Grotesque |
| Zen Maru Gothic | Font (OFL 1.1) | 400 / 700 | なし | 必須 | 同上 | https://fonts.google.com/specimen/Zen+Maru+Gothic |
| Martian Mono | Font (OFL 1.1) | 可変（`wght` 100-800, `wdth` 75-112.5） | なし | 必須 | 同上 | https://fonts.google.com/specimen/Martian+Mono |

> 本プロジェクトは上記以外の第三者ライブラリを追加しない（§14.4）。JSON は `Codable`、並列処理は Swift Concurrency、外部コマンド実行は `Foundation.Process` を使う。更新の署名検証は CryptoKit の Ed25519（`Curve25519.Signing.PublicKey.isValidSignature`）、通信は `URLSession` で行い、Sparkle 等の更新フレームワークは導入しない（F-17 / F-18）。

#### 6.2 開発時ツール

| Name | Type | Version | 必須/任意 | 取得方法 | Source URL |
|---|---|---|---|---|---|
| Swift toolchain | Tool | 6.3.3 (swiftlang-6.3.3.1.3) | 必須 | Xcode 26.6 に同梱 | https://swift.org |
| Xcode | Tool | 26.6 (17F113) | 必須（GUI ビルド） | Mac App Store / developer.apple.com | https://developer.apple.com/xcode/ |
| SwiftLint | Tool | 0.65.0 | 必須（CI ゲート） | `brew install swiftlint` | https://github.com/realm/SwiftLint |
| swift-format | Tool | 603.0.0（Xcode 26.6 同梱版 6.3.0 を使用） | 必須（CI ゲート） | `xcrun swift-format` | https://github.com/swiftlang/swift-format |
| jq | Tool | 1.7 以降 | 必須（受入テスト） | `brew install jq` | https://jqlang.github.io/jq/ |
| Playwright | Tool | LP の受入テスト（AT-015）でのみ使用。Playwright MCP または `npx playwright@1.56` | 必須（LP テスト） | `npx playwright install chromium` | https://playwright.dev |
| axe-core | Tool | 4.10 系（Playwright 経由で注入） | 必須（LP a11y テスト） | CDN ではなくローカルの `node_modules` から注入 | https://github.com/dequelabs/axe-core |
| Python | Tool | 3.9 以降（macOS 標準） | 必須（LP のローカル配信） | OS 同梱 | https://docs.python.org/3/library/http.server.html |

#### 6.3 実行時に呼び出す外部コマンド（すべて任意 — 無ければ該当ルールをスキップ）

| Name | Type | 検出コマンド | 実行内容 | 必須/任意 | Source URL |
|---|---|---|---|---|---|
| Homebrew | Tool | `brew --version` | `brew cleanup --prune=all -s` | 任意 | https://docs.brew.sh/Manpage |
| npm | Tool | `npm --version` | `npm cache clean --force` | 任意 | https://docs.npmjs.com/cli/v10/commands/npm-cache |
| pnpm | Tool | `pnpm --version` | `pnpm store prune` | 任意 | https://pnpm.io/cli/store |
| Yarn | Tool | `yarn --version` | `yarn cache clean` | 任意 | https://yarnpkg.com/cli/cache/clean |
| uv | Tool | `uv --version` | `uv cache prune` | 任意 | https://docs.astral.sh/uv/reference/cli/ |
| pip | Tool | `pip3 --version` | `pip3 cache purge` | 任意 | https://pip.pypa.io/en/stable/cli/pip_cache/ |
| xcrun simctl | Tool | `xcrun simctl help` | `xcrun simctl delete unavailable` / `list devices --json` | 任意 | https://developer.apple.com/documentation/xcode/ |
| Docker CLI | Tool | `docker info` | `docker system prune -f` / `docker builder prune -f` | 任意 | https://docs.docker.com/reference/cli/docker/system/prune/ |
| tmutil | Tool | `tmutil listlocalsnapshots /` | ローカルスナップショット数の取得のみ | 任意 | https://keith.github.io/xcode-man-pages/tmutil.8.html |

#### 6.4 依存に関する検証済みの事実

| 事実 | 根拠 |
|---|---|
| `docker system prune --volumes` は**匿名ボリュームのみ**を削除し、名前付きボリュームは削除しない。`--volumes` 無しでは一切のボリュームを削除しない | https://docs.docker.com/reference/cli/docker/system/prune/ （2026-08-20 参照）。本ツールでは `-a` と `--volumes` の双方を付けない（F-10） |
| `volumeAvailableCapacityForImportantUsageKey` は purgeable 領域を含む値を返し、`volumeAvailableCapacityKey` は即時利用可能な空きを返す。両者は数十 GB 単位で乖離しうる | https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey / https://eclecticlight.co/2023/04/27/where-does-macos-get-its-volume-free-space-figures-from/ |
| クラウド未ダウンロードファイルは `stat.st_flags` の `SF_DATALESS`(0x40000000) で判定でき、`setiopolicy_np` で実体化を抑止できる | Apple Technical Note TN3150 / https://mjtsai.com/blog/2023/05/11/getting-ready-for-dataless-files/ |
| ディレクトリ列挙は dataless ディレクトリの実体化を引き起こしうる（実例あり） | https://sourceforge.net/p/grandperspectiv/bugs/115/ / https://github.com/fish-shell/fish-shell/issues/8399 |
| CLI バイナリへのフルディスクアクセスは、TCC の responsible process の概念により親プロセス（Terminal 等）に紐づく | https://lapcatsoftware.com/articles/FullDiskAccess.html / https://developer.apple.com/forums/thread/756510 |
| GitHub Actions の `macos-latest` は macOS 26 Arm64 を指す（2026-08 時点） | https://github.com/actions/runner-images |
| Bricolage Grotesque / Zen Maru Gothic / Martian Mono はいずれも SIL Open Font License 1.1 で、埋め込み・再配布・アプリ同梱が許諾される | 各フォントの Google Fonts ページに記載のライセンス（2026-08-20 参照）。同梱時は OFL 全文を `Disclean.app/Contents/Resources/LICENSES/` に含める |
| GitHub Pages は静的ファイルのみを配信し、サーバーサイド処理を持たない | https://docs.github.com/en/pages/getting-started-with-github-pages/about-github-pages |

#### 6.6 更新の配信元（F-17 / F-18）

| 項目 | 値 |
|---|---|
| 既定エンドポイント | `https://github.com/suzuki-junya108/disclean/releases/latest/download/` |
| 取得するファイル | `catalog-manifest.json`（数 KB）/ `catalog-manifest.json.sig`（Ed25519 detached, base64）/ `catalog-<catalogVersion>.tar.gz`（数十 KB） |
| 本体成果物 | 同 manifest の `latestApp.assets[]`（`Disclean-<version>.dmg` / `disclean-<version>-macos-universal.tar.gz`）。**要求されたときのみ**取得する |
| 許可するホスト | `github.com` と `objects.githubusercontent.com` の 2 つのみ。リダイレクト先がこれ以外なら中止する |
| プロトコル | HTTPS のみ（ATS 既定、TLS 1.2 以上）。HTTP へのフォールバックを実装しない |
| 認証 | なし（公開アセット）。API トークン・認証情報を扱わない |
| 送信する情報 | HTTP リクエストのみ（URL と `User-Agent: disclean/<version> (macOS <ver>; <arch>)`）。パス・スキャン結果・マシン識別子を送らない |
| 頻度 | `updateIntervalHours`（既定 24 時間）に 1 回、コマンド実行時のみ。常駐しない（NG14） |
| 無効化 | `DISCLEAN_AUTO_UPDATE=0` / `config.json` の `autoUpdate: false` / `--no-update`。無効時は接続を一切行わない |
| 鍵 | Ed25519。公開鍵はバイナリに埋め込む（`Sources/DiscleanKit/Update/Resources/release-keys.json`、`keyId` で複数鍵を並行保持しローテーション可能）。秘密鍵は GitHub Actions の Encrypted Secrets のみに置く |

> GitHub Releases を使う理由: 配布物（`.dmg` / `.tar.gz`）と同じ経路・同じ権限管理に載せられ、新しいサーバーとドメインを運用に増やさないため。エンドポイントは `DISCLEAN_UPDATE_ENDPOINT` で差し替えられるが、**署名検証は差し替えられない**（テストでも同じ検証を通す）。

#### 6.7 依存に関する検証済みの事実（更新機構）

| 事実 | 根拠 |
|---|---|
| `Curve25519.Signing.PublicKey.isValidSignature(_:for:)` は CryptoKit（macOS 10.15+）で提供され、第三者ライブラリなしに Ed25519 の検証ができる | https://developer.apple.com/documentation/cryptokit/curve25519/signing/publickey |
| GitHub Releases の `/releases/latest/download/<asset>` は最新リリースの同名アセットへ 302 で解決され、実体は `objects.githubusercontent.com` から配信される | https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases |
| Homebrew で導入したバイナリは `$(brew --prefix)/Cellar/<formula>/<version>/` の実体へ symlink される。実行ファイルの `realpath` でこれを判定できる（F-18 の `installMethod`） | https://docs.brew.sh/Formula-Cookbook |
| `spctl --assess --type open` と `codesign --verify --deep --strict` で、ダウンロードした成果物の署名と公証を配布前と同じ基準で検証できる | https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution |

