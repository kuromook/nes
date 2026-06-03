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

; ---- 物理 (ジャンプ / 重力) ----
GRAVITY  = 40      ; 重力加速度 (1/256 px/frame^2)
JUMP_VEL = $FC00   ; ジャンプ初速 = -4.0 px/frame (8.8 符号付き)
FLOOR_Y  = 208     ; 地面の上に立つ Y (地面 row27=y216, スプライト8px)

; ---- 足場 (プラットフォーム) ----
NUM_PLATFORMS = 3  ; 足場の枚数 (plat_top/x0/x1 テーブルと一致させる)

; ---- 背景タイル / ステージ ----
TILE_SKY    = 0    ; 空 (空白タイル)
TILE_GROUND = 2    ; 地面 (レンガタイル)
GROUND_ROW  = 27   ; この行から下を地面にする (27,28,29 の3行)

; ---- キャラのアニメ ----
TILE_WALK_A = 1          ; 歩行フレームA (デフォルト・停止時もこれ)
TILE_WALK_B = 3          ; 歩行フレームB (足の位置違い)
ANIM_MASK   = %00001000  ; このビットで A/B を切替 (= 8フレーム周期)
ATTR_FLIP   = %01000000  ; OAM 属性: 水平反転 (bit6) = 左向き

OAM = $0200        ; OAM バッファ (1ページ = スプライト64個分)

; -------------------------------------------------------------
; 変数 (ゼロページ)
; -------------------------------------------------------------
.segment "ZEROPAGE"
pad1:      .res 1   ; ボタン状態
player_x:  .res 1   ; キャラ X 座標
player_y:  .res 1   ; キャラ Y 座標 (整数部 / OAM へ渡す)
py_sub:    .res 1   ; Y 座標の小数部 (8.8 固定小数の下位)
vy_lo:     .res 1   ; Y 速度 小数部 (8.8 符号付き)
vy_hi:     .res 1   ; Y 速度 整数部
on_ground: .res 1   ; 接地フラグ (1 = 地面の上)
pad1_prev: .res 1   ; 前フレームのボタン状態 (エッジ検出用)
facing_attr:.res 1  ; キャラの向き = OAM 属性 (0=右 / $40=左反転)
anim_timer:.res 1   ; 歩行アニメ用フレームカウンタ
moving:    .res 1   ; このフレームに横入力があったか (1=歩行中)
prev_y:    .res 1   ; 更新前の Y (足場の通過判定に使う)
bg_tile:   .res 1   ; 背景描画ループの一時タイル番号
ptr_lo:    .res 1   ; 汎用ポインタ下位 (足場描画でPPUADDR計算に使用)
ptr_hi:    .res 1   ; 汎用ポインタ上位

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

    jsr draw_background   ; ネームテーブルにステージを描く (描画OFF中)

    ; キャラ初期位置 (画面中央付近・空中スタート → 重力で着地)
    lda #120
    sta player_x
    lda #112
    sta player_y
    lda #0
    sta py_sub
    sta vy_lo
    sta vy_hi
    sta on_ground
    sta pad1_prev

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
    lda player_x
    sta OAM+3          ; X 座標
    jsr animate        ; OAM+1(タイル) と OAM+2(属性=向き) をセット

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
    lda #0
    sta moving         ; 横入力フラグをクリア

    ; --- 左 ---
    lda pad1
    and #BTN_LEFT
    beq @no_left
    lda #ATTR_FLIP     ; 左向き (スプライト反転)
    sta facing_attr
    lda #1
    sta moving
    lda player_x
    cmp #SPEED
    bcc @no_left       ; 左端なら動かさない (向き/歩行は維持)
    sec
    sbc #SPEED
    sta player_x
@no_left:

    ; --- 右 ---
    lda pad1
    and #BTN_RIGHT
    beq @no_right
    lda #$00           ; 右向き (反転なし)
    sta facing_attr
    lda #1
    sta moving
    lda player_x
    cmp #X_MAX
    bcs @no_right      ; 右端なら動かさない
    clc
    adc #SPEED
    sta player_x
@no_right:

    ; --- ジャンプ (A を押した瞬間 & 接地時のみ) ---
    lda pad1_prev
    eor #$ff
    and pad1            ; このフレーム新たに押されたボタン
    and #BTN_A
    beq @no_jump
    lda on_ground
    beq @no_jump
    lda #<JUMP_VEL      ; 上向き初速をセット
    sta vy_lo
    lda #>JUMP_VEL
    sta vy_hi
    lda #0
    sta on_ground
