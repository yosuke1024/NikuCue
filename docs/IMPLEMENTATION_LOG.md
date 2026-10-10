# NikuCue 実装ログ

このファイルは `CLAUDE.md` の作業規約に従い、決定・変更ファイル・実行コマンド・結果・未実施項目を記録する。
「試せなかった項目」は成功扱いせず、**未実施: 理由** として残す。

## 0. 環境調査（2026-10-10, セッション開始時）

| 項目 | 結果 |
|---|---|
| 作業場所 | Claude Code クラウドコンテナ（Linux, Ubuntu 24.04, x86_64） |
| リポジトリ | `yosuke1024/NikuCue`、初期状態はコミットなし。作業ブランチ `claude/exciting-hypatia-ykvvz2`（セッションで指定されたブランチ） |
| 既存コード/未コミット変更 | なし（空リポジトリ。壊すものはない） |
| macOS / Xcode / xcodebuild / xcrun / Simulator | **なし**（Linux コンテナ。`xcode-select`・Simulator は存在しない） |
| Swift toolchain | 初期状態なし。`download.swift.org` / `static.swift.org` はネットワークポリシーで遮断（403）。Docker daemon なし。Docker Registry HTTP API 経由で公式 `swift` イメージのレイヤを取得して純Swiftロジックのテストを試みる（結果は後述） |
| 利用可能 | Python 3.13（Pillow あり）、Node 22 + Playwright 1.56 + Chromium、ImageMagick 6、ffmpeg、git |
| ネットワーク | GitHub API / PyPI / apt / Docker Registry / developer.apple.com は到達可。swift.org のダウンロードは不可 |

### この環境での方針（`00_START_HERE.md` 「開発環境がない場合」に従う）

- iOS ビルド・Simulator 実行・XCUITest・StoreKit Test・実機録画は **未実施** として残す。「ビルド成功」とは書かない。
- 移植可能な Swift ソース、純粋ロジック（Domain / ReactionEngine / 日付）の Unit Test、JSON 契約の検証、レビューを進める。
- 猫の見た目を今の環境で確認できるようにするため、同じ JSON 契約（`character_spec.json` / `animations.json` / 本リポジトリで追加したパス定義）から描画する **開発用ブラウザプレビュー**（`tools/rig-preview/`）を用意し、Playwright/Chromium で静止画と動画を記録する。これは iOS Simulator の記録ではない（ラベルを明記する）。描画ロジックの正本は Swift 側であり、プレビューは絵・pivot・タイミングの確認用で、出荷物ではない。
- Apple の公開要件（developer.apple.com/news/upcoming-requirements、2026-10-10 取得）: 2026-04-28 以降は **Xcode 26 以降・iOS 26 SDK** でのビルドが必須。Deployment Target は仕様どおり iOS 17 を初期値とする。

### git push について

`00_START_HERE.md` は「承認前の GitHub への push」を禁じている。一方、このセッションはオーナーが作業ブランチ `claude/exciting-hypatia-ykvvz2` を指定して開始しており、コンテナは一時的で push しないと成果が失われる。
→ **指定された作業ブランチにのみ push する**（`main` には触れない。Pull Request は作らない。公開・配信・課金設定の変更は一切行わない）。この解釈に問題があればオーナーが差し戻せるよう、ここに明記する。

## 1. 作業計画（P00 → P01 → バックログ順）

| タスク | 本環境でできること | 未実施として残すもの |
|---|---|---|
| P00 | リポジトリ構成、Xcode プロジェクト（手書き pbxproj、Xcode 16+ の同期フォルダ形式）、`AppConfiguration` のプレースホルダ + Mock 構成、ログ | `xcodebuild` 起動確認、Simulator 一覧 |
| P01 | SpriteKit rig（Swift）、`CharacterArtProvider`、`AnimationLibrary`、`CatSceneController`、デモ画面、ブラウザプレビューでの画像/動画記録 | Simulator / 実機の録画、Reduce Motion の OS 連携確認 |
| P02 | Gallery 画面、全8クリップ、JSON 参照検証テスト | 実機での継ぎ目確認 |
| P03 | Domain（日付・予定版・集計・反応選択）の Unit Test（Linux Swift で実行できれば実行する） | ― |
| P04 | SwiftData Repository、Backup DTO、検証ロジック（純粋部分はテスト） | SwiftData の実行テスト |
| P05〜P10 | SwiftUI 画面、通知、StoreKit 2、広告ゲート（Mock） | 画面・通知・購入・広告の実行確認 |
| P11〜P12 | QA シナリオの対応表、アイコン生成（editable source + 1024px PNG + 小サイズプレビュー） | 実機 QA、審査準備の人間確認 |

