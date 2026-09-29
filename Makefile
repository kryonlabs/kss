.DEFAULT_GOAL := check

ZIRAN ?= ziran
CC ?= cc
BUILD := build
FUZZ_SEED ?= 1
FUZZ_COUNT ?= 2000
STYLE_PACKS := classic
STYLE_PACK_TOOL := $(BUILD)/tools/style_pack_module

.PHONY: check test style-packs style-pack-check fuzz clean

check: test style-pack-check fuzz

test:
	$(ZIRAN) check --project
	$(ZIRAN) bundle --project --entry style_parse_behavior:Answer \
		-o $(BUILD)/style-parse.zib tests/style_parse_behavior.zi
	test "$$($(ZIRAN) run --project $(BUILD)/style-parse.zib)" = 42
	rm -rf $(BUILD)/style-parse-c
	$(ZIRAN) build --project --target=c --entry style_parse_behavior:Answer \
		-o $(BUILD)/style-parse-c tests/style_parse_behavior.zi
	printf '#include "style_parse_behavior.h"\nint main(void) { return Answer() == 42 ? 0 : 1; }\n' \
		> $(BUILD)/style-parse-c/main.c
	$(CC) -std=c11 -I$$($(ZIRAN) pkg path ziran)/include -I$(BUILD)/style-parse-c \
		$(BUILD)/style-parse-c/*.c -o $(BUILD)/style-parse
	$(BUILD)/style-parse
	# The whole classic pack is more than the portable runner's step
	# budget, so the system style test runs as native code.
	rm -rf $(BUILD)/system-style-c
	$(ZIRAN) build --project --target=c --entry system_style_behavior:main \
		-o $(BUILD)/system-style-c tests/system_style_behavior.zi
	$(CC) -std=c11 -I$$($(ZIRAN) pkg path ziran)/include -I$(BUILD)/system-style-c \
		$(BUILD)/system-style-c/*.c -o $(BUILD)/system-style
	$(BUILD)/system-style

# Style packs apps can install without the .kss file. Their modules are
# committed, because apps import KSS as a package without running this
# Makefile; style-pack-check fails when a module no longer matches its pack.
$(STYLE_PACK_TOOL): tools/style_pack_module.zi
	rm -rf $@-c
	mkdir -p $(dir $@)
	$(ZIRAN) build --project --target=c --entry style_pack_module:main \
		-o $@-c tools/style_pack_module.zi
	$(CC) -std=c11 -O2 -I$$($(ZIRAN) pkg path ziran)/include -I$@-c $@-c/*.c -o $@

style-packs: $(STYLE_PACK_TOOL)
	@for pack in $(STYLE_PACKS); do $(STYLE_PACK_TOOL) write $$pack || exit 1; done

style-pack-check: $(STYLE_PACK_TOOL)
	@for pack in $(STYLE_PACKS); do $(STYLE_PACK_TOOL) check $$pack || exit 1; done
	@echo "Style pack modules match: $(STYLE_PACKS)"

# Generated and damaged style sheets through the parser, the rule table,
# and the formatter, built with AddressSanitizer and UndefinedBehaviorSanitizer.
# The same seed makes the same sheets; see tests/kss_fuzz.zi.
fuzz:
	@ZIRAN=$(ZIRAN) sh tests/kss_fuzz.sh $(FUZZ_SEED) $(FUZZ_COUNT)

clean:
	rm -rf $(BUILD)
