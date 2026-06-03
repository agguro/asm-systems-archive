# ====================================================================
# Makefile for quadraticequations CGI backend
# Target: Linux x86_64 ELF Static Executable
# ====================================================================

# Compiler and Linker definitions
ASM       := nasm
LD        := ld

# Flags
# -felf64: 64-bit ELF format
# -l: Generates an assembly listing file for debugging/archive
ASM_FLAGS := -felf64 -l quadraticequations.lst

# -s: Strip all symbol table and relocation information (minimizes binary size)
# -melf_x86_64: Explicitly target the 64-bit emulation layer
LD_FLAGS  := -s -melf_x86_64

# Files
TARGET    := quadraticequations
OBJ       := quadraticequations.o
SRC       := quadraticequations.asm

# Dependencies (Forces a rebuild if any class or macro files change)
DEPS      := unistd.inc fraction.class math.inc

# Default rule
all: $(TARGET)

# Link rule
$(TARGET): $(OBJ)
	$(LD) $(LD_FLAGS) -o $(TARGET) $(OBJ)

# Assemble rule
$(OBJ): $(SRC) $(DEPS)
	$(ASM) $(ASM_FLAGS) $(SRC) -o $(OBJ)

# Clean up build artifacts
clean:
	rm -f $(OBJ) $(TARGET) quadraticequations.lst

# Phony targets
.PHONY: all clean