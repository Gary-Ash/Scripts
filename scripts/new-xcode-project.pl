#!/usr/bin/env perl
#*****************************************************************************************
# new-xcode-project.pl
#
# This script build new Xcode project based on a template project
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Jun-2025  3:54pm
# Modified :
#
# Copyright © 2024-2025 By Gary Ash All rights reserved.
#*****************************************************************************************

#-----------------------------------------------------------------------------------------
# libraries
#-----------------------------------------------------------------------------------------
use strict;
use warnings;
use English;
use File::Find;
use File::Basename;
use Cwd qw(cwd);
use Cwd qw(abs_path);

use File::Path qw(make_path);
use File::Copy;
use POSIX qw(strftime);

use Text::Wrap;

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

my %searchReplaceOptions = (
    wanted      => \&searchReplace,
    no_chdir    => 0,
    bydepth     => 0,
    follow_skip => 2,
);
my @ignoreExtensions = ("png", "tff", "jpg", "jpeg", "bmp", "psd", "mov", "mp3", "ogg", "mp4", "caf", "pbxproj", "xcuserstate");

my $SetFileDate = strftime("%D %I:%M %p",        localtime);
my $currentDate = strftime("%e-%b-%Y  %-I:%M%p", localtime);
my $currentYear = strftime("%Y",                 localtime);
$currentDate =~ s/AM/am/;
$currentDate =~ s/PM/pm/;

#-----------------------------------------------------------------------------------------
# parse command line arguments
#-----------------------------------------------------------------------------------------
my $licenseText            = "";
my $noGitHub               = 0;
my $noXcode                = 0;
my $closedSource           = 0;
my $inFileLicense          = 0;
my $numberArgumentsOptions = $#ARGV + 1;

for (my $index = 0; $index < $numberArgumentsOptions; ++$index) {
    my $dashCheck = substr($ARGV[$index], 0, 1);

    if ($dashCheck eq "-") {
        my $option = lc($ARGV[$index]);
        if ($option eq "--no-github" || $option eq "-ng") {
            $noGitHub = 1;
            splice(@ARGV, $index, 1);
            --$numberArgumentsOptions;
            --$index;
        }
        elsif ($option eq "--no-xcode" || $option eq "-nx") {
            $noXcode = 1;
            splice(@ARGV, $index, 1);
            --$numberArgumentsOptions;
            --$index;
        }
        elsif ($option eq "--closed" || $option eq "-cs") {
            $closedSource = 1;
            splice(@ARGV, $index, 1);
            --$numberArgumentsOptions;
            --$index;
        }
        elsif ($option eq "--infilelicense" || $option eq "-lif") {
            $inFileLicense = 1;
            splice(@ARGV, $index, 1);
            --$numberArgumentsOptions;
            --$index;
        }
        else {
            print "Unrecognized option given: $ARGV[$index]\n";
            exit(2);
        }
    }

}

my $numberArguments = $#ARGV + 1;

if ($numberArguments != 3 && $numberArguments != 4) {
    print "*** Error: $BASE_PROGRAM_NAME <template name> <project name> <location of project> [company]\n\n";
    print "-cs,  --closed:    Created a project with a closed source license\n";
    print "-lif, --inFileLicense:    Add the source license to the files\n";
    print "-ng,  --no-github: Do Not create a GitHub repository\n";
    print "-nx,  --no-xcode:  Do Not start Xcode after the project is generated\n";
    exit(1);
}

my $templateName    = $ARGV[0];
my $projectName     = $ARGV[1];
my $projectLocation = abs_path($ARGV[2]);
my $company         = "";

