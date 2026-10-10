# 実装契約（モジュール間 API）

docs/06 の推奨構成を具体化したもの。すべての Swift コードはこの契約に合わせる。
変更する場合はこのファイルを先に更新し、`docs/IMPLEMENTATION_LOG.md` に理由を書く。

## 1. 構成

```text
Packages/NikuCueDomain/            SwiftPM パッケージ（Foundation のみ。UI/SpriteKit/SwiftData/StoreKit/広告を import しない）
  Sources/NikuCueDomain/
  Tests/NikuCueDomainTests/        swift test で実行（macOS / Linux）
NikuCue.xcodeproj                  Xcode 16 以降の同期フォルダ形式（手書き pbxproj）
NikuCue/                           アプリターゲット（SwiftUI + SpriteKit + SwiftData + UserNotifications + StoreKit 2）
  App/ Character/ Data/ Features/ Services/ Resources/
NikuCueTests/                      XCTest（Repository / Character / Localization 読み込み）
tools/                             開発用（出荷しない）: rig-preview, character generators, icon generator
spec/                              受領した仕様パック（変更しない）
```

依存方向: `Features → Services/Data/Character → NikuCueDomain`。Domain は何にも依存しない。

## 2. Domain の主要型（`import NikuCueDomain`）

```swift
// 日付
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible  // "YYYY-MM-DD" Gregorian ASCII
public struct CalendarService: Sendable { init(timeZone:); dayKey(for: Date) -> DayKey; isoWeekday(of:) -> Int; dayKey(byAdding: Int, to:) ; days(from:to:) -> Int; date(startOf:) -> Date; static appleWeekday(fromISO:) -> Int }
public protocol Clock: Sendable { var now: Date { get }; var timeZone: TimeZone { get } }
public struct SystemClock: Clock
public final class ManualClock: Clock  // テスト用

// 習慣
public enum HabitCategory: String, Codable, CaseIterable, Sendable { water, stretch, read, tidy, custom }
public struct WeekdaySet: Hashable, Codable, Sendable { init(isoWeekdays:); static everyDay; contains(isoWeekday:); isoWeekdays: [Int]; isEmpty; mask: Int }
public struct Habit: Identifiable, Hashable, Codable, Sendable { id, name, category, sortOrder, createdAtUTC, startDayKey }
public struct HabitScheduleVersion: Identifiable, Hashable, Codable, Sendable { id, habitId, effectiveFromDayKey, isActive, weekdays }
public enum ScheduleResolver { static func version(for habitId:, on: DayKey, in: [HabitScheduleVersion]) -> HabitScheduleVersion?; static func isScheduled(habit:, on:, versions:, calendar:) -> Bool; static func isActive(habitId:, on:, versions:) -> Bool }
public enum RecordStatus: String, Codable, Sendable { done, skipped }
public struct HabitDayRecord: Hashable, Codable, Sendable { habitId, dayKey, status, recordedAtUTC, timeZoneID, revision; recordKey }
public enum DayStatus: Sendable { pending, done, skipped, notScheduled }
public enum HabitValidation { static func validateName(_:) -> Result<String, HabitValidationError>; validateNickname; maxActiveHabits = 5; nameMaxGraphemes = 40; nicknameMaxGraphemes = 16 }

// 集計
public struct DayProgress: Equatable, Sendable { scheduled, done, skipped, pending; hasSchedule; isAllDone; isAllResolved }
public enum ProgressCalculator { static func progress(on:, habits:, versions:, records:, calendar:) -> DayProgress; static func distinctDoneDays(records:) -> Int; static func status(of habit:, on:, versions:, records:, calendar:) -> DayStatus; static func editableWindow(today:, calendar:) -> ClosedRange<DayKey> }  // 今日を含む7日
public enum Milestones { static let thresholds = [3, 7, 14]; static func newlyReached(distinctDoneDays:, seen: Set<Int>) -> Int? }

// 記録サービス（Repository を介して書く。Domain は protocol だけ持つ）
public enum DesiredStatus: Sendable { done, skipped, clear }
public struct SetStatusResult: Sendable { record: HabitDayRecord?; newlyCompleted: Bool; changed: Bool; progress: DayProgress; distinctDoneDays: Int; revision: Int }
public protocol HabitRepository: Sendable (async throws API; see Sources/NikuCueDomain/Repository/HabitRepository.swift)
public actor HabitService  // 検証 → repository → 集計 → CatEvent 生成。UI は HabitService を介して書く

// 猫（I/O なし）
public enum ClipID: String, Codable, CaseIterable, Sendable { idle, greet, pet, celebrate, cheer, settle, doze, milestone }
public enum Expression: String, Codable, CaseIterable, Sendable { neutral, softSmile, closedHappy, curious, sleepy }
public enum CatAmbientState: Sendable { idle, dozing }
public struct CatEvent: Sendable { id: UUID; kind: CatEventKind; occurredAt; dayKey; habitId?; category?; revision?; isDemo }
public enum CatEventKind: Sendable { sceneEntered, welcomeBack, sceneLeft, petTapped, completionCommitted, completionUndone, skipCommitted, historyCorrected, dayChanged, modalPresented, modalDismissed, nightAmbient, userRequestedEncouragement }
public struct ReactionSnapshot: Sendable { dayKey; progress; distinctDoneDays; seenMilestones; allDoneShownToday; isDemo }
public struct ReactionIntent: Equatable, Sendable { reactionId; clip: ClipID; expression: Expression; priority; messageKey; textDwellMs; marksMilestone: Int?; marksAllDoneDay: DayKey?; event: CatEvent }
public struct ReactionCatalog: Codable, Sendable  // reactions.json
public struct CatReactionEngine { init(catalog:, rng:); mutating func intent(for:, snapshot:) -> ReactionIntent? }  // docs/05 §4 の順序で一つだけ選ぶ
public struct ReactionQueue { enqueue(_:) ; current; waiting(max 1); finishCurrent(); discardAll(); invalidate(where:) }  // docs/05 §5

// ローカライズ（純粋）
public enum AppLanguage: String, Codable, CaseIterable, Sendable { system, th, en, ja }
public struct StringCatalog { init(tables: [String: [String: String]], fallback: "en"); func string(_ key: String, language:, args: [String: String]) -> String; missingKeys(in:) }
public enum LocalizationContract { static let placeholderPattern }

// 通知（純粋）
public struct ReminderSlot: Identifiable, Hashable, Codable, Sendable { id, enabled, hour, minute, weekdays }
public struct ReminderRequestSpec: Hashable, Sendable { identifier; isoWeekday; hour; minute }
public enum ReminderPlanner { static let identifierPrefix = "nikucue.reminder.v1."; static func requests(for slots:) -> [ReminderRequestSpec] (<= 14); static func hasDuplicate(slots:) -> Bool; static func isOwnIdentifier(_:) -> Bool }

// 広告ゲート / 権利（純粋）
public enum EntitlementState: Sendable { unknown, owned, notOwned }
public struct AdGateInputs: Sendable { configValid, entitlement, onboardingComplete, firstRealSessionFinished, homeVisible, sceneActive, canRequestAds, sdkPrivacyConfigurationVerified }
public enum AdGate { static func adsAllowed(_:) -> Bool }

// バックアップ（純粋）
public struct BackupDocument: Codable, Sendable { schemaVersion = 1; exportedAtUTC; habits; scheduleVersions; records; companion; preferences; reminderSlots (enabled は復元時に必ず false); seenMilestones; allDoneShownDayKeys }
public enum BackupValidator { static let maxBytes = 5_000_000; static func validate(data:) -> Result<BackupDocument, BackupValidationError> }
```

