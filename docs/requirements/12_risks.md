> 責務: リスク・未解決事項（§12）と前提（§13）。
> 親: ../REQUIREMENTS.md

## 12. Risks & Open Questions

| ID | Risk / Question | Severity | Mitigation / Decision Owner |
|---|---|---|---|
| R-01 | ルール定義の誤りにより、ユーザーが必要としているデータを隔離してしまう | high | 全 `directory` 型削除を隔離庫経由にし、既定 7 日の undo を保証する（F-05, F-07）。Tier A の各ルールに `whatIsLost` を必須とし、レビュー時に「再生成コスト」を確認する。Owner: suzuki.junya |
| R-02 | `command` 型ルール（brew / npm / docker 等）は undo できないため、実行後に取り消せない | high | 実行前の確認画面で「この項目は取り消せません」を明示する。Docker は `-a` と `--volumes` を付けない（F-10）。Owner: suzuki.junya |
| R-03 | TOCTOU: スキャンから実行までの間に対象パスがシンボリックリンクへ差し替えられる | medium | `lstat` によるリンク判定（SG-04）と `realpath` 再検証（SG-01, SG-02）を移動の直前に行う。移動は親ディレクトリを固定した `renameat` 相当で実施する。Owner: suzuki.junya |
| R-04 | iCloud Drive / Google Drive の dataless ファイルをスキャンが実体化させ、逆に容量を消費する | medium | プロセス起動時に `setiopolicy_np` で実体化を無効化し、`SF_DATALESS` の項目は開かない（F-02）。MQ-5 で実機検証する。Owner: suzuki.junya |
| R-05 | 隔離庫が同一ボリューム上にあるため、TTL 満了までは空き容量が回復しない | medium | `apply` のサマリに「実際に空きが増えるのは失効後」を明記し、`disclean purge --run <id>` で即時解放できることを案内する（F-06）。Owner: suzuki.junya |
| R-06 | フルディスクアクセスの付与先が「ターミナル」になり、disclean 以外のプロセスにも権限が及ぶ | medium | CLI では FDA を必須にせず、未付与でも Tier A の主要ルールが機能する設計にする。FDA が要る範囲（`~/.Trash` `~/Downloads` `~/Documents` `~/Desktop` の測定）は Tier C の表示に限定し、GUI 側で `Disclean.app` 単体に付与する導線を提供する（F-14）。Owner: suzuki.junya |
| R-07 | `~/Sync` は Syncthing 同期対象のため、ビルド成果物（`.build`）が全マシンへ同期される | high | **2026-08-20 対応済み**。`~/Sync/.stignore` の除外節（ホワイトリストの `!` 行より前）に `.build` / `.swiftpm` / `DerivedData` / `dist` を追加した。`(?d)` は付けていないため、他デバイスへ削除指示は飛ばずローカルファイルは保持される。Owner: suzuki.junya |
| R-08 | `~/Sync` 配下の git リポジトリは Syncthing のホワイトリスト対象外で、push しない限り他マシンから参照できずディスク障害で失われる | high | 初回コミット前に GitHub リモートを設定し、以後は作業単位で push する。Owner: suzuki.junya |
| R-09 | 署名・公証（Developer ID / notarytool）の証明書とキーの管理を誤ると、秘密情報が公開リポジトリに混入する | high | 証明書と API キーは GitHub Actions の Encrypted Secrets のみに置き、リポジトリの `.gitignore` に `*.p12` `*.p8` `*.mobileprovision` を追加する。値をチャット・コミットに流さない。Owner: suzuki.junya |
| R-10 | シミュレータの削除（`simctl delete unavailable`）が、ユーザーがまだ使う予定のデバイスを消す | medium | `delete unavailable`（実行中の Xcode が対応しないランタイム）のみを Tier A とし、使用中ランタイムのデバイス削除は Tier B に置き、対象デバイス名を一覧表示してから実行する。Owner: suzuki.junya |
| R-11 | Q: 隔離庫の TTL 満了時に、対象が巨大（数十 GB）で削除に時間がかかり、次回の `disclean` 起動が遅くなる | low | 失効処理は起動時に 1 回・非同期で行い、完了を待たずにコマンド本体を進める設計にするか検討する。v1.0 では同期実行とし、実測が 5 秒を超えたら非同期化する。Owner: suzuki.junya |
| R-13 | 「究極にポップ」な見た目が、ファイルを削除するツールの信頼性を損なう（ふざけていると受け取られる） | high | ポップさを色・質感・動きに限定し、リスク情報（何を失うか・取り消せるか・触らないもの）は装飾せず最高コントラストの本文で書く（`docs/design-system.md` §1.1 の禁則）。LP の S-27「触らないもの」節は意図的に装飾を落とす。MQ-9 で目視確認する。Owner: suzuki.junya |
| R-14 | レバーのドラッグ操作が、支援技術利用者・トラックパッド以外の入力手段の利用者を排除する | high | キーボードのみで同じ確認シートに到達できる経路を必須とし（D-05）、`prefers-reduced-motion` 有効時は単一クリックに切り替える（D-06）。XCUITest / Playwright で自動検証する。Owner: suzuki.junya |
| R-15 | GUI（Swift）と LP（CSS）でデザイントークンが分岐し、時間とともに別物になる | medium | 両者の値を突合する AT-014 を CI ゲートにする。値の変更は `docs/design-system.md` を先に更新してから両実装へ反映する。Owner: suzuki.junya |
| R-16 | LP のヒーローが「ユーザーのマシンを診断している」と誤解される | medium | デモは実測の静的データであることをヒーロー内に Caption で明示し、計測日と機種を併記する（NG11, F-16）。Owner: suzuki.junya |
| R-17 | 同梱フォントのライセンス表示漏れ（OFL は著作権表示とライセンス全文の同梱を要求する） | medium | OFL 全文を `Disclean.app/Contents/Resources/LICENSES/` に含め、README にクレジットを書くことを DoD のチェック項目にする。Owner: suzuki.junya |
| R-18 | 日本語 Web フォント（Zen Maru Gothic）の CJK サブセットが 49 ファイル・663KB あり、LP の初回転送量の 97% を占める | medium | 実測に基づき目標を 700KB に設定し直した（当初の 400KB は測定前の想定で、到達不能だった）。`font-display: swap` でフォールバック書体により本文を先に読ませる。これ以上削るには日本語をシステムフォント（Hiragino Maru Gothic ProN）に切り替える必要があり、その場合 GUI と LP の見た目が環境により分岐する。v1.0 では Web フォントを維持する。Owner: suzuki.junya |
| R-19 | 配信元（GitHub アカウント / リリースアセット）が侵害され、悪意あるルールが配られる | high | 署名検証（Ed25519、公開鍵はバイナリ埋め込み）を必須にし、TLS と GitHub の信頼に依存しない。さらに削除対象を拡大する差分は承認必須（F-17）で、承認画面に「新たに削除対象になるパス」を実サイズ付きで表示する。禁止パス検証（SG-01〜SG-04）は更新カタログにも同一に適用する。Owner: suzuki.junya |
| R-20 | 署名用の秘密鍵を紛失・失効させると、以後どの利用者にもカタログを配れなくなる | high | 鍵は GitHub Actions の Encrypted Secrets に置き、オフラインバックアップを別媒体に 1 部保持する。`release-keys.json` は複数鍵（`keyId` + `validFrom`）を保持でき、「新鍵入りの本体を先にリリース → 旧鍵の署名を停止」の順でローテーションする。復旧不能時の最終手段は本体の再リリース（Homebrew 経由で届く）。Owner: suzuki.junya |
| R-21 | 更新の差し止め（古いカタログに留められる） / 巻き戻し（脆弱な旧版の再配信） | medium | `catalogVersion` の単調増加と `publishedAt` の逆行拒否で巻き戻しを、manifest の `expiresAt`（発行 +90 日）で差し止めを検知する。期限切れは「配信が 90 日以上止まっています」と警告表示する。CI の週次ジョブで残日数 30 日を切ったら再署名・再公開する。Owner: suzuki.junya |
| R-22 | 「ネットワーク通信をしないツール」という既存の公開文言と、更新機構の実装が食い違う（利用者を欺く） | high | **2026-08-20 対応**。NG6 を「更新の取得のみ例外」に改訂し、LP の FAQ・README・初回実行時の案内に「通信すること・送る情報・止め方」を明記する。DoD に旧文言の残存チェックを入れた（§11.1 Documentation）。Owner: suzuki.junya |
| R-23 | 自動更新の承認プロンプトが頻繁に出て、利用者が内容を読まずに承認する習慣がつく | medium | 承認が要るのは拡大差分のみ（縮小・中立は自動）。配信側は「OS 追随などの実質的な変更があるときだけ `catalogVersion` を上げる」運用とし、文言修正だけの更新で承認を求めない。承認画面は差分のみを見せ、変更のないルールを並べない。Owner: suzuki.junya |
| R-24 | 更新チェックの失敗（オフライン・プロキシ・企業ネットワーク）がコマンド本体の失敗に見える | medium | チェックは並行実行し完了を待たない。失敗は終了コードに影響させず、`--verbose` 指定時のみ stderr に 1 行出す。WS-o と MQ-15 でオフライン動作を検証する。Owner: suzuki.junya |
| R-25 | Q: 本体の自動ダウンロード（数十 MB）が従量課金・低速回線の利用者に負担となる | low | v1.0 では本体は「通知のみ、要求時に取得」とし、既定で自動ダウンロードしない（F-18）。カタログ（数十 KB）のみ自動取得する。将来 `NWPathMonitor` の `isExpensive` を見て制御するかは v1.1 以降で判断する。Owner: suzuki.junya |
| R-12 | Q: OrbStack / Colima / Docker Desktop が併存する環境で、どのコンテキストのキャッシュを対象にするか判別できない | medium | v1.0 では `docker context ls` の現在アクティブなコンテキストのみを対象とし、他コンテキストは Tier C レポートにサイズだけ表示する。Owner: suzuki.junya |

