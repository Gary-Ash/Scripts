#!/usr/bin/env perl
#*****************************************************************************************
# gitkeep-repro.pl
#
# This script will add .gitkeep files to a repository's directory structure to properly
# maintain the structure in Git.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   7-Mar-2022  7:40pm
# Modified :  19-Aug-2023  9:16pm
#
# Copyright © 2022-2023 By Gee Dbl A All rights reserved.
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
my $lastDir                   = "";
my %processDirectoriesOptions = (
    wanted      => \&processDirectories,
    no_chdir    => 1,
    follow_skip => 2,
);

my $workRoot = (@ARGV == 1) ? $ARGV[0] : ".";
`find $workRoot -name ".DS_Store" -delete`;

find(\%processDirectoriesOptions, $workRoot);

#*****************************************************************************************
# process directories
#*****************************************************************************************
sub processDirectories {
    return if $_ eq "." or $_ eq "..";
    return if $_ =~ /.git\/*/;
    return if index($_, '\r') > 0;
    return if -f $_;

    if ($lastDir eq $File::Find::dir) {
        return;
    }
    else {
        $lastDir = $File::Find::dir;
    }

    my %processFilesOptions = (
        wanted      => \&processFiles,
        no_chdir    => 1,
        follow_skip => 2,
    );

    my $foundFile = 0;
    opendir(my $d, $File::Find::dir) || die "Can't open $File::Find::dir: $!\n";
    my @files = readdir($d);
    closedir($d);

    foreach my $file (@files) {
        next if $file eq "." or $file eq ".." or $file eq ".DS_Store";

        if (-f "$File::Find::dir/$file") {
            $foundFile = 1;
            last;
        }
    }

    if ($foundFile == 0) {
        open(my $FILE, ">>$File::Find::dir/.gitkeep") || die("Cannot open file:" . $!);
        close($FILE);
    }
}
