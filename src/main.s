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

; ---- 移動パラメータ / ワールド ----
SPEED      = 2
WORLD_W    = 512   ; ワールド幅 = 2画面 (ネームテーブル2枚)
WORLD_MAX  = 504   ; キャラ X の右端 (512 - 8px)
SCREEN_W   = 256   ; 画面幅
CAM_OFFSET = 120   ; カメラがキャラを置く画面内X (中央付近)
CAM_MAX    = WORLD_W - SCREEN_W  ; カメラXの上限 = 256

; ---- 物理 (ジャンプ / 重力) ----
GRAVITY  = 40      ; 重力加速度 (1/256 px/frame^2)
JUMP_VEL = $FC00   ; ジャンプ初速 = -4.0 px/frame (8.8 符号付き)
FLOOR_Y  = 208     ; 地面の上に立つ Y (地面 row27=y216, スプライト8px)

; ---- 足場 (プラットフォーム) ----
NUM_PLATFORMS = 6  ; 足場の枚数 (plat_* テーブルと一致させる)

; ---- コイン / 得点 ----
NUM_COINS  = 8           ; コインの枚数 (coin_* テーブルと一致させる)
TILE_COIN  = 4           ; コインの CHR タイル番号
DIGIT_BASE = 5           ; 数字 '0'..'9' = タイル 5..14
COIN_PAL   = %00000001   ; OAM 属性: スプライトパレット1 (金)
SCORE_PAL  = %00000010   ; OAM 属性: スプライトパレット2 (白)
COIN_SLOT0 = 4           ; コインの OAM 開始オフセット (スロット1 = 4)
SCORE_SLOT = 36          ; 得点HUD の OAM 開始オフセット (スロット9 = 9*4)
HUD_DIGITS = 4           ; 得点の表示桁数
HUD_X      = 16          ; 得点表示の画面内X (左端の桁)
HUD_Y      = 16          ; 得点表示の画面内Y
BLINK_MASK = %00001000   ; このビットで狙いのコインを点滅 (8フレーム周期)
; ---- コンボ加点 (方法A) ----
;   コイン取得ごとに combo_rem を半減 → bonus = COIN_MAX - combo_rem を加算。
;   取り続けるほど combo_rem が小さくなり bonus が COIN_MAX に近づく (= 加点増)。
;   ※NESのCPUはBCD無効なので得点は16bit2進で持ち、表示時に10進変換する。
COIN_MAX   = 64          ; combo_rem の初期値 (= bonus の上限)

; ---- トゲ (障害物) ----
NUM_SPIKES = 4           ; トゲの本数 (spike_* テーブルと一致させる)
TILE_SPIKE = 15          ; トゲの CHR タイル番号
SPIKE_PAL  = %00000011   ; OAM 属性: スプライトパレット3 (灰)
SPIKE_SLOT0 = 52         ; トゲの OAM 開始オフセット (スロット13 = 13*4)
;   触れたら即死 → init_game_state で最初から完全リスタート

; ---- 敵キャラ (動く障害物) ----
NUM_ENEMIES = 3          ; 敵の数 (enemy_* テーブルと一致させる)
TILE_ENEMY  = 16         ; 敵の CHR タイル番号
ENEMY_PAL   = %00000011  ; OAM 属性: スプライトパレット3 (トゲと共有 / 敵は index2=緑)
ENEMY_SLOT0 = 68         ; 敵の OAM 開始オフセット (スロット17 = 17*4)
ENEMY_SPEED = 1          ; 敵の移動速度 (px/frame)
;   地面を左右に往復 (端で反転)。触れたら即死

; ---- ゴール (全コイン取得で出現) ----
TILE_GOAL  = 17          ; ゴールの CHR タイル (金の星)
GOAL_PAL   = %00000001   ; OAM 属性: スプライトパレット1 (金)
GOAL_SLOT  = 80          ; ゴールの OAM オフセット (スロット20 = 20*4)
GOAL_X     = 16          ; ゴールのワールドX (左端＝コイン群から離した出口)
GOAL_Y     = 204         ; ゴールのY (地面に立つプレイヤーと重なる高さ)

