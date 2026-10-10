# Mali 画像アセット方式への移行設計

作成: 2026-10-10 / 方針変更: オーナー指示（コード描画の猫は開発用プレースホルダーに限定し、製品用は高品質 2D イラストの画像パーツをアニメーションさせる）

## 0. 決定事項（この文書で固定するもの）

| # | 決定 |
|---|---|
| A1 | コードで図形を組み合わせて描く猫（`VectorArtProvider` + `mali_paths.json`）は**開発用プレースホルダー**。これ以上作り込まない。`isProductionArt: false` のまま、Gallery と吹き出しに「placeholder」を表示する |
| A2 | 製品用の猫は**原画（高品質 2D イラスト）をパーツ分けした PNG** を SpriteKit で動かす。レンダリング方式は「画像パーツ + 既存の rig / キーフレーム」 |
| A3 | SpriteKit、ノード階層（`character_spec.json`）、キーフレーム（`animations.json`）、`CatRig` / `AnimationLibrary` / `CatSceneController`、Domain（反応エンジン・キュー・習慣ロジック）は**そのまま維持** |
| A4 | 原画の差し替えは `CharacterArtProvider` の実装差し替え（`TexturePackArtProvider`）と `mali_texture_pack.json` の同梱で行い、状態遷移・習慣ロジックには触れない |
| A5 | 正式な原画がオーナーから提供され、Gallery で承認されるまで、猫のビジュアルは**未完成**（RELEASE_BLOCKERS R02 は開いたまま） |
| A6 | **暫定段階（2026-10-10 〜）**: オーナー提供の全身イラスト 6 枚（`docs/assets/mali_v1`）を `WholeBodyArtProvider` で表示し、クリップごとにポーズを cross-fade + 軽い動き（持ち上げ・小さな傾き・呼吸 ≤ 1.5 %）で見せる。パーツ分け原画（A2）が来るまでの置き換えであり、瞬き・しっぽ・手足は動かさない。製品ビジュアルの完成扱いはしない |

## 1. 現在の実装の仕分け

### 1-a. そのまま再利用する（画像方式でも変更不要）

| 部品 | 場所 | 理由 |
|---|---|---|
| rig 契約（ノード ID・親子・z-order・pivot の意味） | `NikuCue/Resources/Character/character_spec.json` | 画像でも同じ階層で動かす。**position / size の数値だけ**原画のピボットから再生成する（REV として記録） |
| キーフレーム track（8 クリップ + Reduce Motion 版 + blink + hearts） | `NikuCue/Resources/Character/animations.json` | ノード単位の回転・移動・scale・表情の時系列。絵に依存しない。原画後に ±20% の調整のみ |
| `CatRig`（ノード生成、rest transform、表情クロスフェード、heart 生成） | `NikuCue/Character/CatRig.swift` | 絵は `CharacterArtProvider` から `PartArt`（texture / size / anchor）として受け取るだけ |
| `AnimationLibrary` / `KeyframeSampler` | `NikuCue/Character/AnimationLibrary.swift` | track → キー付き `SKAction`。絵に依存しない |
| `CatSceneController`（キュー・pause/復帰・Reduce Motion・ハート・吹き出し dwell） | `NikuCue/Character/CatSceneController.swift` | 絵に依存しない |
| `CatScene` / `CatSceneView` / `CatRoom` | `NikuCue/Character/` | 1 シーン、30fps、タップ、部屋の色。将来、部屋をイラスト化する場合も同じ場所で差し替え |
| `CharacterArtProvider` protocol / `PartArt` | `NikuCue/Character/CharacterArtProvider.swift` | **差し替えの継ぎ目**。画像実装を追加する |
| `AnimationSpec` / `RigSpec` デコーダと検証 | `NikuCue/Character/RigSpec.swift` | そのまま |
| Domain（`CatReactionEngine` / `ReactionQueue` / `CatEvent` / `HabitService` ほか） | `Packages/NikuCueDomain` | 描画と完全に分離済み。56 テスト通過 |
| `CatCoordinator` / `HomeViewModel` / Demo / Gallery 画面 | `NikuCue/App`, `NikuCue/Features` | provider が変わっても呼び出しは同じ |
| `tools/rig-preview`（ブラウザ描画） | `tools/rig-preview/` | 画像パーツを `drawImage` で描く拡張を入れれば、Xcode なしでも原画のアニメ確認に使える（任意、§6） |

