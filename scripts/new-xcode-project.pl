#!/usr/bin/env perl
#*****************************************************************************************
# new-xcode-project.pl
#
# This script will generate a clean new Xcode project based one of template projects
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   4-Aug-2025  4:29pm
# Modified :   5-Sep-2025  4:54pm
#
# Copyright © 2025 By Gary Ash All rights reserved.
#*****************************************************************************************

#-----------------------------------------------------------------------------------------
# libraries
#-----------------------------------------------------------------------------------------
use strict;
use warnings;
use English;

use Text::Wrap;

use File::Copy;
use File::Find;
use File::Spec;
use File::Basename;
use File::Path            qw(make_path);
use File::Copy::Recursive qw(dircopy);

use POSIX qw(strftime);

use Cwd qw(cwd abs_path);

#-----------------------------------------------------------------------------------------
# constants
#-----------------------------------------------------------------------------------------
our $HOME              = $ENV{"HOME"};
our $TEMPLATE_LOCATION = "$HOME/Developer/GeeDblA/ProjectTemplates/";

#-----------------------------------------------------------------------------------------
# regular expressions
#-----------------------------------------------------------------------------------------

# this will match copyright declarations an isolate the copyright holder into $1
our $findFilesToProcess = qr/Copyright\s*(?:.*)\s*(?:\d{4}\s*-\s*\d{4}|\d{4}) By (.*) All rights reserved\./;

# this maches the copyright declaration found in non Xcode project files
# $1 contains the comment leader of the line containing the copyright
our $nonProjectFileCopyright = qr/(.*)Copyright\s*(?:.*)\s*(\d{4}\s*-\s*\d{4}|\d{4})\s*By\s*(.*) All rights reserved\./;

# this maches the copyright declaration found in Xcode project files
our $projectFileCopyright = qr/(?:\\n)(.{0,3}\s*)Copyright\s*(?:.*)\s*(?:\d{4}\s*-\s*\d{4}|\d{4})\s*By\s*CompanyName All rights reserved\./;

#-----------------------------------------------------------------------------------------
#  global variables
#-----------------------------------------------------------------------------------------

# command line arguments and optional switches
our $projectTemplate;
our $projectLocation;
our $projectName;
our $companyName = "Gary Ash";

our $setupGithub       = 1;
our $openXcode         = 1;
our $openSourceProject = 1;
our $inFileLicense     = 1;

# variables that hold the template substitution values
our @companies;
our @templates;
our $timestamp;
our $licenseText;
our $copyrightNotice;
our $setFileDateFormat;

#-----------------------------------------------------------------------------------------
# utility subroutines
#-----------------------------------------------------------------------------------------

sub wrapText {
    my ($text, $width, $prefix) = @_;

    local $Text::Wrap::columns = $width - length($prefix);

    my $initial_tab    = $prefix;
    my $subsequent_tab = $prefix;
    my $wrapped_text   = wrap($initial_tab, $subsequent_tab, $text);

    return $wrapped_text;
}

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
    my @ignoreExtensions = (".png", ".tff", "jpg", ".jpeg", ".bmp", ".psd", ".mov", ".mp3", ".ogg", ".mp4", ".caf", ".scpt", ".xcuserstate");

    (undef, undef, my $extension) = fileparse($filename, qr/\.[^.]*$/);

    for my $ext (@ignoreExtensions) {
        if ($ext eq $extension) {
            return 1;
        }
    }
    return 0;
}

#-----------------------------------------------------------------------------------------
# startup subroutines
#-----------------------------------------------------------------------------------------

sub searchPath {
    my ($file) = @_;

    my @dirs = split(/:/, $ENV{PATH});
    push @dirs, "/Applications/";

    for my $dir (@dirs) {
        my $filepath = File::Spec->catfile($dir, $file);
        if (-f $filepath && -x $filepath || (substr($filepath, -4) eq ".app" && -d $filepath)) {
            return $filepath;
        }
    }
    return undef;
}