@no_jump:

    ; --- 重力: vy += GRAVITY ---
    clc
    lda vy_lo
    adc #<GRAVITY
    sta vy_lo
    lda vy_hi
    adc #>GRAVITY
    sta vy_hi

    ; --- 位置更新: (player_y.py_sub) += vy  (8.8 符号付き加算) ---
    lda player_y
    sta prev_y         ; 通過判定用に更新前のYを保存
    clc
    lda py_sub
    adc vy_lo
    sta py_sub
    lda player_y
    adc vy_hi
    sta player_y

    ; --- 足場(プラットフォーム)との当たり判定 (落下中のみ=一方通行) ---
    lda vy_hi
    bmi @after_plat    ; vy<0 (上昇中) は足場を通り抜ける
    ldy #NUM_PLATFORMS-1
@ploop:
    ; X 重なり: player_x < x1 かつ player_x+7 >= x0
    lda player_x
    cmp plat_x1,y
    bcs @pnext         ; player_x >= x1 → 横が重ならない
    lda player_x
    clc
    adc #7
    cmp plat_x0,y
    bcc @pnext         ; player_x+7 < x0 → 横が重ならない
    ; 縦の通過: prev_feet <= top かつ new_feet >= top
    lda prev_y
    clc
    adc #8             ; prev_feet
    cmp plat_top,y
    beq @pcheck_new    ; ==top はOK
    bcs @pnext         ; prev_feet > top → 既に下にいた
@pcheck_new:
    lda player_y
    clc
    adc #8             ; new_feet
    cmp plat_top,y
    bcc @pnext         ; new_feet < top → まだ届いていない
    ; 着地: 足場の上にスナップして停止
    lda plat_top,y
    sec
    sbc #8
    sta player_y
    lda #0
    sta py_sub
    sta vy_lo
    sta vy_hi
    lda #1
    sta on_ground
    jmp @save_pad
@pnext:
    dey
    bpl @ploop
@after_plat:

    ; --- 地面との当たり判定 ---
    lda player_y
    cmp #FLOOR_Y
    bcc @airborne      ; player_y < FLOOR_Y → 空中
    lda #FLOOR_Y       ; 着地: 床にスナップして停止
    sta player_y
    lda #0
    sta py_sub
    sta vy_lo
    sta vy_hi
    lda #1
    sta on_ground
    jmp @save_pad
@airborne:
    lda #0
    sta on_ground

@save_pad:
    lda pad1           ; 次フレームのエッジ検出用に保存
    sta pad1_prev
    rts
.endproc

; -------------------------------------------------------------
; アニメ: キャラのタイル(OAM+1)と向き(OAM+2)を決める
;   歩行中(moving=1): anim_timer を進めて A/B を 8フレーム周期で交互
;   停止中: フレームAで固定・カウンタリセット
;   向きは move_player がセットした facing_attr を反映
; -------------------------------------------------------------
.proc animate
    lda moving
    beq @idle

    inc anim_timer
    lda anim_timer
    and #ANIM_MASK
    beq @frame_a
    lda #TILE_WALK_B
    jmp @set_tile
@frame_a:
    lda #TILE_WALK_A
@set_tile:
    sta OAM+1
    jmp @attr

@idle:
    lda #0
    sta anim_timer
    lda #TILE_WALK_A
    sta OAM+1

@attr:
    lda facing_attr
    sta OAM+2
    rts
.endproc

; -------------------------------------------------------------
; 背景描画: ネームテーブル($2000) にステージを描く
;   上 27 行 = 空(タイル0) / 下 3 行 = 地面(タイル2)
;   属性テーブル(64byte) は全て BG パレット0
;   ※ 描画OFF中に呼ぶこと (960+64 byte の転送に時間がかかる)
; -------------------------------------------------------------
.proc draw_background
    bit PPUSTATUS         ; アドレスラッチをリセット
    lda #$20              ; ネームテーブル0 = $2000
    sta PPUADDR
    lda #$00
    sta PPUADDR

    ldx #0                ; 行番号 0..29
@row:
    cpx #GROUND_ROW
    bcc @sky
    lda #TILE_GROUND      ; 27 行目以降 = 地面
    jmp @set
@sky:
    lda #TILE_SKY         ; それより上 = 空
@set:
    sta bg_tile
    ldy #32               ; 1 行 = 32 列
@col:
    lda bg_tile
    sta PPUDATA
    dey
    bne @col
    inx
    cpx #30
    bne @row

    ; 属性テーブル ($23C0-$23FF) = 64 byte 全て 0 (全タイルが BG パレット0)
    ldy #64
    lda #$00
