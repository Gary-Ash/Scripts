#!/usr/bin/env perl
#*****************************************************************************************
# reset-dates.pl
#
# This script will allow me to reset the file creation and modification dates of files in
# a given directory tree. date information is also edited if my personal source file
# header comment block is detected
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  18-Aug-2023  8:10pm
# Modified :   4-Sep-2023  9:04pm
#
# Copyright © 2023 By Gee Dbl A All rights reserved.
#*****************************************************************************************

#****************************************************************************************
# libraries
#****************************************************************************************
use strict;
use warnings;
use File::Find;
use POSIX qw(strftime);

my %processFilesOptions = (
    wanted      => \&processFiles,
    no_chdir    => 1,
    bydepth     => 0,
    follow_skip => 2,
);

our $SetFileDate = strftime "%D %I:%M %p", localtime;
our $currentDate = strftime "%e-%b-%Y  %-I:%M%p", localtime;
our $currentYear = strftime "%Y", localtime;
$currentDate =~ s/AM/am/;
$currentDate =~ s/PM/pm/;

if (@ARGV != 2 && @ARGV != 1) {
    print "reset-date.pl \"company name\" <directory>\n";
    exit(1);
}

my $company = $ARGV[0];
my $workRoot = (@ARGV == 2) ? $ARGV[1] : ".";

find(\%processFilesOptions, $workRoot);
`xattr -cr $workRoot/*`;
`find $workRoot/ -exec SetFile -d "$SetFileDate" -m "$SetFileDate" {} \\;`;
`find "$workRoot/" \\( -name "*~" -or -name ".*~" -or -name "#*#" -or -name ".#*#" -or -name "*.o" -or -name "*(deleted*" -or -name "*conflicted*" -or -name "*.DS_Store" \\) -exec rm -frv {} \\;`;

#*****************************************************************************************
# process a source file
#*****************************************************************************************
sub processFiles {
    return if $_ eq "." or $_ eq "..";
    return if $_  =~ /.git\/*/;
    return if !-f $_;
    return if index($_, '\r') > 0;

    if (open(my $sourcefile, "<$File::Find::name")) {
        my $source = do { local $/; <$sourcefile> };
        close($sourcefile);

        $source =~ s/\x{43}reated  :.*\n/\x{43}reated  :  $currentDate\n/g;
        $source =~ s/\x{4D}odified :.*\n/\x{4D}odified :\n/g;
        $source =~ s/\x{43}opyright © [0-9\-]* .*\n/\x{43}opyright © $currentYear By $company All rights reserved.\n/g;

        open($sourcefile, ">$File::Find::name")
            || die "*** Unable to read the $File::Find::name - $!\n";

        print $sourcefile $source;
        close($sourcefile);
    }
}
