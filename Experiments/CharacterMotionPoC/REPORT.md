# Mali キャラクター基盤 技術検証レポート（Spine 2D + spine-ios ／ SpriteKit 比較）

作成: 2026-10-15 ／ ブランチ `claude/loving-gates-ak20t5` ／ 対象ディレクトリ `Experiments/CharacterMotionPoC/`

> 公式サンプル `spineboy` は技術検証専用（画像は非商用ライセンス）。製品アセットではなく、リポジトリにも録画にも製品として含めない。既存の `NikuCue/` アプリ・Domain・Mali 原画には一切手を入れていない。

## 0. 結論（要約）

- **推奨方式: A（Spine 2D + 公式 spine-ios）＋ 新しい行動エンジン `CatBehavior`**。採用はライセンス購入と仕様改訂（§8）が前提。行動エンジンは描画から独立させたので、描画方式を後から替えても行動エンジンと Domain は無変更で済む（§6）。
- 無操作 90 秒で **18 回・8 種類**の行動（歩いて止まる 7 回、振り向き 7 回、待機・見回す・窓・休む・遊ぶ・正面へ来る）を、同じ行動が 3 連続しない順序で自発的に選んだ（§4.2。iOS Simulator では 18 回・8 種類）。
- **足の滑り**: 歩行中は根の移動をクリップ時間から計算するので、1 歩の接地の間のつま先の移動は最大 17.5 units（身長の 2.5%、かかと〜つま先の転がりを含む）。クリップの切替時は IK で接地足を固定し、振り向き時の足の移動を **477 → 7 units** に減らした（§4.3）。
- **瞬間移動なし**: 1 フレームの最大移動はブラウザで 8.3 units（＝歩く速さ）、Simulator ではフレーム落ちの瞬間に最大 20.1 units（エンジンが 1 回の積分を 1/20 秒に制限するので歩行 1/20 秒ぶんまで）。振り向き以外での向きの反転は全シナリオで 0 回（§4.4）。
- **割り込み**: 体の前方へのタップには視線が同じフレームで応答、体は足を着いた位置で止まってから反応（歩行中のなでる 60 回で中央値 1.03 秒・最大 1.67 秒）。20 分の乱打ファズでも不変条件が崩れない（§4.5）。
- **Reduce Motion**: 歩行・跳躍 0 フレーム（その場の振り向き・視線・静かな待機で反応）。**バックグラウンド**: 停止中は行動エンジンも描画も進まず、復帰時に溜まった時間を再生しない（§4.6〜4.7）。
- **iOS Simulator**（GitHub Actions、Xcode 26.6 / iPhone 17・iOS 26.5、CI run 8）: MotionLab を 6 シナリオで録画・計測。60 fps（中央値）、メモリ 20〜24 MB（Spine）。Simulator で **iOS 側だけの不具合を 2 件発見して修正**した（spine-ios の座標が y 下向き、SwiftUI の更新で spine-ios のフレーム時計がリセットされる。§4.8）。**実機は未確認**。
- **SpriteKit 継続との比較**: 同じ 4 クリップのフリップブックはテクスチャ 115.3 MB（Simulator 実測、メモリのピーク 138 MB）対 Spine atlas 1.0 MB。クリップ間のブレンド・視線・足の接地を実行時に作れるのは Spine だけ（§5）。
- 公式サンプル `spineboy` は技術検証専用で、リポジトリにも製品にも含めていない（取得スクリプトがハッシュ検証して `.gitignore` 下に置く）。

## 1. 依頼項目と実施状況

| # | 依頼 | 実施内容 | 状態 |
|---|---|---|---|
| 1 | 現在のキャラクター関連コードの依存関係と再利用可能部分の調査 | §2 | 完了 |
| 2 | Spine 公式サンプル + spine-ios で SwiftUI 内アニメーション再生の技術検証 | `MotionLab`（SwiftUI の `SpineView` に spine-ios を組み込み）。CI の macOS / Xcode 26.6 でビルドし、iPhone 17 Simulator で再生・録画 | 完了（Simulator。§4.8） |
| 3 | 画面内を歩き、停止し、方向転換する試作 | `CatBehavior` の Motor / Navigator（歩幅と足の接地を Spine の書き出しから計測し、足が滑らない移動を計画） | 完了（テスト・ブラウザ・Simulator） |
| 4 | 自発的な行動選択、移動、ユーザー操作による割り込み | `CatBehavior` の行動選択（隠れた気分 + 反復抑制 + 自然な順序）、刺激（なでる・呼ぶ・達成のお祝い・休む）の割り込み | 完了 |
| 5 | SpriteKit を続けた場合との比較（実装難易度・表現力・アセット制作負荷・保守性） | §5。同じエンジンで SpriteKit フリップブック描画も実装し、メモリを実測・推計 | 完了 |
| 6 | 実機または Simulator での動作確認と画面録画 | Simulator: GitHub Actions の macOS ランナーで 6 シナリオを録画・計測（§4.8）。ブラウザでも同じエンジンで 4 シナリオを録画。実機: **未実施**（この環境は Linux で、実機に接続できない） | Simulator 完了 / 実機 未実施 |

## 2. 現行キャラクター実装の依存関係と再利用可否

### 2.1 依存関係

```text
Features（Home / Onboarding / Demo / Gallery / Settings）、App（NikuCueApp / CatCoordinator）
   │  CatRoom(height:)  ・ controller.messageKey / currentClip / reduceMotion
   │  enterScene / leaveScene / pause(.modal) / resume / setPaused / playDemo
   │  ※ SpriteKit の scene を直接呼ぶ箇所もある: scene.setTimeOfDay（Home / Onboarding / Demo / CatCoordinator）、
   │    scene.isPaused（NikuCueApp）、Gallery は container.rig / rigSpec / animationSpec / artProvider を直接使う
   ▼
CatRoom ─▶ CatSceneView(SpriteView 30fps) ─▶ CatScene(SKScene, 1 個だけ)
                                               │ onTap → CatCoordinator.petTapped()
                                               ▼
                                     CatSceneController(@MainActor)
                                       ├ ReactionQueue（Domain）… 実行 1 + 待機 1
                                       ├ 余韻・反応間の間・吹き出しの遅延・ハート
                                       ├ CatRig ── CharacterArtProvider
                                       │            ├ WholeBodyArtProvider（全身 6 枚 + 尻尾レイヤー）← 現行
                                       │            ├ TexturePackArtProvider（パーツ原画、未納品）
                                       │            └ VectorArtProvider（コード描画、開発用）
                                       └ AnimationLibrary ── RigSpec / AnimationSpec（JSON 契約 3 種）
CatCoordinator（App）
   ├ HabitService（Domain, actor）… 書込 → CatEvent
   ├ CatReactionEngine（Domain, 純粋）… CatEvent + Snapshot → ReactionIntent（clip / expression / message）
   └ isStillValid（待機中の反応の再検証） / onReactionStarted（節目トークンの記録）
```