if ($numberArguments == 4) {
    $company = $ARGV[3];
}
else {
    $company = "Gary Ash";
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

if (!-e "$projectDirectory") {
    make_path($projectDirectory);
}

if ($inFileLicense == 1) {
    if ($closedSource == 1) {
        open(my $fh, '<', "$TEMPLATE_LOCATION/_github/Closed-LICENSE.markdown") or die "cannot open file Closed-LICENSE";
        {
            local $/;
            $licenseText = <$fh>;
        }
        close($fh);
    }
    else {
        open(my $fh, '<', "$TEMPLATE_LOCATION/_github/LICENSE.markdown") or die "cannot open file LICENSE";
        {
            local $/;
            $licenseText = <$fh>;
        }
        close($fh);
        my $p = index($licenseText, "\x{43}opyright ©");
        $licenseText = substr($licenseText, $p);
    }
    $licenseText =~ s/\x{43}opyright © .*\n/\x{43}opyright © $currentYear By $company All rights reserved.\n/;
}

`cp -rf "$TEMPLATE_LOCATION/_BuildEnv" "$projectDirectory"`;
`cp -rf "$TEMPLATE_LOCATION/_github" "$projectDirectory"`;
`mv $projectDirectory/_BuildEnv $projectDirectory/BuildEnv`;
`rm -rf $projectDirectory/BuildEnv/Assets.xcassets`;
`mv $projectDirectory/_github $projectDirectory/.github`;
`touch $projectDirectory/README.markdown`;

find(\%processFilesOptions,  $locationOfSelectedTemplate);
find(\%searchReplaceOptions, $projectDirectory);

if ($closedSource == 0) {
    `rm -rf $projectDirectory/.github/Closed-LICENSE.markdown`;
    `mv $projectDirectory/.github/LICENSE.markdown $projectDirectory/`;

    if ($inFileLicense == 1) {
        `mv $projectDirectory/BuildEnv/IDETemplateMacros-Open.plist $projectDirectory/$projectNameUnderscore\.xcodeproj/xcuserdata/$ENV{"USER"}.xcuserdatad/IDETemplateMacros.plist`;
    }
}
else {
    `rm -rf $projectDirectory/.github/LICENSE.markdown `;
    `mv $projectDirectory/.github/Closed-LICENSE.markdown $projectDirectory/LICENSE.markdown`;

    if ($inFileLicense == 1) {
        `mv $projectDirectory/BuildEnv/IDETemplateMacros-Closed.plist $projectDirectory/$projectNameUnderscore\.xcodeproj/xcuserdata/$ENV{"USER"}.xcuserdatad/IDETemplateMacros.plist`;
    }
}

`rm -rf $projectDirectory/BuildEnv/IDETemplateMacros-*`;

`mv $projectDirectory/BuildEnv/.gitignore $projectDirectory/`;
`mv $projectDirectory/BuildEnv/.swiftlint.yml $projectDirectory/`;

`cp -rf "$TEMPLATE_LOCATION/_BuildEnv/Assets.xcassets" "$projectDirectory/$projectNameUnderscore/Resources/"`;

`git init "$projectDirectory" &> /dev/null`;
if ($noGitHub == 0) {
    `cd "$projectDirectory";git remote add origin git\@github.com:Gary-Ash/$projectName.git;git checkout -b develop &> /dev/null`;
    `cd "$projectDirectory";gh repo create "$projectName" --private --source=. --remote=upstream`;
    `rm -rf ~/,local`;
}

if ($noXcode == 0) {
    system("open -a Xcode $projectDirectory/$projectName.xcodeproj &");
}

#*****************************************************************************************
#  word wrap a string
#*****************************************************************************************
sub wrapText {
    my ($text, $width, $prefix) = @_;

    # Set the desired wrap width
    local $Text::Wrap::columns = $width - length($prefix);

    # Set the prefix for the first and subsequent lines
    my $initial_tab    = $prefix;
    my $subsequent_tab = $prefix;

    # Wrap the text with the specified settings
    my $wrapped_text = wrap($initial_tab, $subsequent_tab, $text) . "\n";

    return $wrapped_text;
}

#*****************************************************************************************
# process a source file
#*****************************************************************************************
sub processFiles {
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
    }
}

#*****************************************************************************************
# process a source file
#*****************************************************************************************
sub searchReplace {
    if (-f "$File::Find::name") {
        return if index($File::Find::name, '\r') > 0;
        return if $File::Find::name eq ".DS_Store";

        my $extension;
        (undef, undef, $extension) = fileparse($File::Find::name, qr/\.[^.]*$/);

        for my $ext (@ignoreExtensions) {
            return if $ext eq $extension;
        }
        if (open(my $sourcefile, "<$File::Find::name")) {
            my $source = do { local $/; <$sourcefile> };
            close($sourcefile);

            $source =~ s/$TEMPLATE_LOCATION/$projectLocation/g;
            $source =~ s/$locationOfSelectedTemplate/$projectDirectory/g;
            $source =~ s/$templateName/$projectName/g;
            $source =~ s/$templateNameUnderscore/$projectNameUnderscore/g;

            $source =~ s/\x{43}reated  :.*\n/\x{43}reated  :  $currentDate\n/g;
            $source =~ s/\x{4D}odified :.*\n/\x{4D}odified :\n/g;

            if ($inFileLicense == 1) {
                if ($source =~ /(.*)\x{43}opyright © .*\n/) {
                    my $wrapped = wrapText($licenseText, 90, $1);
                    $source =~ s/(.*)\x{43}opyright © .*\n/$wrapped/;
                }
            }
            else {
                $source =~ s/\x{43}opyright © .*\n/\x{43}opyright © $currentYear By $company All rights reserved.\n/;
            }
            open(my $sourcefile, ">$File::Find::name");
            print $sourcefile $source;
            close($sourcefile);
        }
        else {
            die "*** Error: unable to open $File::Find::name: $!\n";
        }

        `SetFile -d "$SetFileDate" -m "$SetFileDate" "$File::Find::name"`;
    }
}

