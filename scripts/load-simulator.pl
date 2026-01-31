#!/usr/bin/env perl
#*****************************************************************************************
# load-simulator.pl
#
# This script will restore the state of the iOS simulator
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
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
our %simulators;
our $mediaList = "";

my $HOME          = $ENV{"HOME"};
my $simulatorsLoc = "$HOME/Library/Developer/CoreSimulator/Devices";
my $media         = "$HOME/Documents/GeeDblA/Resources/Development/Apple/SimulatorBackup";

find(\&getSimulators, $simulatorsLoc);
find(\&addMedia,      $media);

`/Applications/Xcode.app/Contents/Developer/usr/bin/simctl shutdown all;/Applications/Xcode.app/Contents/Developer/usr/bin/simctl delete unavailable;/Applications/Xcode.app/Contents/Developer/usr/bin/simctl erase all`;
for my $key (keys %simulators) {
    if (system("/Applications/Xcode.app/Contents/Developer/usr/bin/simctl boot \"$key\" &> /dev/null") == 0) {
        if (system("/Applications/Xcode.app/Contents/Developer/usr/bin/simctl addmedia booted $mediaList") != 0) {
            exit(1);
        }
        if (system("/Applications/Xcode.app/Contents/Developer/usr/bin/simctl shutdown booted") != 0) {
            exit(1);
        }

    }
}
`/Applications/Xcode.app/Contents/Developer/usr/bin/simctl shutdown all`;

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
            my $uuid = $plist->objectForKey_("UDID")->UTF8String;
            $simulators{$name} = $uuid;
        }
    }
}

#*****************************************************************************************
# this routine will build a list of all the media in the SimulatorBackup folder
#*****************************************************************************************
sub addMedia {
    return if $_ =~ /^\..*/;
    return if !-f $_;

    if ($mediaList ne "") {
        $mediaList .= " ";
    }
    $mediaList .= $File::Find::name;
}
