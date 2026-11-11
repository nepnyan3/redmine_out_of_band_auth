# Redmine 7.0 移行・認証検証

検証日: 2026-11-11。OpenAI Codex による検証・再現テスト作成。

## 結論

**Redmine 3.4.13 + 旧プラグイン 1.0.0 で実際にメール認証済みのユーザーは、今回の修正を含む Redmine 7.0.3 + プラグイン 2.0.0 へ DB を移行後、同じユーザー ID・ログイン名・パスワード・メールアドレスで認証できた。再登録・再有効化は不要だった。**

旧メールコードと旧ログインセッションは引き継がない。移行後のログインで新しく送られるコードを使用する。

## 実施環境・対象

| 項目 | 旧環境 | 新環境 |
| --- | --- | --- |
| Redmine | 3.4.13.stable | 7.0.3.stable |
| Rails | 4.2.11.1 | 8.1.4 |
| Ruby | 2.4.10 | 4.0.9 |
| Plugin | 1.0.0, `45e8c909baef2df161d23f5648ef95844f8e3507` | 2.0.0, `74c9761486f4894d11419426f4d144f3e497c73d` + 今回のローカル修正 |
| DB | SQLite | 同じ SQLite DB の隔離コピー |

- 旧公式イメージ: `redmine:3.4.13@sha256:3827122e3c22810ed3c93cdeb0ec45f2f9c42e40447629c73f8c82a5c262f46d`
- 新公式イメージ: `redmine:7.0.3@sha256:eff65d7d651d8b07784cbaf37aec5aa74c1ccea3b834e8157e7043c003bdbf70`
- Windows の Docker Desktop Linux コンテナーで実行。テスト中は `--network none`、架空の `example.test` ユーザーのみを使用。
- メールは ActionMailer のテスト配信に捕捉し、外部 SMTP には送信していない。
- 旧 DB は読み取り専用でマウントし、新コンテナー内にコピーしてから移行した。本番データ・既存サービスには変更を加えていない。

## 実旧 DB による認証結果

1. 旧版でユーザーを作成し、旧プラグインの設定を有効化。
2. パスワード認証後に旧 `/out_of_band_auths/login` の確認が必要になることを確認。
3. 不正コードを拒否し、実際のメール本文から取得したコードでログイン成功、My page が HTTP 200。
4. 旧 DB に remember-me / session トークンと未使用の旧コードが存在する状態を保存。
5. Redmine 7 で本体とプラグインを移行。
6. ID、ログイン名、メールアドレス、パスワードハッシュ、salt が一致。
7. 旧有効ユーザーは `twofa_scheme=email`、旧無効ユーザーは未登録のまま。
8. ネイティブ二要素認証が任意に切り替わり、旧 session / remember-me トークンが失効。
9. 旧コードと旧 `verification_code` 列が削除される。
10. 同じパスワードで `/account/twofa/confirm` に進み、元の主メールアドレス宛てに新コードを発行。
11. コード確認前の My account アクセスはログインに戻され、remember-me Cookie も未発行。
12. 不正コードは拒否、正しい新コードで My page が HTTP 200。再有効化は不要。
13. 正しいコードの再利用は拒否。成功後にのみ remember-me Cookie が発行される。
14. ネイティブのバックアップコードによるログインも成功。
15. 旧無効ユーザーは勝手に登録されず、パスワードでログイン可能。

最終結果: `LEGACY_AUTHENTICATION_PASS` / `REAL_LEGACY_UPGRADE_AUTHENTICATION_PASS`。

## 発見し修正した問題

### 本体とプラグインを同じ rake プロセスで移行した場合の設定移行漏れ

修正前は次のように本体・プラグイン移行を連結すると、旧有効ユーザーの `twofa_scheme` が空のまま残ることを実旧 DB で再現した。

```sh
bundle exec rake db:migrate redmine:plugins:migrate
```

本体移行前に読み込まれたモデル情報が残るため、プラグイン移行で `User` と `UserPreference` の列情報をリセットするよう修正した。同一プロセスでの移行も上記全項目が通過した。別々の rake 呼び出しでも修正前から成功することを確認した。

すでに旧対応版で問題の移行を実施済みの場合、このファイル変更だけでは適用済みの移行は再実行されない。移行済み本番 DB を手動で巻き戻さず、事前バックアップから検証用コピーを作り、状態を確認して復旧計画を立てること。

### Windows checkout の CRLF

Windows の自動改行変換で `Gemfile.lock` が CRLF になると、Bundler の frozen モードで「lockfile needs to be updated」となり Docker build が失敗した。`.gitattributes` で shell script と `Gemfile.lock` を LF に固定した。依存バージョンは変更せず、frozen モードのまま build 成功を確認した。

## 既存回帰テスト

修正後の公式イメージベースで次を実行した。

- 20 tests / 144 assertions: failures 0、errors 0、skips 0。
- 旧形式 seed の移行、既存 TOTP の保持、セッション失効: 成功。
- eager loading (`zeitwerk:check`): 成功。
- development のクラス再読み込み: 成功。
- 新規登録・解除、必須 2FA、バックアップコード、期限切れ、再利用拒否、試行回数・再送制限などは既存テストで確認。

## 再現手順

完全な Git 履歴を含む checkout と Docker が必要。shallow clone の場合は旧コミットを取得してから実行する。

```sh
docker build -t redmine-oob-test test/docker
```

Windows PowerShell:

```powershell
.\test\upgrade\run.ps1 -TestImage redmine-oob-test
```

Linux / Bash:

```sh
TEST_IMAGE=redmine-oob-test bash test/upgrade/run.sh
```

旧コミットと旧 Docker イメージは固定済み。ランナーはテスト用コンテナーだけを削除し、生成した架空ユーザーの元 DB と比較用 JSON は表示した一時ディレクトリーに残す。実旧版→新版ランナーは Windows PowerShell で通し実行済み。Bash ランナーは構文検査済みで、GitHub Actions に追加したがリモート CI は未実行。

通常の回帰テスト:

```sh
docker run --rm --network none \
  --mount "type=bind,src=$PWD,dst=/usr/src/redmine/plugins/redmine_out_of_band_auth,readonly" \
  redmine-oob-test bash plugins/redmine_out_of_band_auth/test/run.sh
```

## 検証範囲の制限

- 実移行の組合せは **3.4.13 → 7.0.3、SQLite**。他の旧 Redmine、MySQL、PostgreSQL、本番固有データ・他プラグインとの組合せは未検証。
- SMTP 接続・実メールの到達性、LDAP / SSO の全経路、実ユーザーのメールボックスは未検証。
- HTTP リクエストを Rails Integration Session で実行した認証検証であり、ブラウザーの画面操作そのものを検証したものではない。
- 旧版はサポート終了済みのため、ネットワーク無効の再現検証だけに使用する。
- 本番移行前には DB、添付ファイル、設定・secret key、旧プラグインをバックアップし、実データのコピーでも確認すること。

## English summary

A real Redmine 3.4.13 database was created with legacy plugin 1.0.0. A synthetic user completed the old email challenge using the delivered message body. The same database was copied into Redmine 7.0.3 with plugin 2.0.0 and migrated. The original identity, password hash and email were retained; the user completed the native email second factor without re-enrollment. Legacy sessions and codes were invalidated. The same-process core/plugin migration defect was reproduced and fixed. Existing tests passed: 20 runs, 144 assertions, zero failures/errors/skips. Scope: SQLite and test email delivery, not production SMTP or every old Redmine release.
