#!/usr/bin/env perl
#*****************************************************************************************
# check-path.pl
#
# This little utility will scan the current PATH and make a list directories that exist
# and those that don't
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

use strict;
use warnings;

my $path_env = $ENV{PATH} // '';

die "PATH environment variable is not set\n" unless $path_env;

my @paths = split /:/, $path_env;

my $total       = scalar @paths;
my $existing    = 0;
my $missing     = 0;
my @clean_paths = ();

print "Checking PATH directories:\n";
print "=" x 60 . "\n\n";

foreach my $dir (@paths) {
    if (-d $dir) {
        print "􀆅   $dir\n";
        push @clean_paths, $dir;
        $existing++;
    }
    else {
        print "􀀲   $dir\n";
        $missing++;
    }
}

print "\n\nA clean PATH declaration:\n";
print "=" x 60 . "\n\n";
print "export PATH=" . '"' . join(':', @clean_paths) . '"' . "\n";

print "\n" . "=" x 60 . "\n";
print "Summary:\n";
print "  Total:    $total\n";
print "  Existing: $existing\n";
print "  Missing:  $missing\n";
print "=" x 60 . "\n";