## 13. Assumptions

- **A-01**: 対象マシンは APFS ボリューム上で動作し、ホームディレクトリと `$DISCLEAN_STATE_DIR` が同一ボリュームにある。異なる場合は `cross-volume` として全項目がスキップされる。
- **A-02**: `~/.local/state/disclean` と `~/.config/disclean`（XDG 準拠のパス）を既定の状態・設定ディレクトリとして使う。macOS 慣例の `~/Library/Application Support` は使わない（CLI 利用者の可視性を優先）。
- **A-03**: 実測データ（CoreSimulator 71.5GB / Docker 26.6GB / `~/.cache` 9.7GB / `~/.colima` 10.0GB / `~/.ollama` 6.5GB）は 2026-08-20 時点の対象マシンの状態であり、他の環境や将来時点では異なる。目標 M4（60GB 回収）はこの実測環境に対する値。
- **A-04**: `~/.Trash` `~/Downloads` `~/Documents` `~/Desktop` は TCC によりフルディスクアクセスなしでは測定できない（実測で `Operation not permitted` を確認済み）。これらは Tier C（表示のみ）に置く。
- **A-05**: 隔離庫は同一ボリューム内の `rename` で実装するため、移動自体は対象サイズによらず短時間で完了する。
- **A-06**: Tier A の `simctl delete unavailable` は、現在の Xcode が対応しないランタイムのデバイスのみを削除する。実測環境の 71.5GB のうち回収可能量はこの判定結果に依存し、確定値ではない。
- **A-07**: GUI（`Disclean.app`）は App Sandbox を無効にしてビルドする。サンドボックス下では他プロセスのキャッシュディレクトリへアクセスできないため。Mac App Store での配布は行わない。
- **A-08**: リリースには Apple Developer Program の有効なメンバーシップ（Developer ID 証明書の発行に必要）があることを前提とする。無い場合、公証なしの配布となり、利用者は Gatekeeper の警告を手動で解除する必要がある。
- **A-09**: ルール JSON のスキーマは v1.0 で `schemaVersion: 1` とし、破壊的変更を伴う場合のみ版数を上げる。
- **A-15**: 「ディスクリン」と `disclean` を、表示名と識別子として使い分ける（§7 Naming）。GitHub アカウントは実在の `suzuki-junya108`（要件初版に書いた `suzuki-junya` は存在しなかったため 2026-08-20 に修正）。2026-08-20 時点で `disclean` は Homebrew core（formula / cask とも）、npm、`github.com/suzuki-junya` のいずれにも存在せず取得可能であることを確認済み。GitHub 全体には無関係の類似名リポジトリが 9 件あるが、tap 名前空間はアカウント単位のため衝突しない。
- **A-14**: LP の転送量目標（700KB）は 2026-08-20 に Playwright で実測した 679KB に基づく。フォントのサブセット構成が変われば再計測が必要。
- **A-11**: 「究極にポップ」という要求を、`docs/design-system.md` の HEAVY CANDY（物理的な塊・キャンディ色・黒キーライン・ハードオフセット影・レバーと瓶）として具体化した。この解釈が意図と異なる場合、修正対象は同ドキュメントのトークンとシグネチャー定義であり、機能要件（§4）には影響しない。
- **A-12**: LP は GitHub Pages の無料枠で配信し、独自ドメインを使わない（`https://suzuki-junya.github.io/disclean/`）。独自ドメインを使う場合は DNS 設定と証明書の手順が追加になる。
- **A-13**: LP のヒーローに表示する実測値は 2026-08-20 の対象マシンの値であり、訪問者の環境を表さない。数値を更新する場合は計測日と機種の表記も同時に更新する。
- **A-16**: 更新の信頼の起点はバイナリに埋め込んだ Ed25519 公開鍵であり、TLS・GitHub・CDN のいずれも信頼しない前提で設計する。エンドポイント（`DISCLEAN_UPDATE_ENDPOINT`）は差し替え可能だが、署名検証を無効化する手段は提供しない。
- **A-17**: 利用者は 24 時間に 1 回以上 `disclean` を実行するとは限らない。カタログの到達は「次に実行したとき」であり、緊急の revocation でも即時性は保証されない。即時性が要る事象（重大な誤削除ルール）は、revocation の公開と同時に GitHub Release・LP で告知する。
- **A-18**: 自動更新が届くのは同梱カタログ由来のルールのみで、`rules.d` のユーザー定義には一切触れない。ユーザーが同じ `id` で上書きしているルールは、更新後もユーザー定義が優先される（利用者が自分で消さない限り、更新の恩恵も受けない）。
- **A-10**: 「7 日」という TTL の既定値は、誤削除に気づくまでの猶予として設定した値であり、実データに基づく最適値ではない。`DISCLEAN_QUARANTINE_TTL_DAYS` と GUI 設定で 1〜90 日に変更できる。
