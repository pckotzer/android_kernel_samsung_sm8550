# SPDX-License-Identifier: GPL-2.0
#
# Makefile for Kernel-based Virtual Machine module, HYP part
#

# Definiert die zu filternden Flags (Erweitert um den Haupt-Verursacher -fno-plt)
KVM_FILTER_FLAGS := -fno-plt

# FIX: Schließende Klammer am Ende wurde hinzugefügt, um den Makefile-Absturz zu beheben
KBUILD_CFLAGS := $(filter-out $(KVM_FILTER_FLAGS), $(KBUILD_CFLAGS))

incdir := $(srctree)/$(src)/include
subdir-asflags-y := -I$(incdir)
subdir-ccflags-y := -I$(incdir)         \
            -fno-stack-protector        \
            -DDISABLE_BRANCH_PROFILING  \
            $(DISABLE_STACKLEAK_PLUGIN)

obj-$(CONFIG_KVM) += vhe/ nvhe/ pgtable.o
