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

1. Debug ビルドを Simulator / 実機で起動 → Home 右上「Gallery」（Debug のみ）。表示ラベルが「whole-body textures mali_v1_wholebody (review)」であること（placeholder ではない）。「Poses」の 6 ボタン（idle / happy / celebrate / pet / sleepy / sad）で cross-fade を、8 クリップで動きを確認する。
2. 画面録画（15〜30 秒: 待機 → なでる → できた（celebrate）→ 休む（settle）→ 節目（milestone）→ 夜の部屋で doze）を `artifacts/mali-assets-v1/` に保存。ブラウザ描画のファイルと混同しないよう `simulator_` / `device_` を接頭辞にする。暗い面の確認は Gallery の夜の部屋（`#D3C6D4`）と、ブラウザ記録の `contact_sheet_dark.png` を併用する。
   - 見る点: 耳の先とハートが部屋の上端で切れない、床（前足の下端）が全ポーズで同じ高さ、celebrate の持ち上げが戻る、切替時に顔が歪まない（cross-fade だけ）、`sad` がクリップ中に出ない。
   - 待機の生きている感じ（2026-10-11 追加）: 呼吸（約 3.6 秒）と尻尾の揺れ（約 4.8 秒、±5°）が見えること。尻尾の付け根（腰）に切り口や隙間が見えないか、揺れの途中で「なでる」「できた」を押しても尻尾が跳ねずに戻るか、sleepy で床に見える足が 3 本（口元の手を含めて 4 本）になっているか。
3. 設定の「動きを減らす」と iOS の「視差効果を減らす」で跳躍とハートが止まることを確認。
4. 30 fps 設定で Instruments（Time Profiler / Allocations）10 分表示、なで続け 1 分で action 数が増えないこと（Gallery の Active actions 表示）。

## 5. StoreKit / 広告（Mock → 公式テスト設定）

- `NikuCue/Resources/NikuCue.storekit` は scheme に添付済み（相対パスは Xcode で「Edit Scheme → Run → Options → StoreKit Configuration」から実ファイルが選ばれているか確認し、違っていれば選び直す）。product ID は placeholder。App Store Connect で製品を作ったら `AppConfiguration.swift` と `.storekit` の ID を置き換える。
- Google Mobile Ads SDK: 公式 Quick Start で現行の安定版と SPM の追加方法を確認し、パッケージを追加 → `Package.resolved` をコミット → `GADApplicationIdentifier` を `INFOPLIST_KEY_GADApplicationIdentifier` としてビルド設定に追加 → `GoogleMobileAdsAdapter.swift` が `#if canImport(GoogleMobileAds)` で有効化される → SDK の privacy manifest を確認して `AppContainer` の `sdkPrivacyConfigurationVerified` を true にする。確認するまで広告は出ない。
- テストは必ず公式テスト広告 ID / 登録済みテスト端末で行う。

## 6. 公開前

`spec/RELEASE_BLOCKERS.md` の R01〜R14 と `docs/QA_STATUS.md` の not_run を解消する。`scripts/check_release_config.sh` が通らない限り Release ビルドは失敗する。
