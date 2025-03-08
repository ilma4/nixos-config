#!/usr/bin/env python3

from enum import Enum
import os
from sys import argv
import sys


CPU_DIR_PREFIX = '/sys/devices/system/cpu/cpu'
CPU_DIR_SUFFIX = '/cpufreq/energy_performance_preference'

PLATFORM_MODE_FILE = '/sys/firmware/acpi/platform_profile'
PCI_MODE_FILE = '/sys/module/pcie_aspm/parameters/policy'


class PowerMode(Enum):
    POWER = 1,
    BALANCED = 2,
    UKNOWN = 3,
    PERFORMANCE = 4
    
def readFile(path: str) -> str:
    if not os.path.exists(path):
        return f'Cannot read file {path}'

    with open(path, 'r') as f:
        return f.read().strip()

def writeFile(path: str, content: object):
    if not os.path.exists(path):
        print(f'Cannot write to file {path}', file=sys.stderr)
        return

    with open(path, 'w') as f:
        f.write(str(content))


def setup_cpus(mode: str, cpu_count: int | None = os.cpu_count()):
    if cpu_count == None:
        print("Cannot determine number of CPUs")
        return
    
    print(f"Setting cpu mode: {mode}")
    for i in range(cpu_count):
        cpu = (CPU_DIR_PREFIX + str(i)) + CPU_DIR_SUFFIX
        writeFile(cpu, mode)
    print("Successfuly set cpu mode")


def setup_platform(mode: str):
    print (f"Setting platform mode: {mode}")
    path = PLATFORM_MODE_FILE
    writeFile(path, mode)
    print("Successfuly set platform mode")


def setup_pcie(mode: str):
    print (f"Setting PCIe mode: {mode}")
    writeFile(PCI_MODE_FILE, mode)
    print("Successfuly set PCIe mode")


def currentMode() -> PowerMode:
    if not os.path.exists(PLATFORM_MODE_FILE):
        print(f'platform power profile file does not exist: {PLATFORM_MODE_FILE}', file=sys.stderr)
        return PowerMode.UKNOWN 

    current = readFile(PLATFORM_MODE_FILE)
    if current == 'low-power':
        return PowerMode.POWER
    elif current == 'balanced':
        return PowerMode.BALANCED
    elif current == 'performance':
        return PowerMode.PERFORMANCE
    else:
        print(f'unexpected platform power profile: {current}', file=sys.stderr)
        sys.exit(1)
    
    
def oppositeMode(mode: PowerMode) -> PowerMode:
    if mode == PowerMode.BALANCED:
        return PowerMode.POWER
    elif mode == PowerMode.POWER:
        return PowerMode.BALANCED
    elif mode == PowerMode.PERFORMANCE:
        return PowerMode.BALANCED
    else:
        print(f"Unexpected mode: {mode}", file=sys.stderr)
        exit(1)


def display_current_settings():
    current_platform_mode = readFile(PLATFORM_MODE_FILE)    
    current_pcie_mode = readFile(PCI_MODE_FILE)

    print(f'Current power mode settings:')
    print(f' Platform Mode: {current_platform_mode}')
    print(f' PCIe Mode: {current_pcie_mode}')

    basedir = '/sys/devices/system/cpu/cpu'
    second = '/cpufreq/energy_performance_preference'
    cpus = os.cpu_count()
    if cpus == None:
        print("Cannot determine number of CPUs")
        return
    
    cpu_modes = set[str]()
    for i in range(cpus):
        cpu = (basedir + str(i)) + second
        current_cpu_mode = readFile(cpu)
        cpu_modes.add(current_cpu_mode)

    if len(cpu_modes) == 1:
        print(f' All CPUs have mode: {cpu_modes.pop()}')
    else:
        print(" CPUs modes:")
        for i in range(cpus):
            cpu = (basedir + str(i)) + second
            current_cpu_mode = readFile(cpu)
            print(f'  CPU {i} Mode: {current_cpu_mode}')


def print_help():
    print("Set various power consumption related Linux system settings.")
    print("Usage: python script.py [OPTION]")
    print("\nOptions:")
    print("  power          Set power mode")
    print("  balance        Set balanced mode")
    print("  -i, --info     Display current power mode settings")
    print("  -h, --help     Print this help message")


def main():
    if len(argv) == 2 and (argv[1] == '-h' or argv[1] == '--help'):
        print_help()
        exit(0)
    elif len(argv) == 2 and (argv[1] == '--info' or argv[1] == '-i'):
        display_current_settings()
        exit(0)
    elif len(argv) == 1:
        print ("toggle mode")
        current = currentMode()
        mode = oppositeMode(current)
        print(f'Switching from {current} to {mode}')
    elif len(argv) >= 3:
        print ("too many args")
        exit(1)
    else:
        arg = argv[1]
        if arg == 'power':
            mode = PowerMode.POWER
        elif arg in {'balance', 'balanced', 'ok', 'normal', 'default'}:
            mode = PowerMode.BALANCED
        elif arg in {'perf', 'performance'}:
            mode = PowerMode.PERFORMANCE
        else:
            print(f"Error! Unknown mode: {arg}", file=sys.stderr)
            exit(1)


    if os.getuid() != 0:
        print("Changing power setting require root permissions!", file=sys.stderr)
        os.execvp("sudo", ["sudo"] + sys.argv)
    
    if mode == PowerMode.POWER:
        cpuMode = 'power'
        platformMode = 'low-power'
        pcieMode = 'powersave'
    elif mode == PowerMode.BALANCED:
        cpuMode = 'balance_performance'
        platformMode = 'balanced'
        pcieMode = 'default'
    elif mode == PowerMode.PERFORMANCE:
        cpuMode = 'balance_performance'
        platformMode = 'performance'
        pcieMode = 'default'
    else:
        print(f"Error! Unknown mode to set: {mode}", file=sys.stderr)
        exit(1)
        
    setup_cpus(mode=cpuMode)
    setup_platform(mode=platformMode)
    setup_pcie(mode=pcieMode)


if __name__ == "__main__":
    main()