; ---- ステージクリア表示 "CLEAR" ----
TILE_C     = 18          ; 文字タイル C/L/E/A/R = 18..22
TILE_L     = 19
TILE_E     = 20
TILE_A     = 21
TILE_R     = 22
CLEAR_SLOT0 = 84         ; "CLEAR" の OAM 開始オフセット (スロット21)
CLEAR_PAL  = %00000010   ; スプライトパレット2 (白)
CLEAR_X    = 108         ; 5文字×8px=40px を画面中央へ
CLEAR_Y    = 64          ; 空の高い位置 (足場のレンガに重ならないよう)

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
px_lo:     .res 1   ; キャラ X ワールド座標 下位 (0..504)
px_hi:     .res 1   ; キャラ X ワールド座標 上位 (0 or 1)
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
camera_lo: .res 1   ; カメラ X 下位 (スクロール量 0..256)
camera_hi: .res 1   ; カメラ X 上位 (0 or 1 = ネームテーブル選択)
screen_x:  .res 1   ; キャラの画面内X (= px - camera, OAM へ渡す)
bg_tile:   .res 1   ; 背景描画ループの一時タイル番号
ptr_lo:    .res 1   ; 汎用ポインタ下位 (描画/当たり判定の一時計算用)
ptr_hi:    .res 1   ; 汎用ポインタ上位
tmp_lo:    .res 1   ; 汎用一時 下位 (コイン判定/描画の計算用)
tmp_hi:    .res 1   ; 汎用一時 上位
score_lo:  .res 1   ; 得点 (16bit 2進) 下位
score_hi:  .res 1   ; 得点 (16bit 2進) 上位
combo_rem: .res 1   ; コンボ残量 (方法A: 取得ごと半減 / MAXとの差がボーナス)
next_coin: .res 1   ; 次に取るべきコイン番号 (0..8 / 順番制)
frame_cnt: .res 1   ; NMI ごとに +1 (点滅などの周期用)
coin_active: .res NUM_COINS ; コイン表示フラグ (1=未取得/表示, 0=取得済)
score_dec: .res HUD_DIGITS  ; 得点の10進各桁 (表示用 / bin2dec の出力)
enemy_x_lo: .res NUM_ENEMIES ; 敵の現在X 下位 (RAM)
enemy_x_hi: .res NUM_ENEMIES ; 敵の現在X 上位 (画面内patrolなので不変)
enemy_dir:  .res NUM_ENEMIES ; 敵の進行方向 (0=右 / 1=左)
cleared:    .res 1   ; ステージクリア状態 (0=プレイ中 / 1=クリア)

; -------------------------------------------------------------
; iNES ヘッダ
; -------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte 2            ; PRG 32KB
    .byte 1            ; CHR 8KB
    .byte $01          ; flags6: mapper0 / bit0=1 垂直ミラー (水平スクロール用)
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

    jsr init_game_state   ; プレイヤー位置・スコア・コンボ・コインを初期化

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
; ゲーム状態の初期化 (起動時 & 死亡時の完全リスタートで共用)
;   プレイヤーを初期位置(空中)へ / スコア・コンボ・コインを初期状態へ
;   ※背景/パレットは不変なので触らない (描画ON中に呼んでも安全)
; -------------------------------------------------------------
.proc init_game_state
    lda #120           ; キャラ初期位置 (ワールドX=120・空中→落下)
    sta px_lo
    lda #0
    sta px_hi
    lda #112
    sta player_y
    lda #0
    sta py_sub
    sta vy_lo
    sta vy_hi
    sta on_ground
    sta pad1_prev
    sta score_lo       ; 得点 0
    sta score_hi
    sta next_coin      ; 最初に取るコイン = 0番
    sta cleared        ; クリア状態を解除
    lda #COIN_MAX      ; コンボ残量を初期化
    sta combo_rem
    ldx #NUM_COINS-1   ; 全コインを「未取得(表示)」に
    lda #1
@init_coins:
    sta coin_active, x
    dex
    bpl @init_coins

    ldx #NUM_ENEMIES-1 ; 敵を初期位置(min)・右向きへ
@init_enemies:
    lda enemy_min_lo, x
    sta enemy_x_lo, x
    lda enemy_min_hi, x
    sta enemy_x_hi, x
    lda #0
    sta enemy_dir, x
    dex
    bpl @init_enemies
    rts
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

    inc frame_cnt      ; 点滅などの周期カウンタ

    jsr read_controller

    lda cleared
    bne @frozen        ; クリア後はゲーム更新を止める (Startで再開)

    ; --- プレイ中: ゲーム更新 ---
    jsr move_player
    jsr update_coins   ; コイン取得判定 → 得点加算 (ワールド座標, カメラ不要)
    jsr update_enemies ; 敵を左右に動かす
    jsr check_spikes   ; トゲ当たり判定 → 触れたら最初からリスタート
    jsr check_enemies  ; 敵当たり判定 → 触れたら最初からリスタート
    jsr check_goal     ; 全コイン取得後、ゴール接触で cleared=1
    jmp @render

@frozen:
    lda pad1           ; クリア画面: Start で最初から
    and #BTN_START
    beq @render
    jsr init_game_state