### 1-b. 開発用プレースホルダーに限定する（削除はしないが作り込まない）

| 部品 | 扱い |
|---|---|
| `VectorArtProvider`（CGPath → テクスチャ） | テクスチャパックが同梱されていない間のフォールバック。Debug Gallery で「placeholder」と明示 |
| `mali_paths.json` / `tools/character/generate_mali_paths.py` | 凍結。形の調整は行わない（REV-007 を最後とする） |
| `artifacts/P01/*`・公開プレビュー | 「動作検証用プレースホルダー」とラベルを改める |

### 1-c. 新規に作るもの

| 部品 | 内容 |
|---|---|
| `mali_texture_pack.json`（manifest） | パーツ名 → テクスチャ名・bounds（ノード原点基準、design units）。表情 variant。`pixelsPerUnit`。ライセンスと出典 |
| `TexturePackArtProvider` | manifest + `SKTextureAtlas`（または同梱 PNG）から `PartArt` を返す。読み込み時に全パーツを preload、`validate(against:)` で欠落検出 |
| `tools/character/build_texture_pack.py` | イラストレーターの書き出し（PNG + レイヤー bounds + ピボット座標）→ manifest + atlas フォルダ + `character_spec.json` の position/size 更新 + 合成チェック画像 |
| `scripts/check_resources.py` の拡張 | manifest・PNG の存在・ピクセルサイズ・表情 variant の網羅を検証 |
| `NikuCueTests/TexturePackArtProviderTests` | 合成テクスチャで provider の size / anchor / 欠落検出を検証 |
| provider 選択（`AppContainer`） | 同梱 manifest があればテクスチャパック、なければプレースホルダー。Debug Gallery で切替 |

## 2. 座標系と契約（原画と実装の共通言語）

- **デザインキャンバス**: 1024 × 1024 design units、原点は左下、y は上向き（SpriteKit と同じ）。地面の中心 `root` = (512, 180)。これは現行と同じ。
- **書き出し解像度**: `pixelsPerUnit = 2`（キャンバス 2048 × 2048 px）。猫（約 760 units）は 1520 px になり、300pt × @3x = 900 px の部屋に対して十分。1 サイズのみ同梱し、SpriteKit の線形フィルタで縮小する。
- **ノード位置**: `character_spec.json` の `position` は親ノード原点からの相対（units）。原画のピボットから `build_texture_pack.py` が計算する。
- **パーツ bounds**: 各パーツ画像の矩形を**そのパーツのノード原点基準**で `[minX, minY, maxX, maxY]`（units, y 上向き）として manifest に持つ。SpriteKit の `anchorPoint` は `(-minX/幅, -minY/高さ)` で求める（`VectorArtProvider` と同じ式。画像の px サイズ = bounds の幅・高さ × pixelsPerUnit）。
- **ピボット（関節）**: イラストレーターが印を付けるのは次の 8 点だけ。残りのパーツの原点は画像の中心で良い。

| マーカー名 | 位置 | 回転・移動の最大値（animations.json より） |
|---|---|---|
| `root` | 地面の中心（影の中心） | 動かない。ジャンプは `bodyPivot` が +34 units |
| `bodyPivot` | 胴の中心（呼吸・ジャンプの基準） | scale ±3.5%、Y +34 |
| `tailPivot` | しっぽの付け根（胴に隠れる位置） | 回転 ±10° |
| `forePawLPivot` / `forePawRPivot` | 左右の肩（前足の回転中心） | 回転 最大 34°、Y +30、縦 scale 0.7（cheer） |
| `headPivot` | 首（頭の回転中心） | 回転 ±7°、X ±6、Y −14〜+12 |
| `earLPivot` / `earRPivot` | 耳の付け根 | 現状回転なし（将来の余地） |

