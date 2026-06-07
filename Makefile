# NES (ca65) ビルド用 Makefile
NAME    := game
SRC     := src/main.s
CFG     := nes.cfg
OBJ     := $(SRC:.s=.o)
ROM     := $(NAME).nes

EMU     := fceux        # 動作確認用エミュレータ
# このマシンの Mesa ハードウェアGLは FCEUX で入力時にクラッシュ(画面が真っ黒で固まる)するため
# ソフトウェア描画を強制する。直ったらこの行は外してよい。
EMU_ENV := LIBGL_ALWAYS_SOFTWARE=1

.PHONY: all run clean

all: $(ROM)

# アセンブル → リンク
$(ROM): $(OBJ) $(CFG)
	ld65 $(OBJ) -C $(CFG) -o $(ROM)

%.o: %.s
	ca65 $< -o $@

# ビルドして実行
run: $(ROM)
	$(EMU_ENV) $(EMU) $(ROM)

clean:
	rm -f $(OBJ) $(ROM)