sub checkForRequiredTools {
    if (-d "$TEMPLATE_LOCATION") {
        find(
            sub {
                if (-d $File::Find::name && $_ =~ /^[A-Za-z].*/) {
                    my $depth = $File::Find::dir =~ tr[/][];
                    if ($depth < 6) {
                        push @templates, $_;
                    }
                }
            },
            "$TEMPLATE_LOCATION"
        );
    }
    else {
        print STDERR "*** Error: No project templates found at $TEMPLATE_LOCATION\n";
        exit(1);
    }

    if (!searchPath("Xcode.app") || !searchPath("git") || !searchPath("gh")) {
        print STDERR "*** Error: Missing dependency\n";
        exit(1);
    }
}

#-----------------------------------------------------------------------------------------
# parse the command line
#-----------------------------------------------------------------------------------------

sub help {
    my $scriptName = basename($PROGRAM_NAME);

    print STDERR "$scriptName <template name> <project name> <location of project> [company]\n\n";
    print STDERR "-cs,\t---closed        \tCreated a project with a closed source license\n";
    print STDERR "-lif,\t--inFileLicense \tAdd the source license to the files\n";
    print STDERR "-ng,\t--no-github      \tDo Not create a GitHub repository\n";
    print STDERR "-nx,\t--no-xcode       \tDo Not start Xcode after the project is generated\n";
    exit(1);
}