## 3. アプリ側の境界

| 型 | 役割 | 禁止事項 |
|---|---|---|
| `AppConfiguration` | bundle/product/AdMob ID、URL のプレースホルダ。`isReleaseReady` | 本番 ID の推測。Release で placeholder が残れば `validateForRelease()` が fatalError |
| `AppContainer` (`@MainActor`) | Clock, Repository, HabitService, Localizer, Preferences, Notification/Purchase/Ad services を組み立てる | ViewModel が ModelContext を直接触る |
| `CharacterArtProvider` protocol | `PartArt?` (texture, size, anchor) を part/expression/scale で返す | state machine からの描画依存 |
| `VectorArtProvider` | `mali_paths.json` → CGPath → `SKTexture`（scale ごとにキャッシュ） | 毎フレームのパス生成 |
| `CatRig` | `character_spec.json` からノードツリー生成、rest transform 保持、`reset()`、表情切替（crossfade） | ノード ID のハードコード増殖 |
| `AnimationLibrary` | `animations.json` の tracks → key 付き `SKAction` | 同一キーの無限 action 重複 |
| `CatSceneController` (`@MainActor`) | `ReactionQueue`、ambient、pause/resume、Reduce Motion | DB 書込 |
| `CatScene: SKScene` | 1 つだけ生成。部屋の色、タップ → `onPet` | 再生成 |
| `SwiftDataHabitRepository` (actor) | `HabitRepository` 実装。直列化・冪等 upsert・atomic replace | UI への ModelContext 公開 |
| `LocalNotificationService` | `ReminderPlanner` の差分適用（prefix 内のみ） | 起動ごとの別 UUID |
| `PurchaseService` | StoreKit 2。`.verified` のみ owned。`Transaction.updates` 監視、`AppStore.sync()` は明示操作時のみ | UserDefaults bool だけでの unlock |
| `AdConsentService` / `BannerService` | UMP + GMA はプロトコル越しに Mock で開発。`AdGate` が true のときだけ request | 習慣データを SDK へ渡す |
