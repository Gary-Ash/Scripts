#!/usr/bin/env perl
#*****************************************************************************************
# new-xcode-project.pl
#
# This script build new Xcode project based on a template project
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  16-Aug-2023  6:24pm
# Modified :   8-Mar-2024  7:17pm
#
# Copyright © 2023-2024 By Gee Dbl A All rights reserved.
#*****************************************************************************************

#-----------------------------------------------------------------------------------------
# libraries
#-----------------------------------------------------------------------------------------
use strict;
use warnings;
use English;
use File::Find;
use File::Basename;
use Cwd        qw(cwd);
use File::Path qw(make_path);
use File::Copy;
use POSIX qw(strftime);
use File::Basename;
#-----------------------------------------------------------------------------------------
# constants
#-----------------------------------------------------------------------------------------
my $HOME              = $ENV{"HOME"};
my $TEMPLATE_LOCATION = "$HOME/Developer/GeeDblA/ProjectTemplates/";
my $BASE_PROGRAM_NAME = basename($PROGRAM_NAME);

#-----------------------------------------------------------------------------------------
# variables
#-----------------------------------------------------------------------------------------
my %processFilesOptions = (
    wanted      => \&processFiles,
    no_chdir    => 0,
    bydepth     => 0,
    follow_skip => 2,
);

my $SetFileDate = strftime("%D %I:%M %p",        localtime);
my $currentDate = strftime("%e-%b-%Y  %-I:%M%p", localtime);
my $currentYear = strftime("%Y",                 localtime);
$currentDate =~ s/AM/am/;
$currentDate =~ s/PM/pm/;

#-----------------------------------------------------------------------------------------
# parse command line arguments
#-----------------------------------------------------------------------------------------
my $noGitHub = 0;
my $numberArgumentsOptions = $#ARGV + 1;
for (my $index = 0; $index < $numberArgumentsOptions; ++$index) {
        if ($ARGV[$index] eq "--no-github"|| $ARGV[$index] eq "-n") {
        $noGitHub = 1;
        splice(@ARGV, $index, 1);
        last;
    }
}

my $numberArguments = $#ARGV + 1;

if ($numberArguments != 3 && $numberArguments != 4) {
    print "*** Error: $BASE_PROGRAM_NAME <template name> <project name> <location of project> <company>\n";
    exit(1);
}

my $templateName    = $ARGV[0];
my $projectName     = $ARGV[1];
my $projectLocation = $ARGV[2];
my $company         = "";

if ($numberArguments == 4) {
    $company = $ARGV[3];
}
else {
    $company = "Gee Dbl A";
}

if (length($projectName) < 3 || length($projectName) > 255) {
    print STDERR "*** Error: Bad project name\n";
    exit(1);
}

if ($projectName eq "." || $projectName eq "..") {
    print STDERR "*** Error: Bad project name\n";
    exit(1);
}

if ($projectName !~ /^[0-9a-zA-Z_-]+$/) {
    print STDERR "*** Error: Bad project name\n";
    exit(1);
}

my $locationOfSelectedTemplate = $TEMPLATE_LOCATION . $templateName;
if (!-d "$locationOfSelectedTemplate") {
    print STDERR "*** Error: No template by the name $templateName found.\n";
    exit(1);
}

my $currentDir = cwd;
chdir($locationOfSelectedTemplate) or die "$!";
$locationOfSelectedTemplate = cwd;
$templateName               = substr($locationOfSelectedTemplate, rindex($locationOfSelectedTemplate, "/") + 1);
chdir($currentDir) or die "$!";

if ($projectLocation eq ".") {
    $projectLocation = cwd;
}

if (-e "$projectLocation" && -f "$projectLocation") {
    print "*** Error: $templateName is file not a directory.\n";
    exit(1);
}

if (substr($projectLocation, -1) ne "/") {
    $projectLocation .= "/";
}

my $projectDirectory = $projectLocation . $projectName;
if (-e "$projectDirectory" && -f "$projectDirectory") {
    print "*** Error: $projectDirectory is file not a directory.\n";
    exit(1);
}

my $projectNameUnderscore = $projectName;
$projectNameUnderscore =~ s/-/_/g;

my $templateNameUnderscore = $templateName;
$templateNameUnderscore =~ s/-/_/g;

find(\%processFilesOptions, $locationOfSelectedTemplate);

`cp -rf "$TEMPLATE_LOCATION/_BuildEnv" "$projectDirectory"`;
`cp -rf "$TEMPLATE_LOCATION/_github" "$projectDirectory"`;
`mv $projectDirectory/_BuildEnv $projectDirectory/BuildEnv`;
`mv $projectDirectory/_github $projectDirectory/.github`;

`git init "$projectDirectory" &> /dev/null`;
if ($noGitHub == 0) {
    `cd "$projectDirectory";git remote add origin https://github.com/Gary-Ash/$projectName.git;git checkout -b develop &> /dev/null`;
    `cd "$projectDirectory";gh repo create "$projectName" --private --source=. --remote=upstream`;
    `rm -rf ~/,local`;
}

#*****************************************************************************************
# process a source file
#*****************************************************************************************
sub processFiles {
    my @ignoreExtensions = ("png", "tff", "jpg", "jpeg", "bmp", "psd", "mov", "mp3", "ogg", "mp4", "caf", "xcuserstate");

    return if $_ eq "." or $_ eq ".." or $_ eq ".DS_Store" or $_ eq ".ProjectDescription";

    my $dir = $File::Find::dir;
    $dir =~ s/$TEMPLATE_LOCATION/$projectLocation/g;
    $dir =~ s/$templateName/$projectName/g;
    $dir =~ s/$templateNameUnderscore/$projectNameUnderscore/g;

    if (!-e "$dir") {
        make_path($dir);
    }

    if (-f "$File::Find::name") {
        my $extension;
        my $filename = basename($File::Find::name);
        $filename =~ s/$templateName/$projectName/g;
        $filename =~ s/$templateNameUnderscore/$projectNameUnderscore/g;

        my $destPath = "$dir/$filename";
        copy($File::Find::name, $destPath) or die "Copy failed: $!";
        (undef, undef, $extension) = fileparse($destPath, qr/\.[^.]*$/);

        return if index($File::Find::name, '\r') > 0;
        return if $File::Find::name eq ".DS_Store";

        $extension = lc($extension);
        for my $ext (@ignoreExtensions) {
            return if $ext eq $extension;
        }
        if ($destPath !~ /.git\/*/) {
            if (open(my $sourcefile, "<$destPath")) {
                my $source = do { local $/; <$sourcefile> };
                close($sourcefile);

                $source =~ s/$TEMPLATE_LOCATION/$projectLocation/g;
                $source =~ s/$locationOfSelectedTemplate/$projectDirectory/g;
                $source =~ s/$templateName/$projectName/g;
                $source =~ s/$templateNameUnderscore/$projectNameUnderscore/g;

                $source =~ s/\x{43}reated  :.*\n/\x{43}reated  :  $currentDate\n/g;
                $source =~ s/\x{4D}odified :.*\n/\x{4D}odified :\n/g;
                $source =~ s/\x{43}opyright © [0-9\-]* .*\n/\x{43}opyright © $currentYear By $company All rights reserved.\n/g;

                open(my $sourcefile, ">$destPath");
                print $sourcefile $source;
                close($sourcefile);
            }
            else {
                die "*** Error: unable to open $destPath: $!\n";
            }
        }
        `SetFile -d "$SetFileDate" -m "$SetFileDate" "$destPath"`;
    }
}

