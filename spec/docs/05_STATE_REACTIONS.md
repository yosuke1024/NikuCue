# 05. 状態遷移 / 反応設計

## 1. 分離する状態

- `HabitDayState`: pending / done / skipped。DB上の正本。
- `CatAmbientState`: idle / dozing。時刻・設定から決める表示。
- `CatInteractionState`: greeting / petted / cheering / celebrating / settling / milestone。
- `AppSceneState`: foreground / inactive / background / modal。
- `EntitlementState`: unknown / owned / notOwned（購入進行状態とは分離）。

「猫の機嫌」を習慣達成率から減点する永続ステータスは作らない。

## 2. イベント契約

各イベントにeventId（UUID）、occurredAt、dayKey、必要ならhabitIdとcategory、revisionを付ける。習慣名は反応エンジンへ渡さない。`completionCommitted`は新しくdoneになった場合のみ。

主要イベント: sceneEntered, sceneLeft, petTapped, completionCommitted, completionUndone, skipCommitted, historyCorrected, dayChanged, modalPresented, modalDismissed。

書込をしないdemoイベントは別namespaceにし、統計・節目・バックアップへ混ぜない。

## 3. 遷移

| 現状態 | イベント/条件 | 次状態 | 効果 |
|---|---|---|---|
| 停止 | foreground + Home | greetingまたはambient | 当日未歓迎なら歓迎、以外はambient |
| ambient | petTapped、cooldown外 | petted | 900ms。記録は変更しない |
| ambient/dozing | completionCommitted | celebrating / milestone | 保存済みのみ。眠い時間でも普通に祝う |
| interaction | completionCommitted | 現在の一回を終え、最新1件へ | 各記録は即時保存。演出だけキュー制限 |
| interaction | petTapped | 無視 | クリック連打で猫が壊れない |
| 任意 | completionUndone、対象イベントが演出中 | ambient | 祝福をキャンセル。悲しませない |
| ambient | skipCommitted | settling | 「休んでも大丈夫」 |
| 任意 | historyCorrected | 状態を維持 | 保存フィードバックのみ |
| 任意 | sceneLeft/modal | 停止 | 未再生キュー破棄、DBはそのまま |
| 停止 | foreground再開 | ambientまたは歓迎 | 古いお祝いを再生しない |
| 任意 | dayChanged | 集計再読込 | 昨日の未達を罰しない |

## 4. 完了後の一回だけの反応選択

completionCommittedごとに、現在のDBスナップショットから以下の順で**一つ**を選ぶ。

1. 累計3/7/14日の新しい節目に到達 → milestone。
2. 本日の対象が1件以上、全件done、当日のallDone未演出 → all_done。
3. 本日がすべてdone/skipped、skippedを含む、doneが1件以上 → all_resolved。
4. カテゴリ別（水/ストレッチ/読書/片付け）の反応。
5. 汎用の喜び。

1と2を同時に出さない。節目を出すときに全達成も成立していれば、その日のallDone演出済みも一緒に記録し、次のタップで重複お祝いしない。

milestone表示済みは**実際に表示を開始した時**に記録する。キュー破棄だけで未表示を消費しない。過去訂正で到達した節目は静かな履歴表示のみとし、既到達の数値として記録して後から大げさに再演しない。

## 5. キュー / 取り消し / 日跨ぎ

max queued interaction = 1。実行中1件 + 待機1件だけ。新イベントで待機を置換する。集計自体は全件分反映される。
待機開始前にrevisionを再検証し、取り消し済み/別日/削除済み/過去訂正イベントなら破棄。
優先順位はmilestone > all_done > complete > all_resolved > greeting > pet > cheer > ambient。skipにより全件resolvedになってもall_doneにはならない。

猫の演出で操作をブロックしない。2〜3件を素早くチェックしたら、最後に最新の集計に合う反応を見せる。途中経過の反応を全部再生しようとしない。

## 6. 時間帯

猫の部屋は端末の現在時刻で朝/昼/夜の色を切替。夜の猫はうとうとするが、ユーザーへ就寝を強制しない。猫をなでる/記録で起き、終了後にdozeへ戻る。生活リズムの良し悪しを判定しない。

部屋の時刻区分は朝05:00–10:59、昼11:00–18:59、夜19:00–04:59という演出用初期値。通知時刻とは連動しない。行動評価・睡眠推奨時刻ではない。

## 7. 反応文の選択

`assets-spec/reactions.json`のkeyを使用。各event/categoryから候補を選び、直前2つの同種文言と連続しない。候補不足時は重複を許す。テストではseedを固定し、通常時は端末内の乱数のみ。サーバーもモデル推論も呼ばない。

自由入力の習慣名を「水を飲んだね」などに誤分類しない。カテゴリは本人の選択。量/回数/体調の断定をしない。吹き出しは2〜3行、意味が読み切れる時間（4秒目安）残し、動きの終了と同時に文を消さない。

## 8. 禁止文言と演出

「やらないと悲しい」「何日も放置された」「広告を見てごはんをあげて」「君のために頑張ったのに」「失敗」「連続記録が全部無駄」。猫が病気/空腹になる、死ぬ、好感度が下がる、戻ってきたユーザーへ謝罪を要求する、も禁止。