## 2. 変更履歴

（タスクごとに追記）

### P00 環境調査 / プロジェクト生成 / Mock 構成（2026-10-10）

**決定**

| ID | 決定 | 理由 |
|---|---|---|
| D-P00-1 | `NikuCue.xcodeproj` を Python スクリプト（`tools/xcodeproj/generate_pbxproj.py`）で生成する。Xcode 16 以降の `PBXFileSystemSynchronizedRootGroup` 形式 | Linux には Xcode がない。同期フォルダ形式ならファイル追加のたびに pbxproj を編集しなくてよい。`tools/xcodeproj/validate_pbxproj.py` で参照整合性を検査（Xcode で開く検証は未実施） |
| D-P00-2 | Domain を `Packages/NikuCueDomain`（ローカル SwiftPM、Foundation のみ）に分離 | docs/06 §2「広告・購入・猫の描画が Domain へ import されない」をコンパイル境界で保証し、Linux の Swift でも `swift test` できる |
| D-P00-3 | アプリ側は Swift 5 言語モード（`SWIFT_VERSION = 5.0`、`SWIFT_STRICT_CONCURRENCY = targeted`）、Deployment Target iOS 17.0、iPhone のみ・縦向き | Xcode でコンパイルできない環境で書くため、Swift 6 モードの厳格な Sendable 検査による未検証エラーを避ける。Domain は `StrictConcurrency` を有効にして警告ゼロを維持。macOS でビルドできたら Swift 6 モードへ切替を検討（TODO） |
| D-P00-4 | Swift toolchain として SwiftWasm 配布の `swift-wasm-6.0.3-RELEASE` (Ubuntu 22.04 向け Linux ホスト toolchain) を `/tmp/swift-toolchain` に展開して使用 | swift.org のダウンロードは遮断。Docker daemon なし。GitHub Releases は到達可能。ホスト toolchain は通常の Swift 6.0.3（`swift --version` で確認）。iOS SDK は含まれないので Domain パッケージのみビルド可能 |
| D-P00-5 | 本番 ID は `NikuCue/App/AppConfiguration.swift` の `REPLACE_WITH_` placeholder、bundle ID は `placeholder.nikucue.app` | 推測禁止（CLAUDE.md）。Release ビルドでは Run Script `scripts/check_release_config.sh` が placeholder を検出して失敗（QA Q36 の設計）。Debug は Mock で起動 |
| D-P00-6 | 同梱 JSON は `NikuCue/Resources/` に複製し、`scripts/check_resources.py` で `spec/` との同一性（文言・反応）と、記録済み差分（キャラ rig）を検証 | パックの JSON をビルド時入力として同梱する（CLAUDE.md 8）。差分は `docs/SPEC_REVISIONS.md` |

**作成ファイル**: `CLAUDE.md`（パックと同一）, `README.md`, `.gitignore`, `NikuCue.xcodeproj/`, `NikuCue/App/*`, `NikuCue/Resources/*`, `Packages/NikuCueDomain/*`, `NikuCueTests/*`, `scripts/*`, `tools/*`, `docs/*`, `spec/*`

**実行したコマンドと結果**

```text
python3 -I spec/scripts/validate_pack.py            → PASS（169 keys × 3, 26 nodes, 8 clips, 16 reactions, 40 QA）
sha256sum -c spec/SHA256SUMS.txt                    → 28 件 OK
python3 -I scripts/check_resources.py               → PASS
python3 -I tools/xcodeproj/generate_pbxproj.py      → wrote NikuCue.xcodeproj
python3 -I tools/xcodeproj/validate_pbxproj.py      → PASS（参照整合性のみ）
/tmp/swift-toolchain/.../swift --version            → Swift version 6.0.3 (swift-6.0.3-RELEASE) x86_64-unknown-linux-gnu
cd Packages/NikuCueDomain && swift build            → 成功（警告 0 を目標。Sendable 警告は修正済み）
cd Packages/NikuCueDomain && swift test             → 下記 P03 の節を参照
```

**未実施（理由: macOS / Xcode / Simulator がない）**: `xcodebuild -version`, `xcrun simctl list`, `xcodebuild -list`, アプリターゲットのビルド、`NikuCueTests` の実行、Xcode での pbxproj の読込確認。

