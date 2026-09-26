# Kageboshi

主人公と影が上下の画面で同期し、光源でずれる横スクロールアクション (Godot 4.7 / Steam)。仕様・スコープは [documents/PROJECT.md](documents/PROJECT.md) を参照 (SSOT)。

## 制約

- C# (.NET 版 Godot) を導入しない。レンダラを GL Compatibility から変えない。サーバー・計測 SDK を追加しない。Steamworks SDK (GodotSteam 等) は別 ADR で決めてから追加する (根拠: [ADR 0001](documents/adr/0001-godot-gdscript-steam-desktop-no-backend.md))

## 検証方法

ビルド・Godot の起動 (headless を含む)・描画付きの撮影は、開発マシンの負荷を避けるため、このマシンでは実行せず GitHub Actions (`.github/workflows/ci.yml`) に任せる。本リポジトリは public のため Actions の Linux ランナーを使う。private リポジトリへ変える場合は、描画を伴う動作確認を Devin のセッションで行う (devin-macos-e2e skill)。simtunnel は iOS Simulator 用のため本プロジェクトでは使わない。

- このマシンで実行してよいのは `make lint` (gdlint) だけ。ユーザーが明示的に頼んだ時と、人が遊んで確かめる `make run` はこの限りでない
- 変更は push して PR を開き、CI の結果で成否を判断する。`gh pr checks <PR 番号> --watch` で完了を待ち、失敗したら `gh run view <run ID> --log-failed` と artifact `kageboshi-check-logs` の `tmp/*.log` を読む
- 見た目の確認は artifact `kageboshi-screenshot-and-movie` を `gh run download <run ID> -n kageboshi-screenshot-and-movie -D tmp/artifact` で取得し、PNG と、mp4 の末尾のフレーム (`ffmpeg -sseof -1 -i tmp/artifact/movie.mp4 -frames:v 1 tmp/artifact/movie-last.png`) を目視してから完了報告する

各 target の内容と成功条件 (CI が実行する。`GODOT` 未指定時の既定は macOS の `/Applications/Godot.app/Contents/MacOS/Godot`、CI では Linux バイナリを渡す):

| 目的 | コマンド | 成功条件 |
|---|---|---|
| lint | `make lint` (`gdlint scripts/`) | exit 0 |
| アセットインポート (初回・素材追加後) | `make import` | exit 0 (ログは `tmp/import.log`) |
| 起動検証 (メインシーン・スクリプトのロード) | `make check` | exit 0 かつ `tmp/check.log` に `kageboshi boot` が出力され、WARNING / ERROR 行がない |
| ロジック検証 (移動・スクロール・攻撃・敵・体力・同期ボーナスの計算、画面の遷移表、入力割り当て、設定と進行の保存・読み込みと壊れた保存データの扱い、全シーンのロード、BGM の繰り返しと BGM・効果音を鳴らす音量のバス、全素材が `assets/CREDITS.md` に記録されていること) | `make selfcheck` | exit 0 かつ `tmp/selfcheck.log` に `selfcheck OK` が出力され、WARNING / ERROR 行がない |
| 入力統合テスト (キー入力で主人公を動かし、地形との当たり判定・スクロール、影が同じ動き・同じ攻撃をすること、敵を倒す・被弾・ゲームオーバー・同期ボーナス、タイトル・ポーズ・リトライ・ステージクリア・設定の画面の遷移と、設定画面での音量・キー割り当ての変更と保存、BGM がプレイ中だけ鳴ることと攻撃・ダメージ・同期ボーナス・影縫いの効果音を確認) | `make integration` | exit 0 かつ `tmp/integration.log` に `integration OK` が出力され、WARNING / ERROR 行がない |
| headless 検証の一括実行 (lint → check → selfcheck → integration) | `make test` | exit 0 |
| スクリーンショット (タイトル・プレイ開始・ジャンプ・段差・スクロール・ポーズ・敵・同期ボーナス・ゲームオーバー・ステージクリア・クリアを保存したタイトル・設定画面・壊れた保存データの知らせの見た目。headless の検証では見た目の崩れを検出できない) | `make screenshot` | exit 0 かつ `tmp/screenshot-*.png` が生成される |
| 起動の録画 (操作なしの起動〜タイトルの表示。起動直後の描画崩れ・真っ黒を検出する) | `make movie` | exit 0 かつ `tmp/movie.mp4` が生成され、末尾のフレームの輝度平均が基準以上 (ffmpeg が必要) |
| ゲームをエディタなしで起動 (人が遊んで確かめる) | `make run` | ウィンドウが開きメインシーンが表示される |
| デスクトップエクスポート | `make build-macos` / `make build-windows` / `make build-linux` / `make build-all` | exit 0 で `build/<platform>/` に成果物が生成される |

- 画面や状態を追加したら `scripts/dev/screenshot.gd` の `_capture_scenes()` に撮影を足し、入力で変わる振る舞いは `scripts/dev/integration.gd` に検証を足す
- Godot の起動にはすべて `--log-file` を付ける (Makefile の `ENGINE_LOG`)。付けないと Godot が `user://` にログを書こうとし、書き込みを拒否するサンドボックスでは起動に失敗する
- ログは `tmp/*.log` に保存して全文を WARNING / ERROR 検査する (`tail` で切り詰めて判定しない)
- エクスポートには Godot 4.7 の export templates が要る。CI は `.github/actions/setup-godot` が tpz から必要なテンプレートだけを取り出してキャッシュする

## 規約

- コーディング規約は `~/.claude/rules/` の Godot・素材ライセンスの規約と、[.claude/rules/](.claude/rules/) のプロジェクト固有の規約に従う

<!-- ai-review-config begin -->
<!--
このブロックは自動生成です。直接編集せず、テンプレートを更新してから再生成してください。
内容は AI コードレビュー時の挙動指示であり、コードベース自体への規約ではありません。
-->

## レビュー時の応答スタイル

- 応答は日本語で行う

## レビュー範囲外

以下は自動レビューで指摘しない (別の検出経路があるため):

- コンパイルエラー・型エラー (ローカル/CI のビルドで検出される)
- Lint/フォーマット違反 (リンター・フォーマッターで検出される)
<!-- ai-review-config end -->
