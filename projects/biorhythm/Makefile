# ====================================================================
# Makefile for pure assembly Biorhythm utility
# Targets: GNU System Assembler (as) and Linker (ld)
# ====================================================================

TARGET := biorhythm
SRC    := biorhythm.asm
OBJ    := biorhythm.o

AS     := as
LD     := ld

# Assembler configurations (No debug junk, absolute 64-bit platform target)
ASFLAGS := --64
LDFLAGS := -s -m elf_x86_64

all: $(TARGET)

$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJ)

$(OBJ): $(SRC)
	$(AS) $(ASFLAGS) -o $(OBJ) $(SRC)

clean:
	rm -f $(OBJ) $(TARGET)

.PHONY: all clean