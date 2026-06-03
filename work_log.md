# 開発ログ (NES game)

ファミコン(NES)ゲーム開発の進捗メモ。ca65アセンブリ / NROM-256 (PRG 32KB + CHR 8KB, mapper 0) / エミュレータ FCEUX。

> ハードウェア不安定問題（このマシン固有・開発とは無関係）の調査記録は別ファイル `hardware_issue.md`（gitignore済）にある。

---

## 進捗

### ✅ 1. 開発環境の整備
- ツールチェーン: cc65 V2.18 (ca65 / ld65)、make、git（導入済み）
- エミュレータ: FCEUX (`/usr/games/fceux`)
- プロジェクト雛形: `Makefile`（make / run / clean）、`nes.cfg`（ld65設定）、`src/main.s`

### ✅ 2. Hello World（背景1色塗り）
- iNESヘッダ / リセット処理（vblank2回待ち・RAMクリア）/ パレット書き込み / NMI の基本骨格
- 青い背景が出ることを確認

### ✅ 3. コントローラ入力
- `read_controller`: `$4016` に 1→0 でラッチ → 8回読み出し `pad1` に格納（A B Sel St ↑ ↓ ← →）
- デモ: 押したボタンで背景色 `$3F00` が変化
- 動作確認OK

### ✅ 4. スプライト表示＋移動 ← イマココ
- CHRタイル1にキャラ絵（8x8の赤い丸、目2px透明）を定義
- OAMバッファ `$0200` を起動時 `$FF` で初期化（全スプライト画面外）
- 毎フレームNMIで OAM DMA（`$4014`←`$02`）転送、スクロール0リセット
- `move_player`: 十字キーで `player_x/player_y` を ±2px、画面端でクランプ
- PPUMASK にスプライト表示ON（`%00011110`）
- 動作確認OK（十字キーでキャラが動く）

---

## ファイル構成
```
~/code/nes/
├── Makefile          # make / make run / make clean
├── nes.cfg           # ld65設定 (NROM-256, mapper0)
├── src/main.s        # メインソース (現在: スプライト移動デモ)
├── README.md
├── work_log.md       # このファイル
├── hardware_issue.md # HW調査メモ (gitignore済・別件)
└── game.nes          # ビルド成果物 (gitignore済)
```

## ビルド & 実行
```bash
make        # game.nes をビルド
make run    # FCEUX で起動
make clean
```

---

## 次の候補（未着手）
1. **アニメーション** — 歩行でタイル切替 / 進行方向でスプライト左右反転（OAM属性 bit6）
2. **複数スプライト** — 8x8を4枚で16x16の大きいキャラ
3. **背景描画** — ネームテーブルに地面・壁などのステージを描く
4. **入力エッジ検出** — 前フレーム差分で「押した瞬間」を取る（メニュー/ジャンプ向け）

## メモ / 注意
- 実機キー割り当て（矢印/A=F/B=D等）はFCEUX側設定で、NESコードとは独立。
- RAM不安定問題が未解決のため、節目ごとに git commit してローカルに溜めない方針。
