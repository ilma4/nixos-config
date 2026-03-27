#!/usr/bin/env python3

import argparse
import os
import sys
from enum import Enum
from pathlib import Path

CPU_DIR = Path('/sys/devices/system/cpu')
PLATFORM_MODE_FILE = Path('/sys/firmware/acpi/platform_profile')
PCI_MODE_FILE = Path('/sys/module/pcie_aspm/parameters/policy')

class PowerMode(Enum):
    POWER = 'power'
    BALANCED = 'balanced'
    PERFORMANCE = 'performance'

# Mode mappings: (cpu_mode, platform_mode, pcie_mode)
MODE_MAPPINGS = {
    PowerMode.POWER: ('power', 'low-power', 'powersave'),
    PowerMode.BALANCED: ('balance_performance', 'balanced', 'default'),
    PowerMode.PERFORMANCE: ('balance_performance', 'performance', 'default')
}

def read_file(path: Path) -> str:
    if not path.exists():
        return f'Cannot read file {path}'
    return path.read_text().strip()

def write_file(path: Path, content: str):
    if not path.exists():
        print(f'Cannot write to file {path}', file=sys.stderr)
        return
    path.write_text(content)

def get_cpu_files():
    # Only match cpu[0-9]*
    return [d / 'cpufreq/energy_performance_preference' for d in CPU_DIR.glob('cpu[0-9]*')]

def current_mode() -> PowerMode:
    if not PLATFORM_MODE_FILE.exists():
        print(f'platform power profile file does not exist: {PLATFORM_MODE_FILE}', file=sys.stderr)
        return PowerMode.BALANCED

    current = read_file(PLATFORM_MODE_FILE)
    if current == 'low-power':
        return PowerMode.POWER
    elif current == 'balanced':
        return PowerMode.BALANCED
    elif current == 'performance':
        return PowerMode.PERFORMANCE
    else:
        print(f'unexpected platform power profile: {current}', file=sys.stderr)
        sys.exit(1)

def opposite_mode(mode: PowerMode) -> PowerMode:
    if mode == PowerMode.BALANCED:
        return PowerMode.POWER
    elif mode == PowerMode.POWER:
        return PowerMode.BALANCED
    elif mode == PowerMode.PERFORMANCE:
        return PowerMode.BALANCED
    else:
        print(f"Unexpected mode: {mode}", file=sys.stderr)
        sys.exit(1)

def display_info():
    print('Current power mode settings:')
    print(f' Platform Mode: {read_file(PLATFORM_MODE_FILE)}')
    print(f' PCIe Mode: {read_file(PCI_MODE_FILE)}')

    cpu_files = get_cpu_files()
    if not cpu_files:
        print("Cannot determine number of CPUs")
        return

    cpu_modes = set()
    for f in cpu_files:
        cpu_modes.add(read_file(f))

    if len(cpu_modes) == 1:
        print(f' All CPUs have mode: {cpu_modes.pop()}')
    else:
        print(" CPUs modes:")
        for i, f in enumerate(sorted(cpu_files, key=lambda x: int(x.parent.parent.name[3:]))):
            print(f'  CPU {i} Mode: {read_file(f)}')

def main():
    parser = argparse.ArgumentParser(description="Set various power consumption related Linux system settings.")
    parser.add_argument('-i', '--info', action='store_true', help="Display current power mode settings")
    parser.add_argument('mode', nargs='?', help="power, balance, perf. If omitted, toggles.")
    
    args = parser.parse_args()

    if args.info:
        display_info()
        sys.exit(0)

    if args.mode:
        mode_str = args.mode.lower()
        if mode_str == 'power':
            mode = PowerMode.POWER
        elif mode_str in ('balance', 'balanced', 'ok', 'normal', 'default'):
            mode = PowerMode.BALANCED
        elif mode_str in ('perf', 'performance'):
            mode = PowerMode.PERFORMANCE
        else:
            print(f"Error! Unknown mode: {args.mode}", file=sys.stderr)
            sys.exit(1)
    else:
        print("toggle mode")
        current = current_mode()
        mode = opposite_mode(current)
        print(f'Switching from {current.name} to {mode.name}')

    if os.getuid() != 0:
        print("Changing power setting require root permissions!", file=sys.stderr)
        os.execvp("sudo", ["sudo"] + sys.argv)

    cpu_mode, platform_mode, pcie_mode = MODE_MAPPINGS[mode]

    print(f"Setting cpu mode: {cpu_mode}")
    for cpu_file in get_cpu_files():
        write_file(cpu_file, cpu_mode)
    print("Successfuly set cpu mode")

    print(f"Setting platform mode: {platform_mode}")
    write_file(PLATFORM_MODE_FILE, platform_mode)
    print("Successfuly set platform mode")

    print(f"Setting PCIe mode: {pcie_mode}")
    write_file(PCI_MODE_FILE, pcie_mode)
    print("Successfuly set PCIe mode")

if __name__ == "__main__":
    main()
