#!/usr/bin/env perl
#*****************************************************************************************
# fix-xcode-templates.pl
#
# This script will "fix" the internal Xcode project and file templates my searching for
# instances of the comment marker // ___FILEHEADER___ and removing double slashes.
#
# NOTE: This script must be run sudo
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#****************************************************************************************
# libraries
#****************************************************************************************
use strict;
use warnings;
use File::Find;
use File::Basename;

#*****************************************************************************************
# script main line
#*****************************************************************************************
my %processFilesOptions = (
    wanted      => \&processFiles,
    no_chdir    => 0,
    bydepth     => 0,
    follow_skip => 2,
);

find(\%processFilesOptions, "/Applications/Xcode.app/Contents/");
if (open(my $sourcefile, ">/Applications/Xcode.app/Contents/Developer/Library/Xcode/Templates/File Templates/MultiPlatform/Resource/Strings File.xctemplate/___FILEBASENAME___.strings")) {
    print $sourcefile "___FILEHEADER___";
    close($sourcefile);
}

#*****************************************************************************************
# process a source file
#*****************************************************************************************
sub processFiles {
    return if $_ eq "." or $_ eq "..";
    return if !-f $_;

    open(my $sourcefile, "<$File::Find::name") || die "*** Unable to read the $File::Find::name - $!\n";
    my $source = do { local $/; <$sourcefile> };
    close($sourcefile);
    $source =~ s{//\s*___FILEHEADER___}{___FILEHEADER___}g;

    open($sourcefile, ">$File::Find::name")
      || die "*** Unable to read the $File::Find::name - $!\n";

    print $sourcefile $source;
    close($sourcefile);
}
