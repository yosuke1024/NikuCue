# 08. 収益化 / 広告 / 課金 / プライバシー

## 1. 収益モデル

無料版: 猫・5習慣・履歴・通知・バックアップを全て利用。Homeのバナー1枠のみ。
買い切り: そのアプリ内の広告を削除。機能、猫の反応、愛情、通知上限は同じ。

非消耗型1商品。仮product ID: `REPLACE_WITH_CONFIRMED_BUNDLE_ID.remove_ads`。この文字列をそのまま本番登録しない。
価格の検証開始案は米国$2.99相当。公開価格はownerがApp Store Connectで決定し、各国の実際の表示価格をStoreKitから取得する。タイ語画面にUSD価格をハードコードしない。[S06]

月額、広告視聴で猫への餌、全画面広告、リワード広告、起動広告、mediation、広告クリック誘導は採用しない。

## 2. バナー位置

Homeの画面最下部、safe area内の専用領域にanchored adaptive banner。下部タブバーはなし。[S10][S11]

- 猫、チェック、追加ボタン、戻るボタン、購入ボタンと重ねない。
- 上側に32ptを初期目安とした非操作余白。これは本製品の値であり、Googleが保証する安全距離ではない。
- SDKの正式なad sizeを使用。勝手に拡縮・切抜き・半透明化しない。
- 予約した広告領域の高さは、そのHome表示中に突然増減させない。表示遅延でチェックボタンが指の下から動かない。
- no fill/offline時にゲーム風の広告placeholderを出さない。中立の余白とし、次回画面表示時に無広告レイアウトへ変更可。
- 初回のオンボーディングと最初のHomeセッションは広告なし。次回以降に導入する。
- `firstRealSessionFinished`は、オンボーディング完了後にHomeを一度表示し、その後scenePhaseがbackgroundになった時だけ保存する。inactiveや同意/購入sheetではセッション終了とみなさない。強制終了等で保存できなければ次回も広告なしでよい。
- 習慣編集、設定、購入、デモ、キャラクター承認用Galleryには広告なし。
- 猫が広告を指す/広告の近くを歩く/広告タップ後に喜ぶことは禁止。

過度なrefreshはしない。AdMob側で自動更新を使う場合はSDKに任せ、独自の周期loadを重ねない。非表示/バックグラウンド/owned時は広告requestを止め、bannerを破棄する。演出のたびにreloadしない。

## 3. 表示ゲート

```text
adsAllowed =
  productionOrTestConfigValid
  AND entitlement == notOwned
  AND onboardingComplete
  AND firstRealSessionFinished
  AND homeVisible
  AND sceneActive
  AND ump.canRequestAds
  AND sdkPrivacyConfigurationVerified
```

owned/unknown/consent未解決なら非表示。確認不能な間は売上より誤配信防止を優先する。GoogleはUMPによる同意確認と必要なprivacy options入口を案内している。[S09]

購入状態確定より先に広告SDKを初期化しない。無料ユーザーの必要な同意確認は起動ごとに行い、フォームは必要時のみ表示する。フォーム表示中は猫をpauseする。

## 4. トラッキング方針

初期方針は、IDFAアクセスなし・クロスアプリ追跡なし・パーソナライズしない広告。MVPではATT許可ダイアログを表示しない設計を目指す。ただし**NPAを付けるだけで、ATTや地域別同意の検討が不要になるわけではない**。[S13][S14]

GoogleのPublisher first-party IDを無効にする。確認時の公式Swift例は`MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)`。採用SDKで有効なAPIを再確認する。[S17]

UMP、NPA/limited ads、地域別要件、SDKの実際の収集、ATT対象行為の有無を公開前に照合する。満たせない場合は勝手に追跡へ変更せず、広告をOFFにしたままRelease blockerとする。購入/習慣機能を同意の強制手段にしない。

広告SDKへ習慣名、カテゴリ、達成状態、健康に関わる入力、猫の呼び名、ユーザーIDを渡さない。Google Analytics/Firebase/Crashlyticsや外部ログ転送は入れない。

