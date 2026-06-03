; =============================================================
; NES コントローラ入力デモ (ca65 / NROM-256, mapper 0)
;   押したボタンで画面全体の背景色が変わる。
;     ↑=緑 ↓=赤 ←=黄 →=水色 / A=白 B=マゼンタ / 無押下=黒
;   $4016 から1コントローラ分(8ボタン)を読み取る基本形。
; =============================================================

; ---- PPU / コントローラ レジスタ ----
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
JOYPAD1   = $4016

; ---- ボタンビット (pad1 内の並び: A B Sel St U D L R) ----
BTN_A      = %10000000
BTN_B      = %01000000
BTN_SELECT = %00100000
BTN_START  = %00010000
BTN_UP     = %00001000
BTN_DOWN   = %00000100
BTN_LEFT   = %00000010
BTN_RIGHT  = %00000001

; -------------------------------------------------------------
; 変数 (ゼロページ)
; -------------------------------------------------------------
.segment "ZEROPAGE"
pad1:    .res 1         ; 現在のボタン状態
bgcolor: .res 1         ; 表示する背景色 ($3F00 に書く値)

; -------------------------------------------------------------
; iNES ヘッダ (16 byte)
; -------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte 2            ; PRG-ROM 2 * 16KB = 32KB
    .byte 1            ; CHR-ROM 1 * 8KB
    .byte $00          ; flags6 : mapper 0
    .byte $00          ; flags7
    .byte $00,$00,$00,$00,$00,$00,$00,$00

; -------------------------------------------------------------
; リセット処理
; -------------------------------------------------------------
.segment "CODE"
.proc reset
    sei
    cld
    ldx #$40
    stx $4017          ; APU フレーム IRQ 無効
    ldx #$ff
    txs
    inx                ; X = 0
    stx PPUCTRL        ; NMI 無効
    stx PPUMASK        ; 描画オフ
    stx $4010          ; DMC IRQ 無効

:   bit PPUSTATUS      ; 1回目の vblank 待ち
    bpl :-

    txa                ; RAM クリア
clear_ram:
    sta $0000, x
    sta $0100, x
    sta $0200, x
    sta $0300, x
    sta $0400, x
    sta $0500, x
    sta $0600, x
    sta $0700, x
    inx
    bne clear_ram

:   bit PPUSTATUS      ; 2回目の vblank 待ち
    bpl :-

    ; パレット書き込み ($3F00-)
    bit PPUSTATUS
    lda #$3f
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #0
load_palette:
    lda palette, x
    sta PPUDATA
    inx
    cpx #32
    bne load_palette

    lda #$0f           ; 背景色の初期値 = 黒
    sta bgcolor

    lda #$00           ; スクロール初期化
    sta PPUADDR
    sta PPUADDR

    lda #%10000000     ; NMI 有効
    sta PPUCTRL
    lda #%00001110     ; 背景表示 ON
    sta PPUMASK

forever:
    jmp forever        ; あとは NMI に任せる
.endproc

; -------------------------------------------------------------
; NMI (毎フレーム vblank): 入力読取 → 色決定 → 画面反映
; -------------------------------------------------------------
.proc nmi
    pha
    txa
    pha
    tya
    pha

    jsr read_controller
    jsr update_color

    ; 背景色 $3F00 を更新 (vblank 中なので書き込み可)
    bit PPUSTATUS
    lda #$3f
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda bgcolor
    sta PPUDATA

    ; VRAM アドレス / スクロールを 0 に戻す
    lda #$00
    sta PPUADDR
    sta PPUADDR
    sta PPUSCROLL
    sta PPUSCROLL

    pla
    tay
    pla
    tax
    pla
    rti
.endproc

; -------------------------------------------------------------
; コントローラ1 を読み取り pad1 に格納
;   ストローブ後 8 回読むと pad1 = A B Sel St U D L R (bit7..0)
; -------------------------------------------------------------
.proc read_controller
    lda #$01
    sta JOYPAD1
    lda #$00
    sta JOYPAD1        ; 1→0 で状態をラッチ
    ldx #8
loop:
    lda JOYPAD1        ; bit0 にボタン状態 (1=押下)
    lsr a              ; bit0 → キャリー
    rol pad1           ; キャリーを pad1 に取り込む
    dex
    bne loop
    rts
.endproc

; -------------------------------------------------------------
; pad1 の内容から bgcolor を決定
;   複数同時押し時は後で評価したボタンが優先される
; -------------------------------------------------------------
.proc update_color
    lda #$0f           ; 既定: 黒
    sta bgcolor

    lda pad1
    and #BTN_UP
    beq :+
    lda #$2a           ; 緑
    sta bgcolor
:
    lda pad1
    and #BTN_DOWN
    beq :+
    lda #$16           ; 赤
    sta bgcolor
:
    lda pad1
    and #BTN_LEFT
    beq :+
    lda #$28           ; 黄
    sta bgcolor
:
    lda pad1
    and #BTN_RIGHT
    beq :+
    lda #$21           ; 水色
    sta bgcolor
:
    lda pad1
    and #BTN_B
    beq :+
    lda #$14           ; マゼンタ
    sta bgcolor
:
    lda pad1
    and #BTN_A
    beq :+
    lda #$30           ; 白
    sta bgcolor
:
    rts
.endproc

; -------------------------------------------------------------
; パレットデータ
; -------------------------------------------------------------
.segment "RODATA"
palette:
    .byte $0f,$10,$30,$0f,  $0f,$06,$16,$0f
    .byte $0f,$09,$19,$0f,  $0f,$01,$11,$0f
    .byte $0f,$10,$30,$0f,  $0f,$06,$16,$0f
    .byte $0f,$09,$19,$0f,  $0f,$01,$11,$0f

; -------------------------------------------------------------
; 割り込みベクタ
; -------------------------------------------------------------
.segment "VECTORS"
    .word nmi          ; $FFFA: NMI
    .word reset        ; $FFFC: RESET
    .word 0            ; $FFFE: IRQ/BRK

; -------------------------------------------------------------
; CHR-ROM (8KB) — タイルは未使用 (全0)
; -------------------------------------------------------------
.segment "CHARS"
    .res 8192, $00
