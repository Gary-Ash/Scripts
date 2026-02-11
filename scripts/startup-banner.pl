#!/usr/bin/env perl
#*****************************************************************************************
# startup-banner.pl
#
# Terminal startup banner
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :  12-Feb-2026  4:00pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# Libraries
#*****************************************************************************************
use strict;
use warnings;
use Foundation;
use MIME::Base64;
use File::Basename;

$| = 1;

#*****************************************************************************************
# global variables
#*****************************************************************************************
my $theme   = 1;
my $columns = `tput cols`;

#*****************************************************************************************
# parse command line
#*****************************************************************************************
while (scalar(@ARGV)) {
    my $argument = shift @ARGV;

    if ($argument =~ /^(-l|--light)$/) {
        $theme = 1;
    }
    elsif ($argument =~ /^(-d|--dark)$/) {
        $theme = 0;
    }
    else {
        print STDERR "**** Unknown argument: $argument\n";
        exit(2);
    }
}

#*****************************************************************************************
# visual theme variables
#*****************************************************************************************
my $boldText       = "\033[1m";
my $headingText    = "$boldText\033[38;5;255m";
my $highlightText  = "$boldText\033[38;5;255m";
my $normalInfoText = "\x1b[0m";
my $problemText    = "$boldText\033[38;5;160m";

if ($theme == 1) {
    $headingText   = "$boldText";
    $highlightText = "$boldText";
}

my @specs     = ();
my @results   = ();
my $specsLine = 1;

#*****************************************************************************************
# gather system information
#*****************************************************************************************
my $hardwareData = `system_profiler SPHardwareDataType SPSoftwareDataType  SPDisplaysDataType`;
my $dfData       = `df -H / 2> /dev/null`;
my $shell        = $ENV{'SHELL'};
my $batteryData  = `pmset -g batt 2> /dev/null`;
my $internalIP   = `ipconfig getifaddr en0 2> /dev/null`;
my $externalIP   = `/usr/bin/dig +short myip.opendns.com \@resolver1.opendns.com`;

#*****************************************************************************************
# parse user name
#*****************************************************************************************
@results = $hardwareData =~ /User Name: (.*)\n/;
push @specs, "User         : $results[0]";

#*****************************************************************************************
# parse OS name and version
#*****************************************************************************************
@results = $hardwareData =~ /System Version: (.*)\n/;
my @os_version = split / /, $results[0];
if    ($os_version[1] =~ /10.12.*/) { $os_version[0] = "macOS Sierra"; }
elsif ($os_version[1] =~ /10.13.*/) { $os_version[0] = "macOS High Sierra"; }
elsif ($os_version[1] =~ /10.14.*/) { $os_version[0] = "macOS Mojave"; }
elsif ($os_version[1] =~ /10.15.*/) { $os_version[0] = "macOS Catalina"; }
elsif ($os_version[1] =~ /11.*/)    { $os_version[0] = "macOS Big Sur"; }
elsif ($os_version[1] =~ /12.*/)    { $os_version[0] = "macOS Monterey"; }
elsif ($os_version[1] =~ /13.*/)    { $os_version[0] = "macOS Ventura"; }
elsif ($os_version[1] =~ /14.*/)    { $os_version[0] = "macOS Sonoma"; }
elsif ($os_version[1] =~ /15.*/)    { $os_version[0] = "macOS Sequoia"; }
elsif ($os_version[1] =~ /26.*/)    { $os_version[0] = "macOS Tahoe"; }

$results[0] = "$os_version[0] $os_version[1] $os_version[2]";
push @specs, "OS           : $results[0]";

#*****************************************************************************************
# Homebrew package manager
#*****************************************************************************************
if (-x "/usr/local/bin/brew" || -x "/opt/homebrew/bin/brew") {
    `brew update &> /dev/null`;
    my $output = `brew list --formula`;

    @results = split(/\s/, $output);
    my $installed = scalar @results;

    $output = `brew outdated`;

    @results = split(/\s/, $output);
    my $outdated = scalar @results;
    if ($outdated > 0) {
        $outdated = $highlightText . $outdated . $normalInfoText;
    }
    push @specs, "Homebrew     : $installed Packages $outdated Updates";
}

#*****************************************************************************************
# parse the current shell details
#*****************************************************************************************
if ($shell =~ /bash/) {
    my $v = `$shell -c 'echo \${BASH_VERSINFO[0]}.\${BASH_VERSINFO[1]}.\${BASH_VERSINFO[2]}'`;
    chomp $v;
    $shell = "Bash v$v ($shell)";
}
elsif ($shell =~ /zsh/) {
    my $v = `$shell -c 'echo \$ZSH_VERSION'`;
    chomp $v;
    $shell = "ZSH v$v ($shell)";
}

$shell = "Shell        : $shell";
push @specs, $shell;

#*****************************************************************************************
# parse machine data
#*****************************************************************************************
my $hardwareID;
my $machineSpecs;
@results = $hardwareData =~ /Computer Name: (.*)\n/;
my $machine = "Machine      : $results[0]";

