# ストア掲載の準備状況（P12、2026-10-10 時点）

`spec/store/metadata.json` と `spec/docs/12_STORE_LAUNCH_COPY.md` は「仕様どおり実装された場合の草案」。実装との照合結果と、公開前にオーナーが行う項目を記す。公開の判断は G3（`spec/RELEASE_BLOCKERS.md`）。

## 名称・アイコン

| 項目 | 状態 |
|---|---|
| アプリ名 `NikuCue`（画面・ターゲット・`app.name`・README） | 統一済み。旧ブランド名は使用なし |
| 肉球アイコン（editable source + 1024px PNG + 小サイズプレビュー） | `tools/icon/generate_app_icon.py`、`AppIcon-1024.png`、`artifacts/icon/`。**R14 承認待ち** |
| 商標・ストア名の可用性 | 未確認（R01） |

## 説明文と実装の対応

| 説明文の主張 | 実装 |
|---|---|
| 最大 5 つの習慣、毎日または曜日指定 | `HabitValidation.maxActiveHabits = 5`、`WeekdaySet` |
| 「できた」「今日は休む」を記録 | Home の Done / Rest、undo 10 秒 |
| なでると反応する猫 | pet 反応（2 秒 cooldown）。**猫のビジュアルは画像アセット待ち（R02）** |
| 履歴カレンダーと一緒にできた日数 | History、`distinctDoneDays` |
| ローカル通知（任意の時刻） | 最大 2 枠 × 曜日、`LocalNotificationService` |
| タイ語・英語・日本語 | 3 言語 JSON。**タイ語ネイティブ確認待ち（R03）** |
| アカウント不要、端末保存、オフラインで基本機能 | SwiftData ローカル、CloudKit なし。実機の機内モード確認は未実施（Q01） |
| 手動バックアップ | 書き出し / 取り込み（検証・二重確認・復元後通知 OFF） |
| 無料版にバナー広告、買い切りで削除、通信を利用 | StoreKit 2 実装済み。**広告 SDK は未リンク**（R07/R08）。SDK を入れるまでは「広告あり」の記述を載せない |
| 猫はアプリ内のみ、AI チャットなし、常駐なし | 該当機能なし |

## 公開前にオーナーが行うこと

1. `AppConfiguration.swift` の placeholder（product ID / AdMob ID / URL / 連絡先）を実値に置換し、bundle ID を確定（R05–R09）。
2. 広告 SDK の採用版を公式資料で確認して追加、privacy manifest と App Store の申告を照合（R08、Q31）。
3. タイ語レビュー（R03）、猫の原画の制作と承認（R02）、肉球アイコンの承認（R14）。
4. スクリーンショット 5 枚と 15〜20 秒のプレビュー動画を**実機の画面**から作る（ブラウザ描画のプレースホルダーは使わない）。
5. 審査メモ（`spec/docs/11_QA_RELEASE.md` §7）を実装と照合して提出。
