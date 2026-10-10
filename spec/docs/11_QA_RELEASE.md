# 11. QA / 実機 / 公開チェック

## 1. 自動テスト

qa/scenarios.jsonをテストケースの入口にする。最低限以下を実装する。

日付はGregorian保存、Thai Buddhist表示、timezone移動、夏時間、翌日境界。1habit/day二重保存なし。今日/6日前は編集可、7日前は不可。予定外は操作不可。アーカイブ/再開と曜日版が履歴を壊さない。

保存失敗でチェック/喜びが出ない。undoは加算を戻し、猫が悲しまない。skipはdone数に入らない。予定なしはallDoneにならない。節目は別々のdone日で数え、5件doneを1日とする。

反応の優先順位、キュー上限、undo/日跨ぎでstale反応破棄、scene再作成なし、バックグラウンドで停止。

購入: verified成功、cancel、pending、失敗、復元、失効、offline、再インストール、StoreKitの未完了照会。所有不明は広告なし。非所有・同意済みの場合だけ1request系統。

import: サイズ超過、不正JSON、不明schemaVersion、不正日付、参照切れ、重複、entitlement混入、DB保存失敗時のrollback。復元後通知OFF。

## 2. 実機マトリクス

最小対応iOSを動かす端末/Simulator、現在の提出用SDKのiPhone、小画面、標準、大画面。最初の利用者のiPhoneはモデルとOSを確認して最優先に含める。存在しない環境の結果を書かない。

タイ語/日本語/英語、system language切替、最大文字サイズ、VoiceOver、Reduce Motion、低電力、通知拒否、集中モード、機内モード、弱い回線、アプリkill/再起動。

スマホに渡す前に、猫全クリップの動画、端の切れ/重なり、tailの付け根、目/耳の接続、文字のはみ出しを確認する。動作確認に広告をクリックさせない。

## 3. 性能基準（検証用の設計目標）

ローカル操作からチェック反映まで100ms程度以内、猫の反応開始は保存後200ms程度以内を目安に計測。端末差は記録し、測っていない数値を達成済みにしない。
猫sceneは標準30fps目標。Home以外・backgroundでは描画更新停止。1分なで続けてもaction/node/taskが増殖しない。10分表示で顕著な発熱/メモリ増加がないことを実機測定。

## 4. プライバシー/SDK

許諾前/後/拒否/撤回、owned/notOwned/unknown、offlineの各状態で通信を観測。習慣名・猫名・履歴が広告リクエストやクラッシュログへ含まれないことを確認。アプリデータの完全ローカル保存と広告SDKの通信を混同しない。[S12][S13]

PrivacyInfo.xcprivacy、required reason API、Google SDKのmanifest、App Store Connect申告を照合。プライバシーポリシーとsupport URLは実際に開けるものを設定。ポリシーは自動的に法的適合が保証されるものではない。[S08]

## 5. 最初の試用で聞くこと

「可愛い？」だけでなく、どのしぐさが好きか、通知を切ったか/理由、なでただけか実際に記録したか、休みの反応が嫌でなかったか、タイ語で言い方を変えたい箇所を聞く。

主観を否定せず反映するが、一人の好みだけで一般市場の需要を断定しない。個人の贈り物の成功と商用アプリの成功を分ける。

診断は初期OFF。ONにした場合だけ端末内にイベントを保存し、本人がプレビューしてShare Sheetで渡せる。通常ログに習慣本文なし、外部自動送信なし。D7等の全利用者分析は独自イベント収集なしでは直接得られないことを認める。

## 6. 審査前

- 本番bundle/product/ad IDと署名をownerが確認。試験用ID/強制購入済みflag/Debug Galleryが本番で露出しない。
- 非消耗型の審査情報、価格、復元、購入キャンセルを確認。
- 規定のSDK/Xcode、スクリーンショットサイズ、最新の年齢質問票、地域別申告を確認。[S16]
- 猫と音素材の権利、NikuCueの商標/ストア名、肉球アイコンの原画・権利・小サイズ視認性、ライセンス表示を確認。
- ストアの「offline」「privacy」「無料」「買い切り」が実装と一致。
- 広告の位置と不適切広告の報告導線を確認。[S08][S10]
- 全データ削除で広告削除購入が消えない。
- 副業/会社のIP・利益相反の扱いをownerが確認。会社の機密・コード・アカウントを混ぜない。

## 7. 審査メモ案（owner確認用）

This is a local-first habit app with a cat companion. No account is required. Users can create up to five active habits, mark them done or skipped, view history, and optionally schedule local reminders. The cat animations run within the app; there is no background character overlay or AI chat. The only in-app purchase is a non-consumable purchase that removes banner ads. Restore Purchases is available in Settings. Core habit features remain usable without a network connection; advertising, purchasing and restoring purchases require network services. Please review the actual build and configured identifiers before submitting this note.
