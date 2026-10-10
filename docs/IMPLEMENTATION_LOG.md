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
