# 仕様パックからの差分（根拠つき）

`spec/` は受け取った仕様パックをそのまま保持する（`spec/SHA256SUMS.txt` で検証可能）。
アプリに同梱する正本は `NikuCue/Resources/` 以下。文章と JSON の不整合、または実装上必要な追加は、
README の方針「勝手に片方を無視せず修正して根拠を記録する」に従いここに記録する。

| ID | 対象 | 変更 | 根拠 |
|---|---|---|---|
| REV-001 | `character_spec.json` `forePawL` / `forePawR` の `position` | `[0,-84]` → `[0,0]`（親 pivot に対する相対位置） | anchor `[0.5,0.87]` のとき position は肩の位置になる。`[0,-84]` では高さ 225 の前足の下端がキャンバス y≈88 となり、地面 `rootGroundY=180` と後ろ足の下端（≈172）より 90 以上沈む。`[0,0]` なら前足は y≈172…397 で後ろ足と同じ地面に接する。JSON の `revisions` にも記録 |
| REV-002 | `animations.json` | 各クリップに `tracks` / `reducedMotionTracks`、`milestone.hearts`、`ambient.blink`、`expressionBlendMs` を追加（既存フィールドは変更なし） | docs/04 §4 の文章による動作記述を、Swift（`AnimationLibrary`）とブラウザプレビューが共通で読める数値キーフレームにした。8 クリップ・`controls`・`durationMs`・`reducedMotion` は維持。値は docs/04 の初期値で、±20% の調整はここに記録する |
| REV-003 | `mali_paths.json`（新規） | 各パーツのベクターパス（M/L/C/Q/Z）とレイヤー（fill/stroke） | docs/04 §2「Core Graphics/CGPath で描いたオリジナル形状をテクスチャ化」の編集可能な書き出し元。生成スクリプトは `tools/character/generate_mali_paths.py`。パレットに派生色 `outline` (#E2C9A6, クリームを少し濃くした輪郭色) を追加 |
| REV-004 | `milestone` のハート位置 | 顔の上ではなく頭の横/上（root 基準 `[-268,600]`,`[0,760]`,`[268,600]`） | 顔に重なると表情が隠れ、承認基準「目と口が顔から滑らない」の確認を妨げるため |
| REV-005 | `cheer` の前足 | 回転 ±14° + 持ち上げ 30 + 縦 scale 0.7 | 回転だけで「胸の前へ」を表現すると前足が交差して不自然だった（プレビュー画像で確認） |
| REV-006 | 部屋の時間帯の色 | 朝 `#FFF1D6` / 昼 `#FBEFD9` / 夜 `#D3C6D4` | docs/05 §6 に色の指定はなく「色変化だけ」とある。夜はクリームの猫が沈まない薄いラベンダーを採用。人間確認項目 |

未変更で読み替えたもの:

- `character_spec.json` の `anchor` は、`mali_paths.json` の各パーツがノード原点（pivot）を基準に描かれているため、描画時には使わない（原点＝anchor の位置になるようパスを生成している）。`anchor` は制作意図の記録として残す。

補足（2026-10-10 方針変更）: REV-003〜REV-007 はコード描画の**開発用プレースホルダー**に関する記録。製品用の猫は画像アセット方式（`docs/CHARACTER_ASSET_PIPELINE.md`）で制作し、原画取り込み時に `character_spec.json` の position / size を `tools/character/build_texture_pack.py` が再生成する（REV-ART-n として JSON 内に記録）。

| REV-L10N-1 | `localization/{en,ja,th}.json` | 追加キー: `habit.moveUp`, `habit.moveDown`, `common.more`, `history.previousMonth`, `history.nextMonth`, `home.otherHabits`, `home.archivedHabits`（パックの 169 キーは値も含めて無変更） | docs/02 §2「並び替えは有効な習慣内で可能」の操作ラベル、履歴の月送りボタンの VoiceOver ラベル、Home で今日以外の曜日の習慣とアーカイブ済み習慣の編集導線に必要。タイ語は他のキーと同様にネイティブ確認（R03）の対象 |

| REV-WB-1 | `mali_poses.json` / `mali_wholebody_spec.json` / `mali_wholebody_animations.json`（新規、生成物） | オーナー提供の全身イラスト 6 枚用の rig（root / shadow / bodyPivot / pose の 4 ノード、フレーム 1024 × 1066、root = (512, 60)）と、8 クリップを「ポーズ切替 + 軽い動き」に置き換えた track。`character_spec.json` / `animations.json` は無変更 | docs/04 §2「絵を差し替えるときは `CharacterArtProvider` を差し替える」の範囲で、アセット README の制約（cross-fade 120–220 ms、呼吸 ≤ 1.5 %、持ち上げと戻りのみ、伸縮なし、sad を skip で出さない）を数値で固定した。clip → ポーズはアセット manifest の `clip_mapping`、milestone は celebrate → happy。生成元 `tools/character/import_wholebody_pack.py` / `generate_wholebody_tracks.py`。R02 承認まで `isProductionArt: false` |
| REV-WB-2 | `milestone.hearts`（全身 rig 版） | 位置 `[-360,840]`, `[320,860]`, `[440,620]`、上昇 80 | celebrate ポーズの alpha を測り、顔・上げた前足に重ならずフレーム内（床から 1006 以内）に収まる角へ。REV-004 と同じ理由 |
| REV-WB-3 | `mali_poses.json` `poses.idle`（`layers.tail`, `layerParts`）、`mali_wholebody_spec.json`（`tailPivot` / `tail` ノード）、`mali_wholebody_animations.json` idle | 待機を 14.4 秒ループにし、呼吸（scaleY 1.015 / scaleX 0.996、3.6 秒）と尻尾の揺れ（tailPivot ±5°、4.8 秒）を追加。尻尾はオーナーの idle 画像から切り出した派生レイヤーで、体の後ろに描く | オーナー要望（2026-10-11）「アイドル中にゆっくり呼吸と尻尾の揺れ」。README §6 のとおり尻尾は別レイヤーでのみ動かし、一枚絵は伸縮させない。切り出しは `tools/character/import_wholebody_pack.py` が再現可能に生成し、`tail_split_check.png` で人が確認する |
| REV-WB-4（廃止） | `MaliSleepy` 画像セット（コードによる前足レタッチ） | オーナーが v1.1 で修正版の原画を提供したため廃止。スクリプト・フック・確認シートは削除 | 同日中に REV-WB-5 で置き換え |
| REV-WB-5 | `docs/assets/mali_v1_1`（v1.1 パック）、`MaliSleepy` 画像セット | sleepy を修正版（座り姿勢 + 半眼・閉じた口。前足 2 本 + 後ろ足 2 本）に置き換え、旧 v1 パックは削除。他の 5 枚はバイト同一 | `ANATOMY_CORRECTION_v1_1.md`。clip → ポーズ対応（doze→sleepy、expressionMap sleepy→sleepy）と他の表情は無変更 |
| REV-WB-6 | `mali_wholebody_animations.json`（全クリップの時間・キー、`lingerMs` / `messageAtMs` / `reactionGapMs`）、`CatSceneController` | 動作の間を見直した（反応の余韻、連続反応の間、吹き出しの遅延、idle / doze の呼吸と尻尾の変化、取り消しで瞬間リセットしない）。長さは docs/04 から greet +9 %、pet +11 %、cheer +8 %、settle +8 %、milestone +4.5 % | オーナー要望（2026-10-11）。docs/04 §4「±20% 程度の調整は記録して行ってよい」。§5「表情の切替は 80〜120ms」は parts rig 向けで、全身画像はアセット README の 120〜220 ms（180 ms）を維持 |

