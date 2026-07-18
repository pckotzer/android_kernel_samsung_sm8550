# SPDX-License-Identifier: GPL-2.0-only

KCOV_INSTRUMENT := n
KCSAN_SANITIZE := n

obj-$(CONFIG_SCHED_WALT) += sched-walt.o

# Base objects that are always compiled for WALT
sched-walt-$(CONFIG_SCHED_WALT) := walt.o boost.o sched_avg.o walt_halt.o core_ctl.o trace.o input-boost.o sysctl.o fixup.o walt_lb.o walt_rt.o walt_cfs.o walt_tp.o hyst_qos.o

# Mutually exclusive governor selection to prevent duplicate symbol errors
ifeq ($(CONFIG_CPU_FREQ_GOV_SUPERWALT),y)
sched-walt-$(CONFIG_SCHED_WALT) += cpufreq_superwalt.o
else
sched-walt-$(CONFIG_SCHED_WALT) += cpufreq_walt.o
endif

obj-$(CONFIG_SCHED_WALT_DEBUG) += sched-walt-debug.o
sched-walt-debug-$(CONFIG_SCHED_WALT_DEBUG) := walt_debug.o preemptirq_long.o