@render:
    jsr update_camera  ; camera_lo/hi と screen_x を計算

    ; スプライト0 (キャラ) を OAM バッファへ書き込み
    lda player_y
    sta OAM+0          ; Y 座標
    lda screen_x
    sta OAM+3          ; 画面内X 座標
    jsr animate        ; OAM+1(タイル) と OAM+2(属性=向き) をセット
    jsr draw_coins     ; コイン(スロット1-8) と 得点HUD(スロット9-12) を描画
    jsr draw_spikes    ; トゲ(スロット13-16) を描画
    jsr draw_enemies   ; 敵(スロット17-19) を描画
    jsr draw_goal      ; ゴール(スロット20) を描画 (全コイン取得後のみ)
    jsr draw_clear     ; "CLEAR"(スロット21-25) を描画 (cleared 時のみ)

    ; OAM DMA: $0200-$02FF を PPU の OAM へ一括転送
    lda #$00
    sta OAMADDR
    lda #>OAM          ; = $02
    sta OAMDMA

    ; スクロール設定: カメラXを反映 (PPUCTRL のネームテーブルbit + PPUSCROLL)
    bit PPUSTATUS      ; 書き込みトグル(w)をリセット
    lda #%10000000     ; NMI有効 / パターン$0000
    ora camera_hi      ; bit0 = ネームテーブルX (camera_hi が 1 で右画面)
    sta PPUCTRL
    lda camera_lo
    sta PPUSCROLL      ; X スクロール
    lda #$00
    sta PPUSCROLL      ; Y スクロール = 0

    pla
    tay
    pla
    tax
    pla
    rti
.endproc

; -------------------------------------------------------------
; 十字キーで横移動(px 16bit) / ジャンプ・重力で縦移動 / 足場・地面の当たり判定
; -------------------------------------------------------------
.proc move_player
    lda #0
    sta moving         ; 横入力フラグをクリア

    ; --- 左 (px -= SPEED, 0 でクランプ) ---
    lda pad1
    and #BTN_LEFT
    beq @no_left
    lda #ATTR_FLIP     ; 左向き (スプライト反転)
    sta facing_attr
    lda #1
    sta moving
    sec
    lda px_lo
    sbc #SPEED
    sta px_lo
    lda px_hi
    sbc #0
    sta px_hi
    bcs @no_left       ; 借りなし → 0以上、OK
    lda #0             ; アンダーフロー → 0 にクランプ
    sta px_lo
    sta px_hi
@no_left:

    ; --- 右 (px += SPEED, WORLD_MAX でクランプ) ---
    lda pad1
    and #BTN_RIGHT
    beq @no_right
    lda #$00           ; 右向き (反転なし)
    sta facing_attr
    lda #1
    sta moving
    clc
    lda px_lo
    adc #SPEED
    sta px_lo
    lda px_hi
    adc #0
    sta px_hi
    ; px > WORLD_MAX ならクランプ
    lda px_hi
    cmp #>WORLD_MAX
    bcc @no_right      ; hi < 1 → 範囲内
    bne @clamp_r       ; hi > 1 → クランプ
    lda px_lo
    cmp #<WORLD_MAX
    bcc @no_right      ; lo < 248 → 範囲内
    beq @no_right      ; == ちょうど右端 → OK
@clamp_r:
    lda #<WORLD_MAX
    sta px_lo
    lda #>WORLD_MAX
    sta px_hi
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
    ; X 重なり (16bit): px < x1 かつ px+7 >= x0
    ; --- px < x1 ? (px >= x1 なら重ならない) ---
    lda px_hi
    cmp plat_x1_hi,y
    bcc @xok1          ; px_hi < x1_hi → px < x1
    bne @pnext         ; px_hi > x1_hi → px >= x1
    lda px_lo
    cmp plat_x1_lo,y
    bcs @pnext         ; px_lo >= x1_lo → px >= x1
@xok1:
    ; --- px+7 >= x0 ? (px+7 < x0 なら重ならない) ---
    clc
    lda px_lo
    adc #7
    sta ptr_lo
    lda px_hi
    adc #0
    sta ptr_hi         ; ptr = px+7 (16bit)
    lda ptr_hi
    cmp plat_x0_hi,y
    bcc @pnext         ; (px+7)_hi < x0_hi → px+7 < x0
    bne @xok2          ; (px+7)_hi > x0_hi → px+7 > x0
    lda ptr_lo
    cmp plat_x0_lo,y
    bcc @pnext         ; (px+7)_lo < x0_lo → px+7 < x0
@xok2:
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
; カメラ更新: キャラを画面中央付近に置くよう追従
;   camera = px - CAM_OFFSET、[0, CAM_MAX] にクランプ
;   screen_x = px - camera (キャラの画面内X)
; -------------------------------------------------------------
.proc update_camera
    ; camera = px - CAM_OFFSET (16bit)
    sec
    lda px_lo
    sbc #CAM_OFFSET
    sta camera_lo
    lda px_hi
    sbc #0
    sta camera_hi
    bcs @chk_max       ; 借りなし → 0以上
    lda #0             ; px < CAM_OFFSET → camera = 0
    sta camera_lo
    sta camera_hi
    jmp @calc_sx
