# 更新プロトコル（カタログ配信）

掃除ルールだけを、本体を入れ替えずに配るための仕組みです。
信頼の起点は**バイナリに埋め込んだ Ed25519 公開鍵**であり、TLS も GitHub も信頼しません。

## 配信物

| ファイル | 内容 |
|---|---|
| `catalog-manifest.json` | 版数・有効期限・各ファイルの sha256・無効化リスト・本体の最新版（署名対象のバイト列そのもの） |
| `catalog-manifest.json.sig` | 上のファイルに対する Ed25519 detached 署名（base64） |
| `catalog-<catalogVersion>.tar.gz` | `rules/*.json` を収めたアーカイブ |

配信元は GitHub Releases の `latest/download/`。許可ホストは `github.com` と
`objects.githubusercontent.com` のみで、他へリダイレクトされたら中止します。

## manifest の形

```json
{
  "schemaVersion": 1,
  "catalogVersion": 3,
  "publishedAt": "2026-08-20T22:00:00.000+09:00",
  "expiresAt": "2026-11-18T22:00:00.000+09:00",
  "minDiscleanVersion": "0.1.0",
  "keyId": "disclean-2026a",
  "archive": { "name": "catalog-3.tar.gz", "sha256": "…", "bytes": 12345 },
  "files": [ { "name": "10-package-managers.json", "sha256": "…", "bytes": 2345 } ],
  "revocations": ["broken-rule-id"],
  "latestApp": {
    "version": "0.2.0",
    "minMacOS": "14.0",
    "assets": [ { "name": "Disclean-0.2.0.dmg", "url": "https://…", "sha256": "…", "bytes": 1234567 } ]
  }
}
```

## 受信側の判定順序

1. 署名検証（`keyId` に一致する埋め込み公開鍵で Ed25519 検証）
2. `catalogVersion` が適用済みより大きいこと（**巻き戻し拒否**）
3. `publishedAt` が適用済みより新しいこと
4. `expiresAt` が未来であること（**差し止め検知**。発行から 90 日）
5. `minDiscleanVersion` が自分のバージョン以下であること
6. アーカイブと各ファイルの sha256 一致
7. 同梱ルールと**同じ検証**（スキーマ・禁止パス）を通ること

1 つでも満たさなければ適用せず、監査ログに理由を残して終了コード 7 を返します。

## 差分の分類と承認

| 分類 | 例 | 適用 |
|---|---|---|
| 拡大 | ルール追加 / パス追加 / Tier 引き上げ / コマンド変更 / 最小日数の短縮 / OS 範囲の拡大 | **承認必須** |
| 縮小 | ルール削除・無効化 / パス削除 / Tier 引き下げ / 最小日数の延長 / OS 範囲の縮小 | 自動適用 |
| 中立 | 表示文言・`verifiedOn` の変更 | 自動適用 |

承認までは `staged` に留まり、`active` は切り替わりません。

## 配信手順（リリース時）

```bash
# 1. 鍵を作る（最初の 1 回だけ。秘密鍵は絶対にコミットしない）
swift run disclean-catalog keygen --out ~/.disclean-keys --key-id disclean-2026a

# 2. 公開鍵をバイナリに埋め込む
cp ~/.disclean-keys/disclean-2026a.release-keys.json \
   Sources/DiscleanKit/Resources/release-keys.json

# 3. カタログを作って署名する（catalogVersion は単調増加させる）
swift run disclean-catalog build \
  --rules-dir Sources/DiscleanKit/Resources/rules \
  --out-dir dist/catalog \
  --catalog-version 2 \
  --key-file ~/.disclean-keys/disclean-2026a.private.key \
  --key-id disclean-2026a \
  --min-disclean-version 0.1.0 \
  --app-version 0.1.0

# 4. 検証してから Release に添付する
swift run disclean-catalog verify \
  --manifest dist/catalog/catalog-manifest.json \
  --keys Sources/DiscleanKit/Resources/release-keys.json
gh release upload v0.1.0 dist/catalog/*
```

## 緊急のルール停止（revocation）

誤ったルールを配ってしまったら、`--revoke <ruleId>` を付けた新しい manifest を公開します。
無効化は「消す対象が減る」方向なので、利用者の承認を待たずに次回実行時へ届きます。
ただし**利用者がコマンドを実行するまで届かない**ため、重大な事象では Release と LP でも告知します。

## 鍵のローテーション

1. 新しい鍵を作り、`release-keys.json` に**追加**した本体をリリースする（旧鍵も残す）
2. 十分に普及したら、新鍵での署名に切り替える
3. さらに時間をおいてから旧鍵を `release-keys.json` から外す

新鍵だけを配ると、旧バージョンの利用者が更新を受け取れなくなります。順序を守ってください。

## 運用上の注意

- 秘密鍵は GitHub Actions の Encrypted Secrets とオフラインの控えにだけ置きます
- `expiresAt` の残りが 30 日を切ったら、内容が同じでも再署名して公開し直します
- 文言だけの修正で `catalogVersion` を上げると、利用者に無用な承認を求めることになります（拡大差分が無ければ自動適用なので実害はありませんが、更新の頻度は必要な時だけに保ちます）