## 5. StoreKit 2

Appleが署名したTransactionの検証結果を利用し、`.verified`の対象productのみを権利として扱う。`Transaction.currentEntitlements`で初期状態を取得し、`Transaction.updates`を継続監視する。StoreKitはアプリ側の購入情報取得と署名済みTransactionを提供する。[S06][S07]

サーバーレシート検証やRevenueCatを追加しない。クライアント単独の非消耗型広告削除として構成する。

購入処理: Product取得 → ユーザー操作でpurchase → verified成功なら広告を即時停止しowned → finish。cancelは静かに戻る、pendingは承認待ち表示、unverifiedは権利を付与せず説明。処理中の二重購入開始は禁止。

復元: 明示的な「購入を復元」操作で`AppStore.sync()` → entitlements再評価。自動起動でsyncを繰り返さない。

オフライン: 最後に検証済みの所有状態とStoreKitの端末上の情報を尊重する。単なるネットワーク失敗を理由に購入済みユーザーへ広告を戻さない。新規端末/再インストール後の初回復元には通信が必要な場合がある。即時の返金反映をオフラインで保証しない。

返金/失効: verifiedなrevocation情報、または正しく完了した権利照会で所有がなくなったことを確認したらnotOwned。過去のキャッシュが失効情報を上書きしない。未完了・失敗と「正常に照会して非所有」を分離する。

所有キャッシュはUIちらつき防止に限定。UserDefaultsのboolだけで無条件unlockしない。未検証Transactionを信頼する実装や自作の署名検証ライブラリ追加も不要。StoreKit Testing / Sandbox / 本番を分離する。

## 6. プライバシー文言の基準

正しい説明:
「習慣と記録はこの端末に保存されます。広告表示、購入、購入の復元には通信を利用します。手動バックアップはあなたが選んだ保存先へ書き出されます。」

禁止する説明:
「データを一切収集しません」「完全に通信しません」「広告があっても第三者送信ゼロ」。AdMob SDKはIPアドレスや広告/診断関連情報等を収集し得るため、実装に合わせた開示が必要。[S12]

Privacy policyは静的ページとアプリ内に置く。実URLと連絡先はownerが公開して設定。通常の端末バックアップ、手動export、Google SDK、Apple購入の違いを分けて書く。申告はこの草案を丸写しせず、実際のSDK/version/privacy manifestと照合する。[S08][S12]

## 7. 年齢・安全・広告運用

成人を中心とした一般向けであり、Kids categoryを安易に選ばない。実際に子ども向けに設計/宣伝する場合は、この広告方針をそのまま適用できない。年齢評価、広告の最大コンテンツレーティング、地域設定は正確に決める。[S08]

不適切広告の報告導線を設ける。ownerがAdMobのブロック設定と申告を管理する。自動公開の審査突破を保証しない。

開発者・パートナーのテストでは必ずtest adsまたは登録したtest device。本番広告を何度もクリックして動作確認しない。[S11]

## 8. 収益の見方

月次バナー概算 = 実際に表示された月間impressions ÷ 1,000 × 実測eCPM。
無料DAUやセッション数から直接収益を断定しない。no fill・同意・購入済み・オフラインでは広告が出ない。

このアプリは短時間利用が想定されるため、広告表示機会を増やすために無意味に待たせない。広告収益が小さくても利用体験を壊して補わず、広告削除の購入実績と併せて判断する。金銭的なサーバー費ゼロと、人間の保守費用ゼロは別。

## 9. 静的サイトとapp-ads.txt

ストアのDeveloper Websiteと公開ドメインのapp-ads.txtを、AdMob管理画面の正式なpublisher情報と照合する。既存PixAppsサイトの設定を壊さず必要分だけ追加する。ファイル自体は静的配信でよく、アプリ用バックエンドを新設する理由にはしない。app-ads.txtの探索はストアに掲載された開発者サイトを基に行われる。[S18]
