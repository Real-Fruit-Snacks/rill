# rill — pure x86_64 Linux assembly multi-call binary.
#
# Targets:
#   all       Build build/rill (default)
#   symlinks  Create build/<applet> symlinks pointing at rill
#   test      Build + symlinks, then run the integration suite (bats)
#   size      Print the size of the linked binary
#   clean     Remove build/

NASM      ?= nasm
LD        ?= ld
BATS      ?= bats

# -w-reloc-{abs,rel}-*: suppress warnings about cross-section relocations.
# These fire on the applet table (.rodata pointers into .text) and on every
# RIP-relative LEA into .rodata. Both resolve correctly for our static
# non-PIE binary at a fixed load address. Newer nasm (2.16+) is noisier
# than 2.15; this keeps the build quiet on both.
NASMFLAGS := -f elf64 -g -F dwarf -Iinclude/ -w+all \
             -w-reloc-abs-qword -w-reloc-rel-dword -w-unknown-warning
LDFLAGS   := --gc-sections -nostdlib -static -T linker.ld

BUILD     := build
BIN       := $(BUILD)/rill

START_SRC  := src/start.asm
CORE_SRC   := $(wildcard src/core/*.asm)
APPLET_SRC := $(wildcard src/applets/*.asm)
SRC        := $(START_SRC) $(CORE_SRC) $(APPLET_SRC)
OBJ        := $(SRC:%.asm=$(BUILD)/%.o)

# Applet names that should get a symlink in build/. Each applet's .asm file
# under src/applets/<name>.asm contributes <name> to this list.
APPLETS    := $(notdir $(basename $(APPLET_SRC)))

.PHONY: all clean test symlinks size

all: $(BIN)

$(BIN): $(OBJ) linker.ld
	@mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $(OBJ)

$(BUILD)/%.o: %.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<

symlinks: $(BIN)
	@for a in $(APPLETS); do \
	    ln -sf rill $(BUILD)/$$a; \
	done

test: $(BIN) symlinks
	$(BATS) tests/integration

size: $(BIN)
	@stat -c '%n: %s bytes' $(BIN)

clean:
	rm -rf $(BUILD)
