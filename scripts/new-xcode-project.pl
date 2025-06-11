#!/usr/bin/env perl
#*****************************************************************************************
# new-xcode-project.pl
#
# This script will generate a new Xcode project based a selected template project
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  23-Jun-2025  9:40pm
# Modified :  24-Jun-2025  3:14pm
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
my $HOME              = $ENV{"HOME"};
my $TEMPLATE_LOCATION = "$HOME/Developer/GeeDblA/ProjectTemplates/";

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
our $inFileLicense     = 0;

my @ignoreExtensions = (".png", ".tff", "jpg", ".jpeg", ".bmp", ".psd", ".mov", ".mp3", ".ogg", ".mp4", ".caf", ".xcuserstate");

my $SetFileDate = strftime("%D %I:%M %p",        localtime);
my $currentDate = strftime("%e-%b-%Y  %-I:%M%p", localtime);
my $currentYear = strftime("%Y",                 localtime);
$currentDate =~ s/AM/am/;
$currentDate =~ s/PM/pm/;

my $licenseText     = "";
my $copyrightNotice = "Copyright © $currentYear By $companyName All rights reserved.";

#=========================================================================================

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
    if (!searchPath("Xcode.app") || !searchPath("git") || !searchPath("gh")) {
        print STDERR "*** Error: Missing dependency\n";
        exit(1);
    }

    if (!-d "$TEMPLATE_LOCATION") {
        print STDERR "*** Error: No project templates found at $TEMPLATE_LOCATION\n";
        exit(1);
    }
}

#=========================================================================================

sub help {
    my $scriptName = basename($PROGRAM_NAME);

    print STDERR "$scriptName <template name> <project name> <location of project> [company]\n\n";
    print STDERR "-cs,  --closed \t\tCreated a project with a closed source license\n";
    print STDERR"-lif,  --inFileLicense \tAdd the source license to the files\n";
    print STDERR "-ng,  --no-github \tDo Not create a GitHub repository\n";
    print STDERR "-nx,  --no-xcode \tDo Not start Xcode after the project is generated\n";
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
                elsif ($option eq "--infilelicense" || $option eq "lif") {
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
                if ($nameIndex > 3) {
                    print STDERR "*** Error: Too much information\n";
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
    #  validate the project name
    #=====================================================================================
    if (length($projectName) < 3 || length($projectName) > 255) {
        print STDERR "*** Error: Bad project name\n";
        exit(1);
    }

    if ($projectName eq "." || $projectName eq "..") {
        print STDERR "*** Error: Bad project name\n";
        exit(1);
    }

    if ($projectName !~ /^[a-zA-Z][0-9a-zA-Z_-]+$/) {
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

    #=====================================================================================
    #  validate the chosen template exits
    #=====================================================================================
    if (!-d "$TEMPLATE_LOCATION/$projectTemplate") {
        print STDERR "*** Error: invalid template name\n";
        exit(1);
    }
}

#=========================================================================================

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
            $source =~ s/$projectTemplate/$projectName/g;

            if ($extension eq ".pbxproj") {
                $source =~ s/CompanyName/"$companyName"/;
            }
            $source =~ s/\x{43}reated  :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|\x{43}reated  :*[^\n|\\n]/\x{43}reated  :  $currentDate/;
            $source =~ s/\x{4D}odified :[\/\t 0-9A-Za-z-:]*[^\n|\\n]|\x{4D}odified :*[^\n|\\n]/\x{4D}odified :/;

            if ($inFileLicense == 1) {
                while ($source =~ /(.*)\x{43}opyright © [0-9]* By CompanyName All rights reserved\./) {
                    if ($extension eq ".pbxproj") {
                        if ($source =~ /\\n(.{0,3}\s*)\x{43}opyright © [0-9]* By CompanyName All rights reserved\./) {
                        	my $commentCharacters = $1;
   	                        my $wrapped = wrapText($licenseText, 90, $1);
							$wrapped =~ s{\\}{\\\\}g;
							$wrapped =~ s{'}{\\'}g;
							$wrapped =~ s{"}{\\"}g;
							$wrapped =~ s{\n}{\\n}g;
							$wrapped =~ s{“}{\\“}g;
	                        $source =~ s/\\n$commentCharacters\x{43}opyright © [0-9]* By CompanyName All rights reserved\./\n$wrapped/;
                        }
                    }
                    else {
                        my $wrapped = wrapText($licenseText, 90, $1);
                        $source =~ s/(.*)\x{43}opyright © [0-9]* By CompanyName All rights reserved\./$wrapped/;
                    }
                }
            }
            else {
                $source =~ s/\x{43}opyright © [0-9]* By CompanyName All rights reserved\./$copyrightNotice/;
            }

            open(my $sourcefile, ">$File::Find::name");
            print $sourcefile $source;
            close($sourcefile);
        }
        else {
            die "*** Error: unable to open $File::Find::name: $!\n";
        }
    }
}