### P01 猫 rig の縦切りデモ（2026-10-10）

**実装**（`NikuCue/Character/`, `NikuCue/Features/Demo/`）

- `RigSpec` / `ArtPaths` / `AnimationSpec`: 同梱 JSON のデコードと構造検証（`validate()`）。
- `CharacterArtProvider` protocol + `VectorArtProvider`: `mali_paths.json` の M/L/C/Q/Z パスを `CGPath` にして `UIGraphicsImageRenderer` で一度だけテクスチャ化（part × 表情 × 解像度でキャッシュ）。毎フレームのパス生成なし。承認済み PNG への差し替えは provider の差し替えで可能（state machine 無変更）。
- `CatRig`: `character_spec.json` の親子ノード（26 ノード、z-order は contract の値）。rest transform を保持し `resetToRest()`。目と口は 2 枚のスプライトで 100ms クロスフェード。
- `AnimationLibrary`: `animations.json` の keyframe tracks → キー付き `SKAction.customAction`。rest からの相対値で適用。瞬きは 4〜7 秒の seeded 間隔。
- `CatSceneController`（`@MainActor`、DB 書込なし）: `ReactionQueue`（実行 1 + 待機 1）、ambient（idle / doze）、pause / resume（離脱で待機破棄・古い反応を再生しない）、Reduce Motion（跳躍・ハート移動なし、表情クロスフェードのみ）、ハート最大 3 つ、吹き出しの dwell（動きの終了と独立）。
- `CatScene`（1 インスタンス、`resizeFill`）、`CatSceneView`（`SpriteView` 30fps、VoiceOver ボタン化）、`CatDemoView`（できた（デモ）/ 休む / なでる / Reduce Motion / 朝昼夜）。デモイベントは `isDemo = true` で統計・節目に影響しない。

**絵の反復（オーナー指摘「全然可愛くない」→ REV-007）**

1 回目: 仕様値のまま（胴 365×410、目 29×39、目の位置が顔の上半分）→ 硬い・人形的。
2 回目: 頭 540×430 / 胴 400×340 / 目 64×80 を顔の下寄りに、前足 96×150、頬・ひげ追加 → 胴が小さすぎる、眠い目が睨みに見える。
3 回目（現状）: 頭 510×400 / 胴 440×360 / 前足 100×160、眠い目を閉じた弧に、しっぽを外へ。`docs/SPEC_REVISIONS.md` REV-007。最終判定は G1（Yoh と最初の利用者）。

**記録物（ブラウザ描画。Simulator / 実機の記録ではない）**: `artifacts/P01/` — 待機・5 表情・celebrate の 10 フレーム・pet / greet / cheer / settle / doze / milestone・夜の部屋（PNG 23 枚）、`mali_rig_preview_30s.mp4`（30 秒: idle → greet → pet → celebrate → settle → milestone → doze）、`contact_sheet_64px.png` / `contact_sheet_180px.png`。
共有用プレビュー（同じ JSON をブラウザで描画、タップ・全クリップ・表情・Reduce Motion を操作可能）: https://claude.ai/artifact/S3rXqf6ReZcbdC3Nhamoqq

**受入基準との対応**

| 基準 | 状態 |
|---|---|
| idle / pet / celebrate | 実装・ブラウザ描画で確認。iOS 実行は未実施 |
| 3 表情（5 実装） | 実装・ブラウザ描画で確認 |
| pause / 復帰 | `CatSceneController.leaveScene / enterScene`、`scenePhase` 連動を実装。`NikuCueTests/CatSceneControllerTests` を用意（未実行） |
| Reduce Motion | app 設定 OR OS 設定で `reducedMotionTracks` を使用。ブラウザ描画で確認 |
| 30 秒録画 | `artifacts/P01/mali_rig_preview_30s.mp4`（ブラウザ） |

**未実施**: Simulator / 実機での描画・30fps 計測・pause 確認・VoiceOver。`NikuCueTests` の実行。

### P02 Character Gallery（2026-10-10, 実装のみ）

`NikuCue/Features/Gallery/CharacterGalleryView.swift`（Debug のみ到達可）: 8 クリップ・5 表情・Reduce Motion・action 数表示。JSON 参照検証は `scripts/check_resources.py` と `NikuCueTests/CharacterContractTests`。pivot / 継ぎ目の画像確認はブラウザ描画（`artifacts/P01`）で代替、実機は未実施。

### P03 Domain / 日付 / 予定版 / 集計（2026-10-10）