- **重なり（継ぎ目対策）**: 上の最大値で回しても地が見えないよう、隠れる側を塗り足す。目安: 頭の下（首）60 units、前足の上端 40 units、しっぽの付け根 50 units、耳の付け根 30 units。docs/04 §3「10〜15% 重ねる」の具体化。
- **表情**: `eyeL` / `eyeR` / `mouth` に `neutral / softSmile / closedHappy / curious / sleepy` の 5 差分（15 枚）。目と口の**位置を変えず**差し替える（`CatRig` の 2 枚スプライトで 100ms クロスフェード）。任意で `blink`（閉じ目）差分を加えると瞬きを画像差し替えにできる（無ければ縦 scale で代用）。
- **その他**: `heart`（節目のハート 1 枚）、`shadow`（影 1 枚。無ければ現行の楕円を使う）、`muzzle` / `cheekL` / `cheekR` / `nose` は頭と別レイヤー（顔の位置合わせのため）。

## 3. 原画の制作仕様（イラストレーターへの依頼内容）

1. **キャラクター**: docs/04 §1 のバイブル（クリーム色の丸い猫、キャラメル色の耳としっぽ先、白い口元、小さなピンクの鼻、丸い頬、短い足、太いしっぽ。アクセサリーなし。他 IP の流用なし）。正面に近い座りポーズ（プレースホルダーと同じ構図でよい。スクリーンショットを参考として渡す）。
2. **キャンバス**: 2048 × 2048 px、透明背景、sRGB。猫の本体は中央、地面は下から y=360 px（= 180 units）付近。本体はおよそ 1520 × 1440 px 以内。
3. **レイヤー分け**（名前は固定、1 レイヤー 1 パーツ）: `shadow`, `tail`, `body`, `hindPawL`, `hindPawR`, `forePawL`, `forePawR`, `earL`, `earR`, `head`, `muzzle`, `cheekL`, `cheekR`, `nose`, `eyeL.neutral` … `eyeL.sleepy`, `eyeR.*`, `mouth.*`, `heart`。隠れる部分も塗る（§2 の重なり）。
4. **ピボット**: `pivots` グループに §2 の 8 点を小さな点レイヤーとして置く（または座標を JSON / テキストで添付）。
5. **納品物**: 編集可能な元データ（PSD / Procreate / Affinity 等）、レイヤーごとの PNG（レイヤー境界でトリミング）、各レイヤーの位置・サイズ（px, 左上原点）の一覧（`layers_export.json`。多くのツールの書き出しで得られる。無ければ手書きで可）、著作権・商用利用の確認文。
6. **確認基準**（docs/04 §6）: 64 px でも猫と分かる。表情差分で別の猫にならない。回転しても継ぎ目が裂けない。悲しみ・涙・空腹の差分は作らない。

## 4. ランタイム設計

```text
AppContainer
 ├ CharacterArtSelection.resolve(bundle:)
 │    ├ mali_poses.json がある        → WholeBodyArtProvider（暫定: 全身 6 枚、rig = mali_wholebody_spec.json, track = mali_wholebody_animations.json）
 │    ├ mali_texture_pack.json がある → TexturePackArtProvider（production or review、rig = character_spec.json）
 │    └ 無い                         → VectorArtProvider（placeholder、rig = character_spec.json）
 ├ CatRig(spec: selection.rigResourceName, art: provider)   ← look（表情名 or ポーズ名）を 2 枚スプライトで cross-fade
 ├ AnimationLibrary(spec: selection.animationResourceName)  ← expression track は look 名を運ぶ
 └ CatScene / CatSceneController                            ← 変更なし（瞬きは目ノードがある rig だけ）
```

- 全身段階の契約: `mali_poses.json`（ポーズ → image set、床中心基準の bounds、clip → ポーズ、`expressionMap`、`optionalPoses` / `neverShowOnSkip`）。各ポーズは同じ 1024 フレームを保ち、bounds でポーズごとの床を root に合わせる（実行時クロップなし）。rig フレームは 1024 × 1066、root = (512, 60)、`designSize` = フレーム。`CatScene.layoutRig` は designSize を画面の 92 % に収め root を下端 6 % に置くので、最も高いポーズ + 持ち上げ + ハートがフレーム内に収まる（`check_resources.py` が検証）。
- パーツ分け原画が納品されたら `mali_poses.json` を同梱から外す（または `build_texture_pack.py` の出力を同梱する）だけで A2 の経路に戻る。状態遷移・反応・習慣ロジックは触らない。

