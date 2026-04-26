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

# Probe whether this nasm understands the reloc-* warning categories
# (NASM 2.16+ emits them on cross-section relocations; 2.15 does not, and
# rejects the flag with its own warning).
NASM_HAS_RELOC_WARN := $(shell $(NASM) -f elf64 -w-reloc-abs-qword -o /dev/null /dev/null 2>/dev/null && echo yes)
ifeq ($(NASM_HAS_RELOC_WARN),yes)
    NASMFLAGS_RELOC := -w-reloc-abs-qword -w-reloc-rel-dword
endif

NASMFLAGS := -f elf64 -g -F dwarf -Iinclude/ -w+all $(NASMFLAGS_RELOC)
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
