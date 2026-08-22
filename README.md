# ディスクリン / disclean

macOS のディスクを、**消す前に重さで見せて**片づけるツールです。
削除は隔離庫（quarantine）を経由し、既定で 7 日間は元の場所へ戻せます。

- 「スキャン（読むだけ）→ 計画（選ぶ）→ 実行（隔離庫へ移す）」を分離しています
- 権限不足・対象なし・ツール未検出は、成功件数に数えず**理由付きで報告**します（サイレント失敗ゼロ）
- CLI（`disclean`）と GUI（`Disclean.app`）が同じコアを共有し、同じ隔離庫・同じ記録を読み書きします

## 入れる

```bash
brew install suzuki-junya108/disclean/disclean
```

GUI は [Releases](https://github.com/suzuki-junya108/disclean/releases) の `.dmg` から入れられます。

対応: macOS 14 以降 / Apple Silicon・Intel

## 使う

```bash
disclean doctor     # 環境を確認する（権限・外部ツール・保存先・OS の変化）
disclean scan       # 何がどれだけ空けられるかを読み取りだけで調べる
disclean inspect uv-cache   # その中に何が入っているかをファイル単位で見る
disclean apply      # 選んだものを隔離庫へ移す（Tier A が既定選択）
disclean undo --last  # 直前の実行を取り消す
disclean purge      # 隔離庫から完全に削除する（戻せなくなります）
disclean report     # ディスクリンが触らない大きなものを見るだけ表示する
disclean history    # これまでの操作の記録
disclean update     # 掃除ルールの更新を確認・適用する
```

すべてのサブコマンドに `--json` があります（`schemaVersion` 付きの 1 オブジェクトを stdout に出します）。

### 何が消えるのかを、消す前に見る

`inspect` は読み取りだけで、中身を大きい順に並べます。ファイルの種類（圧縮ファイル・ログ・
キャッシュの実体など）と、それが無くなると何が起きるかも添えます。

```bash
disclean inspect uv-cache                 # 片づける対象の中身
disclean inspect --path ~/.cache/uv/wheels  # 1 段下を見る（ホーム配下と隔離庫のみ）
disclean inspect --run 01J...              # 隔離庫に入れたものの中身
```

GUI では、各項目と隔離庫の「なかを見る」から同じものが開きます。

### 何を見ているか

同梱ルールは 99 本です（Tier A 35 / B 48 / 見るだけ 16）。

- **パッケージ管理**: npm / pnpm / Yarn / Homebrew / uv / pip / Composer / NuGet / Maven / sbt・Ivy・Coursier / RubyGems / Bun / Deno / Go / Cargo / CocoaPods / Carthage / pub (Flutter) / Conan
- **ビルドまわり**: Xcode（DerivedData・キャッシュ・実機サポート・SwiftUI プレビュー）/ シミュレータ（端末内アプリのキャッシュ）/ Gradle / Android / node-gyp / Electron / ccache・sccache / Docker
- **アプリ**: ブラウザ各種（Safari / Chrome / Edge / Brave / Firefox / Arc / Chromium 系）/ Slack・Discord・Teams・Zoom・Telegram・WhatsApp / Notion・Figma・Sketch / VS Code / Steam / Google ドライブ / Dropbox / Spotify・ミュージック / Adobe / Finder のサムネイル
- **見るだけ（消しません）**: ゴミ箱 / ダウンロード / iPhone のバックアップ / Ollama・Hugging Face などのモデル / Android エミュレータ / シミュレータの端末一覧 / nvm・pyenv 等のランタイム / conda の環境 / エディタの拡張機能 / Final Cut・Logic の作業ファイル

`disclean rules list` で全件を確認できます。

### リスク階層（Tier）

| Tier | 意味 | 既定 |
|---|---|---|
| A | 再取得が容易でリスクが低い | 選択済み |
| B | 中身を見てから消すもの | 未選択 |
| 見るだけ (C) | **削除しません**。大きさと手動手順の提示のみ | 選択不可 |

### 取り消せるもの / 取り消せないもの

- ディレクトリを隔離庫へ移す種類（Xcode の DerivedData 等）は `disclean undo` で戻せます。
- パッケージマネージャのキャッシュ（npm / pnpm / Yarn / Homebrew / uv / pip）も隔離庫を通るため戻せます。
- 外部ツールに任せる種類（Docker / シミュレータ）は**取り消せません**。実行前の確認画面で明示します。

## 掃除ルールの更新について

macOS が新しくなるとキャッシュの置き場所が変わることがあるため、**掃除ルールだけ**を署名付きで配っています。

- 1 日 1 回、コマンドを実行したときにだけ確認します（常駐しません）
- 受け取ったルールは Ed25519 の署名を検証し、**消す対象が増える変更はあなたが承認するまで有効になりません**
- アプリ本体は自動で入れ替えません。新しい版があることをお知らせするだけです
- 止めるとき: `disclean update --off`（または `DISCLEAN_AUTO_UPDATE=0`）。以後は通信そのものが発生しません

送信するのは HTTP リクエストだけで、内容は「ディスクリンのバージョン・macOS のバージョン・アーキテクチャ」です。
ファイルの場所・スキャン結果・識別子は送りません。接続元の IP と時刻は、どんな通信でも相手側（GitHub）の記録に残ります。

## 自分でルールを足す・上書きする

`~/.config/disclean/rules.d/*.json` に置いたルールが最優先されます（同じ `id` なら同梱ルールを置き換えます）。
書式は [docs/rule-schema.md](docs/rule-schema.md) を参照してください。

```bash
disclean rules list       # 有効なルールと出所を見る
disclean rules validate   # 自分で書いたルールを検証する
```

## 環境変数（すべて任意）

| 変数 | 既定 | 用途 |
|---|---|---|
| `DISCLEAN_CONFIG_DIR` | `~/.config/disclean` | 設定とユーザールールの場所 |
| `DISCLEAN_STATE_DIR` | `~/.local/state/disclean` | 隔離庫・記録・キャッシュの場所 |
| `DISCLEAN_QUARANTINE_TTL_DAYS` | `7` | 隔離庫に置いておく日数（1〜90） |
| `DISCLEAN_CONCURRENCY` | `min(8, CPU数)` | 同時に調べる数（1〜32） |
| `DISCLEAN_AUTO_UPDATE` | 有効 | `0` で更新チェックを完全に無効化（通信しません） |
| `DISCLEAN_UPDATE_INTERVAL_HOURS` | `24` | 更新を確認する間隔（1〜168） |
| `DISCLEAN_UPDATE_ENDPOINT` | GitHub Releases | 配信元（署名検証は無効化できません） |
| `NO_COLOR` | — | 設定すると色を出しません |

## やめる

```bash
disclean purge --all --force        # 隔離庫を空にする（戻したいものがあれば先に undo）
brew uninstall disclean             # または /Applications/Disclean.app を削除
rm -rf ~/.local/state/disclean ~/.config/disclean   # 記録を残すなら audit/ を退避
```

システム設定 → プライバシーとセキュリティ → フルディスクアクセス からも削除してください。

## 安全のしくみ

- 削除の実体は、**同じディスク内での移動**（`rename`）です。容量によらず一瞬で終わります
- 実行のたびに、対象・理由・結果を JSONL の監査ログに 1 件ずつ記録します。**記録できないときは削除しません**
- ホームディレクトリの外には出ません。`sudo` を使いません。システム領域は表示だけで、削除機能を持ちません
- シンボリックリンクは辿りません。`~/Sync` など除外パスは既定で対象外です

隔離庫はバックアップではありません。Time Machine 等の通常のバックアップを置き換えるものではありません。

## 開発

```bash
swift build -c release            # CLI をビルド
swift test                        # 単体・結合テスト
acceptance/run-all.sh       # 受入テスト（CLI の実バイナリを使う）
tools/make-app.sh                 # Disclean.app を組み立てる
tools/make-dist.sh                # 配布用 tar.gz を作る（展開して動くかを毎回検証する）
tools/check-download-links.sh     # 公開後のダウンロードリンクが本当に取得できるか確かめる
swiftlint lint --strict           # 0 violations が条件
xcrun swift-format lint --recursive --strict Sources Tests
```

要件定義は [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)、デザイン言語は [docs/design-system.md](docs/design-system.md) にあります。

## 旧 `mac_cleanup.sh` からの移行

このリポジトリの `mac_cleanup.sh` は **非推奨**です。無確認で削除し、失敗を握り潰し、記録も残しません。
`disclean scan` → `disclean apply` に置き換えてください。

## ライセンス

MIT（[LICENSE](LICENSE)）。
