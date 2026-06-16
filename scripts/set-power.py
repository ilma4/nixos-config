#!/usr/bin/env python3
import os
import sys
from pathlib import Path

CPU_DIR = Path("/sys/devices/system/cpu")
PLATFORM_MODE_FILE = Path("/sys/firmware/acpi/platform_profile")
PCI_MODE_FILE = Path("/sys/module/pcie_aspm/parameters/policy")

# cpu_mode, platform_mode, pcie_mode
MODES = {
    "power": ("power", "low-power", "powersave"),
    "balanced": ("balance_performance", "balanced", "default"),
    "performance": ("performance", "performance", "default"),
}
ALIASES = {
    "balance": "balanced",
    "ok": "balanced",
    "normal": "balanced",
    "default": "balanced",
    "perf": "performance",
}


def describe_cpu_modes(cpu_files):
    if not cpu_files:
        return "N/A"

    modes = {read(file) for file in cpu_files}
    return modes.pop() if len(modes) == 1 else "mixed"


def read(path):
    return path.read_text().strip() if path.exists() else "N/A"


def write(path, value):
    if path.exists():
        path.write_text(value)


def main():
    info = "-i" in sys.argv or "--info" in sys.argv
    args = [arg.lower() for arg in sys.argv[1:] if not arg.startswith("-")]
    mode = args[0] if args else None

    cpu_files = list(CPU_DIR.glob("cpu[0-9]*/cpufreq/energy_performance_preference"))

    if info:
        print(f"Platform: {read(PLATFORM_MODE_FILE)}\nPCIe: {read(PCI_MODE_FILE)}")
        print(f"CPUs: {describe_cpu_modes(cpu_files)}")
        return

    mode = ALIASES.get(mode, mode)

    if not mode:
        mode = "balanced" if read(PLATFORM_MODE_FILE) == "low-power" else "power"
        print(f"Toggled to {mode}")

    if mode not in MODES:
        sys.exit(f"Unknown mode: {mode}")

    if os.getuid() != 0:
        os.execvp("sudo", ["sudo", *sys.argv])

    cpu_mode, platform_mode, pcie_mode = MODES[mode]
    for file in cpu_files:
        write(file, cpu_mode)
    write(PLATFORM_MODE_FILE, platform_mode)
    write(PCI_MODE_FILE, pcie_mode)
    print(f"Set: CPU={cpu_mode}, Platform={platform_mode}, PCIe={pcie_mode}")


if __name__ == "__main__":
    main()
