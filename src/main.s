; =============================================================
; NES スプライト移動デモ (ca65 / NROM-256, mapper 0)
;   十字キーでキャラ(8x8スプライト)が上下左右に動く。
;   - CHR にキャラ絵(タイル1)を用意
;   - OAM バッファ($0200)を OAM DMA($4014)で毎フレーム転送
;   - 十字キー入力で player_x / player_y を増減
; =============================================================

; ---- PPU / コントローラ / DMA レジスタ ----
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014
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

; ---- 移動パラメータ ----
SPEED = 2
X_MAX = 248        ; 画面右端 (256 - 8px)
Y_MAX = 224        ; 下方向の上限

OAM = $0200        ; OAM バッファ (1ページ = スプライト64個分)

; -------------------------------------------------------------
; 変数 (ゼロページ)
; -------------------------------------------------------------
.segment "ZEROPAGE"
pad1:     .res 1   ; ボタン状態
player_x: .res 1   ; キャラ X 座標
player_y: .res 1   ; キャラ Y 座標

; -------------------------------------------------------------
; iNES ヘッダ
; -------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte 2            ; PRG 32KB
    .byte 1            ; CHR 8KB
    .byte $00          ; mapper 0
    .byte $00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

; -------------------------------------------------------------
; リセット処理
; -------------------------------------------------------------
.segment "CODE"
.proc reset
    sei
    cld
    ldx #$40
    stx $4017
    ldx #$ff
    txs
    inx                ; X = 0
    stx PPUCTRL
    stx PPUMASK
    stx $4010

:   bit PPUSTATUS      ; 1回目 vblank
    bpl :-

    txa                ; RAM クリア
clear_ram:
    sta $0000, x
    sta $0100, x
    sta $0300, x
    sta $0400, x
    sta $0500, x
    sta $0600, x
    sta $0700, x
    inx
    bne clear_ram

    ; OAM バッファを $FF で埋めて全スプライトを画面外に隠す
    lda #$ff
    ldx #0
clear_oam:
    sta OAM, x
    inx
    bne clear_oam

:   bit PPUSTATUS      ; 2回目 vblank
    bpl :-

    ; パレット書き込み
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

    ; キャラ初期位置 (画面中央付近)
    lda #120
    sta player_x
    lda #112
    sta player_y

    lda #$00           ; スクロール初期化
    sta PPUADDR
    sta PPUADDR

    lda #%10000000     ; NMI 有効 / パターンテーブルは $0000
    sta PPUCTRL
    lda #%00011110     ; 背景 + スプライト 表示 ON
    sta PPUMASK

forever:
    jmp forever
.endproc

; -------------------------------------------------------------
; NMI: 入力読取 → 移動 → OAM更新 → DMA転送 → スクロール戻し
; -------------------------------------------------------------
.proc nmi
    pha
    txa
    pha
    tya
    pha

    jsr read_controller
    jsr move_player

    ; スプライト0 (キャラ) を OAM バッファへ書き込み
    lda player_y
    sta OAM+0          ; Y 座標
    lda #1
    sta OAM+1          ; タイル番号 (1 = キャラ絵)
    lda #0
    sta OAM+2          ; 属性 (パレット0 / 反転なし)
    lda player_x
    sta OAM+3          ; X 座標

    ; OAM DMA: $0200-$02FF を PPU の OAM へ一括転送
    lda #$00
    sta OAMADDR
    lda #>OAM          ; = $02
    sta OAMDMA

    ; スクロールを 0 に戻す
    bit PPUSTATUS
    lda #$00
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
; 十字キーで player_x / player_y を更新 (画面端でクランプ)
; -------------------------------------------------------------
.proc move_player
    ; --- 左 ---
    lda pad1
    and #BTN_LEFT
    beq @no_left
    lda player_x
    cmp #SPEED
    bcc @no_left       ; 左端なら動かさない
    sec
    sbc #SPEED
    sta player_x
@no_left:

    ; --- 右 ---
    lda pad1
    and #BTN_RIGHT
    beq @no_right
    lda player_x
    cmp #X_MAX
    bcs @no_right      ; 右端なら動かさない
    clc
    adc #SPEED
    sta player_x
@no_right:

    ; --- 上 ---
    lda pad1
    and #BTN_UP
    beq @no_up
    lda player_y
    cmp #SPEED
    bcc @no_up
    sec
    sbc #SPEED
    sta player_y
@no_up:

    ; --- 下 ---
    lda pad1
    and #BTN_DOWN
    beq @no_down
    lda player_y
    cmp #Y_MAX
    bcs @no_down
    clc
    adc #SPEED
    sta player_y
@no_down:

    rts
.endproc

; -------------------------------------------------------------
; コントローラ1 を読み取り pad1 に格納
; -------------------------------------------------------------
.proc read_controller
    lda #$01
    sta JOYPAD1
    lda #$00
    sta JOYPAD1
    ldx #8
loop:
    lda JOYPAD1
    lsr a
    rol pad1
    dex
    bne loop
    rts
.endproc

; -------------------------------------------------------------
; パレット (BG 16 + スプライト 16)
;   スプライトパレット0 の色1 = $16(赤) → キャラ本体の色
; -------------------------------------------------------------
.segment "RODATA"
palette:
    ; 背景パレット (今回は背景色 $3F00=$0f 黒 のみ見える)
    .byte $0f,$00,$10,$30,  $0f,$00,$10,$30
    .byte $0f,$00,$10,$30,  $0f,$00,$10,$30
    ; スプライトパレット
    .byte $0f,$16,$27,$30,  $0f,$1a,$2a,$30
    .byte $0f,$12,$22,$30,  $0f,$14,$24,$30

; -------------------------------------------------------------
; 割り込みベクタ
; -------------------------------------------------------------
.segment "VECTORS"
    .word nmi
    .word reset
    .word 0

; -------------------------------------------------------------
; CHR-ROM (8KB)
;   タイル0 = 空白 / タイル1 = キャラ絵(目が空いた丸)
;   1タイル = 16byte (plane0 8byte + plane1 8byte)
; -------------------------------------------------------------
.segment "CHARS"
    ; タイル0: 空白
    .res 16, $00
    ; タイル1: キャラ絵 (color index 1 で塗り、目の2pxは透明)
    .byte %00111100    ; plane 0
    .byte %01111110
    .byte %11011011
    .byte %11111111
    .byte %11111111
    .byte %11111111
    .byte %01111110
    .byte %00111100
    .byte $00,$00,$00,$00,$00,$00,$00,$00   ; plane 1 (全0 → 色は index1)
    ; 残りを 0 で埋めて 8KB に
    .res 8192 - 32, $00