@attr:
    sta PPUDATA
    dey
    bne @attr

    jsr draw_platforms    ; 足場をネームテーブルへ上書き
    rts
.endproc

; -------------------------------------------------------------
; 足場描画: plat_top/x0/x1 の各足場をレンガ(タイル2)で描く
;   ネームテーブルアドレス = $2000 + top*4 + x0/8
;     (top=row*8 なので top*4 = row*32 = 行頭オフセット)
;   タイル数 = (x1 - x0) / 8
; -------------------------------------------------------------
.proc draw_platforms
    ldy #0
@ploop:
    cpy #NUM_PLATFORMS
    bcs @done

    ; ptr = top*4
    lda plat_top,y
    sta ptr_lo
    lda #0
    sta ptr_hi
    asl ptr_lo
    rol ptr_hi
    asl ptr_lo
    rol ptr_hi
    ; ptr += x0/8
    lda plat_x0,y
    lsr a
    lsr a
    lsr a
    clc
    adc ptr_lo
    sta ptr_lo
    lda ptr_hi
    adc #0
    sta ptr_hi
    ; ptr += $2000
    lda ptr_hi
    clc
    adc #$20
    sta ptr_hi

    ; PPUADDR = ptr
    bit PPUSTATUS
    lda ptr_hi
    sta PPUADDR
    lda ptr_lo
    sta PPUADDR

    ; タイル数 = (x1-x0)/8 → X
    lda plat_x1,y
    sec
    sbc plat_x0,y
    lsr a
    lsr a
    lsr a
    tax
@wloop:
    lda #TILE_GROUND
    sta PPUDATA
    dex
    bne @wloop

    iny
    jmp @ploop
@done:
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
    ; 背景パレット0: $3F00=空の青(backdrop) / 1=レンガ茶 / 2=明茶 / 3=目地の白
    .byte $22,$07,$17,$30,  $22,$07,$17,$30
    .byte $22,$07,$17,$30,  $22,$07,$17,$30
    ; スプライトパレット
    .byte $0f,$16,$27,$30,  $0f,$1a,$2a,$30
    .byte $0f,$12,$22,$30,  $0f,$14,$24,$30

; -------------------------------------------------------------
; 足場テーブル (ピクセル座標 / 描画と当たり判定で共用)
;   top = 上面Y / x0 = 左端X / x1 = 右端X(排他)。タイル境界(8の倍数)
;   右上へ向かう階段状の3枚 (row22/18/14, 幅4/5/5 タイル)
; -------------------------------------------------------------
plat_top: .byte 176, 144, 112   ; row 22 / 18 / 14 (*8)
plat_x0:  .byte  32,  96, 176   ; col 4 / 12 / 22 (*8)
plat_x1:  .byte  64, 136, 216   ; col 8 / 17 / 27 (*8)

; -------------------------------------------------------------
; 割り込みベクタ
; -------------------------------------------------------------
.segment "VECTORS"
    .word nmi
    .word reset
    .word 0

; -------------------------------------------------------------
; CHR-ROM (8KB)
;   タイル0=空白 / 1=歩行A / 2=地面 / 3=歩行B
;   1タイル = 16byte (plane0 8byte + plane1 8byte)
;   キャラ: body=index1(赤), 目=index3(白)。右側に目→反転で左右の向きが出る
; -------------------------------------------------------------
.segment "CHARS"
    ; タイル0: 空白
    .res 16, $00
    ; タイル1: キャラ 歩行フレームA (右向き)
    .byte $3c,$7e,$ff,$ff,$ff,$ff,$66,$c2   ; plane 0 (キャラ全体)
    .byte $00,$00,$00,$04,$00,$00,$00,$00   ; plane 1 (目 index3 のみ)
    ; タイル2: レンガの地面 (本体=index1 茶 / 目地=index3 白)
    ;   plane0 は全ピクセル1 (index1/3 はどちらも plane0=1)
    ;   plane1 が1の所だけ目地(index3)。上半分と下半分で継ぎ目をずらす
    .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff   ; plane 0
    .byte $ff,$10,$10,$10,$ff,$01,$01,$01   ; plane 1 (横ライン+縦継ぎ目)
    ; タイル3: キャラ 歩行フレームB (足の位置だけ違う)
    .byte $3c,$7e,$ff,$ff,$ff,$ff,$66,$43   ; plane 0
    .byte $00,$00,$00,$04,$00,$00,$00,$00   ; plane 1 (目 index3 のみ)
    ; 残りを 0 で埋めて 8KB に (タイル0..3 = 64byte)
    .res 8192 - 64, $00