外部（Features）が主に触るのは `container.scene.controller`（`CatSceneController`）の公開 API と `CatRoom` で、これが差し替えの主な継ぎ目になる。ただし完全には閉じていない：時間帯の切替（部屋の色と夜のうたた寝）は `CatScene.setTimeOfDay` を Features と `CatCoordinator` が直接呼び、アプリの一時停止は `scene.isPaused` も操作し、なでる判定は `CatScene.touchesEnded` がリグのフレームに対して行い、VoiceOver の値は `controller.currentClip`（`ClipID`）で分岐し、Gallery はリグと JSON 契約を直接表示する。移行ではこれらも置き換える（§6.1〜6.2）。

### 2.2 再利用可否

| 部品 | 場所 | 判定 | 理由 |
|---|---|---|---|
| Domain の反応決定（`CatReactionEngine`、`ReactionCatalog`、`CatEvent`、`ReactionIntent`、`ReactionQueue`、`TimeOfDay`） | `Packages/NikuCueDomain/Sources/NikuCueDomain/Cat/` | **そのまま再利用** | 描画と完全に分離済み（Foundation のみ。NikuCueDomain 全体で 56 テスト、うち反応関連は `ReactionTests` 10 件）。「何に反応するか」は方式に依存しない |
| `CatCoordinator`（書込結果の振り分け、再検証、節目トークン） | `NikuCue/App/CatCoordinator.swift` | **再利用（接続先を変更）** | `scene.controller` の代わりに新しい `CatStage`（§6）に繋ぐ。再検証と「実際に始まったときに記録」の規則は維持 |
| `CatSceneController` の外部 API と規則（pause 理由の集合、画面の所有者、復帰時に古い反応を再生しない、吹き出しは SwiftUI） | `NikuCue/Character/CatSceneController.swift` | **API と規則を再利用、中身は置換** | 規則は docs/04 §5・docs/05 の要件そのもの。中身（SKAction のキー管理・余韻・ハート）は描画方式に依存 |
| `CatRoom` / `CatSceneView` / 吹き出し・VoiceOver | `NikuCue/Character/`, `Features/` | **再利用（中の View を差し替え）** | レイアウトと吹き出しはそのまま。ただし `SpriteView` → `SpineView` に加えて、なでる判定（今は SKScene 内でリグのフレームに対して判定）と VoiceOver の値（今は `currentClip` で分岐）は作り直しが必要 |
| `CatRig` / `AnimationLibrary` / `RigSpec` / `AnimationSpec` / JSON 契約 3 種 / 3 つの ArtProvider | `NikuCue/Character/`, `Resources/Character/` | **Spine 採用時は置換**（SpriteKit 継続時は再利用） | 骨・キーフレーム・表情差分・ポーズ切替は Spine のスケルトンとアニメーションが担う |
| `tools/character/*`（全身パックの取り込み、尻尾切り出し、トラック生成）・`tools/rig-preview` | `tools/` | **Spine 採用時は廃止**（参考として保持） | 代わりに `tools/measure_profile.mjs`（書き出しの受け入れ検査）を使う |
| Mali 原画 v1.1（全身 6 枚） | `docs/assets/mali_v1_1` | **デザイン資料として再利用** | Spine 用にはパーツ分け・隠れ部分の描き足し・横向き/歩行用の絵が別途必要（§6.4） |

## 3. 検証用に作ったもの（構成）

```text
Experiments/CharacterMotionPoC/
├ CatBehavior/                 Swift パッケージ（標準ライブラリのみ。UI・Spine・SpriteKit・Foundation を import しない）
│  ├ Behavior.swift            行動の選択（気分・反復抑制・自然な順序）と計画（Plan = Step の列）
│  ├ Engine.swift              刺激（なでる・呼ぶ・お祝い・休む）の優先度と割り込み、視線、一時停止、Reduce Motion、出力
│  ├ Motor.swift               体：位置・向き・基本クリップ。根の移動 = 歩行クリップの時間（足が滑らない）
│  ├ Navigation.swift          床・場所（窓・クッション・おもちゃ・正面）・停止位置の計画（ブレンド窓に着地）
│  ├ FootPlanter.swift         クリップのブレンド中は接地した足を固定し、終わったら小さく持ち上げて踏み直す
│  └ MotionProfile.swift       キャラクターごとの数値（計測ツールが出す）
├ MotionLab/                   iOS 検証アプリ（SwiftUI）。Spine 描画と SpriteKit フリップブック描画を切替
├ web/                         ブラウザ検証（公式 spine-ts + 同じ Swift ソースを WebAssembly 化）
├ tools/measure_profile.mjs    Spine の書き出しを公式ランタイムで解析：歩幅、接地、停止できる位相、ルートモーション
├ tools/estimate_flipbook.mjs  同じクリップをフリップブックにした場合のメモリ推計
└ .github/workflows/character-motion-poc.yml（リポジトリ直下）  macOS で build → Simulator で 6 シナリオ録画
```

### 3.1 エンジンの考え方（足が滑らない・瞬間移動しない・壊れない）

1. **根の移動はクリップの時間そのもの。** 歩行中は `root += groundSpeed × Δ(歩行クリップ時間)` で動かす。`groundSpeed`（spineboy は 473.6 units/s）は接地している足が後ろへ動く速さを書き出しから実測した値。速さを変えるときはクリップの再生速度（timeScale）を変えるので、地面に着いた足は常に止まって見える。加減速は timeScale の変化率を 2.5/s に制限して急変させない。
2. **止まれる位相に止まる。** 歩行から待機へのブレンドで足が滑らない位相（接地している足が待機姿勢の位置から 30 units 以内）を計測し（spineboy: 0.378〜0.507）、自律移動は「その範囲で歩き始めて、その範囲で止まる」距離に計画する。足が接地しているので、着地時の位相は距離だけで決まる。
3. **向きは方向転換クリップの最初のフレームでだけ反転する。** 歩行中の反転はしない（いったん止まる → 振り向く → 歩く）。
4. **割り込みは「視線で即応、体は安全な瞬間に」。** 体の前方へのタップには同じフレームで頭（視線）が向く。体はブレーキ距離のあとブレンド窓に入った位置で止まってから反応する。後方へのタップは頭が肩越しに振り返れないので視線は動かず、歩行中なら減速して止まり、振り向いて応じる。ジャンプの空中・方向転換の途中では体の反応を待たせる。待機枠は 1 つで、優先度（お祝い > なでる・休む > 呼ぶ）で決める（Domain の `ReactionQueue` の「最新が置き換える」とは規則が違う。§6.2）。なでるの連打は 2 秒のクールダウン中は視線だけ。なでる反応は、タップした時点の「体のどこを触ったか」に答える（止まるまでに体が進んでも、空いた床を振り返らない）。
5. **フレームが詰まっても跳ばない。** 1 フレームの積分は最大 1/20 秒。一時停止から戻った最初のフレームは、ホストが何秒と報告してもエンジンが 0 秒として扱う。一時停止では待機中の反応を捨て、実行中の反応は今のステップ（跳躍の着地など）で終える。
6. **罪悪感の仕組みを作らない。** 気分（energy / curiosity / playfulness / sociability）は行動の多様性のためだけに使い、表示しない・習慣やユーザーの不在に依存しない・悪い状態がない（energy が下がると昼寝しやすくなるだけ）。
7. **視線は前方だけ。** 後ろの目標は前方に映して見上げる・見渡す。歩いて通り過ぎた目標への視線は終わり、振り向き中は視線を外す（頭が肩越しにねじれない）。

