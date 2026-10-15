# Mali キャラクター基盤 技術検証レポート（Spine 2D + spine-ios ／ SpriteKit 比較）

作成: 2026-10-15 ／ ブランチ `claude/loving-gates-ak20t5` ／ 対象ディレクトリ `Experiments/CharacterMotionPoC/`

> 公式サンプル `spineboy` は技術検証専用（画像は非商用ライセンス）。製品アセットではなく、リポジトリにも録画にも製品として含めない。既存の `NikuCue/` アプリ・Domain・Mali 原画には一切手を入れていない。

<!-- RESULTS_SUMMARY -->

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

<!-- RESULTS -->

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
5. **Simulator の録画を見る**：GitHub の Actions 実行ページ（<!-- SIM_RUN_URL -->）の成果物 `motionlab-simulator-results`（14 日で消えます。6 シナリオの mp4・スクリーンショット・診断 JSON）。この環境から直接確認できるようにするには、環境のネットワーク設定で `productionresultssa3.blob.core.windows.net`（または `*.blob.core.windows.net`）を許可してください。