**実装**（`Packages/NikuCueDomain/Sources/NikuCueDomain/`）: `DayKey`（`YYYY-MM-DD` Gregorian ASCII のみ）、`CalendarService`（Calendar の日単位演算。`seconds/86400` 不使用）、`Clock` / `ManualClock`、`WeekdaySet`（ISO 月=1…日=7）、`Habit` / `HabitScheduleVersion` / `HabitDayRecord`（`recordKey = habitId:dayKey`）、`ScheduleResolver`（版の適用日）、`HabitValidation`（拡張書記素で 1〜40 / 1〜16）、`ProgressCalculator`（done / skipped 分離、`isAllDone` / `isAllResolved`、distinct done days、今日を含む 7 日の訂正窓）、`Milestones`（3/7/14）、`HabitRepository` protocol + `InMemoryHabitRepository`（直列化・冪等 upsert・失敗注入）、`HabitService` actor（検証 → 保存 → 集計 → `CatEvent`）、`CatReactionEngine`（docs/05 §4 の順序で 1 件、pet 2 秒 cooldown、直前 2 文言を回避、seed 可能）、`ReactionQueue`（実行 1 + 待機 1）、`StringCatalog`、`ReminderPlanner`（slot × 曜日 ≤ 14、identifier prefix、差分）、`AdGate`、`BackupDocument` / `BackupValidator`。

**テスト**（`Packages/NikuCueDomain/Tests/`、56 件）: QA シナリオ Q02–Q09, Q10–Q16, Q18, Q21, Q28, Q30, Q32–Q34, Q37, Q39 に対応する純粋ロジックのケース（ファイル内に Q 番号を注記）。

```text
cd Packages/NikuCueDomain && swift test   （Swift 6.0.3, Linux x86_64）
→ Executed 56 tests, with 0 failures (0 unexpected)   2026-10-10 15:38 UTC
```

途中で見つけて直した不具合: `DayProgress` の Hashable 欠落、`XCTAssert` 内の `try await`（Swift では autoclosure 不可 → ローカル変数へ）、履歴訂正テストが習慣作成前の日を対象にしていた、undo 後の revision（記録が消えるため 0 を返し、再登録は 1 から）、バックアップの未来日（仏暦年 2569 を Gregorian key として受理していた → 出力日 +1 日より後の記録は拒否）。

**未実施**: SwiftData 実装（P04）、Xcode での同一テスト実行（macOS で `swift test` を再実行すること）。

### P04 SwiftData Repository / 移行 / バックアップ（2026-10-10, 実装のみ）

- `NikuCue/Data/SwiftDataModels.swift`: `HabitModel` / `ScheduleVersionModel` / `DayRecordModel`（`recordKey` unique）/ `SingletonBlobModel`（CompanionProfile・UserPreferences を Codable JSON で保存。項目追加に強い）/ `ReminderSlotModel`、`NikuCueSchemaV1` + `NikuCueMigrationPlan`（段階なし）、`NikuCueStore.makeContainer`（Application Support、`cloudKitDatabase: .none`。失敗時にストアを削除しない）。
- `NikuCue/Data/SwiftDataHabitRepository.swift`: `@ModelActor` で直列化。全書込は `write { }` で 1 トランザクション、失敗時 `rollback()` → 元データ維持（QA Q03 / Q39）。冪等 upsert は `InMemoryHabitRepository.apply` と同じ決定表を共有。`replaceAll` は全削除 + 全挿入を 1 save。
- `NikuCue/Data/BackupService.swift`: `nikucue-backup-v1.json` の一時書き出し、5MB 超の事前拒否、検証（Domain）→ プレビュー → 置換。
- `AppContainer`: 起動時に永続コンテナを開き、失敗なら `databaseError` を保持して `DatabaseErrorView`（再試行 / 削除しない）。
- テスト: `NikuCueTests/SwiftDataRepositoryTests.swift`（CRUD、10 連打で 1 件、revision 競合、再オープンで保持、復元で通知 OFF、全削除）。**未実行**（Simulator がない）。

### P06 CatReactionEngine 統合（2026-10-10, 実装のみ）

`NikuCue/App/CatCoordinator.swift`: `WriteOutcome.event` → `CatReactionEngine` → `CatSceneController`。`completionUndone` は演出キャンセル（悲しませない）。反応開始時に `HabitService.markShown`（節目 / 当日 allDone）を記録、待機中の反応は開始前に「今日・同じ記録・同じ revision」で再検証。`HomeViewModel` が保存 → 集計 → UI → 猫イベントの順を守り、連打は `busyHabitIds` で 1 書込に抑える。