## 4. 検証結果

計測の場所は 3 つ。どれも同じ Swift ソースの行動エンジンを動かしている。

- **単体テスト**（Linux の Swift 6.0.3 と CI の macOS）: エンジン単体。描画なし。
- **ブラウザ**（Chromium + 公式 spine-ts 4.3.13、エンジンは WebAssembly 化した同じ Swift ソース）: 足の位置の精密な計測と録画。仮想時間で 60 Hz 固定なので結果が毎回同じ。**iOS の録画ではない**。
- **iOS Simulator**（GitHub Actions の macOS 26、Xcode 26.6、iPhone 17 / iOS 26.5。MotionLab = SwiftUI + spine-ios）: 実際の iOS アプリとしての動作、録画、フレーム時間、メモリ。CI run 8 の結果。

### 4.1 受け入れ基準の判定

| 基準 | 判定 | ブラウザ | iOS Simulator |
|---|---|---|---|
| 60〜90 秒の無操作で複数の行動を自然な順序で | **合格** | 90 秒で 18 回・8 種類（§4.2）。単体テスト: 40 シード × 90 秒で同じ行動の 3 連続なし・長く止まりっぱなしにならない | 90 秒で 18 回・8 種類（ブラウザと同じ内訳） |
| 歩く・止まる・振り向く・待機・ユーザー操作への反応 | **合格** | 停止 7 回・振り向き 7 回・待機 5 回。なでる・呼ぶ・お祝い・休む に反応（§4.5） | 操作ありで `callReaction` 3、`celebrateReaction` 3、`petReaction` 2、`restReaction` 1 |
| 歩行中に足が滑らない | **合格** | 1 歩の接地の間のつま先の移動 最大 17.5 units（身長の 2.5%、かかと〜つま先の転がりを含む）。クリップ時間と根の移動のずれ 0 ms | 1 歩の接地の間 最大 25.2 units。クリップ時間のずれ 最大 0.00 ms |
| 状態切替で不自然な瞬間移動がない | **合格（サンプル由来の残りあり）** | 1 フレームの最大移動 8.3 units、振り向き以外の反転 0 回。切替 1 回の接地足の移動は最大 39 units（身長の 5.7%、跳躍の前後。他の切替は 8 units 以下。§4.3） | 最大移動 16.6 units（Simulator のフレーム落ちの瞬間。§4.8）、反転 0 回、切替の接地足の移動 最大 44 units |
| ユーザー操作の割り込みで壊れない | **合格** | 歩行中・跳躍中・振り向き中・連打・お祝いの重複を含むシナリオと 20 分の乱打ファズで、瞬間移動・不正な反転・空中での中断なし | 同じ操作シナリオで同じ結果（反転 0、瞬間移動なし） |
| Reduce Motion | **合格** | 歩行 0・跳躍 0 フレーム | アプリ設定: 歩行 0・跳躍 0 フレーム。**OS の設定**（`systemReduceMotion` = true）: 歩行 0・跳躍 0 フレーム |
| バックグラウンドで停止 | **合格** | 10 秒の不在を 1 フレームの経過時間として受けても、エンジンは進まない（0.000 秒） | 設定アプリへ切り替えて約 17 秒: エンジン時間 31.4277 → 31.4277 s、位置 1248.184 → 1248.184（進まない） |
| メモリ | **計測済み（Simulator）** | — | Spine: 20〜24 MB。フリップブック: ピーク 138 MB（テクスチャ 115.3 MB） |
| 実機での確認 | **未実施** | — | この環境は Linux で実機に接続できない（§8 の手順で要確認） |

### 4.2 無操作 90 秒の行動列（ブラウザ、seed 7）

| 時刻 | 行動 | 移動・停止・振り向き |
|---:|---|---|
| 0.0 s | 落ち着く（`settle`） |  |
| 2.4 s | うろうろ歩く（`wander`） | 振り向き ←、停止 x=233 |
| 6.8 s | 見回す（`lookAround`） | 振り向き → |
| 10.3 s | おもちゃで遊ぶ（跳ぶ）（`play`） | 停止 x=1119 |
| 16.6 s | クッションで休む（`nap`） | 停止 x=1532、振り向き ← |
| 31.2 s | 窓へ行って外を見る（`visitWindow`） | 停止 x=524 |
| 40.2 s | 待機（`idle`） |  |
| 45.1 s | 見回す（`lookAround`） | 振り向き → |
| 49.2 s | 待機（`idle`） |  |
| 53.4 s | 正面へ来てユーザーを見る（`approachUser`） | 停止 x=937 |
| 59.0 s | おもちゃで遊ぶ（跳ぶ）（`play`） |  |
| 62.6 s | 待機（`idle`） |  |
| 66.8 s | うろうろ歩く（`wander`） | 振り向き ←、停止 x=402 |
| 72.0 s | 待機（`idle`） |  |
| 75.6 s | 窓へ行って外を見る（`visitWindow`） |  |
| 80.3 s | 待機（`idle`） |  |
| 83.5 s | うろうろ歩く（`wander`） | 振り向き →、停止 x=937 |
| 88.4 s | 見回す（`lookAround`） | 振り向き ← |

止まった位置の歩行位相はすべてブレンド窓 0.378〜0.507 の中。行動の内訳: 待機 5、うろうろ歩く 3、見回す 3、おもちゃで遊ぶ（跳ぶ） 2、窓へ行って外を見る 2、落ち着く 1、クッションで休む 1、正面へ来てユーザーを見る 1。iOS Simulator の同じシナリオ（同じ seed、実際のフレーム時間）の内訳: `approachUser` 1、`idle` 5、`lookAround` 3、`nap` 1、`play` 2、`settle` 1、`visitWindow` 2、`wander` 3。

### 4.3 足の滑り

1 回の切替（ブレンド）の間に、接地している足が動いた距離の合計（両足、units）の最悪値。spineboy の身長は 686 units。「補正なし」は同じセッションを接地補正（IK による足の固定と踏み直し）なしで再生した値（ブラウザ）。

| 場面 | ブラウザ 補正あり | ブラウザ 補正なし | iOS Simulator 補正あり | 補正ありの身長比（ブラウザ） |
|---|---:|---:|---:|---:|
| 待機 → 振り向き | 3.0 | 379.6 | 15.5 | 0.4% |
| 到着 → 振り向き | 7.3 | 476.8 | 7.3 | 1.1% |
| 振り向きの最中 | 1.1 | 37.7 | 4.3 | 0.2% |
| 着地 → 待機 | 23.5 | 113.6 | 23.5 | 3.4% |
| 待機 → 跳躍 | 38.8 | 66.1 | 44.0 | 5.7% |
| 歩き始め | 5.2 | 40.8 | 7.5 | 0.8% |
| 止まる | 4.9 | 42.0 | 6.1 | 0.7% |