- `TexturePackArtProvider.art(for:expression:pixelsPerUnit:)`: manifest の part / variant を引き、テクスチャを `SKTextureAtlas(named:)`（`MaliParts.spriteatlas`、Xcode が自動でアトラス化）か同梱 PNG から取得。`size` = bounds の幅・高さ（units）、`anchorPoint` = bounds から計算。`pixelsPerUnit` 引数は無視（画像の解像度は固定）。
- 起動時 `validate(against: rigSpec)`: 描画ノード全てにパーツがある、目と口に 5 表情、bounds が正、テクスチャが存在。欠落があれば Debug ではエラー表示、Release では placeholder にフォールバック**しない**（製品は画像のみ。欠落は出荷前に検出）。
- メモリ目安: 26 パーツ + 表情 15 枚、2 px/unit で合計 10〜15 MB（RGBA）。アトラス化で分割読み込み。`purgeCache()` はメモリ警告時に textures を解放し再読込。
- 画像への scale 適用（celebrate の 1.03 / 0.96、cheer の縦 0.7）はラスタでも問題ない範囲。必要なら値を調整。

## 5. 移行手順と受入基準

| 手順 | 担当 | 受入基準 |
|---|---|---|
| S1 骨組み（provider / manifest / build script / 検証 / テスト / provider 選択） | Claude（今回） | テクスチャパック無しで従来どおり動く。`check_resources.py` が manifest 有無の両方で PASS |
| S1' 全身 6 枚の暫定表示（2026-10-10 実施） | Claude | `import_wholebody_pack.py` → imageset + `mali_poses.json` + rig、`generate_wholebody_tracks.py` → track。`check_resources.py` PASS、ブラウザで 6 ポーズ × 明暗と 8 クリップを記録（`artifacts/mali-assets-v1`）。Simulator / 実機は未実施 |
| S2 原画の制作（追加レイヤーの判断はオーナー: 瞬き・しっぽ・耳・前足など §3 の順で） | オーナー（イラストレーター） | §3 の納品物が揃う |
| S3 変換 | Claude | `build_texture_pack.py` で manifest・atlas・`character_spec.json` の position を生成。合成チェック画像が原画と一致（ピボット誤差 ≤ 2 px） |
| S4 ブラウザ / Gallery 確認 | オーナー + Claude | 8 クリップで継ぎ目なし、64 px 判読、表情で位置ずれなし、Reduce Motion、30fps・メモリ（実機） |
| S5 キーフレーム調整 | Claude | ±20% 以内の調整を `SPEC_REVISIONS.md` に記録 |
| S6 承認 | オーナー | manifest の `isProductionArt: true`、R02 を閉じる |

## 6. 任意の補助

- `tools/rig-preview/rig.js` は manifest + PNG の `drawImage` モードを持つ（実装済み）。`mali_texture_pack.json` が `NikuCue/Resources/Character/` にあれば `build.py` / `build_artifact.py` が PNG を data URI で埋め込み、Xcode を使わずブラウザで原画のアニメを確認できる（ダミー画像で動作確認済み）。
- Gallery に provider 切替（placeholder ↔ texture pack）を置き、同じクリップで見比べられるようにする。

## 7. リスクと対策

| リスク | 対策 |
|---|---|
| ピボットのずれで関節が不自然 | 合成チェック画像で原画と比較。8 点のみ artist に依頼、残りは bbox 中心 |
| 表情差し替えで目・口が滑る | 表情レイヤーは同じ頭レイヤー上で描き、トリミング前の位置を `layers_export.json` から取る |
| 回転で地が見える | §2 の重なり量を依頼時に明記。Gallery の最大角で確認 |
| メモリ / 起動時間 | アトラス + preload。2 px/unit に固定。必要なら 1.5 px/unit に下げる |
| placeholder と製品の混同 | manifest の `isProductionArt` と Gallery の表示で区別。R02 を閉じるまで「完成」と書かない |

## 8. オーナーへの確認事項

1. ポーズと構図は現行（正面の座り）で良いか。別ポーズ（横向き・丸まり）は rig の変更を伴う。
2. 納品フォーマット（PSD / Procreate / Figma）と、レイヤー位置の書き出し方法。
3. 影とハート、部屋の背景も原画に含めるか（含めない場合は現行の単色・楕円を使う）。
4. 輪郭線の有無・線の太さなど画風（プレースホルダーの線画風に合わせる必要はない）。
