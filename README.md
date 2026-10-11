# NikuCue

猫の Mali（มะลิ / マリ）が小さな習慣を見守り、記録した「できた」を一緒に喜ぶ iPhone アプリ。
**Small wins, with a little cat.**

- 仕様: `spec/`（受領した仕様パック。`spec/README.md` → `spec/00_START_HERE.md` → `CLAUDE.md`）
- 実装ログ: `docs/IMPLEMENTATION_LOG.md`（決定・コマンド・結果・未実施項目）
- 仕様からの差分: `docs/SPEC_REVISIONS.md`
- モジュール契約: `docs/ARCHITECTURE_CONTRACTS.md`
- QA シナリオの状態: `docs/QA_STATUS.md` / macOS での次の手順: `docs/OWNER_NEXT_STEPS.md`
- 猫の画像アセット方式への移行設計: `docs/CHARACTER_ASSET_PIPELINE.md`（コード描画の猫は開発用プレースホルダー）
- プレースホルダーのブラウザプレビュー（開発用、iOS アプリではない）: https://claude.ai/artifact/S3rXqf6ReZcbdC3Nhamoqq

## 構成

| パス | 内容 |
|---|---|
| `NikuCue.xcodeproj` | Xcode 16 以降の同期フォルダ形式。`tools/xcodeproj/generate_pbxproj.py` で生成 |
| `NikuCue/` | アプリ（SwiftUI + SpriteKit + SwiftData + UserNotifications + StoreKit 2）。iOS 17 以降、iPhone 縦向き |
| `NikuCue/Resources/` | 同梱する JSON 契約（文言 3 言語、反応、キャラクター rig / パス / アニメーション、全身ポーズ `mali_poses.json`）、Mali の画像セット（`Assets.xcassets/Mali`、オーナー提供 v1）、PrivacyInfo |
| `Packages/NikuCueDomain/` | 純粋な Domain（Foundation のみ）。`swift test` で macOS / Linux で実行できる |
| `NikuCueTests/` | アプリ側の XCTest（Simulator で実行） |
| `tools/character/` | 開発用プレースホルダー絵の生成、アニメーション track の生成、**全身イラストの取り込み（`import_wholebody_pack.py` + `generate_wholebody_tracks.py`、現在の表示。idle の尻尾レイヤー切り出しを含む。原画は `docs/assets/mali_v1_1`）**、パーツ分け原画の取り込み（`build_texture_pack.py`） |
| `tools/rig-preview/` | 同じ JSON をブラウザで描画する開発用プレビューと Playwright キャプチャ |
| `artifacts/` | 記録した画像・動画（`artifacts/mali-assets-v1` = 全身 6 枚のポーズ表・クリップ静止画・32 秒動画、`artifacts/P01` = 旧 placeholder。いずれもブラウザ描画で Simulator の記録ではない） |
| `scripts/` | `check_resources.py`（同梱 JSON の検証）、`check_release_config.sh`（Release ビルドの placeholder 検査） |

## ローカル検証

```sh
python3 scripts/check_resources.py                 # 同梱 JSON 契約
python3 tools/xcodeproj/validate_pbxproj.py        # 生成した project.pbxproj の参照整合性
cd Packages/NikuCueDomain && swift test            # Domain の Unit Test（Swift 6 以降）
# macOS のみ:
xcodebuild -list -project NikuCue.xcodeproj
xcrun simctl list devices available
xcodebuild test -project NikuCue.xcodeproj -scheme NikuCue -destination 'platform=iOS Simulator,id=<CONFIRMED_UDID>'
```

## 公開前に人が確認する項目

`spec/RELEASE_BLOCKERS.md` を参照。本番の bundle ID / product ID / AdMob ID / URL は `NikuCue/App/AppConfiguration.swift` の placeholder を置き換える。placeholder が残っている Release ビルドは `scripts/check_release_config.sh` で失敗する。
