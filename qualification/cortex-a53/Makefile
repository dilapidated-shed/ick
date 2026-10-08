# Qualification graph; shell recipes are single external-tool invocations.
# ICK owns every kernel object. Stock compilers own only libc/test drivers.
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
OUT ?= $(ROOT)/../../build/cortex-a53
ICK ?= $(ROOT)/../../stage/bin/aarch64-linux-gnu-gcc
PREFIX ?= aarch64-linux-gnu-
LINUX_CC ?= aarch64-linux-gnu-gcc
QEMU ?= qemu-aarch64
NDK_CC ?= $(ANDROID_NDK_ROOT)/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang
COMMON := -std=c11 -O3 -fPIC -ffixed-x18 -march=armv8-a -ffp-contract=off -fno-fast-math
KERNEL_FLAGS := $(COMMON) -ffreestanding -nostdinc -I$(ROOT)
KERNELS := scalar vector branch volume
MODES := generic cortex-a53
OBJECTS := $(foreach mode,$(MODES),$(foreach kernel,$(KERNELS),$(OUT)/$(mode)/$(kernel).o))
REPORTS := $(foreach mode,$(MODES),$(foreach kernel,$(KERNELS),$(OUT)/$(mode)/$(kernel).report))
ASSEMBLY := $(OBJECTS:.o=.s)
REPLAYS := $(OBJECTS:.o=.replay)
ORACLES := $(foreach mode,$(MODES),$(OUT)/$(mode)/linux-oracle.txt)
LIBRARIES := $(foreach mode,$(MODES),$(OUT)/$(mode)/libkernels.so)
ANDROID_ORACLES := $(foreach mode,$(MODES),$(OUT)/$(mode)/android-oracle)

.PHONY: all correctness android evidence regression
.SECONDARY:
all: correctness evidence android
correctness: $(ORACLES)
	cmp $(OUT)/generic/linux-oracle.txt $(OUT)/cortex-a53/linux-oracle.txt