### P08 ローカル通知（2026-10-10, 実装のみ）

`NikuCue/Services/LocalNotificationService.swift`: slot × 曜日の `UNCalendarNotificationTrigger(repeats: true)` を最大 14、identifier `nikucue.reminder.v1.<slot>.weekday.<iso>`、prefix 内だけ差分適用（QA Q18）、文言変更は同 identifier で置換（Q21）、バッジ・音なし、foreground では banner を出さない delegate、tap は Home（自動完了なし）。Mock は `MockNotificationScheduler`。画面は `ReminderSettingsView`（並行実装中）。**未実行**。

### P09 StoreKit 2 広告削除（2026-10-10, 実装のみ）

`NikuCue/Services/PurchaseService.swift`: `Transaction.currentEntitlements` で初期状態（照会完了まで `unknown`）、`Transaction.updates` 常時監視、`.verified` かつ `revocationDate == nil` のみ owned、`AppStore.sync()` は明示復元のみ、cancel は静か、pending / unverified は権利なし、二重購入開始の禁止。`NikuCue/Resources/NikuCue.storekit`（placeholder product ID の非消耗型 1 商品、scheme に添付）。`PurchaseViewModel` + `MockPurchaseService`、テスト `NikuCueTests/MonetizationTests.swift`（Q24–Q27）。**未実行**。価格は常に StoreKit から取得し定数を置かない。

### P10 UMP / 広告 / privacy manifest（2026-10-10, 部分実装）

`NikuCue/Services/AdServices.swift`: `AdConsentServicing`（UMP 境界）、`BannerService`（`AdGate` を entitlement / consent / Home 可視 / scene active / 初回セッション / 設定有効 / SDK プライバシー確認の全条件で評価。owned / unknown / 未同意では request なし、バックグラウンドで破棄、演出ごとの reload なし）、Mock 群。`GoogleMobileAdsAdapter.swift` は `#if canImport(GoogleMobileAds)` で囲み、SDK を SPM で追加するまでコンパイル対象外。
**SDK のバージョン**: developers.google.com はこの環境のネットワークポリシーで遮断されており、現行の安定版を確認できない。CLAUDE.md「バージョン番号を創作しない」に従い、SPM 依存は追加していない（owner が公式資料で版を確認して追加 → `Package.resolved` を記録 → `sdkPrivacyConfigurationVerified` を true に）。それまで広告は一切出ない。

### P12 肉球 App アイコン（2026-10-10, 暫定）

`tools/icon/generate_app_icon.py`（編集可能な元データ、幾何は Python 定数）→ `AppIcon-1024.png`（1024×1024 sRGB 不透明、角丸なし）、`artifacts/icon/app_icon_source.svg`、`preview_sizes.png`（180/120/60/40）、`preview_home_light/dark.png`。文字・カメラモチーフなし、パッド 1 + 指球 4。**R14 未完了**（Yoh の視覚承認待ち）。

### 方針変更: 猫のビジュアルは画像アセット方式へ（2026-10-10, オーナー指示）

| ID | 決定 | 理由 |
|---|---|---|
| D-ART-1 | コード描画の猫（`VectorArtProvider` + `mali_paths.json`）は**開発用プレースホルダー**に限定し、これ以上作り込まない | オーナー判断: 動作検証には十分だがビジュアル品質が製品水準ではない |
| D-ART-2 | 製品用の猫は高品質 2D イラストの原画をパーツ分けした画像を SpriteKit で動かす。rig / キーフレーム / 状態遷移 / 習慣ロジックは維持 | docs/04 §2 の「絵を差し替える時は同じ node ID と pivot を保ち `CharacterArtProvider` を差し替える」に沿う |
| D-ART-3 | 正式な原画がオーナーから提供され Gallery で承認されるまで、猫のビジュアルは未完成（R02 継続）。manifest の `isProductionArt` が承認の印 | 「完成扱いしない」指示 |

設計: `docs/CHARACTER_ASSET_PIPELINE.md`（再利用できる部品の仕分け、座標系と原画の契約、イラストレーター向け制作仕様、ランタイム設計、移行手順、リスク、確認事項）。