sub parseCommandLine {
    my $nameIndex = 0;
    my @names     = (\$projectTemplate, \$projectName, \$projectLocation, \$companyName);

    if (scalar($#ARGV) > 1) {
        for (my $index = 0; $index < scalar($#ARGV) + 1; ++$index) {
            my $dashCheck = substr($ARGV[$index], 0, 1);
            if ($dashCheck eq "-") {
                #=========================================================================
                #  process a probable option switch
                #=========================================================================
                my $option = lc($ARGV[$index]);
                if ($option eq "--no-github" || $option eq "-ng") {
                    $setupGithub = 0;
                }
                elsif ($option eq "--no-xcode" || $option eq "-nx") {
                    $openXcode = 0;
                }
                elsif ($option eq "--closed" || $option eq "-cs") {
                    $openSourceProject = 0;
                }
                elsif ($option eq "--infilelicense" || $option eq "-lif") {
                    $inFileLicense = 1;
                }
                else {
                    print STDERR "*** Error: Unknown option: $ARGV[$index]\n";
                    help();
                }
            }
            else {
                #=========================================================================
                #  process a name or location argument
                #=========================================================================
                if ($nameIndex > scalar($#names)) {
                    print STDERR "*** Error: Too much information -- $ARGV[$index]\n";
                    help();
                }
                else {
                    ${ $names[$nameIndex] } = $ARGV[$index];
                    ++$nameIndex;
                }
            }
        }
    }
    else {
        print STDERR "*** Error: Not enough information given.\n";
        help();
    }

    #=====================================================================================
    #  validate the chosen template exits
    #=====================================================================================
    if (!-d "$TEMPLATE_LOCATION/$projectTemplate") {
        print STDERR "*** Error: invalid template name\n";
        exit(1);
    }

    if (!-d "$TEMPLATE_LOCATION/$projectTemplate") {
        print STDERR "*** Error: invalid template name\n";
        exit(1);
    }

    for my $item (@templates) {
        if (lc($projectTemplate) eq lc($item)) {
            $projectTemplate = $item;
            last;
        }
    }
    #=====================================================================================
    #  validate the project name
    #=====================================================================================
    if (length($projectName) < 3 || length($projectName) > 255) {
        print STDERR "*** Error: Bad project name\n";
        exit(1);
    }
    if ($projectName eq "." || $projectName eq ".." || $projectName !~ /^[a-zA-Z][0-9a-zA-Z_-]+$/) {
        print STDERR "*** Error: Bad project name\n";
        exit(1);
    }

    #=====================================================================================
    #  validate the project location
    #=====================================================================================
    if ($projectLocation eq ".") {
        $projectLocation = cwd;
    }
    else {
        $projectLocation = abs_path($projectLocation);
    }

    if (!-d "$projectLocation") {
        print STDERR "*** Error: invalid project location\n";
        exit(1);
    }

    if (-d "$projectLocation/$projectName") {
        print STDERR "*** Error: project or directory already exists\n";
        exit(1);
    }
}

#-----------------------------------------------------------------------------------------
# project building subroutines
#-----------------------------------------------------------------------------------------

sub prepareTemplateVariables {
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

    if ($inFileLicense == 1) {
        #=================================================================================
        # the user wants "in the source code license statement"
        # load the text of selected license (open or closed) to allow for faster processing
        #=================================================================================
        my $licenseFilePath = "$TEMPLATE_LOCATION/_Files/LICENSE-Open.markdown";
        if ($openSourceProject == 0) {
            $licenseFilePath = "$TEMPLATE_LOCATION/_Files/LICENSE-Closed.markdown";
        }

        my $licenseFH;
        if (open($licenseFH, '+<', $licenseFilePath) == 0) {
            print STDERR "*** Error: Unable to read the  : $!\n";
            exit(1);
        }

        local $/;
        $licenseText = <$licenseFH>;
        utf8::upgrade($licenseText);

        my $p = index($licenseText, "Copyright");
        $licenseText = substr($licenseText, $p);
        $licenseText =~ s/$findFilesToProcess/$copyrightNotice/;
        $licenseText =~ s/^\s+|\s+$//g;
        seek($licenseFH, 0, 0);
        print $licenseFH "$licenseText";

        close($licenseFH);

    }
}

sub createProjectFileStructure {
    find(
        sub {
            if ($File::Find::name =~ /.*\/\.DS_Store|.*\/\.ProjectDescription/) { return; }

            my $dir = $File::Find::dir;
            $dir =~ s/$TEMPLATE_LOCATION/$projectLocation/g;
            $dir =~ s/$projectTemplate/$projectName/g;
            make_path($dir);

            if (-f $File::Find::name) {
                my $file = $File::Find::name;
                $file =~ s/$TEMPLATE_LOCATION/$projectLocation/g;
                $file =~ s/$projectTemplate/$projectName/g;

                if (copy($File::Find::name, $file) == 0) {
                    print STDERR "*** Error: Unable to copy file - $!\n";
                    exit(1);
                }
            }
        },
        "$TEMPLATE_LOCATION/$projectTemplate"
    );
	system("unzip -q $TEMPLATE_LOCATION/_Files/Assets.xcassets.zip -d $projectLocation/$projectName/$projectName/Resources/ -x '__MACOSX/*'");

    if (dircopy("$TEMPLATE_LOCATION/_Files/BuildEnv", "$projectLocation/$projectName/BuildEnv") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }
    if (copy("$TEMPLATE_LOCATION/_Files/.swiftlint.yml", "$projectLocation/$projectName/") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }

    my $licenseFilePath = "$TEMPLATE_LOCATION/_Files/LICENSE-Open.markdown";
    if ($openSourceProject == 0) {
        $licenseFilePath = "$TEMPLATE_LOCATION/_Files/LICENSE-Closed.markdown";
    }
    if (copy($licenseFilePath, "$projectLocation/$projectName/LICENSE.markdown") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }

    my $IDETemplateMacrosFile = "$TEMPLATE_LOCATION/_Files/IDETemplateMacros.plist";
    if ($inFileLicense) {
        if ($openSourceProject) {
            $IDETemplateMacrosFile = "$TEMPLATE_LOCATION/_Files/IDETemplateMacros-Open.plist";
        }
        else {
            $IDETemplateMacrosFile = "$TEMPLATE_LOCATION/_Files/IDETemplateMacros-Closed.plist";
        }
    }
    if (copy($IDETemplateMacrosFile, "$projectLocation/$projectName/$projectName.xcodeproj/xcuserdata/IDETemplateMacros.plist") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }

    if (copy("$TEMPLATE_LOCATION/_Files/.xcodesamplecode.plist", "$projectLocation/$projectName/$projectName.xcodeproj/xcuserdata/") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }

    if (make_path("$projectLocation/$projectName/Documentation") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }

    my $readmefh;
    if (open($readmefh, '>', "$projectLocation/$projectName/README.markdown") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }
    print $readmefh "\n";
    close($readmefh);

    if (system("git init \"$projectLocation/$projectName/\" &> /dev/null") != 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);

    }

    if (system("cd \"$projectLocation/$projectName/\" && git checkout -b develop &> /dev/null") != 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }
}

sub searchReplace {
    if ($File::Find::name =~ /.*\/\.DS_Store/) {
        unlink($File::Find::name);
        return;
    }

    (undef, undef, my $extension) = fileparse($File::Find::name, qr/\.[^.]*$/);
    if (index($File::Find::name, '\r') < 0 && -f $File::Find::name && !shouldIgnoreFile($File::Find::name)) {
        my $sourcefile;

        if (open($sourcefile, '+<', "$File::Find::name")) {
            my $source = do { local $/; <$sourcefile> };
            if ($source =~ /$findFilesToProcess/ && isValidOrganization("$1")) {
                $source =~ s/$projectTemplate/$projectName/g;

                if ($extension eq '.pbxproj') {
                    $source =~ s/ORGANIZATIONNAME\s*=\s*.*;/ORGANIZATIONNAME = \"$companyName\";/;
                    $source =~ s/Created  :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Created  :*[^\n|\\n]/Created  :  $timestamp/g;
                    $source =~ s/Modified :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Modified :*[^\n|\\n]/Modified :/g;

                    our $count = 0;
                    while ($source =~ /$projectFileCopyright/) {
                        my $commentLeader = $1;
                        if ($inFileLicense) {
                            my $wrapped = wrapText($licenseText, 90, $commentLeader);
                            $wrapped =~ s{\\}{\\\\}g;
                            $wrapped =~ s{'}{\\'}g;
                            $wrapped =~ s{"}{\\"}g;
                            $wrapped =~ s{\n}{\\n}g;
                            $wrapped =~ s{“}{\\“}g;
                            $wrapped = "\\n" . $wrapped;
                            $source =~ s/$projectFileCopyright/$wrapped/;
                        }
                        else {
                            $source =~ s/$findFilesToProcess/$copyrightNotice/;
                        }
                        if ((++$count) > 10) {
                            last;
                        }
                    }
                }
                else {
                    $source =~ s/Created  :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Created  :*[^\n|\\n]/Created  :  $timestamp/;
                    $source =~ s/Modified :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|Modified :*[^\n|\\n]/Modified :/;

                    if ($inFileLicense) {
                        if ($source =~ /$nonProjectFileCopyright/) {
                            my $wrapped = wrapText($licenseText, 90, $1);
                            $source =~ s/$nonProjectFileCopyright/$wrapped/;
                        }
                    }
                    else {
                        $source =~ s/$findFilesToProcess/$copyrightNotice/;
                    }
                }

                close($sourcefile);
                open($sourcefile, '>', "$File::Find::name");
                print $sourcefile "$source";
            }
            close($sourcefile);
        }
    }
    system("SetFile -d \"$setFileDateFormat\" -m \"$setFileDateFormat\" \"$File::Find::name\"");
}

#*****************************************************************************************
# script main line
#*****************************************************************************************
checkForRequiredTools();
parseCommandLine();
prepareTemplateVariables();
createProjectFileStructure();

find(\&searchReplace, "$projectLocation/$projectName");
if ($openXcode) {
    system("open -a Xcode $projectLocation/$projectName/$projectName.xcodeproj &");
}

if ($setupGithub) {
    system("cd \"$projectLocation/$projectName/\" && gh repo create \"$projectName\" --private --source=. --remote=upstream");
    system("rm -rf ~/,local");
}
