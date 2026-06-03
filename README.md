# NES ゲーム開発プロジェクト

ファミコン (NES) 用ゲームを cc65 ツールチェーン (ca65 アセンブラ) で開発するプロジェクト。

## 開発環境

| 役割 | ツール | 状態 |
|------|--------|------|
| アセンブラ / リンカ | cc65 (ca65 / ld65) V2.18 | インストール済み |
| エミュレータ | FCEUX | `sudo apt install fceux` |
| ビルド | make | インストール済み |

## ディレクトリ構成

```
.
├── Makefile      ビルド定義
├── nes.cfg       ld65 リンカ設定 (NROM-256, mapper 0)
├── src/
│   └── main.s    メインソース (6502 アセンブリ)
└── game.nes      ← ビルド生成物 (.gitignore 済み)
```

## 使い方

```bash
make        # game.nes をビルド
make run    # ビルドして FCEUX で起動
make clean  # 生成物を削除
```

## メモ

- ROM 構成は NROM-256 (PRG 32KB + CHR 8KB, mapper 0)。
- 現状の `main.s` は背景を 1 色で塗りつぶすだけの最小サンプル。
- スプライト・BG タイル・コントローラ入力などはここから拡張していく。
