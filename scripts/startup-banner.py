#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  startup-banner.py
#
# Terminal startup banner
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import base64
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

LOGO_FILE = Path("/opt/geedbla/pictures/apple-logo.png")

MODEL_LIST_FILES = (
    Path(
        "/System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/"
        "Resources/English.lproj/SIMachineAttributes.plist"
    ),
    Path(
        "/System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/"
        "Resources/en.lproj/SIMachineAttributes.plist"
    ),
)

# marketing names for the releases that system_profiler reports by number alone
MACOS_NAMES = (
    (r"10\.12", "macOS Sierra"),
    (r"10\.13", "macOS High Sierra"),
    (r"10\.14", "macOS Mojave"),
    (r"10\.15", "macOS Catalina"),
    (r"11", "macOS Big Sur"),
    (r"12", "macOS Monterey"),
    (r"13", "macOS Ventura"),
    (r"14", "macOS Sonoma"),
    (r"15", "macOS Sequoia"),
    (r"26", "macOS Tahoe"),
)

KNOWN_MODELS = {
    "MacBookPro16,1": '16" MacBook Pro (2019) True Tone Display',
    "iMac20,2": 'iMac 5k 27" (2020) True Tone Display',
    "Mac13,2": "Mac Studio 2022",
    "Mac14,6": '16" MacBook Pro (2023) Retina XDR Display',
}

APPLE_LOGO = """\033[38;5;034m                                        @@
\033[38;5;034m                                    @@@@@@
\033[38;5;034m                                 @@@@@@@@
\033[38;5;034m                               @@@@@@@@@@
\033[38;5;034m                              @@@@@@@@@@
\033[38;5;034m                             @@@@@@@@@@
\033[38;5;034m                             @@@@@@@@
\033[38;5;034m                            @@@@@@
\033[38;5;034m                            @@
\033[38;5;034m           @@@@@@@@@@@@        @@@@@@@@@@@@@@@
\033[38;5;034m        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;034m      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;034m    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;226m   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;226m  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;208m @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;208m @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;196m @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;196m @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;196m  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;196m   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;129m    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;129m     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;129m      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;038m        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;038m          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;038m            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
\033[38;5;038m              @@@@@@@@@          @@@@@@@@@

"""


def shell(command):
    return subprocess.run(
        command, shell=True, capture_output=True, text=True, check=False
    ).stdout


def capture(text, pattern, group=1):
    match = re.search(pattern, text)
    return match.group(group) if match else None


def macos_name(version):
    for pattern, name in MACOS_NAMES:
        if re.match(pattern, version):
            return name
    return None


def detect_format(filename):
    lowered = str(filename).lower()
    if lowered.endswith(".png"):
        return 100
    if lowered.endswith((".jpg", ".jpeg")):
        return 24
    return 100


def display_logo():
    terminal = os.environ.get("TERM_PROGRAM")

    if LOGO_FILE.exists() and terminal is not None and terminal != "Apple_Terminal":
        encoded = base64.b64encode(LOGO_FILE.read_bytes()).decode("ascii")
        image_format = detect_format(LOGO_FILE)
        print(f"\033[0;0H\033_Ga=T,f={image_format};{encoded}\033\\", end="")
    else:
        print("\033[0;0H\n" + APPLE_LOGO, end="")


# ****************************************************************************************
# parse command line
# ****************************************************************************************
def parse_command_line(argv):
    theme = 1

    for argument in argv:
        if argument in ("-l", "--light"):
            theme = 1
        elif argument in ("-d", "--dark"):
            theme = 0
        else:
            sys.stderr.write(f"**** Unknown argument: {argument}\n")
            sys.exit(2)

    return theme