1 歩の接地（つま先が床に着いてから離れるまで）の間のつま先の移動の最大値（units）:

| 場面 | ブラウザ 補正あり | ブラウザ 補正なし | iOS Simulator 補正あり |
|---|---:|---:|---:|
| 歩行中 | 17.5 | 16.5 | 25.2 |
| 立っている間（切替のブレンドを除く） | 0.9 | 0.0 | 1.3 |

- 振り向き（`idle-turn`）はサンプルの作りが「最初のフレームで体を左右反転し、反転直後に足を寄せる」もので、補正なしでは接地足が最大 477 units 動く。補正ありでは反転の前後で足を固定し、持ち上げて踏み直すので 7 units。
- 跳躍の前後は、`jump` が大きな跳躍で着地姿勢が待機と違うため補正後も残る。Mali では「その場で小さく跳ぶ」クリップを待機姿勢で着地させる（§6.4）。
- 歩行中は補正を使わない（アニメーションそのままで足が地面に止まる設計）。値はつま先の骨で測っており、かかと〜つま先の転がりを含む上限値。

### 4.4 瞬間移動・向き

| シナリオ | フレーム | 1 フレームの最大移動 | 振り向き以外の向きの反転 | クリップ時間のずれ（歩行中） |
|---|---:|---:|---:|---:|
| 無操作 90 秒（ブラウザ） | 5400 | 7.5 units | 0 | 0.00 ms |
| 無操作 90 秒（Simulator） | 5319 | 12.7 units | 0 | 0.00 ms |
| 操作あり 90 秒（ブラウザ） | 5400 | 8.3 units | 0 | 0.00 ms |
| 操作あり 90 秒（Simulator） | 5192 | 16.6 units | 0 | 0.00 ms |
| バックグラウンドを挟む 45 秒（ブラウザ） | 2701 | 7.5 units | 0 | 0.00 ms |
| バックグラウンドを挟む 45 秒（Simulator） | 1843 | 20.1 units | 0 | 0.00 ms |
| Reduce Motion 40 秒（ブラウザ） | 2400 | 0.0 units | 0 | 0.00 ms |
| Reduce Motion 40 秒（Simulator） | 2143 | 0.0 units | 0 | 0.00 ms |

1 フレームの最大移動は、ブラウザ（60 Hz 固定）では歩行の速さ（474 units/s × 再生速度の上限 1.2 ÷ 60 ≒ 9.5）以下。Simulator ではフレーム落ち（最大 301 ms）の瞬間に大きくなるが、エンジンは 1 回の積分を最大 1/20 秒に制限するので、どんな引っかかりでも 1 フレームの移動は最大 28 units（歩行 1/20 秒ぶん）。単体テストでも不規則なフレーム間隔と 0.5 秒の引っかかりで確認した。

### 4.5 ユーザー操作の割り込み

操作ありのシナリオ（90 秒、seed 11）の入力: 8 s 猫をなでる → 16 s 右端の床をタップ（呼ぶ）→ 26 s 習慣達成のお祝い → 27.5 s 猫を 2 秒で 10 回連打 → 36 s 背中側をタップ → 46 s 「休もう」→ 55 s と 55.4 s にお祝いを 2 回 → 70 s 左端を呼ぶ → 80 s なでる。録画では入力の位置に「scripted tap」の輪を描き、人の操作と区別した。iOS ではタップのジェスチャーと同じ `StageModel.tap` を通す。

| 刺激 | 回数 | 体が応じるまで（ブラウザ 中央 / 最大） | （Simulator 中央 / 最大） |
|---|---:|---:|---:|
| `call` | 3 | 0.00 s / 0.05 s | 0.00 s / 0.82 s |
| `celebrate` | 3 | 0.00 s / 3.78 s | 0.00 s / 3.80 s |
| `encourageRest` | 1 | 0.00 s / 0.00 s | 0.00 s / 0.00 s |
| `pet` | 2 | 0.38 s / 0.38 s | 0.00 s / 0.00 s |

- お祝いの最大値（約 3.8 秒）は、55.4 s の 2 回目のお祝いが 1 回目（55 s）の終わりを待った時間（待機枠 1）。27.5 s からの連打 10 回はお祝いの最中なので、すべて視線だけ（`glance pet busy`）。
- 体の前方へのタップには視線が同じフレームで向く（後方へのタップは頭が振り返れないので、止まって振り向いてから応じる）。体（止まる・振り向く・跳ぶ）は、歩行中ならブレーキ距離のあと足が接地して止まれる位相で止まってから。単体テストで歩行中のなでるを 60 回測ると中央値 1.03 秒・90 パーセンタイル 1.45 秒・最大 1.67 秒（サンプルの歩行に止まれる区間が 1 周期に 1 か所のため。§6.4 の制作条件で短縮できる）。
- 跳躍中のお祝いは着地まで待つ。前方への呼びかけは歩きながら目的地を変え、後方への呼びかけは止まる → 振り向く → 歩く。
- 20 分の乱打ファズ（ランダムな時刻に 4 種の刺激・一時停止・Reduce Motion 切替）で、瞬間移動・振り向き以外の反転・空中での切替・プランの破綻がないことを確認（`testRandomInterruptFuzz`）。

### 4.6 Reduce Motion

- ブラウザ（`prefers-reduced-motion: reduce` を模擬）40 秒: 歩行 0・跳躍 0 フレーム。行動: `callReaction` 1、`celebrateReaction` 1、`idle` 4、`lookAround` 4、`nap` 1、`petReaction` 1、`settle` 1。
- Simulator、アプリの設定で有効（40 秒）: 歩行 0・跳躍 0 フレーム。行動: `callReaction` 1、`celebrateReaction` 1、`idle` 4、`lookAround` 3、`nap` 1、`petReaction` 1、`settle` 1。
- Simulator、**iOS の設定**（`com.apple.Accessibility ReduceMotionEnabled`）で有効（30 秒）: アプリが受け取った値 `UIAccessibility.isReduceMotionEnabled` = true、歩行 0・跳躍 0 フレーム。
- なでる・お祝い・呼ぶには、歩かず跳ばずに、視線とその場の振り向きで応じる。歩行中に Reduce Motion を有効にすると、予定より手前の、接地して止まれる位相で止まる（`testTurningOnReducedMotionMidWalkCutsTheWalkShortOnAPlantedFoot`）。

### 4.7 バックグラウンド停止

- **Simulator**: エンジン時間 31.4 秒の時点で設定アプリを前面にし、約 17 秒後（アプリが記録した非アクティブの時間）に MotionLab を戻した（プロセスはそのまま）。停止時と復帰時のエンジン時間は 31.4277 s と 31.4277 s、位置は 1248.184 と 1248.184（**不在の間は進まない**）。Metal ビューも止め（`isRendering = false` と `SpineController.pause()`）、復帰後の最初のフレームは 0 秒から数える。
- **ブラウザ**（より厳しい条件）: 10 秒の不在をそのまま 1 フレームの経過時間として渡しても、エンジンが進んだのは 0.000 秒、根の移動 0.00 units（一時停止から戻った最初のフレームはエンジンが 0 秒として扱う）。
- 停止中に届いた待機中の反応は捨て、実行中の反応は今のステップ（跳躍の着地など）で終える（復帰時に古い反応を再生しない。docs/05 §3。`testPauseFreezesEverythingAndDropsWaitingReactions`、`testPauseEndsARunningCelebrationAfterTheHopLands`）。

