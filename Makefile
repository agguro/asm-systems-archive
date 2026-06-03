NASM     := nasm
LD       := ld

# Dynamically locate the absolute path of your includes folder
INC_DIR  := $(CURDIR)/includes

# Integrated include flag (-I requires a trailing slash for NASM)
NASMFLAGS:= -f elf64 -g -F dwarf -I$(INC_DIR)/
LDFLAGS  := -m elf_x86_64

# Output Structures
BUILD_DIR := build
BIN_DIR   := bin

# Recursively locate all assembly source files under projects/
SRCS      := $(shell find projects -name "*.asm" -type f)

# Map source files to their respective object and binary targets
OBJS      := $(patsubst projects/%,$(BUILD_DIR)/%,$(SRCS:.asm=.o))
BINS      := $(patsubst projects/%,$(BIN_DIR)/%,$(SRCS:.asm=))

.PHONY: all clean directories

all: directories $(BINS)
	@echo ">>> ARCHIVE BUILD COMPLETE: Output binaries separated cleanly."

# Rule to dynamically mirror the source folder structure inside build/ and bin/
directories:
	@mkdir -p $(BUILD_DIR) $(BIN_DIR)
	@find projects -type d | sed 's|^projects/||' | while read -r dir; do \
		if [ -n "$$dir" ] && [ "$$dir" != "projects" ]; then \
			mkdir -p "$(BUILD_DIR)/$$dir" "$(BIN_DIR)/$$dir"; \
		fi; \
	done

# Compilation Pattern: Assemble raw .asm directly into the isolated build/ tree
$(BUILD_DIR)/%.o: projects/%.asm
	@echo "[ASM] Assembling $< -> $@"
	$(NASM) $(NASMFLAGS) $< -o $@

# Linking Pattern: Link isolated objects into standalone execution binaries inside bin/
$(BIN_DIR)/%: $(BUILD_DIR)/%.o
	@echo "[LINK] Forging executable $< -> $@"
	$(LD) $(LDFLAGS) $< -o $@

clean:
	@echo "[CLEAN] Vaporizing transient build and bin environments..."
	rm -rf $(BUILD_DIR) $(BIN_DIR)
