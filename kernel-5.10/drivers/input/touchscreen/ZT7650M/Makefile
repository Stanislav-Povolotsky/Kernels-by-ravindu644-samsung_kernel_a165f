ifeq ($(KERNELRELEASE),)
# Invoked directly (e.g. as an out-of-tree / EXT_MODULES build): bounce into
# the kernel build system so a bare `make -C <this dir>` builds the module.
KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
M ?= $(CURDIR)

.PHONY: all modules modules_install clean
all: modules

modules modules_install clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(M) $@

else
# Invoked by kbuild (in-tree, or via `make -C <kernel> M=<this dir>`).
ccflags-$(CONFIG_DRM_MEDIATEK_V2) += -I$(srctree)/drivers/gpu/drm/mediatek/mediatek_v2/

# NOTE: sec_tsp_log.o is deliberately NOT built into this module. Its symbols
# (sec_debug_tsp_command_history, sec_debug_tsp_log, ...) are already exported
# by the loaded sec_common_fn module; bundling them here would export duplicate
# symbols and the kernel would reject loading (Exec format error). They are
# resolved externally from sec_common_fn instead, matching the stock module.
obj-m += zt7650m_ts.o
zt7650m_ts-y := zinitix_ts.o
endif
