> 責務: 背景・問題（§1）— 何が壊れている / 不足しているのか、現状ワークフロー、なぜ今やるかを書く。
> 親: ../REQUIREMENTS.md

## 1. Background & Problem

### 1.1 Problem Statement

既存の `~/Sync/disclean/mac_cleanup.sh`（233 行の bash スクリプト）は、確認・記録・復元の手段を持たないまま固定パスを再帰削除する。2026-08-20 に対象マシン（macOS 26.5.2 / Apple M4 / 460GB SSD）で実測した結果、このスクリプトが削除しに行く対象の実サイズは合計 2GB 未満である一方、実際に容量を占有しているのは同スクリプトが扱えない領域だった。

| 場所 | 実サイズ（2026-08-20 実測） | 既存スクリプトの扱い |
|---|---|---|
| `~/Library/Developer/CoreSimulator/Devices` | 71.5 GB（40 台、最大の 1 台が 44.3 GB） | 対象外（削除するのは 0GB の `CoreSimulator/Caches`） |
| `~/Library/Containers/com.docker.docker` | 26.6 GB（`Docker.raw` はスパースファイル、見かけ 460GB） | `docker system prune -af --volumes` を実行 |
| `~/.colima` | 10.0 GB | 対象外 |
| `~/.cache` | 9.7 GB（uv 3.2 / HuggingFace 1.9 / whisper 1.5 / whisper-cpp 1.5 / codex-runtimes 1.5） | 対象外 |
| `~/.ollama` | 6.5 GB（LLM モデル） | 対象外 |
| `~/.rustup` / `~/.nvm` / `~/.npm` | 1.6 / 1.3 / 1.4 GB | `~/.npm` のみ対象 |
| `~/Library/Caches` | **0.1 GB** | ディレクトリ全体を再帰削除 |
| `~/Library/Logs` / DerivedData / Archives / iOS DeviceSupport | **各 0 GB** | ディレクトリ全体を再帰削除 |
| `~/.Trash` / `~/Downloads` / `~/Documents` / `~/Desktop` | **測定不能**（TCC により `Operation not permitted`） | 削除したことにして通過する |

確認された欠陥は以下の 8 点。

1. **サイレント失敗**: 全コマンドが `2>/dev/null` で標準エラーを捨てるため、TCC に阻まれて 1 バイトも消していない `~/.Trash` に対しても「🗑 Trash」と表示される。実測で `Operation not permitted` を確認済み。
2. **復元手段なし**: `rm -rf` を直接実行し、削除ログも残さない。何を消したか後から確認できない。
3. **効果の誤帰属**: `df -h` の前後差を成果として表示するが、macOS の CacheDelete による purgeable 領域の解放でこの値は単独で変動する（本調査中に、disclean と無関係に空きが 29GiB → 46GiB に変化した）。
4. **再取得コストの無視**: 「キャッシュ」と名の付くディレクトリを一律削除する設計のため、`~/.cache/huggingface`（1.9GB）や `~/.cache/whisper`（1.5GB）のような再ダウンロードに時間のかかるモデル群を無警告で消す構造になっている。
5. **Xcode Archives の全削除**: Archives には配布済みアプリの dSYM が含まれ、削除するとリリース版のクラッシュログを記号化できなくなる。
6. **コンテナボリュームの扱い**: `docker system prune -af --volumes` を無確認で実行する。Docker Engine 29.4.0 では `--volumes` の対象は匿名ボリュームに限られるが、`-a` によるイメージ全削除と全ビルドキャッシュ削除は再構築コストを伴い、確認も記録もないまま実行される。
7. **未定義変数への無防備**: `$HOME` が空のとき `"$HOME/Library/Caches"` は `/Library/Caches` を指し、システム領域を削除しに行く。
8. **選択の余地がない**: 起動したら 7 セクションすべてを無確認で実行する。個別の除外も dry-run もできない。

### 1.2 Current Workflow

容量が逼迫すると `./mac_cleanup.sh` を手動実行する。実行後も空きが増えないため、結局 Finder や `du` を手で叩いて大きなディレクトリを探し、Xcode / Docker / Simulator を個別に開いて手作業で削除している。どこを消したかの記録は残らず、次に容量が減ったときに同じ調査を最初からやり直している。

### 1.3 Why Now

- 対象マシンの Data ボリュームは 460GB 中 377GB 使用（実測時 90〜93%）で、恒常的に逼迫している。
- 容量の 8 割超が「開発ツールが生成した再生成可能データ」であり、正しく分類すれば安全に回収できる。
- 既存スクリプトを使い続ける限り、リスクだけを負って回収量はほぼゼロという状態が続く。