# ****************************************************************************************
# gather system information
# ****************************************************************************************
def gather_specs(highlight_text, normal_info_text):
    hardware_data = shell(
        "system_profiler SPHardwareDataType SPSoftwareDataType  SPDisplaysDataType"
    )
    df_data = shell("df -H / 2> /dev/null")
    battery_data = shell("pmset -g batt 2> /dev/null").rstrip("\n")
    internal_ip = shell("ipconfig getifaddr en0 2> /dev/null").rstrip("\n")
    external_ip = shell(
        "/usr/bin/dig +short myip.opendns.com @resolver1.opendns.com"
    ).rstrip("\n")

    specs = []

    # ------------------------------------------------------------------------------------
    # parse user name
    # ------------------------------------------------------------------------------------
    specs.append(f"User         : {capture(hardware_data, r'User Name: (.*)\n')}")

    # ------------------------------------------------------------------------------------
    # parse OS name and version
    # ------------------------------------------------------------------------------------
    os_version = capture(hardware_data, r"System Version: (.*)\n").split(" ")
    name = macos_name(os_version[1])
    if name:
        os_version[0] = name
    specs.append(f"OS           : {os_version[0]} {os_version[1]} {os_version[2]}")

    # ------------------------------------------------------------------------------------
    # Homebrew package manager
    # ------------------------------------------------------------------------------------
    if os.access("/usr/local/bin/brew", os.X_OK) or os.access(
        "/opt/homebrew/bin/brew", os.X_OK
    ):
        shell("brew update &> /dev/null")

        installed = len(re.split(r"\s", shell("brew list --formula")))
        outdated = len(re.split(r"\s", shell("brew outdated")))

        outdated_text = str(outdated)
        if outdated > 0:
            outdated_text = f"{highlight_text}{outdated}{normal_info_text}"
        specs.append(f"Homebrew     : {installed} Packages {outdated_text} Updates")

    # ------------------------------------------------------------------------------------
    # parse the current shell details
    # ------------------------------------------------------------------------------------
    shell_path = os.environ.get("SHELL", "")
    shell_text = shell_path
    if "bash" in shell_path:
        version = shell(
            f"{shell_path} -c 'echo ${{BASH_VERSINFO[0]}}.${{BASH_VERSINFO[1]}}.${{BASH_VERSINFO[2]}}'"
        ).rstrip("\n")
        shell_text = f"Bash v{version} ({shell_path})"
    elif "zsh" in shell_path:
        version = shell(f"{shell_path} -c 'echo $ZSH_VERSION'").rstrip("\n")
        shell_text = f"ZSH v{version} ({shell_path})"
    specs.append(f"Shell        : {shell_text}")

    # ------------------------------------------------------------------------------------
    # parse machine data
    # ------------------------------------------------------------------------------------
    machine = f"Machine      : {capture(hardware_data, r'Computer Name: (.*)\n')}"

    if not MODEL_LIST_FILES[0].exists():
        model_list_file = MODEL_LIST_FILES[1]
        hardware_id = capture(hardware_data, r"Model Identifier: (.*)\n")

        if model_list_file.is_file():
            marketing_model = None
            try:
                with open(model_list_file, "rb") as plist_file:
                    model_dict = plistlib.load(plist_file).get(hardware_id)
                if model_dict:
                    marketing_model = model_dict.get("_LOCALIZABLE_", {}).get(
                        "marketingModel"
                    )
            except (OSError, plistlib.InvalidFileException):
                model_dict = None

            if marketing_model:
                machine = f"{machine} - {marketing_model}"
            elif hardware_id in KNOWN_MODELS:
                machine = f"{machine} - {KNOWN_MODELS[hardware_id]}"

    specs.append(machine)

    machine_specs = ""
    processor = capture(hardware_data, r"(Processor Name|Chip: )(.*)\n", 2)
    if processor is not None:
        machine_specs += f"             : {processor} "

    cores = capture(hardware_data, r"(Total Number of Cores: )(.*)\n", 2)
    if cores is not None:
        machine_specs += f"{cores} Cores "

    speed = capture(hardware_data, r"(Processor Speed: )(.*)\n", 2)
    if speed is not None:
        machine_specs += f"{speed} "

    memory = capture(hardware_data, r"(Memory: )(.*)\n", 2)
    machine_specs += f"{memory} Memory"
    specs.append(machine_specs)

    if shell("uname -p").strip() != "arm":
        chipset = capture(hardware_data, r"(Chipset Model: )(.*)\n", 2)
        machine_specs = f"GPU          : {chipset} "
        vram = capture(hardware_data, r"(VRAM \(Total\): )(.*)\n", 2)
        if vram is not None:
            machine_specs += f" - {vram} Video RAM"
        specs.append(machine_specs)

    # ------------------------------------------------------------------------------------
    # parse the battery status
    # ------------------------------------------------------------------------------------
    if battery_data != "Now drawing from 'AC Power'":
        charge = capture(battery_data, r"([0-9]+%)")
        if "InternalBattery" in battery_data:
            if "Now drawing from 'AC Power'" in battery_data:
                specs.append(
                    f"Power        : Charging on AC Power Battery charge at {charge}"
                )
            else:
                specs.append(
                    f"Power        : Running on Battery Power charge at {charge}"
                )

    # ------------------------------------------------------------------------------------
    # parse IP addresses
    # ------------------------------------------------------------------------------------
    specs.append(f"IP Addresses : {internal_ip}/{external_ip}")

    # ------------------------------------------------------------------------------------
    # parse the boot disk information
    # ------------------------------------------------------------------------------------
    boot_volume = capture(hardware_data, r"(Boot Volume: )(.*)\n", 2)

    df_data = df_data[df_data.index("\n") + 1 :]
    df_data = re.sub(r"\s\s*", " ", df_data)
    df_split = re.split(r"\s", df_data)

    df_data = f"Size: {df_split[1]} Used: {df_split[2]}  Free: {df_split[3]}"
    df_data = df_data.replace("T", " TB").replace("G", " GB")

    specs.append(f"Boot Disk    : {boot_volume} {df_data}")

    # ------------------------------------------------------------------------------------
    # parse up time information
    # ------------------------------------------------------------------------------------
    specs.append(f"Up Time      : {capture(hardware_data, r'Time since boot: (.*)\n')}")

    return specs


# ****************************************************************************************
# script main line
# ****************************************************************************************
def main(argv):
    theme = parse_command_line(argv)
    columns = int(shell("tput cols").strip() or 80)

    # ------------------------------------------------------------------------------------
    # visual theme variables
    # ------------------------------------------------------------------------------------
    bold_text = "\033[1m"
    heading_text = f"{bold_text}\033[38;5;255m"
    highlight_text = f"{bold_text}\033[38;5;255m"
    normal_info_text = "\x1b[0m"

    if theme == 1:
        heading_text = bold_text
        highlight_text = bold_text

    specs = gather_specs(highlight_text, normal_info_text)

    # ------------------------------------------------------------------------------------
    # calculate the column for the machine specs
    # ------------------------------------------------------------------------------------
    longest = max((len(item) for item in specs), default=0)

    print(shell("tput clear"), end="")
    display_logo()

    specs_column = int((columns - longest) / 2) + 10
    for specs_line, text in enumerate(specs, start=1):
        heading = ""
        colon_index = text.find(":")
        if colon_index > -1:
            heading = text[: colon_index + 1]
            text = text[colon_index + 1 :]

        print(
            f"\033[{specs_line};{specs_column}H{heading_text}{heading}"
            f"{normal_info_text}{text}",
            end="",
        )

    print("\n\n\n", end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