### 4.8 iOS Simulator（GitHub Actions）

GitHub Actions の macOS ランナーで MotionLab を Release ビルドし、iPhone 17 Simulator（iOS 26.5）で 6 シナリオを録画・計測した（CI run 8）。録画は Actions の成果物 `motionlab-simulator-results`（14 日保存）。この環境からは成果物を取得できないため、CI ログに書き出した低解像度のフレーム（2〜4 fps、幅 150 px）から録画を復元して目視確認した。

| シナリオ | 描画 | フレーム | fps（中央） | フレーム時間 p95 / 最大 ms | 1 フレームの最大移動 | 振り向き以外の反転 | 切替の接地足 最悪 u | 1 歩の接地 最大 u | クリップ時間のずれ ms | メモリ MB |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| autonomous | spine | 5319 | 60 | 17.1 / 201 | 12.7 | 0 | 38.8 | 25.2 | 0.00 | 20–24 |
| interaction | spine | 5192 | 60 | 17.7 / 301 | 16.6 | 0 | 44.0 | 25.2 | 0.00 | 20–24 |
| lifecycle | spine | 1843 | 60 | 17.1 / 100 | 20.1 | 0 | 39.0 | 16.5 | 0.00 | 20–24 |
| reducedMotion | spine | 2143 | 60 | 18.3 / 433 | 0.0 | 0 | 3.0 | —（歩かない） | 0.00 | 20–23 |
| systemReduceMotion | spine | 1774 | 60 | 17.3 / 69 | 0.0 | 0 | 2.6 | —（歩かない） | 0.00 | 20–21 |
| flipbook | flipbook | 3535 | 60 | 17.1 / 261 | 12.6 | 0 | 未計測 | 未計測 | 未計測 | 21–138 |

- フレーム時間: 中央値はすべて 60 fps、p95 は 17〜18 ms。CI の Simulator はホストの GPU を共有しており、ときどき最大 433 ms のフレーム落ちがあった（実機の性能の指標にはならない）。行動エンジンは 1 回の積分を 1/20 秒に制限するので、フレーム落ちでも瞬間移動・向きの不正反転は起きていない（反転 0）。フレーム落ちの瞬間の 1 フレームの移動は最大 28 units（歩行 1/20 秒ぶん）。
- メモリ（phys_footprint、iOS がメモリ上限の判定に使う値）: Spine 描画は 20〜24 MB。SpriteKit フリップブックは同じ 4 クリップ（102 フレーム）を表示密度で焼くとテクスチャ 115.3 MB、ピーク 138 MB。
- バックグラウンド: 設定アプリを前面にしている間、エンジン時間と位置は変化せず（31.4277 s / x 1248.184）、復帰後も溜まった時間を再生しない。
- OS の Reduce Motion（`defaults write com.apple.Accessibility ReduceMotionEnabled`）はアプリに届き（`UIAccessibility.isReduceMotionEnabled` = true）、歩行・跳躍 0 フレーム。
- **待機 → 振り向きの切替だけ、Simulator の値がブラウザより大きい**（この run で最大 15.5 units、interaction の 33.85 秒。ひとつ前の run 7 では 39.5。ブラウザは 3.0）。その場面のフレーム記録（足とフットプランターの入出力）を見ると、IK の足ターゲットは切替の間まったく動かず、左右反転の後の踏み替えの最初の 2 フレームで、つま先が床から 5〜12 units の高さのまま横に動き始めている。接地判定（床から 17.2 units 以内）に入るため「滑り」に数えられた。ブラウザで同じ場面をたどると足ターゲットの値は同じで、つま先の高さだけが違う（待機クリップの位相などセッションの細部が違うため。ブラウザでフレーム時間を 600 通り変えても 7.3 以下）。見た目は低い踏み替え（すり足に近い）で、瞬間移動や大きな滑りではない。Mali では、踏み替えの持ち上げを高くして横移動を持ち上げた後に始め、接地は足裏（つま先と踵）で判定する（§6.4）。

**Simulator で初めて見つかった iOS 側の不具合（修正済み）**

最初に Simulator で動いた実行（CI run 3）で、ブラウザでは出ない問題が 2 つ見つかった。どちらも spine-ios の仕様に由来し、公式ソース（固定したリビジョン）で原因を確認して直した。run 3 の足の数値はこのため無効。

| 問題 | 原因 | 対応 |
|---|---|---|
| キャラクターが画面の上端に足だけ見え、体が画面外 | spine-ios の世界座標は **y 下向き**（spine-cpp の `Bone::yDown = true`、シェーダーで y 反転）。MotionLab は y 上向きとして表示範囲を指定していた。同じ理由で足の接地判定（world y ≤ 許容値）が空中の足も「接地」と数え、足の滑りの数値が過大になっていた | 表示範囲と、ボーンから読む世界座標を y 下向きとして変換。ボーンのローカル姿勢（IK ターゲット、視線）は y 上向きのまま |
| 歩行中にクリップがエンジンより最大 58 ms 遅れる | `SpineView` に `isRendering` をバインドすると、SwiftUI がビューを更新するたびに spine-ios のフレーム時計がリセットされ（`SpineUIView.isRendering` の setter が `renderer.lastDraw` を上書き）、次のフレームの経過時間が短くなる。HUD が毎秒 4 回更新していた | アニメーションをエンジンの 1 ステップで進め（`AnimationState.update`）、spine-ios 側の更新は `timeScale = 0` で適用だけにした。クリップ時間のずれは 0.00 ms に |

### 4.9 自動テスト

`CatBehavior` のテスト 32 件（Linux の Swift 6.0.3 と、CI の macOS / Xcode 26.6 の両方で全件成功）。すべての実行で毎フレーム、瞬間移動・振り向き以外の反転・床の外・クリップ時間のずれ・視線が体の後ろを向く・歩行がブレンド窓の外で終わる、を検査する。主なもの:

- 行動: 90 秒で多様な行動、同じ行動の 3 連続なし、長く止まりっぱなしにならない、同じ seed・同じフレーム時間で同じ行動列、気分に悪い状態がなくユーザーの不在に依存しない
- 移動: 90 秒 × 40 シードの不変条件（瞬間移動・振り向き以外の反転・床の外・クリップ時間のずれ）、すべての歩行がブレンド窓で終わる、不規則なフレーム間隔と引っかかり、再生速度が自然な範囲、計画した歩行がブレンド窓で終わる
- 割り込み: 歩行中のなでる、連打、跳躍中のお祝いと重複、前方 / 後方への呼びかけ、20 分の乱打ファズ、反応の遅れの分布、跳躍の着地・振り向きの終わりを待つ、待機中のお祝いが呼びかけに置き換わらない、なでる反応が触った場所に答える（これらのガードは、壊すとそのテストだけが失敗することを確認）
- 一時停止と Reduce Motion: 停止で全て止まり待機中の反応を捨てる、実行中のお祝いは着地で終わる、復帰後の最初のフレームは 0 秒、Reduce Motion で歩かず跳ばない、歩行中に有効化すると予定より手前で接地して止まる（有効化しない同じセッションと比較）、エンジンが Foundation に依存しない
- 接地補正: ブレンド中に接地足が固定されて踏み直す、定常歩行はアニメーションに任せる、振り向きの左右反転をまたいで踏み替える
- 書き出しの計測値とエンジン内蔵の数値の一致、WebAssembly 版との 90 秒の行動列の一致

