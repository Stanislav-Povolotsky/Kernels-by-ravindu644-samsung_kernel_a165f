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

obj-m += zt7650m.o
zt7650m-y := sec_tsp_log.o zinitix_ts.o
endif
