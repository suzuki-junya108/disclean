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
| `paths` | string[] | `directory` では必須（`pathsFrom` があれば不要） | 対象パス。`~` 展開可。`*` `?` のひな形も書ける（下記） |
| `pathsFrom` | PathsFrom | | 対象の場所を**ツール自身に聞いて**決める。`{"command": CommandSpec, "subpaths": [String]}` |
| `command` | CommandSpec | `command` では必須 | 実行する外部コマンド |
| `sizeProbe` | CommandSpec | | 対象量の推定に使うコマンド |
| `detect` | CommandSpec | | ツールの有無を判定するコマンド |
| `minAgeDays` | int | | **最後に使われてから**この日数を過ぎたものだけを対象にする。判定はフォルダの中身（ファイルの更新時刻の最大）で行い、入れ物自身の更新時刻は見ない |
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

### ひな形（`*` と `?`）

キャッシュは「機械ごとに変わる ID」の下に置かれることがあります（シミュレータの端末 ID、
アプリのコンテナ ID など）。決め打ちで書くとその 1 台でしか当たらないため、ひな形で書けます。

```json
"paths": [
  "~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Library/Caches"
]
```

規則は次のとおりです。

- `*` `?` は **1 階層の中だけ**に効きます。`**`（階層をまたぐ）は用意しません
- `*` は隠し項目（`.` で始まる名前）に当たりません。当てたいときは `.*` のように書きます
- **途中の段がリンクなら、その先へは進みません**。当たった先がリンクなら対象にしません
- ワイルドカードより前の固定部分は、カタログ検証のときに検査します（`~/*` のような浅いひな形は拒否）
- 広げた 1 つ 1 つも、同梱ルールと同じ検証（ホーム配下・深さ 2 以上・除外に入っていない）を通します
- 1 本のひな形から広げるのは 4096 か所までです。**上限に達した場合は「上限まででまとめています」と表示します**（黙って減らしません）

### PathsFrom — 場所をツールに聞く

キャッシュの置き場所はツールと環境で変わります（`~/.cache/uv` / `~/Library/Caches/Homebrew` / `~/.npm/_cacache` …）。
決め打ちにすると環境ごとに外れるため、ツールに聞いた場所を対象にします。

```json
"pathsFrom": {
  "command": { "executable": "npm", "arguments": ["config", "get", "cache"] },
  "subpaths": ["_cacache"]
}
```

標準出力の 1 行目をパスとして扱い、`subpaths` があればその下を対象にします。

`paths` を併記した場合、それは**ツールが答えられなかったときの控え**になります。実際に
npm 10 は `npm config get cache` を「保護された項目」として拒みます。ツールが答えない・
答えが範囲外だった場合に限り、`paths` に書かれた既定の場所を（実体があるときだけ）使います。
控えも同じ検証を通します。控えが無い、または実体が無ければ、対象にしません。

**ツールの答えは無条件には信じません。** 返ってきたパスにも、同梱ルールとまったく同じ検証
（ホーム配下・深さ 2 以上・システム領域でない・除外に入っていない）を通します。通らなければ
`skipped(reason: "forbidden-root")` として対象から外します。

### なぜ外部ツールに任せず、自分で移すのか

`uv cache prune` や `npm cache clean` のようなコマンドは、**ツールごとに「何を消すか」が違います**。
実測では、3.1GB ある uv のキャッシュに対して `uv cache prune` が消したのは 0 バイトでした
（prune は「どの環境からも参照されていない分」だけを消すため）。一方、一覧にはキャッシュ全体の
大きさを出していたので、見せた量と実際に減る量が大きく食い違っていました。

そこで v0.2.0 から、これらのキャッシュは **ディスクリン自身が隔離庫へ移します**。

- 見せた量と動かす量が必ず一致する
- **7 日間は元に戻せる**（外部コマンドは取り消せない）
- ツールごとの `prune` / `clean` の違いに左右されない

ツールは、次に使うときにキャッシュを作り直します。

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
