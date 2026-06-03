# ====================================================================
# Makefile for bare-metal Assembly MT19937-64 implementation
# ====================================================================

TARGET := mt19937_64
SRC    := mt19937_64.asm
OBJ    := mt19937_64.o

ASM    := nasm
LD     := ld

ASMFLAGS := -felf64 -l mt19937_64.lst
LDFLAGS  := -s -melf_x86_64

all: $(TARGET)

$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJ)

$(OBJ): $(SRC)
	$(ASM) $(ASMFLAGS) $(SRC) -o $(OBJ)

clean:
	rm -f $(OBJ) $(TARGET) mt19937_64.lst

.PHONY: all clean