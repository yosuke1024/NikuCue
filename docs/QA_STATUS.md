# QA シナリオの状態（spec/qa/scenarios.json ⇄ 実装・テスト）

凡例: **logic** = 純粋ロジックの自動テストが Linux で実行済み / **xctest** = Simulator 用 XCTest を作成済み（未実行）/ **not_run** = 未実施。
実機・Simulator の実行はこの環境では不可能（macOS なし）。「実装済み」は「実行確認済み」ではない。

| ID | 領域 | 状態 | 根拠 |
|---|---|---|---|
| Q01 | offline | not_run | 広告 SDK 未リンクのため通信は StoreKit のみ。機内モード実機確認が必要 |
| Q02 | storage | logic + xctest | `HabitServiceTests.testDoneTenTimesWritesOnceAndEmitsOneEvent`, `SwiftDataRepositoryTests.testStatusWritesAreIdempotentAndUnique` |
| Q03 | storage | logic | `HabitServiceTests.testPersistenceFailureLeavesStateAndProducesNoEvent`（失敗注入、イベントなし、再試行で 1 件） |
| Q04 | state | logic + xctest | `HabitServiceTests.testUndoRemovesRecordAndEmitsUndoEvent`, `ReactionQueueTests.testStaleWaitingIsDiscardedAndUndoCancels`, `CatSceneControllerTests.testUndoCancelsRunningCelebrationWithoutSadness` |
| Q05 | progress | logic | `ProgressCalculatorTests.testTwoDoneOneSkippedIsNotAllDone`, `HabitServiceTests.testSkipIsSeparateFromDone` |
| Q06 | progress | logic | `ProgressCalculatorTests.testZeroScheduledNeverAllDone` |
| Q07 | progress | logic | `ProgressCalculatorTests.testFiveDoneOnOneDayCountsOnce` |
| Q08 | progress | logic | `CatReactionEngineTests.testPriorityOrderMilestoneAllDoneResolvedCategory`（milestone_7 が allDone token を消費） |
| Q09 | queue | logic + xctest | `ReactionQueueTests.testOneRunningOneWaitingLatestWins`, `CatSceneControllerTests.testStartsIdleAndRunsOneInteractionAtATime` |
| Q10 | time | logic | `CalendarServiceTests.testThaiBuddhistPresentationKeepsGregorianKey`, `DayKeyTests`（タイ数字拒否） |
| Q11 | time | logic（一部） | `HomeViewModel.checkDayChange`（60 秒ごと + active 時）。実機での日跨ぎ確認は not_run |
| Q12 | time | logic | `CalendarServiceTests.testTravelKeepsExistingKeysAndUsesCurrentLocalDay` |
| Q13 | time | logic | `CalendarServiceTests.testDayArithmeticAcrossDST`, `testRepeatedHourOnFallBackStaysOnSameDay`。通知の DST 挙動は not_run |
| Q14 | schedule | logic | `HabitServiceTests.testWeekdayChangeAppliesTomorrow` |
| Q15 | schedule | logic | `HabitServiceTests.testArchiveThenResumeCreatesNoMissedDays` |
| Q16 | history | logic | `HabitServiceTests.testUnscheduledAndWindowRules`（6 日前可、7 日前不可、訂正は historyCorrected） |
| Q17 | notification | xctest/実装 | `ReminderSettingsView` の拒否時導線（実装）。OS ダイアログは not_run |
| Q18 | notification | logic | `ReminderPlannerTests.testAtMostFourteenStableRequests`（20 回 reconcile で差分ゼロ） |
| Q19 | notification | 実装 | 文言は固定キー `reminder.notificationTitle/Body`、未達件数なし |
| Q20 | notification | 実装 | `NotificationDelegate`（tap → Home、自動完了なし）。not_run |
| Q21 | notification | logic + 実装 | 同 identifier で content 置換（`LocalNotificationService.reconcile`） |
| Q22 | animation | xctest | `CatSceneControllerTests.testLeaveSceneDiscardsQueueAndPauses` |
| Q23 | accessibility | not_run | Reduce Motion は実装（`reducedMotionTracks`）。Dynamic Type / VoiceOver / タイ語の実機確認が必要 |
| Q24 | purchase | xctest | `MonetizationTests.testVerifiedPurchaseRemovesAdsImmediately`（Mock） |
| Q25 | purchase | xctest | `MonetizationTests.testCancelPendingUnverifiedAndFailureNeverUnlock`（Mock） |
| Q26 | purchase | 実装 | `StoreKitPurchaseService.refreshEntitlement` は端末上の署名済み情報から判定、ネットワーク失敗で notOwned にしない。Sandbox 確認は not_run |
| Q27 | purchase | xctest（一部） | `MonetizationTests.testRestoreIsExplicitAndReportsResult`（Mock）。失効の実機確認は not_run |
| Q28 | ads | logic + xctest | `AdGateTests`, `MonetizationTests.testBannerGateNeverRequestsWhenOwnedUnknownOrWithoutConsent` |
| Q29 | ads | not_run | SDK 未リンク。`BannerService.reservedHeight` を Home セッション中固定にする設計 |
| Q30 | ads | xctest | 同上（同意撤回・background で破棄） |
| Q31 | privacy | not_run | SDK 未リンク。設計上、SDK 境界に習慣データを渡す API がない |
| Q32 | backup | logic | `BackupValidatorTests.testRejections`, `HabitServiceTests.testImportFailureKeepsOriginalData` |
| Q33 | backup | logic + xctest | `HabitServiceTests.testBackupRoundTripRestoresWithRemindersOff`, `SwiftDataRepositoryTests.testReplaceAllAndDeleteAll` |
| Q34 | deletion | logic + xctest | `HabitServiceTests.testDeleteAllKeepsNothingLocal`（権利は DB 外） |
| Q35 | art | ブラウザ描画 + xctest | オーナー提供の全身 6 枚を `artifacts/mali-assets-v1`（6 ポーズ × 明暗、8 クリップ、32 秒動画。Simulator ではない）で記録。`WholeBodyArtProviderTests`（未実行）。人間承認 R02 待ち。`artifacts/P01` は旧 placeholder の記録 |
| Q36 | launch | xctest + script | `MonetizationTests.testPlaceholderConfigurationBlocksAds`, `scripts/check_release_config.sh` |
| Q37 | localization | logic + xctest | `StringCatalogTests`, `LocalizationBundleTests.testLocalizerResolvesNameAndLanguage` |
| Q38 | lifecycle | 実装 | `AppContainer.gatherConsentIfNeeded` が猫を pause。not_run |
| Q39 | restore | logic | `HabitServiceTests.testImportFailureKeepsOriginalData`（InMemory）。SwiftData の rollback は `write{}` 実装、実行は not_run |
| Q40 | art | xctest | `CatSceneControllerTests.testRapidDemoPlaysKeepActionCountBounded`。10 分の実機計測は not_run |
