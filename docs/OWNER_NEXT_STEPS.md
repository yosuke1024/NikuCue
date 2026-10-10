# macOS で行う確認手順（この環境では未実施）

このリポジトリは Linux 上で書かれ、iOS 側は一度もコンパイルされていない。最初に macOS で以下を順に実行し、結果を `docs/IMPLEMENTATION_LOG.md` に追記する。

## 1. 環境と scheme の確認

```sh
xcodebuild -version                       # Xcode 26 以降（App Store 提出要件、2026-04-28〜）
xcrun simctl list devices available       # 使う Simulator の UDID を控える
xcodebuild -list -project NikuCue.xcodeproj
```

プロジェクトは `tools/xcodeproj/generate_pbxproj.py` が生成した Xcode 16 形式（同期フォルダ）。Xcode で開けない場合は、まず `python3 tools/xcodeproj/validate_pbxproj.py` を実行し、エラー内容を記録してから `project.pbxproj` を修正する（修正内容は生成スクリプトにも反映する）。

## 2. Domain テスト（macOS でも同じ）

```sh
cd Packages/NikuCueDomain && swift test
```

## 3. アプリのビルドとテスト

```sh
xcodebuild test -project NikuCue.xcodeproj -scheme NikuCue \
  -destination 'platform=iOS Simulator,id=<CONFIRMED_UDID>' 2>&1 | tee build-test.log
```

コンパイルエラーが出た場合は、ファイル単位で修正し、修正した箇所を実装ログの「レビュー指摘」に残す。警告のうち Swift 6 言語モードに関するものは `SWIFT_VERSION` を 6 にする前に順次解消する。

## 4. 猫の実機確認（G1）

1. Debug ビルドを Simulator / 実機で起動 → Home 右上「Gallery」（Debug のみ）で 8 クリップと 5 表情を再生。
2. 画面録画（30 秒以上: 待機 → なでる → できた → 休む → 節目）を `artifacts/P01/` に保存。ブラウザ描画のファイルと混同しないよう `simulator_` を接頭辞にする。
3. 設定の「動きを減らす」と iOS の「視差効果を減らす」で跳躍とハートが止まることを確認。
4. 30 fps 設定で Instruments（Time Profiler / Allocations）10 分表示、なで続け 1 分で action 数が増えないこと（Gallery の Active actions 表示）。

## 5. StoreKit / 広告（Mock → 公式テスト設定）

- `NikuCue/Resources/NikuCue.storekit` は scheme に添付済み。product ID は placeholder。App Store Connect で製品を作ったら `AppConfiguration.swift` と `.storekit` の ID を置き換える。
- Google Mobile Ads SDK: 公式 Quick Start で現行の安定版と SPM の追加方法を確認し、パッケージを追加 → `Package.resolved` をコミット → `GADApplicationIdentifier` を `INFOPLIST_KEY_GADApplicationIdentifier` としてビルド設定に追加 → `GoogleMobileAdsAdapter.swift` が `#if canImport(GoogleMobileAds)` で有効化される → SDK の privacy manifest を確認して `AppContainer` の `sdkPrivacyConfigurationVerified` を true にする。確認するまで広告は出ない。
- テストは必ず公式テスト広告 ID / 登録済みテスト端末で行う。

## 6. 公開前

`spec/RELEASE_BLOCKERS.md` の R01〜R14 と `docs/QA_STATUS.md` の not_run を解消する。`scripts/check_release_config.sh` が通らない限り Release ビルドは失敗する。