my $modelListFile = "/System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/Resources/English.lproj/SIMachineAttributes.plist";
if (!-e $modelListFile) {
    $modelListFile = "/System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/Resources/en.lproj/SIMachineAttributes.plist";
    @results       = $hardwareData =~ /Model Identifier: (.*)\n/;
    $hardwareID    = $results[0];
    if (-f $modelListFile) {
        my $plistData = NSDictionary->dictionaryWithContentsOfFile_($modelListFile);
        my $modelDict = $plistData->objectForKey_($hardwareID);
        if ($modelDict && $$modelDict) {
            my $localized = $modelDict->objectForKey_("_LOCALIZABLE_");
            $machine = $machine . " - " . $localized->objectForKey_("marketingModel")->UTF8String();
        }
        else {
            if ($hardwareID eq "MacBookPro16,1") { $machine = $machine . " - 16\" MacBook Pro (2019) True Tone Display" }
            if ($hardwareID eq "iMac20,2")       { $machine = $machine . " - iMac 5k 27\" (2020) True Tone Display" }
            if ($hardwareID eq "Mac13,2")        { $machine = $machine . " - Mac Studio 2022" }
            if ($hardwareID eq "Mac14,6")        { $machine = $machine . " - 16\" MacBook Pro (2023) Retina XDR Display" }
        }
    }
}

push @specs, $machine;
@results = $hardwareData =~ /(Processor Name|Chip: )(.*)\n/;
if (scalar @results > 0) {
    $machineSpecs .= "             : $results[1] ";
}

@results = $hardwareData =~ /(Total Number of Cores: )(.*)\n/;
if (scalar @results > 0) {
    $machineSpecs .= "$results[1] Cores ";
}

@results = $hardwareData =~ /(Processor Speed: )(.*)\n/;
if (scalar @results > 0) {
    $machineSpecs .= "$results[1] ";
}
@results = $hardwareData =~ /(Memory: )(.*)\n/;
$machineSpecs .= "$results[1] Memory";
push @specs, $machineSpecs;

my $arch = `uname -p`;
$arch =~ s/^\s*(.*?)\s*$/$1/;
if ($arch ne "arm") {
    @results      = $hardwareData =~ /(Chipset Model: )(.*)\n/;
    $machineSpecs = "GPU          : $results[1] ";
    @results      = $hardwareData =~ /(VRAM \(Total\): )(.*)\n/;
    if (scalar @results > 0) {
        $machineSpecs .= " - $results[1] Video RAM";
    }
    push @specs, $machineSpecs;
}

#*****************************************************************************************
# parse the battery status
#*****************************************************************************************
chomp $batteryData;

if ($batteryData ne "Now drawing from \'AC Power\'") {
    @results = $batteryData =~ /([0-9]+%)/;
    if ($batteryData =~ /InternalBattery/) {
        if ($batteryData =~ /Now drawing from \'AC Power\'/) {
            push @specs, "Power        : Charging on AC Power Battery charge at $results[0]";
        }
        else {
            push @specs, "Power        : Running on Battery Power charge at $results[0]";
        }
    }
}

#*****************************************************************************************
# parse IP addresses
#*****************************************************************************************
chomp($internalIP);
chomp($externalIP);
push @specs, "IP Addresses : $internalIP/$externalIP";

#*****************************************************************************************
# parse the boot disk information
#*****************************************************************************************
@results = $hardwareData =~ /(Boot Volume: )(.*)\n/;

$dfData = substr($dfData, index($dfData, "\n") + 1);
$dfData =~ s/\s\s*/ /g;
my @dfSplit = split(/\s/, $dfData);

$dfData = "Size: $dfSplit[1] Used: $dfSplit[2]  Free: $dfSplit[3]";
$dfData =~ s/T/ TB/g;
$dfData =~ s/G/ GB/g;

push @specs, "Boot Disk    : $results[1] $dfData";

#*****************************************************************************************
# parse up time information
#*****************************************************************************************
@results = $hardwareData =~ /Time since boot: (.*)\n/;
push @specs, "Up Time      : $results[0]";

#*****************************************************************************************
# calculate the column for the machine specs
#*****************************************************************************************
my $longest = 0;
for my $item (@specs) {
    my $len = length($item);
    if ($len > $longest) {
        $longest = $len;
    }
}
print `tput clear`;
displayLogo();

my $specsColumn = int(($columns - $longest) / 2) + 10;
for my $text (@specs) {
    my $theHeadingText = "";
    my $colonIndex     = index($text, ":");
    if ($colonIndex > -1) {
        $theHeadingText = substr($text, 0, $colonIndex + 1);
        $text           = substr($text, $colonIndex + 1);
    }
    print "\033[$specsLine;${specsColumn}H${headingText}${theHeadingText}${normalInfoText}${text}";
    ++$specsLine;
}

print "\n\n\n";

sub detect_format {
    my ($file) = @_;
    return 100 if $file =~ /\.png$/i;
    return 24  if $file =~ /\.(jpg|jpeg)$/i;
    return 100;
}

sub displayLogo {
    my $filename = "/opt/geedbla/pictures/apple-logo.png";

    if (-e $filename
        && (defined $ENV{"TERM_PROGRAM"} && $ENV{"TERM_PROGRAM"} ne "Apple_Terminal"))
    {
        open my $fh, '<', $filename or die "Cannot open $filename: $!\n";
        binmode $fh;
        my $image_data = do { local $/; <$fh> };
        close $fh;

        my $encoded = encode_base64($image_data, '');
        my $format  = detect_format($filename);
        print "\033[0;0H\033_Ga=T,f=$format;${encoded}\033\\";
    }
    else {
        print "\033[0;0H
\033[38;5;034m                                        @@
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

";
    }
}