@chk_max:
    ; camera > CAM_MAX(256=$0100) ならクランプ
    lda camera_hi
    cmp #>CAM_MAX
    bcc @calc_sx       ; hi < 1 → <256 OK
    bne @clamp_max     ; hi > 1 → クランプ
    lda camera_lo
    beq @calc_sx       ; hi==1 かつ lo==0 → ちょうど256 OK
@clamp_max:
    lda #<CAM_MAX
    sta camera_lo
    lda #>CAM_MAX
    sta camera_hi

@calc_sx:
    ; screen_x = px - camera (結果は 0..255 に収まる → 下位のみ)
    sec
    lda px_lo
    sbc camera_lo
    sta screen_x
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
; コイン取得判定: どのコインも触れたら取れる
;   重なり条件: |px - cx| <= 7 かつ |player_y - cy| <= 7 (ワールド座標)
;   順番どおり(= 最小未取得 next_coin)を取れば コンボ継続 (32→48→…)
;   順番外を取ると コンボリセット(combo_rem=MAX)→ そのボーナスは 32 に戻る
;   最後に next_coin(最小未取得 = 点滅対象)を再計算
; -------------------------------------------------------------
.proc update_coins
    ldx #0
@loop:
    lda coin_active, x
    beq @cont           ; 取得済はスキップ
    jsr coin_overlaps   ; X=コイン番号 → C=1 で重なり
    bcc @cont

    ; --- 取得! ---
    lda #0
    sta coin_active, x
    cpx next_coin
    beq @score          ; 順番どおり → コンボ継続
    lda #COIN_MAX       ; 順番外 → コンボリセット (次の加点は 32)
    sta combo_rem
@score:
    ; 方法A: combo_rem -= combo_rem>>1 ; bonus = MAX - combo_rem
    lda combo_rem
    lsr a
    sta tmp_lo
    lda combo_rem
    sec
    sbc tmp_lo
    sta combo_rem
    lda #COIN_MAX
    sec
    sbc combo_rem
    clc
    adc score_lo
    sta score_lo
    lda score_hi
    adc #0
    sta score_hi
@cont:
    inx
    cpx #NUM_COINS
    bne @loop

    ; --- next_coin = 最小の未取得インデックス (点滅 & 順番判定用) ---
    ldx #0
@find:
    lda coin_active, x
    bne @found          ; 未取得を発見
    inx
    cpx #NUM_COINS
    bne @find
    ; 全部取った → next_coin = NUM_COINS (該当なし)
@found:
    stx next_coin
    rts
.endproc

; -------------------------------------------------------------
; X=コイン番号 のコインがプレイヤーと 8x8 で重なるか
;   返り値: C=1 重なり / C=0 重ならない。差+7 が [0,14] かで判定
;   破壊: A, tmp_lo, tmp_hi (X/Y は保持)
; -------------------------------------------------------------
.proc coin_overlaps
    ; X 重なり: dx = px - cx (16bit)
    sec
    lda px_lo
    sbc coin_x_lo, x
    sta tmp_lo
    lda px_hi
    sbc coin_x_hi, x
    sta tmp_hi
    clc
    lda tmp_lo
    adc #7
    sta tmp_lo
    lda tmp_hi
    adc #0
    bne @no             ; 上位が 0 でない → 範囲外
    lda tmp_lo
    cmp #15
    bcs @no
    ; Y 重なり: dy = player_y - cy (8bit)
    lda player_y
    sec
    sbc coin_y, x
    clc
    adc #7
    cmp #15
    bcs @no
    sec                 ; 重なり
    rts
@no:
    clc
    rts
.endproc

; -------------------------------------------------------------
; トゲ当たり判定: プレイヤーがどれかのトゲに重なったら即死→完全リスタート
;   重なり条件はコインと同じ (|px-sx|<=7 かつ |player_y-sy|<=7)
; -------------------------------------------------------------
.proc check_spikes
    ldx #0
@loop:
    ; X 重なり: dx = px - sx (16bit)、dx+7 が [0,14] か
    sec
    lda px_lo
    sbc spike_x_lo, x
    sta tmp_lo
    lda px_hi
    sbc spike_x_hi, x
    sta tmp_hi
    clc
    lda tmp_lo
    adc #7
    sta tmp_lo
    lda tmp_hi
    adc #0
    bne @next
    lda tmp_lo
    cmp #15
    bcs @next
    ; Y 重なり: dy = player_y - sy、dy+7 が [0,14] か
    lda player_y
    sec
    sbc spike_y, x
    clc
    adc #7
    cmp #15
    bcs @next
    ; 衝突! 死亡 → 最初から完全リスタート
    jsr init_game_state
    rts
@next:
    inx
    cpx #NUM_SPIKES
    bne @loop
    rts
.endproc

