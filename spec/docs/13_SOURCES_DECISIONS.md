# 13. 公式資料 / 設計判断 / 残る不確実性

確認日: 2026-10-10。外部の仕様・規約・SDKは変更され得るため、実装開始時と公開直前に再確認する。

このパックの習慣数、反応秒数、コピー、キャラクター、画面構成、価格案、テスト閾値は**本プロダクトへの設計提案**。公式に推奨された唯一の正解や、継続率改善の実証結果ではない。

## 公式資料

### [S01] Apple — SpriteKit
https://developer.apple.com/documentation/spritekit
2D描画、画像/シェイプ、ノード、アニメーションの実装根拠。キャラの可愛さを保証する根拠ではない。

### [S02] Apple — Adding and editing persistent data in your app
https://developer.apple.com/documentation/SwiftData/Adding-and-editing-persistent-data-in-your-app
SwiftDataのモデルと永続化。保存の冪等性やbackup安全性はアプリ側で追加設計する。

### [S03] Apple — ModelConfiguration.CloudKitDatabase.none
https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct/none
ローカル保存構成の参照。採用SDKで生成される設定・entitlementを検証する。

### [S04] Apple — User Notifications
https://developer.apple.com/documentation/usernotifications
ローカル通知とリモート通知の違い、配信保証の限界。
https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
ローカル通知登録の実装入口。
https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:)
登録済みrequestの取得。件数をアプリ側の上限14で管理する。

### [S05] Apple — Asking permission to use notifications
https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
通知許諾の実装入口。どの画面で説明するかはこの製品のUX判断。

### [S06] Apple — StoreKit 2 / nonConsumable
https://developer.apple.com/storekit/
署名済みTransaction、購入情報、ローカライズされた購入体験、テスト。
https://developer.apple.com/documentation/storekit/product/producttype/nonconsumable
非消耗型の商品タイプ。

### [S07] Apple — currentEntitlements / AppStore.sync
https://developer.apple.com/documentation/storekit/transaction/currententitlements
https://developer.apple.com/documentation/storekit/appstore/sync()
https://developer.apple.com/documentation/storekit/appstore
権利確認・復元。返金/失効した商品がcurrentEntitlementsに残る前提で実装しない。実際のoffline・再インストールはSandbox/実機で確認する。

### [S08] Apple — App Review Guidelines
https://developer.apple.com/app-store/review/guidelines/
広告、In-App Purchase、正確なメタデータ、privacy、Kids category等。審査合格の保証ではない。

### [S09] Google — Set up UMP SDK, iOS
https://developers.google.com/admob/ios/privacy
同意情報更新、必要フォーム、canRequestAds、privacy options。独自boolで代替しない。

### [S10] Google — Discouraged banner implementations
https://support.google.com/admob/answer/6275345?hl=en
操作要素との近接や、コンテンツと下部メニューで広告を挟む実装への注意。本パックの余白値が公式の安全保証ではない。

### [S11] Google — Set up banner ads, iOS
https://developers.google.com/admob/ios/banner
正式なbannerサイズと導入、テスト広告。サンプルIDは採用SDKの公式資料から確認する。

### [S12] Google — App store data disclosure, iOS
https://developers.google.com/admob/ios/privacy/data-disclosure
Mobile Ads SDKのデータ取扱いとApp Store申告/manifest。ローカル習慣DBとは別に扱う。

### [S13] Apple — User Privacy and Data Use
https://developer.apple.com/app-store/user-privacy-and-data-use/
ATTが対象にするtrackingの考え方。広告がNPAというだけで全検討を免除しない。

### [S14] Google — Present IDFA message, iOS
https://developers.google.com/admob/ios/privacy/idfa
IDFA/ATTと広告requestの関係。IDFAなしでも広告をrequestできることと、同意/開示の不要性は同義ではない。

### [S15] Apple — Creating your product page / Platform version information
https://developer.apple.com/app-store/product-page/
https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
タイトル/サブタイトル、Preview、メタデータフィールド。最終の字数/byte判定はApp Store Connectでも行う。

### [S16] Apple — Upcoming Requirements
https://developer.apple.com/news/upcoming-requirements/
確認時点での提出用SDK要件、年齢質問票等。deployment targetと提出SDKを混同しない。

### [S17] Google — Privacy strategies, iOS
https://developers.google.com/admob/ios/privacy/strategies
Publisher first-party ID等の設定。SDK更新後はAPI名と既定値を再確認する。

### [S18] Google — Resolve issues with app-ads.txt
https://support.google.com/admob/answer/9776740/resolve-issues-with-app-ads-txt
開発者サイトとapp-ads.txt探索・publisher設定の確認。

## 決定ログ

| ID | 判断 | 理由/トレードオフ |
|---|---|---|
| D01 | iOSネイティブを選択 | iPhoneが最初の対象。OS連携を減らす。Android UIは将来別実装 |
| D02 | 2Dパーツをコードで制御 | GUI専用ツールや有料runtimeに依存しない。絵の制作/品質確認は残る |
| D03 | 負の感情/餌/死なし | 習慣ができない日を罰しない。育成ゲームとしての経済は捨てる |
| D04 | 習慣5件、1日1回 | 画面と検証を抑制。数量/週n回/無制限の訴求はしない |
| D05 | 日時指定の全体reminder 2枠 | ローカル繰返しで成立。未達時だけの完全な通知制御は捨てる |
| D06 | no-trackingを初期方針 | 収益単価より信頼。SDK/同意/地域の確認は残る |
| D07 | バナー1枠+広告削除 | ユーザー確定条件。猫の行動や機能は課金と無関係 |
| D08 | no analytics backend | 詳細な全体ファネル分析を諦め、ローカル診断/聞き取りから始める |
| D09 | th/en/ja | 最初の利用者とownerの検証を両立。タイ語ネイティブ確認は必須 |
| D10 | キャラ体験を先に試作 | 通常の習慣アプリを完成させてから、可愛くないことに気付く順番を避ける |

## 未検証

アプリ名の利用可能性、具体的なiPhone機種、猫の最終デザイン、タイ語の自然さ、実機性能、選定時のSDK/API/データ収集、広告単価、継続率、課金率、App Store審査適合。何れもこのパック作成時点では実績として確認していない。
