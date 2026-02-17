#!/usr/bin/env perl
#*****************************************************************************************
# reset-dates.pl
#
# This script will allow me to reset the file creation and modification dates of files in
# a given directory tree. date information is also edited if my personal source file
# header comment block is detected
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :  12-Feb-2026  4:00pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#-----------------------------------------------------------------------------------------
# libraries
#-----------------------------------------------------------------------------------------
use strict;
use warnings;

use File::Find;
use File::Spec;
use File::Basename;

use POSIX qw(strftime);
use Cwd   qw(abs_path);

#-----------------------------------------------------------------------------------------
# constants
#-----------------------------------------------------------------------------------------
our $HOME              = $ENV{"HOME"};
our $TEMPLATE_LOCATION = "/opt/geedbla/templates/Xcode/";

#-----------------------------------------------------------------------------------------
# regular expressions
#-----------------------------------------------------------------------------------------

# this will match copyright declarations an isolate the copyright holder into $1
our $findFilesToProcess = qr/Copyright\s*(?:.*)\s*(?:\d{4}\s*-\s*\d{4}|\d{4}) By (.*) All rights reserved\./;

#-----------------------------------------------------------------------------------------
#  global variables
#-----------------------------------------------------------------------------------------

# command line arguments and optional switches
our @workPaths   = ();
our $companyName = "Gary Ash";

# variables that hold the template substitution values
my @companies;
my $timestamp;
my $setFileDateFormat;
my $copyrightNotice;

#=========================================================================================

sub isValidOrganization {
    my $org = $_[0];
    for my $anOrg (@companies) {
        if (lc($org) eq lc($anOrg)) {
            return 1;
        }
    }
    return 0;
}

sub shouldIgnoreFile {
    my ($filename) = @_;
    my @ignoreExtensions = (".png", ".ttf", "jpg", ".jpeg", ".bmp", ".psd", ".mov", ".mp3", ".ogg", ".mp4", ".caf", ".xcuserstate");

    (undef, undef, my $extension) = fileparse($filename, qr/\.[^.]*$/);

    for my $ext (@ignoreExtensions) {
        if ($ext eq $extension) {
            return 1;
        }
    }
    return 0;
}

sub processScptFile {
    my ($filename) = @_;

    # decompile .scpt to plain text
    my $source = `osadecompile "$filename" 2>/dev/null`;
    if ($? != 0 || !defined($source) || $source eq '') {
        return;
    }

    if ($source =~ /$findFilesToProcess/ && isValidOrganization("$1")) {
        $source =~ s/Created  :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Created  :*[^\n|\\n]/Created  :  $timestamp/;
        $source =~ s/Modified :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Modified :*[^\n|\\n]/Modified :/;
        $source =~ s/$findFilesToProcess/$copyrightNotice/;

        # recompile back to .scpt
        open(my $osacompile, '|-', "osacompile -o \"$filename\" 2>/dev/null") or return;
        print $osacompile $source;
        close($osacompile);
    }
}

sub parseCommandLine {
    if (@ARGV < 1) {
        print STDERR "Usage: reset-dates.pl \"company name\" [file|directory ...]\n\n";
        print STDERR "Examples:\n";
        print STDERR "  reset-dates.pl \"Gary Ash\"                              # Process current directory\n";
        print STDERR "  reset-dates.pl \"Gary Ash\" ./src ./lib ./tests          # Process multiple directories\n";
        print STDERR "  reset-dates.pl \"Gary Ash\" main.swift AppDelegate.swift # Process specific files\n";
        print STDERR "  reset-dates.pl \"Gary Ash\" ./src config.swift           # Mix of files and directories\n";
        exit(1);
    }

    $companyName = shift @ARGV;

    if (@ARGV == 0) {
        push @workPaths, abs_path(".");
    }
    else {
        for my $path (@ARGV) {
            push @workPaths, abs_path($path);
        }
    }
}

sub prepare {
    #=====================================================================================
    # get and format timestamp values
    #=====================================================================================
    $setFileDateFormat = strftime("%D %I:%M %p", localtime);

    $timestamp = strftime("%e-%b-%Y  %-I:%M%p", localtime);
    $timestamp =~ s/AM/am/;
    $timestamp =~ s/PM/pm/;

    my $currentYear = strftime("%Y", localtime);
    $copyrightNotice = "Copyright © $currentYear By $companyName All rights reserved.";

    my $companiesfh;
    if (open($companiesfh, '<', "$TEMPLATE_LOCATION/_Files/organizations.txt") == 0) {
        print STDERR "*** Error: Unable to open orginations file : $!\n";
        exit(1);
    }

    while (<$companiesfh>) { chomp; push(@companies, $_); }
    close($companiesfh);
    push @companies, "CompanyName";
}

sub searchReplace {
    if ($File::Find::name =~ /.*\/\.DS_Store/) {
        unlink($File::Find::name);
        return;
    }

    (undef, undef, my $extension) = fileparse($File::Find::name, qr/\.[^.]*$/);

    # handle compiled AppleScript files specially
    if ($extension eq '.scpt' && -f $File::Find::name) {
        processScptFile($File::Find::name);
        system("SetFile -d \"$setFileDateFormat\" -m \"$setFileDateFormat\" \"$File::Find::name\" &> /dev/null");
        return;
    }

    if (index($File::Find::name, "\r") < 0 && -f $File::Find::name && !shouldIgnoreFile($File::Find::name)) {
        my $sourcefile;

        if (open($sourcefile, '+<', $File::Find::name)) {
            my $source = do { local $/; <$sourcefile> };
            if ($source =~ /$findFilesToProcess/ && isValidOrganization("$1")) {

                if ($extension eq '.pbxproj') {
                    $source =~ s/ORGANIZATIONNAME\s*=\s*.*;/ORGANIZATIONNAME = \"$companyName\";/;
                    $source =~ s/Created  :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Created  :*[^\n|\\n]/Created  :  $timestamp/g;
                    $source =~ s/Modified :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Modified :*[^\n|\\n]/Modified :/g;

                    my $count = 0;
                    while ($source =~ /$findFilesToProcess/ && isValidOrganization("$1")) {
                        $source =~ s/$findFilesToProcess/$copyrightNotice/;

                        if ((++$count) > 10) {
                            last;
                        }
                    }
                }
                else {
                    $source =~ s/Created  :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Created  :*[^\n|\\n]/Created  :  $timestamp/;
                    $source =~ s/Modified :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Modified :*[^\n|\\n]/Modified :/;
                    $source =~ s/$findFilesToProcess/$copyrightNotice/;
                }
                close($sourcefile);
                open($sourcefile, '>', $File::Find::name);
                print $sourcefile "$source";
            }
        }
    }
    system("SetFile -d \"$setFileDateFormat\" -m \"$setFileDateFormat\" \"$File::Find::name\" &> /dev/null");
}

#*****************************************************************************************
# script main line
#*****************************************************************************************
parseCommandLine();
prepare();

for my $path (@workPaths) {
    if (-d $path) {
        find(\&searchReplace, $path);
    }
    elsif (-f $path) {
        local $File::Find::name = $path;
        searchReplace();
    }
    else {
        print STDERR "*** Warning: '$path' is not a valid file or directory\n";
    }
}