; -------------------------------------------------------------
; トゲ描画 (スロット13-16): 画面内X = sx - camera。画面外は Y=$FF で隠す
; -------------------------------------------------------------
.proc draw_spikes
    ldx #0
    ldy #SPIKE_SLOT0
@loop:
    sec
    lda spike_x_lo, x
    sbc camera_lo
    sta tmp_lo
    lda spike_x_hi, x
    sbc camera_hi
    bne @hide           ; 画面外
    lda spike_y, x
    sta OAM, y
    lda #TILE_SPIKE
    sta OAM+1, y
    lda #SPIKE_PAL
    sta OAM+2, y
    lda tmp_lo
    sta OAM+3, y
    jmp @next
@hide:
    lda #$ff
    sta OAM, y
@next:
    iny
    iny
    iny
    iny
    inx
    cpx #NUM_SPIKES
    bne @loop
    rts
.endproc

; -------------------------------------------------------------
; 敵の移動: 地面を左右に往復 (端 [min,max] で反転)
;   画面内 patrol 前提なので x_lo の 8bit 演算で済む (x_hi は不変)
; -------------------------------------------------------------
.proc update_enemies
    ldx #0
@loop:
    lda enemy_dir, x
    bne @left
    ; --- 右へ ---
    clc
    lda enemy_x_lo, x
    adc #ENEMY_SPEED
    sta enemy_x_lo, x
    cmp enemy_max_lo, x
    bcc @next          ; < max → まだ進める
    lda enemy_max_lo, x ; max に到達 → クランプして左向きへ
    sta enemy_x_lo, x
    lda #1
    sta enemy_dir, x
    jmp @next
@left:
    ; --- 左へ ---
    sec
    lda enemy_x_lo, x
    sbc #ENEMY_SPEED
    sta enemy_x_lo, x
    cmp enemy_min_lo, x
    bcs @next          ; >= min → まだ進める
    lda enemy_min_lo, x ; min を下回った → クランプして右向きへ
    sta enemy_x_lo, x
    lda #0
    sta enemy_dir, x
@next:
    inx
    cpx #NUM_ENEMIES
    bne @loop
    rts
.endproc

; -------------------------------------------------------------
; 敵当たり判定: プレイヤーがどれかの敵に重なったら即死→完全リスタート
; -------------------------------------------------------------
.proc check_enemies
    ldx #0
@loop:
    sec
    lda px_lo
    sbc enemy_x_lo, x
    sta tmp_lo
    lda px_hi
    sbc enemy_x_hi, x
    sta tmp_hi
    clc
    lda tmp_lo
    adc #7
    sta tmp_lo
    lda tmp_hi
    adc #0
    bne @next
    lda tmp_lo
    cmp #15
    bcs @next
    lda player_y
    sec
    sbc enemy_y, x
    clc
    adc #7
    cmp #15
    bcs @next
    jsr init_game_state ; 衝突! 完全リスタート
    rts
@next:
    inx
    cpx #NUM_ENEMIES
    bne @loop
    rts
.endproc

; -------------------------------------------------------------
; 敵描画 (スロット17-19): 画面内X = ex - camera。進行方向で左右反転
; -------------------------------------------------------------
.proc draw_enemies
    ldx #0
    ldy #ENEMY_SLOT0
@loop:
    sec
    lda enemy_x_lo, x
    sbc camera_lo
    sta tmp_lo
    lda enemy_x_hi, x
    sbc camera_hi
    bne @hide          ; 画面外
    lda enemy_y, x
    sta OAM, y
    lda #TILE_ENEMY
    sta OAM+1, y
    lda enemy_dir, x   ; 属性: 左向き(dir=1)なら水平反転
    beq @right
    lda #ENEMY_PAL | $40
    jmp @setattr
@right:
    lda #ENEMY_PAL
@setattr:
    sta OAM+2, y
    lda tmp_lo
    sta OAM+3, y
    jmp @next
@hide:
    lda #$ff
    sta OAM, y
@next:
    iny
    iny
    iny
    iny
    inx
    cpx #NUM_ENEMIES
    bne @loop
    rts
.endproc

; -------------------------------------------------------------
; ゴール判定: 全コイン取得済(next_coin>=NUM_COINS)で、プレイヤーが
;   ゴール(GOAL_X,GOAL_Y)に重なったら cleared=1 (ステージクリア)
; -------------------------------------------------------------
.proc check_goal
    lda next_coin
    cmp #NUM_COINS
    bcc @done           ; まだ全部取ってない → ゴール無し
    ; X 重なり: dx = px - GOAL_X (16bit)
    sec
    lda px_lo
    sbc #<GOAL_X
    sta tmp_lo
    lda px_hi
    sbc #>GOAL_X
    sta tmp_hi
    clc
    lda tmp_lo
    adc #7
    sta tmp_lo
    lda tmp_hi
    adc #0
    bne @done
    lda tmp_lo
    cmp #15
    bcs @done
    ; Y 重なり
    lda player_y
    sec
    sbc #GOAL_Y
    clc
    adc #7
    cmp #15
    bcs @done
    lda #1              ; クリア!
    sta cleared
