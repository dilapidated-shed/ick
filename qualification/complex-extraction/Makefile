# Fixed build-tool interface: all test source is compiled by the selected ICK.
ICK ?= gcc
ICK_FLAGS ?=
ICK_LINK_FLAGS ?= -fno-link-libatomic
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
TESTS := $(ROOT)/ick/source/gcc/testsuite/gcc.dg
BUILD ?= $(CURDIR)/build/complex-extraction
LEVELS := O0 O1 O2 O3 Os
RUN_TESTS := extraction-only polar-layout round
RUN_TARGETS := $(foreach level,$(LEVELS),$(foreach name,$(RUN_TESTS),run-$(level)-$(name)))

.PHONY: all compile $(RUN_TARGETS)
all: $(RUN_TARGETS) compile

define run_test
run-$(1)-$(2):
	mkdir -p "$(BUILD)"
	"$(ICK)" $(ICK_FLAGS) $(ICK_LINK_FLAGS) -std=c11 -Wall -Wextra -Werror -$(1) "$(TESTS)/ick-complex-$(2).c" -lm -o "$(BUILD)/$(2)-$(1)"
	"$(BUILD)/$(2)-$(1)"
endef
$(foreach level,$(LEVELS),$(foreach name,$(RUN_TESTS),$(eval $(call run_test,$(level),$(name)))))

compile:
	mkdir -p "$(BUILD)"
	"$(ICK)" $(ICK_FLAGS) -O2 -c "$(TESTS)/ick-complex-polar-float16.c" -o "$(BUILD)/float16.o"
	"$(ICK)" $(ICK_FLAGS) -O2 -fdump-tree-optimized="$(BUILD)/object-byte-fold.optimized" -c "$(TESTS)/ick-complex-object-byte-fold.c" -o "$(BUILD)/object-byte-fold.o"
	test "$$(grep -c 'return 1;' "$(BUILD)/object-byte-fold.optimized")" = 2
