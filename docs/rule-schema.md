# ルール JSON のスキーマ

ディスクリンが「何を片づけるか」は、すべて JSON のルール定義で決まります。
コードにハードコードされたルールはありません。

## 置き場所と優先順位

| 出所 | 場所 | 優先度 |
|---|---|---|
| 同梱 | 実行ファイル内のリソース | 低 |
| 自動更新 | `~/.local/state/disclean/updates/active/rules/*.json` | 中 |
| ユーザー | `~/.config/disclean/rules.d/*.json` | **最高** |

同じ `id` があれば、優先度の高い側が**置き換え**ます（マージではありません）。
自動更新がユーザー定義を書き換えることはありません。

## フィールド

| フィールド | 型 | 必須 | 意味 |
|---|---|---|---|
| `id` | string | ✔ | 一意の識別子。kebab-case（`^[a-z0-9]+(-[a-z0-9]+)*$`） |
| `title` | string | ✔ | 英語の表示名 |
| `titleJa` | string | | 日本語の表示名（省略時は `title`） |
| `tier` | `"A"` \| `"B"` \| `"C"` | ✔ | リスク階層。A=既定選択 / B=要確認 / C=表示のみ |
| `kind` | `"directory"` \| `"command"` \| `"report"` | ✔ | 処理方式 |
| `paths` | string[] | `directory` では必須 | 対象パス。`~` 展開可 |
| `command` | CommandSpec | `command` では必須 | 実行する外部コマンド |
| `sizeProbe` | CommandSpec | | 対象量の推定に使うコマンド |
| `detect` | CommandSpec | | ツールの有無を判定するコマンド |
| `minAgeDays` | int | | 最終更新からこの日数を過ぎたものだけを対象にする |
| `requiresQuitApps` | string[] | | このバンドル ID のアプリが起動中ならスキップする |
| `whatIsLost` | string | ✔ | 失うものを 1 文で（英語） |
| `whatIsLostJa` | string | | 同上（日本語。省略時は `whatIsLost`） |
| `manualSteps` | string | Tier C では必須 | 利用者が手で行う手順 |
| `enabled` | bool | | 既定 `true`。`false` で無効化（同梱ルールの打ち消しにも使える） |
| `timeoutSeconds` | int | | 既定 180、最大 900 |
| `minMacOS` | string | | この OS 以上でのみ有効（例 `"14.0"`） |
| `maxMacOS` | string | | この OS 以下でのみ有効（例 `"26.99"`） |
| `verifiedOn` | string | | 最後に実機確認した OS ビルド（例 `"25F84"`） |
| `measure` | MeasureSpec | | `command` 型の対象量の測り方。**これが無いと実行前に量を出せない** |

`CommandSpec` は `{"executable": string, "arguments": string[], "expectSuccess": bool}` です。
`executable` は絶対パスか PATH 上の名前。**シェルは経由しません**（`/bin/sh -c` に渡しません）。

### MeasureSpec — 外部ツールに任せる項目の量を測る

`command` 型は「実行してみるまで分からない」になりがちですが、それでは利用者が実行前に判断できません。
`measure` を書くと、**実行前の見積もり**と**実行後の実測（前後の差）**の両方に同じ方法が使われます。

| kind | 意味 | 例 |
|---|---|---|
| `paths` | 決め打ちのパスを測る | `{"kind":"paths","paths":["~/Library/Caches/foo"]}` |
| `commandPath` | コマンドの標準出力をパスとして扱い、そのディレクトリを測る | `{"kind":"commandPath","command":{"executable":"brew","arguments":["--cache"]}}` |
| `dockerReclaimable` | `docker system df` の「回収可能」量を読む | `{"kind":"dockerReclaimable","command":{"executable":"docker","arguments":["system","df","--format","{{json .}}"]}}` |
| `simctlUnavailable` | 対応ランタイムが無いシミュレータのデバイスだけを測る | `{"kind":"simctlUnavailable","command":{"executable":"/usr/bin/xcrun","arguments":["simctl","list","devices","--json"]}}` |

- 測った結果が **0 バイトなら、そのルールは `skipped(reason: "empty")` になり実行されません**（空のキャッシュを掃除しに行かない）。
- `measure` を持たないルールは「不明」として表示され、**0 バイトとは区別されます**（合計には「＋ 実行後に判明する N 件」と添えます）。

## 受け付けられない定義（読み込み時に拒否されます）

- `/` `/System` `/Library` `/private/var` `/usr` `/bin` `/sbin` `/Applications` 配下のパス
- ホームディレクトリの外のパス（`directory` 型）
- ホーム直下から 1 階層しかないパス（例 `~/Library`）
- 設定・状態ディレクトリ自身（自分の隔離庫を消さないため）
- 除外パス（既定 `~/Sync`）の配下
- Tier C なのに `kind` が `report` でない、または `manualSteps` が空
- `timeoutSeconds` が 1〜900 の外
- 同一ファイル内で `id` が重複している

拒否されたルールは一覧に出ず、`disclean rules validate` が理由付きで報告して終了コード 5 を返します。

## 例

```json
[
  {
    "id": "my-app-cache",
    "title": "MyApp cache",
    "titleJa": "MyApp のキャッシュ",
    "tier": "A",
    "kind": "directory",
    "paths": ["~/Library/Caches/com.example.myapp"],
    "requiresQuitApps": ["com.example.myapp"],
    "minAgeDays": 3,
    "whatIsLost": "Cached thumbnails; regenerated on next launch.",
    "whatIsLostJa": "サムネイルの一時データ。次回起動時に作り直されます。",
    "minMacOS": "14.0",
    "verifiedOn": "25F84"
  }
]
```

同梱ルールを打ち消すには、同じ `id` で `"enabled": false` を書きます。

```json
[{ "id": "user-caches", "title": "off", "tier": "B", "kind": "report",
   "paths": ["~/Library/Caches"], "whatIsLost": "-", "manualSteps": "-", "enabled": false }]
```

## OS が変わったとき

`minMacOS` / `maxMacOS` の範囲外になったルールは自動的に対象から外れ、`disclean doctor` の
`rulesDisabledByOS` に理由付きで並びます。OS のビルド番号が変わると、スキャンキャッシュを捨てて
対象パスの存在を測り直し、「この OS で見つからなくなったルール」を報告します。