@done:
    rts
.endproc

; -------------------------------------------------------------
; ゴール描画 (スロット20): 全コイン取得後のみ表示。画面外は隠す
; -------------------------------------------------------------
.proc draw_goal
    lda next_coin
    cmp #NUM_COINS
    bcc @hide           ; 全部取るまで非表示
    ; 画面内X = GOAL_X - camera
    sec
    lda #<GOAL_X
    sbc camera_lo
    sta tmp_lo
    lda #>GOAL_X
    sbc camera_hi
    bne @hide           ; 画面外
    lda #GOAL_Y
    sta OAM+GOAL_SLOT
    lda #TILE_GOAL
    sta OAM+GOAL_SLOT+1
    lda #GOAL_PAL
    sta OAM+GOAL_SLOT+2
    lda tmp_lo
    sta OAM+GOAL_SLOT+3
    rts
@hide:
    lda #$ff
    sta OAM+GOAL_SLOT
    rts
.endproc

; -------------------------------------------------------------
; "CLEAR" 描画 (スロット21-25): cleared 時のみ画面中央に表示
; -------------------------------------------------------------
.proc draw_clear
    lda cleared
    beq @hide
    ldx #0
@loop:
    txa                ; OAM オフセット = CLEAR_SLOT0 + 文字*4
    asl a
    asl a
    clc
    adc #CLEAR_SLOT0
    tay
    lda #CLEAR_Y
    sta OAM, y
    lda clear_tiles, x
    sta OAM+1, y
    lda #CLEAR_PAL
    sta OAM+2, y
    txa                ; 画面内X = CLEAR_X + 文字*8
    asl a
    asl a
    asl a
    clc
    adc #CLEAR_X
    sta OAM+3, y
    inx
    cpx #5
    bne @loop
    rts
@hide:
    ldx #0
    ldy #CLEAR_SLOT0
@hloop:
    lda #$ff
    sta OAM, y
    iny
    iny
    iny
    iny
    inx
    cpx #5
    bne @hloop
    rts
.endproc

; -------------------------------------------------------------
; コイン描画 (スロット1-8) ＋ 得点HUD (スロット9)
;   各コイン: 画面内X = cx - camera。0..255 に収まる時だけ表示
;   未取得かつ画面内のみ表示、それ以外は Y=$FF で隠す
;   「次に取る」コインは点滅させて目印にする
;   得点HUD はスクロール非依存 (画面左上に固定の数字スプライト)
; -------------------------------------------------------------
.proc draw_coins
    ldx #0              ; コイン番号 0..7
    ldy #COIN_SLOT0     ; OAM オフセット (スロット1 から)
@loop:
    lda coin_active, x
    beq @hide           ; 取得済 → 隠す

    ; 画面内X = cx - camera (16bit)。上位が 0 でなければ画面外
    sec
    lda coin_x_lo, x
    sbc camera_lo
    sta tmp_lo
    lda coin_x_hi, x
    sbc camera_hi
    bne @hide           ; 左に出た($ff) / 右に出た(>=1) → 画面外

    ; 次に取るコインは点滅 (BLINK_MASK ビットが立つフレームは隠す)
    cpx next_coin
    bne @show
    lda frame_cnt
    and #BLINK_MASK
    bne @hide
@show:
    lda coin_y, x
    sta OAM, y
    lda #TILE_COIN
    sta OAM+1, y
    lda #COIN_PAL
    sta OAM+2, y
    lda tmp_lo          ; 画面内X
    sta OAM+3, y
    jmp @next
@hide:
    lda #$ff
    sta OAM, y          ; Y=$FF で画面外に隠す
@next:
    iny
    iny
    iny
    iny
    inx
    cpx #NUM_COINS
    bne @loop

    ; --- 得点HUD: 画面左上に HUD_DIGITS 桁 (2進→10進変換して表示) ---
    jsr bin2dec        ; score_lo/hi → score_dec[0..HUD_DIGITS-1]
    ldx #0             ; 桁番号 (0 = 最上位)
@hud:
    txa                ; OAM オフセット = SCORE_SLOT + 桁*4
    asl a
    asl a
    clc
    adc #SCORE_SLOT
    tay
    lda #HUD_Y
    sta OAM, y
    lda score_dec, x   ; 数字 → タイル
    clc
    adc #DIGIT_BASE
    sta OAM+1, y
    lda #SCORE_PAL
    sta OAM+2, y
    txa                ; 画面内X = HUD_X + 桁*8
    asl a
    asl a
    asl a
    clc
    adc #HUD_X
    sta OAM+3, y
    inx
    cpx #HUD_DIGITS
    bne @hud
    rts
.endproc