## 5. 方式比較

比較対象は 3 つ。**A** Spine 2D + 公式 spine-ios（今回の第一候補）、**B** SpriteKit + 本格的なスプライトアニメーション（フリップブック = 全フレームを描いた連番画像）、**C** SpriteKit + 現行のパーツ / 全身リグを拡張（`CatRig` + `SKAction` キーフレーム）。行動の選択・移動・割り込み（`CatBehavior`）は **A・B・C のどれでも同じものを使える**（MotionLab では A と B を同じエンジンで切替えて確認）。

| 観点 | A: Spine + spine-ios | B: SpriteKit フリップブック | C: SpriteKit パーツリグ継続 |
|---|---|---|---|
| アプリ側の実装難易度 | **低〜中**。SwiftUI に `SpineView` を置き、毎フレーム `RenderState` を反映するドライバ約 150 行。CI の Xcode 26 / iOS 26 SDK で初回からビルド成功。C++ コアと Metal 描画は公式ランタイムが担う | **低**。`SKSpriteNode` のテクスチャ差し替え。遷移はクロスフェードを自作 | **中〜高**。既存資産はあるが、骨の階層・IK・メッシュ変形・物理を自作し、キーフレームを JSON で手書きする（エディタなし） |
| 表現力 | **高**。クリップ間の自動ブレンド、トラックの重ね合わせ（歩きながら視線）、IK による視線と足の接地（実証: §4.3）、メッシュ変形・物理（尻尾・ひげ）・スキン（表情差分・衣装）は Professional 版の機能 | **描いた絵の範囲だけ**。クリップ間は 2 枚の半透明重ね（体がにじむ）、視線や足の位置を実行時に変えられない、振り向きは左右反転のみ | **中**。移動・回転・拡大のみ（メッシュ変形なし）。現行の全身 1 枚絵ではポーズ間で輪郭が「跳ぶ」（実装ログ記載の既知事項）。自律歩行には横向きのパーツ一式が別途必要 |
| アセット制作負荷 | 初期のリギング（パーツ分け・骨・ウェイト）は重いが、**クリップの追加は軽い**（同じ部品を動かすだけ）。アニメーターに Spine 経験が必要。書き出しファイルは約 0.3 MB（spineboy: `.skel` 64 KB + atlas PNG 235 KB。展開後のテクスチャは 1.0 MB） | **クリップ × フレーム数**の原画が必要（24fps の歩行 1 周期で 24 枚）。修正は全フレーム描き直し。メモリが大きい（§4.8: 4 クリップで 115 MB 実測 → 15 クリップなら数百 MB 規模） | パーツ PNG + 手書きキーフレーム。可愛さの調整がエンジニア作業になり、アニメーターが直接触れない |
| 保守性 | 公式ランタイム（ソース公開、SPM）。**エディタとランタイムのバージョン（4.3.x）を揃える必要**があり、ランタイム更新時にアセットの再書き出しが要ることがある。spine-ios は比較的新しく、癖がある（世界座標が y 下向き、SwiftUI の更新でフレーム時計がリセットされる。§4.8。どちらもアプリ側で吸収済み）。4.3 の HEAD は変更途中だったため、リリース時点のコミットに固定した | 依存なしで単純。ただし絵の差し替えが重い | 依存なし。自作コード（リグ・IK・補間）が増え続ける |
| 実行時（メモリ・負荷） | atlas 1.0 MB（同じ表示密度なら 1.7 MB）、1 つの Metal ビュー。Simulator 実測でアプリ全体 20〜24 MB、60 fps（§4.8） | テクスチャが支配的。同じ 4 クリップを表示密度で焼くと 115 MB、アプリのピーク 138 MB（Simulator 実測、§4.8） | 軽い（パーツ数枚） |
| ライセンス・費用 | **製品として配布するには Spine のライセンスが必要**（組み込み時点で。Runtimes License / README）。IK 制約・メッシュ等は Professional 版の機能という情報が多い（価格は公式ページで要確認。このセッションからは公式サイトに到達できなかった）。収益・資金調達が直近 12 か月で 50 万 USD を超える事業者は Enterprise（年間契約）が必要 | 無償 | 無償 |
| NikuCue の制約との適合 | 通信なし（ランタイムの HTTP 読み込み機能は使わずバンドルのみ）。**docs/04 §2「Spine/Rive/Live2D を必須にしない」と CLAUDE.md「隠れた制作要件にしない」に対し、オーナーの明示的な仕様改訂が必要** | 適合 | 適合（現行方針） |
| 主なリスク | ライセンス費用、Spine を扱えるアニメーターの確保、ランタイム更新への追従 | メモリ・アプリサイズ、制作量 | 「猫らしい自由行動」の品質に届かない可能性（今回の課題の出発点） |

**判定**: 今回の最重要価値（「Mali が自分の意思で生活しているように感じられ、達成を一緒に喜ぶ」）に必要な、歩く・止まる・振り向く・目で追う・足を地面に着けたまま反応する、という動きは **A が最も少ない実装で最も高い品質に届く**。B は自由行動のために必要なクリップ数でメモリと制作量が破綻しやすく、C は表現の上限が低い。

## 6. 変更対象の設計図（Spine へ移行する場合）

### 6.1 目標の構成

```text
Features（変更は小さい：scene.setTimeOfDay → stage.setTimeOfDay、Gallery のリグ・契約の表示を Spine 用に置換。
          CatRoom・吹き出し・VoiceOver の構成はそのまま。VoiceOver の値は activity からの対応表に）
   │   既存と同じ API：messageKey / currentClip(→activity) / reduceMotion / enterScene / leaveScene /
   │                   pause(reason) / resume(reason) / setPaused / handle(intent) / cancelReactions / playDemo
   ▼
CatStage（新、@MainActor ObservableObject。CatSceneController の外部 API と規則を引き継ぐ）
   ├ CatBehaviorEngine（新パッケージ Packages/CatBehavior。Domain と同列の純粋 Swift、テスト付き）
   │    行動選択・計画・Motor・Navigator・視線・FootPlanter・刺激の優先度・一時停止・Reduce Motion
   ├ StimulusMapper（ReactionIntent → Stimulus、§6.3）
   ├ ReactionTiming（吹き出しの遅延・表示時間・余韻。現行 CatSceneController の規則を移植）
   └ CharacterRenderer（protocol：RenderState を描く・足と視線の骨を扱う・pause/resume・メモリ解放）
        └ SpineCharacterRenderer（spine-ios の SpineView + MotionLab の SpineDriver を製品化。
                                  エンジンの時計でアニメーションを進め、y 下向きの世界座標を変換する）
CatCoordinator（変更小：scene.controller / scene.setTimeOfDay → stage。再検証・節目トークンの記録はそのまま）
NikuCueApp（変更小：scene.isPaused → stage の一時停止に一本化）
NikuCueDomain（変更なし：CatReactionEngine / ReactionQueue / HabitService …）
```

