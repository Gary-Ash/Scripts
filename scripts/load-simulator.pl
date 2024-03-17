#!/usr/bin/env perl
#*****************************************************************************************
# load-simulator.pl
#
# This script will restore the state of the iOS simulator
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  18-Aug-2023  8:10pm
# Modified :  16-Mar-2024 10:39pm
#
# Copyright © 2023-2024 By Gee Dbl A All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# libraries used
#*****************************************************************************************
use strict;
use warnings;
use Foundation;
use File::Copy;
use File::Find;

#*****************************************************************************************
# main line
#*****************************************************************************************
our @mediaFiles;
our %simulators;

my $mediaList      = "";
my $HOME           = $ENV{"HOME"};
my $simulatorsLoc  = "$HOME/Library/Developer/CoreSimulator/Devices";
my $media          = "$HOME/Documents/GeeDblA/Resources/Development/Apple/SimulatorBackup";

`xcrun simctl shutdown all`;
`xcrun simctl delete unavailable`;
`xcrun simctl erase all`;

find(\&getSimulators, $simulatorsLoc);
find(\&addMedia, $media);

`open -a Simulator`;
sleep(8);

for (keys %simulators) {
    `xcrun simctl boot "$_" &> /dev/null`;
}

sleep(4);

for (keys %simulators) {
    for my $file (@mediaFiles) {
        system("xcrun simctl addmedia $simulators{$_} $file");
    }
}
`xcrun simctl shutdown all`;

#*****************************************************************************************
# this routine will load a hash with names and UUIDs of the currently defined simulators
#*****************************************************************************************
sub getSimulators {
    return if ($File::Find::name !~ /\/device.plist/);
    my $plist = NSMutableDictionary->dictionaryWithContentsOfFile_($File::Find::name);
    if ($plist && $$plist) {
        my $platform = $plist->objectForKey_("runtime")->UTF8String;
        if ($platform =~ /.*iOS*/) {
            my $name = $plist->objectForKey_("name")->UTF8String;
            my $uuid = $plist->objectForKey_("UDID")->UTF8String;;
            $simulators{$name} = $uuid;
        }
    }
}

#*****************************************************************************************
# this routine will load a media into the current simulator
#*****************************************************************************************
sub addMedia {
    return if $_ eq "." or $_ eq ".." or $_ eq ".DS_Store";
    return if !-f $_;
    push @mediaFiles, $File::Find::name;
}