; -------------------------------------------------------------
; 2進→10進: score_lo/hi (16bit) を score_dec[] の各桁に分解
;   桁の重み (1000,100,10) を順に引き算して商=桁、最後の余り=1の位
;   ※NESのCPUはBCD無効のため、表示用にソフトで10進変換する
; -------------------------------------------------------------
.proc bin2dec
    lda score_lo
    sta tmp_lo
    lda score_hi
    sta tmp_hi
    ldx #0             ; 重みテーブルの添字 (0=1000,1=100,2=10)
@digit:
    ldy #0             ; この桁の値 (引けた回数)
@sub:
    sec
    lda tmp_lo
    sbc pow10_lo, x
    sta ptr_lo         ; 試し引きの下位を退避
    lda tmp_hi
    sbc pow10_hi, x
    bcc @next          ; 借り発生 → これ以上引けない
    sta tmp_hi
    lda ptr_lo
    sta tmp_lo
    iny
    jmp @sub
@next:
    tya
    sta score_dec, x
    inx
    cpx #HUD_DIGITS-1
    bne @digit
    lda tmp_lo         ; 残り = 1の位 (0..9)
    sta score_dec + HUD_DIGITS-1
    rts
.endproc

; -------------------------------------------------------------
; 背景描画: ネームテーブル2枚 ($2000/$2400) にステージを描く
;   = 512px幅のワールド。各画面: 上27行=空 / 下3行=地面、属性=全0
;   ※ 描画OFF中に呼ぶこと
; -------------------------------------------------------------
.proc draw_background
    lda #$20              ; ネームテーブル0 = $2000 (左画面)
    jsr fill_screen
    lda #$24              ; ネームテーブル1 = $2400 (右画面)
    jsr fill_screen
    jsr draw_platforms    ; 足場を上書き
    rts
.endproc

; 1画面ぶん(960+64byte)を塗る。A = ベース上位バイト ($20 or $24)
.proc fill_screen
    bit PPUSTATUS         ; アドレスラッチをリセット (A は不変)
    sta PPUADDR           ; ベース上位
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

    ; 属性テーブル 64 byte 全て 0 (全タイルが BG パレット0)
    ldy #64
    lda #$00
@attr:
    sta PPUDATA
    dey
    bne @attr
    rts
.endproc

; -------------------------------------------------------------
; 足場描画: 各足場をレンガ(タイル2)で描く (2ネームテーブル対応)
;   各足場は1画面内に収まる前提 (x0_hi == x1_hi)
;   localcol = x0_lo/8 / ネームテーブルは x0_hi (0=$2000 / 1=$2400)
;   addr = $2000 + x0_hi*$0400 + top*4 + localcol
;   タイル数 = (x1_lo - x0_lo)/8
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
    ; ptr += localcol (= x0_lo/8)
    lda plat_x0_lo,y
    lsr a
    lsr a
    lsr a
    clc
    adc ptr_lo
    sta ptr_lo
    lda ptr_hi
    adc #0
    sta ptr_hi
    ; ptr_hi += $20 + x0_hi*4  (ネームテーブル選択)
    lda plat_x0_hi,y
    asl a
    asl a
    clc
    adc #$20
    adc ptr_hi
    sta ptr_hi

    ; PPUADDR = ptr
    bit PPUSTATUS
    lda ptr_hi
    sta PPUADDR
    lda ptr_lo
    sta PPUADDR

    ; タイル数 = (x1_lo - x0_lo)/8 → X
    lda plat_x1_lo,y
    sec
    sbc plat_x0_lo,y
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
    ; スプライトパレット 0=キャラ(赤) / 1=コイン(金) / 2=得点(白)
    ; 3 はトゲ(index1=灰) と 敵(index2=緑) で共有 / index3=白(目)
    .byte $0f,$16,$27,$30,  $0f,$28,$27,$30
    .byte $0f,$30,$30,$30,  $0f,$10,$2a,$30

; -------------------------------------------------------------
; 足場テーブル (ワールド・ピクセル座標 / 描画と当たり判定で共用)
;   top=上面Y(8bit) / x0,x1=左右端X(16bit, 排他)。各足場は1画面内に収める
;   512px幅に6枚配置 (前半3枚=左画面 / 後半3枚=右画面)
; -------------------------------------------------------------
plat_top:    .byte 176, 144, 112, 144, 112, 160
plat_x0_lo:  .byte  32,  96, 176,  24, 104, 184
plat_x0_hi:  .byte   0,   0,   0,   1,   1,   1
plat_x1_lo:  .byte  64, 136, 216,  64, 144, 224
plat_x1_hi:  .byte   0,   0,   0,   1,   1,   1