sub renamer {
    my $filename = $File::Find::name;
    $filename =~ s/$projectTemplate/$projectName/g;
    if ($File::Find::name ne $filename) {
        rename($File::Find::name, $filename);
    }
}

sub dateFixer {
   if ($File::Find::name eq ".DS_Store") {
   		unlink($File::Find::name);
   		return;
   }

   `SetFile -d "$SetFileDate" -m "$SetFileDate" "$File::Find::name"`;
}

sub renameTemplate {
    find(
        {
            wanted  => \&renamer,
            bydepth => 1
        },
        "$projectLocation/$projectName"
    );
    find(
        {
            wanted  => \&renamer,
            bydepth => 1
        },
        "$projectLocation/$projectName"
    );
    find(
        {
            wanted  => \&searchReplace,
            bydepth => 1
        },
        "$projectLocation/$projectName"
    );

        find(
        {
            wanted  => \&dateFixer,
            bydepth => 1
        },
        "$projectLocation/$projectName"
    );

}

sub setupProjectStructure {
    if (dircopy("$TEMPLATE_LOCATION/$projectTemplate", "$projectLocation/$projectName") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }
    if (unlink("$projectLocation/$projectName/.ProjectDescription") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }
    if (dircopy("$TEMPLATE_LOCATION/_Files/Assets.xcassets", "$projectLocation/$projectName/$projectTemplate/Assets.xcassets") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }
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
        $licenseFilePath = "$TEMPLATE_LOCATION/_Files/LICENSE.markdown-Closed-";
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

        my $fh;
        if (open($fh, '<', $licenseFilePath) == 0) {
            print STDERR "*** Error: disk errpr : $!\n";
            exit(1);
        }

        local $/;
        $licenseText = <$fh>;
        close($fh);

        my $p = index($licenseText, "\x{43}opyright ©");
        $licenseText = substr($licenseText, $p);
        $licenseText =~ s/\x{43}opyright © .*\n/\x{43}opyright © $currentYear By $companyName All rights reserved.\n/;
    }

    if (copy($IDETemplateMacrosFile, "$projectLocation/$projectName/$projectTemplate.xcodeproj/xcuserdata/IDETemplateMacros.plist") == 0) {
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

    if (system("git checkout -b develop &> /dev/null") == 0) {
        print STDERR "*** Error: disk errpr : $!\n";
        exit(1);
    }

    if ($setupGithub) {
        if (dircopy("$TEMPLATE_LOCATION/_Files/.github", "$projectLocation/$projectName/.github") == 0) {
            print STDERR "*** Error: disk errpr : $!\n";
            exit(1);
        }
        if (copy("$TEMPLATE_LOCATION/_Files/ci.sh", "$projectLocation/$projectName/BuildEnv") == 0) {
            print STDERR "*** Error: disk errpr : $!\n";
            exit(1);
        }

    `cd "$projectLocation";git remote add origin git\@github.com:Gary-Ash/$projectName.git;git checkout -b develop &> /dev/null`;
    `cd "$projectLocation";gh repo create "$projectName" --private --source=. --remote=upstream`;
    `rm -rf ~/,local`;
    }
}

#=========================================================================================

sub wrapText {
    my ($text, $width, $prefix) = @_;

    local $Text::Wrap::columns = $width - length($prefix);

    my $initial_tab    = $prefix;
    my $subsequent_tab = $prefix;

    my $wrapped_text = wrap($initial_tab, $subsequent_tab, $text);

    return $wrapped_text;
}

#=========================================================================================

#*****************************************************************************************
# script main line
#*****************************************************************************************
checkForRequiredTools();
parseCommandLine();
setupProjectStructure();
renameTemplate();

if ($openXcode) {
    system("open -a Xcode $projectLocation/$projectName.xcodeproj &");
}
