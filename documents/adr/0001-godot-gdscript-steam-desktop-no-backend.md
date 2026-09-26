# 0001. Godot 4.7 + GDScript で Steam 向けデスクトップ版を作り、バックエンドを持たない

## Status

Accepted

## Context

上下 2 画面で主人公と影が同期して動く横スクロールアクションを、Steam (PC) で配信する ( https://github.com/bannzai/IdeaMemo/issues/340 )。企画の段階で「Godot で作る」「Steam で配信する」が決まっている。

- リポジトリは public。GitHub Actions の Linux ランナーを無料で使え、macOS ランナーも無料枠の対象になる
- 開発マシン (macOS) の負荷を下げるため、ビルド・描画付きの検証は GitHub Actions で行いたい。Xvfb 上のソフトウェア GL (Mesa llvmpipe) で描画できるレンダラが必要になる
- オンライン機能 (ランキング・アカウント・マルチプレイ) は企画に無い
- Steam での販売は、購入者の契約相手が Valve になる (Steam 利用規約「お客様が、利用権に基づき Steam を介して行うあらゆる取引の相手方は Valve となります」 https://store.steampowered.com/subscriber_agreement/?l=japanese )

## Decision

- エンジンは Godot 4.7 stable、言語は GDScript にする。C# (.NET 版 Godot) は導入しない。.NET 版はエクスポートと CI の準備が増える一方、2D アクションで C# を要する理由がない
- レンダラは GL Compatibility にする。2D で Forward+ の機能を使わず、CI の Xvfb + llvmpipe でも描画できる
- エクスポート先は Windows x86_64 / macOS universal / Linux x86_64 の 3 つ
- バックエンド (DB・ストレージ・認証・サーバー) を持たない。セーブデータはローカル (`user://`) に置く。Analytics は Steamworks の販売・ウィッシュリスト統計を使い、ゲームに計測 SDK を入れない。このため GCP の課金・エラーアラート、Crashlytics のアラート転送は対象外にする
- Steamworks SDK の連携 (GodotSteam 等による実績・クラウドセーブ・Steam Input) は、Steamworks のパートナー登録とアプリ登録の後に別 ADR で決める
- 特定商取引法に基づく表記は用意しない。Steam での販売は購入者の契約相手が Valve のため。Steam 以外で直接販売する判断をした時に見直す
- 法務ドキュメント (プライバシーポリシー・利用規約) と紹介ページは GitHub Pages (`docs/`) に置く

## Consequences

- 良い点: サーバーの運用費・障害対応が無い。検証は Linux ランナーで完結し、開発マシンで Godot を起動しなくてよい
- 悪い点: クラッシュや不具合の報告はユーザーからの連絡 (Steam のコミュニティ・メール) に頼る。GL Compatibility では Forward+ 専用の描画機能 (一部のポストエフェクト・高度なライティング) を使えない。光源と影の表現は 2D のライト (`PointLight2D` / `LightOccluder2D`) かシェーダーで作る
- エージェントへの制約: C# を導入しない。レンダラを GL Compatibility から変えない。サーバー・計測 SDK を追加しない (根拠は本 ADR)。Steamworks SDK の追加は別 ADR を書いてから行う