; -------------------------------------------------------------
; コインテーブル (ワールド・ピクセル座標 / 8x8)
;   取る順番 = この並び順 (0→7)。左地面→左の足場3枚→右の足場3枚→右地面
;   x は 16bit (hi=0 左画面 / hi=1 右画面)。y は各足場の少し上に浮かせる
;   coin_active(RAM) で取得状態を管理。座標は定数なので RODATA に置く
; -------------------------------------------------------------
coin_x_lo:   .byte  24,  44, 112, 192,  40, 120, 200, 224
coin_x_hi:   .byte   0,   0,   0,   0,   1,   1,   1,   1
coin_y:      .byte 204, 164, 132, 100, 132, 100, 148, 204

; 10進変換用の桁の重み (上位桁から / HUD_DIGITS-1 個)
pow10_lo:    .byte <1000, <100, <10
pow10_hi:    .byte >1000, >100, >10

; -------------------------------------------------------------
; トゲテーブル (ワールド・ピクセル座標 / 8x8)
;   地面(y=FLOOR_Y=208)に配置。コインの x とは重ならない位置にする
;   触れると即死。ジャンプで飛び越える
; -------------------------------------------------------------
spike_x_lo:  .byte 160, 240,  80, 160   ; (x_hi=1 側は 256+80=336, 256+160=416)
spike_x_hi:  .byte   0,   0,   1,   1
spike_y:     .byte 208, 208, 208, 208

; -------------------------------------------------------------
; 敵テーブル (ワールド・ピクセル座標 / 8x8)
;   地面(y=208)を [min,max] の範囲で左右に往復。各敵は1画面内に収める
;   (x_hi は min/max で共通。トゲの x とは重ならない位置に)
; -------------------------------------------------------------
enemy_min_lo: .byte  60,  14, 174   ; 左端X 下位 (E1/E2 は x_hi=1 → world 270/430)
enemy_min_hi: .byte   0,   1,   1
enemy_max_lo: .byte 150, 104, 219   ; 右端X 下位 (world 150 / 360 / 475)
enemy_y:      .byte 208, 208, 208

; "CLEAR" の文字タイル並び
clear_tiles:  .byte TILE_C, TILE_L, TILE_E, TILE_A, TILE_R

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
    ; タイル4: コイン (body=index1 金 / 中央の縦線=index3 白)
    .byte $3c,$7e,$ff,$ff,$ff,$ff,$7e,$3c   ; plane 0 (丸い輪郭)
    .byte $00,$00,$18,$18,$18,$18,$00,$00   ; plane 1 (中央の光沢ライン)
    ; タイル5..14: 数字 '0'..'9' (plane0 のみ = index1)
    .byte $7c,$c6,$ce,$de,$f6,$e6,$7c,$00   ; '0'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $30,$70,$30,$30,$30,$30,$fc,$00   ; '1'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $7c,$c6,$06,$1c,$70,$c0,$fe,$00   ; '2'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $7c,$c6,$06,$3c,$06,$c6,$7c,$00   ; '3'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $1c,$3c,$6c,$cc,$fe,$0c,$0c,$00   ; '4'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $fe,$c0,$fc,$06,$06,$c6,$7c,$00   ; '5'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $3c,$60,$c0,$fc,$c6,$c6,$7c,$00   ; '6'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $fe,$06,$0c,$18,$30,$30,$30,$00   ; '7'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $7c,$c6,$c6,$7c,$c6,$c6,$7c,$00   ; '8'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $7c,$c6,$c6,$7e,$06,$0c,$78,$00   ; '9'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    ; タイル15: トゲ (上向きの三角 / index1 灰)
    .byte $18,$18,$3c,$3c,$7e,$7e,$ff,$ff   ; plane 0
    .byte $00,$00,$00,$00,$00,$00,$00,$00   ; plane 1
    ; タイル16: 敵 (緑のブロブ=index2 / 目=index3 白)
    .byte $00,$00,$00,$24,$00,$00,$00,$00   ; plane 0 (目だけ → 重なり部が index3)
    .byte $3c,$7e,$ff,$ff,$ff,$ff,$ff,$db   ; plane 1 (体 → index2 緑)
    ; タイル17: ゴール (金の星 / plane0 のみ = index1 金)
    .byte $18,$18,$ff,$7e,$3c,$7e,$c3,$00   ; plane 0
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    ; タイル18..22: 文字 'C' 'L' 'E' 'A' 'R' (plane0 のみ = index1)
    .byte $7c,$c6,$c0,$c0,$c0,$c6,$7c,$00   ; 'C'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $c0,$c0,$c0,$c0,$c0,$c0,$fe,$00   ; 'L'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $fe,$c0,$c0,$fc,$c0,$c0,$fe,$00   ; 'E'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $38,$6c,$c6,$c6,$fe,$c6,$c6,$00   ; 'A'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $fc,$c6,$c6,$fc,$d8,$cc,$c6,$00   ; 'R'
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    ; 残りを 0 で埋めて 8KB に (タイル0..22 = 368byte)
    .res 8192 - 368, $00
