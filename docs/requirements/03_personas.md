> 責務: ユーザー・ペルソナ表（§3）。プライマリ / セカンダリ含めて全ユーザーをここに集約。
> 親: ../REQUIREMENTS.md

## 3. Users & Personas

| Persona | Role | Tech Literacy | Frequency | Primary Need |
|---|---|---|---|---|
| P1: 開発者本人（オーナー） | iOS/Web 開発者。Xcode・Docker・Colima・Node/Python ツールチェーンを日常的に使う | high | 週 1〜2 回、および容量警告時 | ビルド生成物とシミュレータが占める数十 GB を、Archives や DB ボリュームを壊さずに回収したい |
| P2: OSS 利用者（開発者） | GitHub 経由で導入する他の macOS 開発者。環境構成は P1 と異なる（Docker 未使用、Xcode 未導入など） | high | 月 1 回程度 | 自分の環境に存在するツールだけが対象になり、無いものは「未検出」と明示されてほしい |
| P4: LP 訪問者（導入検討者） | GitHub / SNS 経由で LP に到達した macOS ユーザー。まだ disclean を信用していない | mid〜high | 1 回（導入判断時） | 「自分のファイルを消させて大丈夫か」を数十秒で判断したい。取り消せる範囲と、触らないものを知りたい |
| P3: 非開発者（GUI 利用者） | 家族・同僚など。ターミナルを使わず Disclean.app のみ利用 | low | 月 1 回程度 | 何が消えるのか・元に戻せるのかが日本語で読めて、危険な操作が最初から選択されていないこと |