`CatBehavior` は `NikuCueDomain` に依存させない（逆も同じ）。結線は App 層の `CatStage` だけが行う。これにより、描画方式を後から替えても Domain と行動エンジンは無変更で済む（今回 A と B を同じエンジンで動かしたのと同じ形）。

### 6.2 既存 API の引き継ぎ

| 現行（CatSceneController） | 移行後（CatStage） | 備考 |
|---|---|---|
| `handle(_ intent: ReactionIntent)` | `StimulusMapper` で `Stimulus` にして `engine.send` | **要追加実装（規則の統一）**。エンジンの待機枠は優先度で決める（お祝いが待っている間のスキップは視線だけ）。Domain の `ReactionQueue` は「待機できる最新の反応が置き換える」。製品では `ReactionQueue` を正とし、`CatStage` が反応を 1 件ずつエンジンへ渡す（エンジンの優先度は自律行動との関係だけに使う）案を推奨 |
| `isStillValid` / `onReactionStarted` | engine に「開始直前の確認」フックを追加し、開始時に `stimulusApplied` イベント → 節目トークン記録 | 現行の「実際に始まったときだけ記録」「古い反応は始めない」を維持（**要追加実装**） |
| `cancelReactions(habitId:dayKey:)` | `engine.cancel(kind:)`（待機中は破棄、実行中は空中なら着地後に静かに戻る） | **要追加実装**。悲しませない・瞬間移動しない規則は今回の Motor が担保 |
| `pause(.sceneInactive / .modal / .sceneLeft)`・`resume` | 同じ理由集合 → `engine.setPaused` + `SpineView(isRendering:)` + `controller.pause()` | エンジン側は実装済み（待機中の反応を捨てる、実行中の反応は今のステップで終える、復帰後の最初のフレームは 0 秒）。**停止理由の集合と画面の所有者（enterScene / leaveScene）は要移植**（MotionLab は scenePhase の 1 つだけ） |
| `reduceMotion` | `engine.setReducedMotion`（歩かない・跳ばない。その場の振り向き・視線・静かな待機で表現） | 今回実装済み |
| `setAmbient(.dozing)`（夜）・`CatScene.setTimeOfDay`（部屋の色） | 行動選択の文脈に `TimeOfDay` を渡し、夜は昼寝・休息の重みを上げる。部屋の色は SwiftUI の背景に移す | **要追加実装**（小） |
| `messageKey`（吹き出し） | `stimulusApplied` + 反応ごとの `messageAtMs` で表示 | 表示は SwiftUI のまま。**吹き出しの遅延・表示時間・余韻・反応間の間は要移植**（現行 `CatSceneController` の規則） |
| `playDemo`（Gallery / Demo） | 刺激を直接送る、または Spine のクリップを単独再生するデモ用 API | **要追加実装**。Gallery のリグ・表情・契約の表示は Spine 用（スキン・アニメーション一覧）に置換 |
| なでる判定（`CatScene.touchesEnded`） | スケルトンの境界（またはスロットの当たり判定）でタップを判定し `.pet` | **要追加実装**（MotionLab は体の幅の帯で判定） |
| VoiceOver の値（`currentClip` で分岐） | `activity`（`ActivityKind`）からアクセシビリティ値への対応表 | **要追加実装**（小） |
| `activeActionCount`（QA Q40） | engine の計画・イベント数とレンダラーのトラック数 | テストで上限を確認 |

### 6.3 反応（Domain）→ 刺激（行動エンジン）の対応

| `ClipID`（Domain） | 発生源 | 行動エンジンでの扱い（Reduce Motion 時） |
|---|---|---|
| `celebrate` | 習慣を完了 | `.celebrate`：正面を向く → 視線をユーザーへ → その場で小さく跳ぶ → 余韻（跳ばずに、その場の振り向きと視線と笑顔） |
| `milestone` | 3 / 7 / 14 日 | `.celebrate` の大きい版（2 段の喜び + ハート）※ハートは SwiftUI か Spine のスロットで。**刺激は要追加** |
| `pet` | 猫をタップ | `.pet(at:)`：触った場所へ視線、必要なら振り向く（同じ。歩かない） |
| `settle` | スキップ | `.encourageRest`：視線をユーザーへ → 休む（同じ）。悲しい表情は使わない |
| `greet` | 画面に入った・おかえり | 新 `.greet`：視線 → 正面へ歩いて座る（視線のみ） |
| `cheer` | 応援を頼む | 新 `.cheer`：正面で見上げる（同じ） |
| `doze` / `idle` | 時間帯・待機 | 自律行動（夜は昼寝の重みを上げる） |

### 6.4 Mali 用 Spine アセットの要件（制作発注の叩き台）

- **視点**: 自由行動は横向き（または 3/4）の歩行が必要。座りは正面寄りでよい。1 つのスケルトン内でスキン / アタッチメント切替で両立させ、振り向きクリップで正面を経由する。
- **最小クリップ**: `sit_idle`（呼吸 + 尻尾、ループ）、`stand_idle`、`walk`（ループ）、`turn`（その場、最初のフレームで反転する作り）、`sit_down` / `stand_up`、`look`（頭と目の視線、加算トラック）、`groom`（毛づくろい）、`stretch`（伸び）、`nap`（ループ）、`yawn`、`happy_hop`（その場、着地は座りか立ちの待機姿勢へ）、`milestone`、`pet_react`（目を細めて寄る）、`cheer`、`settle`、`greet`、`ear_twitch`（耳・頭の小さな動き。後方からのタップに即座に応じる、加算トラック）。悲しい・空腹・病気の表現は作らない（CLAUDE.md）。
- **骨と制約（Professional 機能を前提）**: 頭・目の視線用 IK ターゲット、前後の足の IK ターゲット（root の子、足の接地に使う）、尻尾とひげの物理、表情差分（目・口のアタッチメント）。
- **歩行の作り方（足を滑らせないための条件）**: その場歩き（root は動かさない）、**1 周期に止まれる区間を左右の足で 2 か所**（今回のサンプルは 1 か所で、割り込みに最大約 1.7 秒かかった）、可能なら `walk_start` / `walk_stop`。停止区間の待機姿勢と足の位置を揃える。
- **書き出し規約**: Spine 4.3.x（ランタイムと同じマイナー版）、バイナリ `.skel` + PMA atlas、@3x で 1:1 になる倍率、root = 床の中心・右向き。
- **接地の判定点**: 足裏の骨（つま先と踵の 2 点）を用意する。踏み替えと接地の検査はその 2 点で行う（今回はつま先の骨しかなく、低い踏み替えも「滑り」に数えた）。
- **受け入れ検査**: `tools/measure_profile.mjs` を Mali の骨名に合わせて拡張し、歩幅・停止区間（2 か所・各 0.2 周期以上）・方向転換のルートモーション・跳躍の空中区間・待機との足の距離を CI で判定する。数値は `MotionProfile` として自動生成し、手入力しない。