evidence: $(REPORTS) $(ASSEMBLY) $(REPLAYS) $(OUT)/features.ok
	$(PREFIX)size $(OBJECTS) > $(OUT)/sizes.txt
	$(PREFIX)size -A $(OBJECTS) > $(OUT)/section-sizes.txt
	sha256sum $(OBJECTS) $(ASSEMBLY) > $(OUT)/compiler-output.sha256
	sha256sum $(ROOT)/*.c $(ROOT)/kernels.h $(ROOT)/Makefile $(ROOT)/check-abi.awk $(ROOT)/exports.txt $(ROOT)/negative-elf.txt $(ROOT)/measure.grease > $(OUT)/fixtures.sha256
	git -C $(ROOT) rev-parse HEAD > $(OUT)/ick.commit
	$(ICK) -v 2> $(OUT)/compiler.txt
	cp $(ROOT)/../../ick/SOURCE.lock $(OUT)/SOURCE.lock
	printf '%s\n' '$(KERNEL_FLAGS) -mtune=generic' '$(KERNEL_FLAGS) -mtune=cortex-a53' 'scalar only: -fno-tree-vectorize' > $(OUT)/commands.txt
	printf 'PHYSICAL PERFORMANCE COMPARISON: NOT_RUN\nQEMU: correctness only; no timing collected\n' > $(OUT)/performance.txt
android: $(LIBRARIES) $(ANDROID_ORACLES) $(OUT)/benchmark $(OUT)/android-abi.ok $(OUT)/measure.grease
	sha256sum $(LIBRARIES) $(ANDROID_ORACLES) $(OUT)/benchmark > $(OUT)/android-artifacts.sha256
	git -C $(ROOT) rev-parse HEAD > $(OUT)/ick.commit
	cp $(ROOT)/../../ick/SOURCE.lock $(OUT)/SOURCE.lock
	$(NDK_CC) --version > $(OUT)/ndk-compiler.txt
	cd $(OUT) && sha256sum generic/libkernels.so cortex-a53/libkernels.so generic/android-oracle cortex-a53/android-oracle benchmark measure.grease ick.commit SOURCE.lock ndk-compiler.txt > native.sha256
	tar -C $(OUT) -czf $(OUT)/c67-native-benchmark.tar.gz generic/libkernels.so cortex-a53/libkernels.so generic/android-oracle cortex-a53/android-oracle benchmark measure.grease native.sha256 ick.commit SOURCE.lock ndk-compiler.txt

$(OUT)/measure.grease: $(ROOT)/measure.grease | $(OUT)/generic
	cp $< $@

$(OUT)/generic/%: TUNE = generic
$(OUT)/cortex-a53/%: TUNE = cortex-a53
$(OUT)/%/scalar.o $(OUT)/%/scalar.s $(OUT)/%/scalar.replay: SCALAR = -fno-tree-vectorize

$(OUT)/generic $(OUT)/cortex-a53:
	mkdir -p $@

define kernel_rules
$(OUT)/%/$(1).o: $(ROOT)/$(1).c $(ROOT)/kernels.h | $(OUT)/generic $(OUT)/cortex-a53
	$(ICK) $(KERNEL_FLAGS) -mtune=$$(TUNE) $$(SCALAR) -fopt-info-vec-all=$$(@:.o=.vec.txt) -fdump-rtl-sched2=$$(@:.o=.sched.txt) -c $$< -o $$@
$(OUT)/%/$(1).s: $(ROOT)/$(1).c $(ROOT)/kernels.h | $(OUT)/generic $(OUT)/cortex-a53
	$(ICK) $(KERNEL_FLAGS) -mtune=$$(TUNE) $$(SCALAR) -S $$< -o $$@
$(OUT)/%/$(1).replay: $(OUT)/%/$(1).o
	$(ICK) $(KERNEL_FLAGS) -mtune=$$(TUNE) $$(SCALAR) -c $(ROOT)/$(1).c -o $$@.o
	cmp $$< $$@.o
	touch $$@
$(OUT)/%/$(1).report: $(OUT)/%/$(1).o
	$(PREFIX)readelf -WhAn $$< > $$(@:.report=.elf.txt)
	$(PREFIX)nm --defined-only $$< > $$(@:.report=.symbols.txt)
	$(PREFIX)nm -u $$< > $$(@:.report=.undefined.txt)
	awk 'END { if (NR) exit 1 }' $$(@:.report=.undefined.txt)
	$(PREFIX)objdump -d --no-show-raw-insn $$< > $$(@:.report=.disasm.txt)
	awk '/^[[:space:]]*[0-9a-f]+:/ { count[$$$$2]++ } END { for (mnemonic in count) print mnemonic "\t" count[mnemonic] }' $$(@:.report=.disasm.txt) > $$(@:.report=.mix.txt)
	touch $$@
endef
$(foreach kernel,$(KERNELS),$(eval $(call kernel_rules,$(kernel))))

$(OUT)/linux-driver.o: $(ROOT)/oracle.c $(ROOT)/kernels.h | $(OUT)/generic
	$(LINUX_CC) -std=c11 -O0 -ffp-contract=off -Wall -Wextra -Werror -c $< -o $@
$(OUT)/%/linux-oracle: $(foreach kernel,$(KERNELS),$(OUT)/%/$(kernel).o) $(OUT)/linux-driver.o
	$(LINUX_CC) -static $^ -o $@
$(OUT)/%/linux-oracle.txt: $(OUT)/%/linux-oracle
	$(QEMU) -cpu cortex-a53 $< > $@

$(OUT)/android-driver.o: $(ROOT)/oracle.c $(ROOT)/kernels.h | $(OUT)/generic
	$(NDK_CC) -std=c11 -O0 -ffp-contract=off -Wall -Wextra -Werror -c $< -o $@
$(OUT)/%/android-oracle: $(foreach kernel,$(KERNELS),$(OUT)/%/$(kernel).o) $(OUT)/android-driver.o
	$(NDK_CC) -Wl,-z,max-page-size=16384 -Wl,-z,defs -Wl,--fatal-warnings $^ -o $@
$(OUT)/%/libkernels.so: $(foreach kernel,$(KERNELS),$(OUT)/%/$(kernel).o)
	$(NDK_CC) -shared -Wl,-z,max-page-size=16384 -Wl,-z,defs -Wl,-z,text -Wl,--fatal-warnings -Wl,-soname,libkernels.so $^ -o $@
$(OUT)/benchmark: $(ROOT)/benchmark.c $(ROOT)/kernels.h | $(OUT)/generic
	$(NDK_CC) -std=c11 -O2 -ffp-contract=off -Wall -Wextra -Werror -Wl,-z,max-page-size=16384 $< -ldl -o $@

$(OUT)/features.ok: $(OBJECTS)
	$(ICK) $(COMMON) -mtune=generic -dM -E -x c /dev/null > $(OUT)/generic/macros.txt
	$(ICK) $(COMMON) -mtune=cortex-a53 -dM -E -x c /dev/null > $(OUT)/cortex-a53/macros.txt
	cmp $(OUT)/generic/macros.txt $(OUT)/cortex-a53/macros.txt
	$(ICK) $(COMMON) -mtune=generic -Q --help=target -c $(ROOT)/vector.c -o $(OUT)/generic/options.o > $(OUT)/generic/options.txt
	$(ICK) $(COMMON) -mtune=cortex-a53 -Q --help=target -c $(ROOT)/vector.c -o $(OUT)/cortex-a53/options.o > $(OUT)/cortex-a53/options.txt
	$(ICK) $(COMMON) -mtune=generic -Q --help=optimizers -c $(ROOT)/vector.c -o $(OUT)/generic/optimizers.o > $(OUT)/generic/optimizers.txt
	$(ICK) $(COMMON) -mtune=cortex-a53 -Q --help=optimizers -c $(ROOT)/vector.c -o $(OUT)/cortex-a53/optimizers.o > $(OUT)/cortex-a53/optimizers.txt
	$(ICK) $(COMMON) -mtune=generic -fdump-tuning-model=$(OUT)/generic/tuning-model.txt -c $(ROOT)/vector.c -o $(OUT)/generic/tuning-model.o
	$(ICK) $(COMMON) -mtune=cortex-a53 -fdump-tuning-model=$(OUT)/cortex-a53/tuning-model.txt -c $(ROOT)/vector.c -o $(OUT)/cortex-a53/tuning-model.o
	$(ICK) -mcpu=cortex-a53 -dM -E -x c /dev/null > $(OUT)/mcpu-a53.macros.txt
	$(ICK) -mcpu=cortex-a53 -Q --help=target -c $(ROOT)/vector.c -o $(OUT)/mcpu-a53.o > $(OUT)/mcpu-a53.options.txt
	grep -q '^\#define __ARM_NEON 1' $(OUT)/generic/macros.txt
	grep -q '^\#define __ARM_FEATURE_CRC32 1' $(OUT)/mcpu-a53.macros.txt
	grep -Eq -- '-mtune=[[:space:]]+cortex-a53' $(OUT)/cortex-a53/options.txt
	touch $@

$(OUT)/android-abi.ok: $(LIBRARIES) $(ANDROID_ORACLES) $(OUT)/benchmark $(ROOT)/check-abi.awk
	$(PREFIX)readelf -WhAln $(OUT)/generic/libkernels.so > $(OUT)/generic/android-elf.txt
	$(PREFIX)readelf -WhAln $(OUT)/cortex-a53/libkernels.so > $(OUT)/cortex-a53/android-elf.txt
	$(PREFIX)nm -D --defined-only --format=posix $(OUT)/generic/libkernels.so > $(OUT)/generic/android-exports.txt
	$(PREFIX)nm -D --defined-only --format=posix $(OUT)/cortex-a53/libkernels.so > $(OUT)/cortex-a53/android-exports.txt
	awk '{ print $$1, $$2 }' $(OUT)/generic/android-exports.txt > $(OUT)/generic/export-names.txt
	awk '{ print $$1, $$2 }' $(OUT)/cortex-a53/android-exports.txt > $(OUT)/cortex-a53/export-names.txt
	cmp $(OUT)/generic/export-names.txt $(OUT)/cortex-a53/export-names.txt
	cmp $(ROOT)/exports.txt $(OUT)/generic/export-names.txt
	awk -f $(ROOT)/check-abi.awk $(OUT)/generic/android-elf.txt
	awk -f $(ROOT)/check-abi.awk $(OUT)/cortex-a53/android-elf.txt
	$(PREFIX)readelf -Whl $(OUT)/benchmark > $(OUT)/benchmark-elf.txt
	awk -f $(ROOT)/check-abi.awk $(OUT)/benchmark-elf.txt
	$(PREFIX)readelf -Whl $(OUT)/generic/android-oracle > $(OUT)/generic/android-oracle-elf.txt
	$(PREFIX)readelf -Whl $(OUT)/cortex-a53/android-oracle > $(OUT)/cortex-a53/android-oracle-elf.txt
	awk -f $(ROOT)/check-abi.awk $(OUT)/generic/android-oracle-elf.txt
	awk -f $(ROOT)/check-abi.awk $(OUT)/cortex-a53/android-oracle-elf.txt
	touch $@

# These are required negative controls, not a second implementation.
regression: $(OUT)/generic/linux-oracle $(OUT)/linux-driver.o $(ASSEMBLY)
	$(LINUX_CC) -std=c11 -O0 -c $(ROOT)/negative-volume.c -o $(OUT)/negative-volume.o
	$(LINUX_CC) -static $(OUT)/generic/scalar.o $(OUT)/generic/vector.o $(OUT)/generic/branch.o $(OUT)/negative-volume.o $(OUT)/linux-driver.o -o $(OUT)/negative-oracle
	$(QEMU) -cpu cortex-a53 $(OUT)/negative-oracle > $(OUT)/negative-oracle.txt; test $$? = 16
	awk -f $(ROOT)/check-abi.awk $(ROOT)/negative-elf.txt > $(OUT)/negative-elf.log 2>&1; test $$? = 1
	grep -q 'FAIL ELF64/AArch64/DYN/16KiB load contract' $(OUT)/negative-elf.log
	awk '/(^|[^[:alnum:]_])(x18|w18)([^[:alnum:]_]|$$)/ { bad=1 } END { if (bad) exit 1 }' $(ASSEMBLY)
	grep -Eq 'f(add|mul)[[:space:]]+v[0-9]+\.4s' $(OUT)/generic/vector.s
	grep -Eq 'f(add|mul)[[:space:]]+v[0-9]+\.4s' $(OUT)/cortex-a53/vector.s
	grep -q 'cortex_a53_fp' $(OUT)/cortex-a53/volume.sched.txt