実装した骨組み（S1）: `NikuCue/Character/TexturePackArtProvider.swift`（manifest デコード・検証・`SKTextureAtlas` / PNG からの `PartArt`・preload）、`CharacterArtSelection`（同梱 manifest があれば texture pack、なければ placeholder）、`CharacterArtProvider.artLabel`（Gallery / Demo に表示）、`tools/character/build_texture_pack.py`（原画の書き出し → manifest・atlas・`character_spec.json` の position 更新・合成チェック画像）、`tools/character/examples/layers_export.example.json`（納品形式の例）、`scripts/check_resources.py` の texture pack 検証、`NikuCueTests/TexturePackArtProviderTests.swift`（未実行）。
現時点では texture pack を同梱していないため、起動時は placeholder が選ばれる（`check_resources.py`: "texturePack": "absent"）。

**未実施**: 原画の制作（オーナー）、取り込み（S3）、Gallery / 実機での継ぎ目確認（S4）、キーフレーム調整（S5）。

### P05 / P07 / P08 画面（2026-10-10, 並行実装 + 整合性レビュー, 実装のみ）

4 つの実装エージェントが担当フォルダ内だけにファイルを作成し、1 つのレビューエージェントがシンボル・API・文言キー・仕様の整合性を確認した（Workflow `implement-nikucue-screens`、計 22 ファイル）。

| 画面 | ファイル | 要点 |
|---|---|---|
| Onboarding O01–O05 | `Features/Onboarding/*`（4） | 猫の自己紹介 → デモ（記録なし）→ 呼び名（16 書記素）→ 最初の習慣（テンプレート 5 種）→ 通知（OS 許諾は「設定する」のみ、拒否時は設定への導線）→ 完了。各ステップで `onboardingStep` を保存し、クラッシュ後に再開 |
| Home | `Features/Home/*`（6） | 日付・履歴/設定ボタン（44pt）・猫の部屋（220/160pt）・SwiftUI 吹き出し・今日の行（Done ボタンのみ書込、行タップは何もしない）・休む/編集/並び替えメニュー・進捗行・予定なし表示・追加ボタンと 5 件上限説明・10 秒 Undo トースト・予約バナー領域（高さ 0） |
| 習慣編集 | `Features/HabitEditor/HabitEditorSheet.swift` | 名前/カテゴリ（アイコン + ラベル）/毎日・曜日チップ、「曜日の変更は明日から」常時表示、アーカイブ/再開、二段階削除。版を `HabitService.scheduleVersions()` から読み現在の曜日と archived を表示 |
| 履歴 | `Features/History/*`（4） | 月カレンダー（形と記号で状態区別、赤の失敗表示なし、未来日は不可）、日別内訳（直近 7 日のみ訂正可、訂正は保存表示のみで猫は反応しない） |
| 設定 | `Features/Settings/*`（6） | 呼び名、言語（切替後に通知文言を reconcile）、触覚、動きを減らす、通知設定（2 枠・曜日・重複拒否・拒否時導線）、バックアップ（書き出し / 取り込みプレビュー / 二重確認 / 復元後通知 OFF）、プライバシー文、ヘルプ（placeholder URL は非表示）、診断トグル、全削除（二段階、購入は保持） |
| 購入 | `Features/Purchase/PurchaseView.swift` | `PurchaseViewModel` 駆動。価格は StoreKit、復元は明示操作、価格取得失敗時は再読み込み |

**整合性レビューの指摘と対応（8 件、すべて反映）**: 編集シートが版を読まず常に「毎日」表示 → `scheduleVersions()` を読む／今日の予定にない習慣とアーカイブ済み習慣に編集導線がない → Home に編集専用の行を追加／購入画面が無効のプレースホルダー → 実装に置換／並び替え未実装 → メニューに上へ/下へ（`habit.moveUp/moveDown` キー追加、REV-L10N-1）／カテゴリアイコンが onboarding と Home で不一致 → 共通化／Undo トーストが最下行を隠す → 余白 88pt／履歴の読み込み中に未来日がタップ可能 → 日付キーでも判定／Undo ボタンの幅 44pt 未満 → 修正。

**追加した文言キー**（3 言語、REV-L10N-1）: `habit.moveUp`, `habit.moveDown`, `common.more`, `history.previousMonth`, `history.nextMonth`, `home.otherHabits`, `home.archivedHabits`。タイ語はネイティブ確認対象（R03）。

**未実施**: アプリターゲットのコンパイル、Simulator 表示、XCUITest、タイ語レイアウト確認、通知の実機確認。レビューは静的（エージェントによる読み合わせ）であり、型検査の代わりにはならない。