### 6.5 移行の段階

| 段階 | 内容 | 規模の目安 |
|---|---|---|
| 0 | 意思決定：Spine の版とライセンス購入者、docs/04 §2・CLAUDE.md の改訂 | オーナー |
| 1 | `CatBehavior` を `Packages/` に昇格（今回のテスト 31 件ごと）、`CatStage` と `SpineCharacterRenderer` を実装、Debug ビルドで現行と切替可能にする | 中 |
| 2 | Mali の Spine リグとクリップ制作（§6.4）、受け入れ検査の CI 化 | 大（アーティスト作業が中心） |
| 3 | Domain 反応の結線（§6.3）、吹き出しの時間、`cancel`・開始直前の確認フック、夜の重み、VoiceOver | 中 |
| 4 | 実機検証（30fps 設定、メモリ、発熱、低電力モード）と G1（可愛さ）レビュー | 中 |
| 5 | 旧 `CatRig` / `AnimationLibrary` / ArtProvider / JSON 契約 / 取り込みツールの削除 | 小 |

## 7. 既知の問題・制約（正直な記録）

- **実機では未確認**。この環境は Linux で実機に接続できない。Simulator は GitHub Actions の macOS（Apple Silicon の Simulator、GPU はホストと共有）で、実機の性能・発熱・電池とは違う。CI の Simulator ではフレーム落ち（最大 1 秒程度）が起きた。
- **Simulator のフル解像度の録画は CI の成果物（14 日保存）にあり、この環境からはダウンロードできない**（成果物の保存先ホストがネットワーク方針で遮断）。数値は CI ログから取得し、録画は CI ログに書き出した低解像度フレーム（2〜4 fps、幅 150 px）から復元して確認した。最初のシナリオは録画開始からアプリの描画まで約 25 秒かかり（Simulator の初回起動）、低解像度版は先頭 100 秒だけなので、無操作 90 秒の後半が切れている。フル解像度版には全体が入っている。
- サンプル由来の限界：`idle-turn` は反転直後に足が寄る作りで、振り向きの間は足を固定して踏み替える（ルートモーションで消そうとすると最初の 1/60 秒で 42 units 跳ぶため不採用）。`jump` は大きな跳躍で、着地姿勢が待機と違う（足の接地補正後も 40 units 程度動く）。視線は銃を構える `aim` を薄く重ねて代用しているため、録画では「銃を向ける」姿勢に見える（Mali では頭と目の IK にする）。
- 割り込みの体の反応は中央値約 1 秒・最大約 1.7 秒（視線は即時）。サンプルの歩行に止まれる区間が 1 周期に 1 か所しかないため。§6.4 の制作条件で短縮できる。
- 足の滑りの計測はつま先の骨で行っており、かかと〜つま先の転がり（自然な動き）も「移動」として数える。値は上限側の評価。
- 待機 → 振り向きの切替で、Simulator では接地足の移動がブラウザより大きく出ることがある（run 7: 39.5、run 8: 15.5 units。ブラウザ 3.0）。記録したフレームでは IK の足ターゲットは固定されており、左右反転の後の踏み替えの最初の 2 フレームでつま先が床から 5〜12 units の低さのまま横に動き始めていた（§4.8）。見た目は低い踏み替え。Mali では持ち上げを高くし、横移動を持ち上げた後に始め、接地は足裏で判定する。
- 跳躍の踏み切り・着地の前後は補正後も接地足が 40 units 前後動く（spineboy の `jump` が大きな跳躍で、着地姿勢が待機と違うため。CI の Simulator のフレーム落ちが重なると最大 59 units まで。ブラウザで 600 通りのフレーム時間を試した値）。
- 視線は体の前方だけ（後ろの目標は前方に映して見上げる・見渡す）。歩いて通り過ぎた目標への視線は終わる。振り向き中は視線を外す。
- WebAssembly 版のビルドには SwiftWasm 6.0.3 ツールチェーンを使った（ブラウザ検証専用。製品には関係しない）。WebAssembly 版と通常の Swift 版で 90 秒の行動列が完全一致することを確認済み。
- MotionLab の画面文言はローカライズしていない（開発ツールのため。製品では既存の文言リソースを使う）。
- 移行で追加・移植が必要なもの（§6.2〜6.3）：夜（`doze`）の重み付けと部屋の色、`cancel` API、開始直前の確認フック、`greet` / `cheer` / `milestone` の刺激、`playDemo`（Gallery / Demo）、吹き出しの時間の規則、停止理由の集合と画面の所有者、なでる判定、VoiceOver の値、Domain の `ReactionQueue` と待機規則の統一。
- 後方へのタップ（体の向きと反対側）には視線が応じない（頭が肩越しに振り返れない）。歩行中なら減速して止まり、振り向いて応じるまで約 1〜2 秒かかる。Mali では耳や頭の小さな動きで即座に応じるクリップを用意したい（§6.4）。
- Reduce Motion でもその場の振り向きは行う（歩行・跳躍はしない）。振り向きも止めるべきかはオーナー確認事項。

## 8. オーナー判断事項と次のタスク

1. **Spine 採用の可否と版**：IK・メッシュ・物理を使うなら Professional 版以上。収益・資金調達が直近 12 か月で 50 万 USD を超える場合は Enterprise。最新の価格・規約は公式ページで確認してください（このセッションからは公式サイトに到達できませんでした）。ライセンスは「組み込み時点」で必要です。
2. **仕様の改訂**：docs/04 §2「Rive/Spine/Live2D を必須にしない」と CLAUDE.md「隠れた制作要件にしない」を、Spine を正式な制作要件とする内容に改める（採用する場合）。
3. **Mali の Spine リグ制作の発注**：§6.4 を叩き台に、アニメーターと視点・クリップ・止まれる区間の条件を合意する。
4. **実機確認**：Mac で `Experiments/CharacterMotionPoC/README.md` の手順（サンプル取得 → `MotionLab.xcodeproj` を開いて実機で Run、Signing で自分の Team を選ぶ）。見る点：歩行中に足が滑らないか、止まる・振り向く瞬間の不自然さ、タップへの反応の速さ、Reduce Motion、バックグラウンド復帰、30 分程度の連続表示での発熱。
5. **Simulator の録画を見る**：GitHub の Actions 実行ページ（https://github.com/yosuke1024/NikuCue/actions/runs/38784494560）の成果物 `motionlab-simulator-results`（14 日で消えます。6 シナリオの mp4・スクリーンショット・診断 JSON）。この環境から直接確認できるようにするには、環境のネットワーク設定で `productionresultssa3.blob.core.windows.net`（または `*.blob.core.windows.net`）を許可してください。
