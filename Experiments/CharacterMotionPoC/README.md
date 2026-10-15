# Character motion PoC（技術検証・出荷しない）

Mali のキャラクター層をゼロベースで再評価するための独立した検証ディレクトリ。既存の `NikuCue/` アプリ・Domain・アセットには一切手を入れていない（Xcode の NikuCue ターゲットはこのフォルダを参照しない）。

| パス | 内容 |
|---|---|
| `CatBehavior/` | Swift パッケージ（標準ライブラリのみ）: 自律行動の選択（Behavior Engine）、移動（Locomotion: 足が滑らない歩行・停止・方向転換）、Navigation（床・場所・停止位置の計画）、ユーザー操作の割り込み、Reduce Motion、一時停止。レンダラーに依存しない |
| `MotionLab/` | iOS 検証アプリ（SwiftUI）。`CatBehavior` + 公式 `spine-ios` で公式サンプル spineboy を動かす。比較用に SpriteKit フリップブック描画も同じエンジンで動く |
| `web/` | ブラウザ検証ハーネス（公式 spine-ts + `CatBehavior` を WebAssembly にコンパイルしたもの）。Linux 環境での計測・録画用（`capture.mjs`）。`probe_timing.mjs` はフレーム時間を変えて同じシナリオを何百通りも再生する調査用ツール |
| `tools/measure_profile.mjs` | Spine の書き出しから歩幅・接地フェーズ・停止ウィンドウ・ルートモーションを計測する（推測値を使わない） |
| `Profiles/spineboy.measured.json` | 上記の計測結果（数値のみ。画像は含まない） |
| `scripts/` | サンプル取得（固定コミット + SHA-256 検証）、Simulator シナリオ実行、診断の集計、CI ログからの静止画・録画の復元（`decode_review_frames.py` / `decode_video_frames.py`） |
| `REPORT.md` | 方式比較・設計図・検証結果・推奨（最終成果物） |

## 公式サンプルの扱い（重要）

- `spineboy` は Esoteric Software の公式サンプル。画像は**非商用のみ**（`examples/spineboy/license.txt`）。**技術検証専用で製品アセットではない**。
- リポジトリは公開設定のため、サンプルの画像・データ・それを写した録画は**コミットしない**（`.gitignore`）。`scripts/fetch_spine_samples.sh` が固定コミットから取得し SHA-256 を検証する。
- Spine Runtimes は評価目的なら無償。製品に組み込んで配布するには、組み込み時点で Spine のライセンスが必要（Spine Runtimes License / README）。

## 固定したバージョン

| もの | 版 | 根拠 |
|---|---|---|
| spine-ios（SPM、`spine-runtimes` リポジトリ） | revision `b7beb2ccbbce667a12c02f44d070644f59b04968`（tag `spine-ts-4.3.13`, 2026-07-24） | 4.3 系の最新リリース時点のスナップショット。HEAD（2026-10-12）は SPM の Metal リソース宣言を外した直後の変更途中だったため避けた |
| spine-ts（npm `@esotericsoftware/spine-core` / `spine-webgl`） | 4.3.13（2026-07-24、npm の `latest`） | 同じリリース |
| サンプルデータ | 同じ revision の `examples/spineboy/export`（Spine 4.3 の書き出し） | ランタイムと同一スナップショット |
| GitHub Actions | checkout v7.0.1 / cache v6.1.0 / upload-artifact v7.0.1（コミット SHA で固定） | 2 週間以上前のリリース |
| Simulator 実行環境 | GitHub `macos-26` イメージ、Xcode 26.6（イメージにあれば `xcode-select` で選択、なければ警告して既定を使用）、iPhone 17 / iOS 26.5 Simulator、Release ビルド | 版は `xcodebuild -version` と `simctl list` で CI ログに記録（Simulator ランタイムはイメージ任せで固定していない） |

## 実行方法（macOS）

```sh
cd Experiments/CharacterMotionPoC
./scripts/fetch_spine_samples.sh                # 評価用サンプルを取得（コミットされない）
swift test --package-path CatBehavior            # エンジンのテスト 31 件（Linux でも可）
open MotionLab/MotionLab.xcodeproj               # Run（iPhone Simulator / 実機。実機は Signing で自分の Team を選ぶ）
```

起動引数（Scheme → Run → Arguments）: `-MLScenario autonomous|interaction|lifecycle|reducedMotion -MLSeconds 90 -MLSeed 7 -MLRenderer spine|flipbook -MLReduceMotion YES`。引数なしなら手動操作（キャラクターをタップ = なでる、床をタップ = 呼ぶ、「Done ✓」= 達成のお祝い）。

プロジェクトファイルは `tools/generate_motionlab_project.py` で生成する（同期フォルダ形式なので Swift ファイルの追加に編集は不要）。

## spine-ios を使うときの注意（この検証で見つけたもの）

- **spine-ios の世界座標は y 下向き**（spine-cpp の `Bone::yDown` が既定で true、シェーダーが y を反転）。`RawBounds` やボーンから読んだワールド座標は y 下向きで扱う。ボーンのローカル姿勢（IK ターゲットなど）はスケルトン本来の y 上向きのまま。
- **`SpineView` に `isRendering` をバインドすると、SwiftUI がビューを更新するたびに spine-ios のフレーム時計がリセットされる**（`SpineUIView.isRendering` の setter が `renderer.lastDraw` を書き換える）。アニメーションを spine-ios のフレーム差分で進めると、更新の多い画面ではクリップが遅れる。MotionLab はアプリ側の時計（行動エンジンの 1 ステップ）で `AnimationState.update` を呼び、spine-ios 側の更新は `timeScale = 0` で適用だけにしている。
