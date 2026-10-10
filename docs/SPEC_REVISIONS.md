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
