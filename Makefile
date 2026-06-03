# NES (ca65) ビルド用 Makefile
NAME    := game
SRC     := src/main.s
CFG     := nes.cfg
OBJ     := $(SRC:.s=.o)
ROM     := $(NAME).nes

EMU     := fceux        # 動作確認用エミュレータ

.PHONY: all run clean

all: $(ROM)

# アセンブル → リンク
$(ROM): $(OBJ) $(CFG)
	ld65 $(OBJ) -C $(CFG) -o $(ROM)

%.o: %.s
	ca65 $< -o $@

# ビルドして実行
run: $(ROM)
	$(EMU) $(ROM)

clean:
	rm -f $(OBJ) $(ROM)
