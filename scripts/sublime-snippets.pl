#!/usr/bin/env perl
#*****************************************************************************************
# sublime-snippets.pl
#
# Sublime Text snippet utility
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  14-Oct-2024 10:43pm
# Modified :
#
# Copyright © 2024 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# libraries used
#*****************************************************************************************
use strict;
use warnings;
use Archive::Zip;
use File::Find;
use File::Copy;
use File::Basename;
use File::Path qw(make_path rmtree);

#*****************************************************************************************
# globals
#*****************************************************************************************
my $HOME                      = $ENV{"HOME"};
my $TEMP                      = "$HOME/Downloads/snippets/";
my $snippetFolder             = "$HOME/Library/Application\ Support/Sublime\ Text/Packages/User/Snippets/";
my $installedPackagesFolder   = "$HOME/Library/Application Support/Sublime Text/Installed Packages";
my $applicationPackagesFolder = "/Applications/Sublime Text.app/Contents/MacOS/Packages";
my @packagesFolders           = ($applicationPackagesFolder, $installedPackagesFolder);
my $justDeleteSnippets        = 0;

foreach my $option (@ARGV) {
    if ($option =~ /-d|--delete/) {
        $justDeleteSnippets = 1;
        shift @ARGV;
    }
}

#*****************************************************************************************
# main line
#*****************************************************************************************
rmtree($TEMP);
for my $packageFolder (@packagesFolders) {
    for my $packagePath (glob("\"$packageFolder\"/*.sublime-package")) {
        my $packageFileName = basename($packagePath, ".sublime-package");
        if (!-e "${TEMP}${packageFileName}") {
            make_path("${TEMP}${packageFileName}") or die "Unable create directory - ${TEMP}${packageFileName}: $!\n";
            my $extractPackage = Archive::Zip->new();
            $extractPackage->read($packagePath);
            $extractPackage->extractTree(undef, "${TEMP}${packageFileName}");
            find(\&move_snippets, "${TEMP}${packageFileName}");
            undef $extractPackage;

            unlink($packagePath) or die "The delete operation failed: $packagePath - $!";

            my $zipPackage = Archive::Zip->new();
            $zipPackage->addTree("${TEMP}${packageFileName}", undef);
            $zipPackage->writeToFileNamed($packagePath);
            undef $zipPackage;
        }
    }
}
rmtree($TEMP);

#*****************************************************************************************
# the subroutine will move any snippets it finds to te Better Snippets folder in the
# user's preferences folder tree
#*****************************************************************************************
sub move_snippets() {
    eval {
        return if ($File::Find::name !~ /.sublime-snippet/);

        my $dest = $File::Find::name;
        $dest =~ s/$TEMP//;
        $dest =~ s/[s|S]nippets\///;
        $dest = "$snippetFolder$dest";

        if (!-e "$dest" && $justDeleteSnippets == 0) {
            my $dir = dirname($dest);
            if (!-e "$dir") {
                make_path($dir);
            }
            move($File::Find::name, $dest);
        }
        else {
            unlink($File::Find::name) or die "The delete operation failed: $File::Find::name - $!";
        }
    };
}
