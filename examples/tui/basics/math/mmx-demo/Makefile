# ====================================================================
# Makefile for pure GNU as MMX legacy test program
# Target environment: Linux amd64 native static linkage
# ====================================================================

TARGET := mmx-demo
SRC    := mmx-demo.asm
OBJ    := mmx-demo.o

AS     := as
LD     := ld

# --64: Generates code for x86_64 architecture targets
ASFLAGS := --64
# -s: Strip symbols to construct an incredibly lightweight footprint binary
LDFLAGS := -s -m elf_x86_64

all: $(TARGET)

$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJ)

$(OBJ): $(SRC)
	$(AS) $(ASFLAGS) -o $(OBJ) $(SRC)

clean:
	rm -f $(OBJ) $(TARGET)

.PHONY: all clean