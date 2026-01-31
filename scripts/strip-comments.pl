#!/usr/bin/env perl
#*****************************************************************************************
# strip-comments.pl
#
# Strip comments from C source code
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# libraries
#*****************************************************************************************
use strict;
use warnings;
use File::Find;
use File::Basename;

no warnings 'experimental::smartmatch';

#*****************************************************************************************
# main line
#*****************************************************************************************
my %processFilesOptions = (
    wanted      => \&processFiles,
    no_chdir    => 1,
    bydepth     => 0,
    follow_skip => 2,
);
my $workRoot = (@ARGV == 0) ? "." : $ARGV[0];
find(\%processFilesOptions, $workRoot);

#*****************************************************************************************
# process a source file
#*****************************************************************************************
sub processFiles {
    return if $_ eq "." or $_ eq "..";
    return if !-f $_;

    my @extensions = ("c", "cc", "cpp", "cs", "cxx", "swift", "m", "mm", "h", "hh", "hpp", "hxx", "pch");
    my $ext        = (fileparse($File::Find::name, qr/\.[^.]*/))[2];
    $ext = substr($ext, 1);
    if ($ext ~~ @extensions) {
        open(my $sourcefile, "<$File::Find::name")
          || die "**** Unable to read $File::Find::name - $!\n";
        my $source = do { local $/; <$sourcefile> };
        close($sourcefile);

        zap(\$source);
        $source =~ s/^(\s*\r\n){2,}/\n/gm;
        open($sourcefile, ">$File::Find::name")
          || die "**** Unable to read $File::Find::name - $!\n";
        print $sourcefile $source;
        close($sourcefile);
    }
}

#*****************************************************************************************
# zap the source code comments
#*****************************************************************************************
sub zap {
    my $sourceRef = shift;
    my $source    = $$sourceRef;

    my $sourceIndex  = 0;
    my $sourceLength = length($source);

    while ($sourceIndex < $sourceLength) {
        my $sourceCharacter = substr($source, $sourceIndex, 1);
        if ($sourceCharacter eq qq(") || $sourceCharacter eq qq('')) {
            my $quote = $sourceCharacter;

            while ($sourceIndex < $sourceLength) {
                ++$sourceIndex;
                $sourceCharacter = substr($source, $sourceIndex, 1);
                if ($sourceCharacter eq qq(\\)) {
                    $sourceIndex += 2;
                    $sourceCharacter = substr($source, $sourceIndex, 1);
                }
                if ($sourceCharacter eq $quote) {
                    last;
                }
            }
        }
        if ($sourceCharacter eq "/") {
            ++$sourceIndex;
            $sourceCharacter = substr($source, $sourceIndex, 1);
            if ($sourceCharacter eq "/") {
                my $commentStart = $sourceIndex - 1;
                while ($sourceIndex < $sourceLength
                    && $sourceCharacter ne "\n")
                {
                    ++$sourceIndex;
                    $sourceCharacter = substr($source, $sourceIndex, 1);
                }
                $source       = substr($source, 0, $commentStart) . substr($source, $sourceIndex + 1);
                $sourceIndex  = 0;
                $sourceLength = length($source);
            }
            elsif ($sourceCharacter eq "*") {
                my $nesting      = 1;
                my $commentStart = $sourceIndex - 1;
                while ($sourceIndex < $sourceLength) {
                    ++$sourceIndex;
                    $sourceCharacter = substr($source, $sourceIndex, 1);
                    if ($sourceCharacter eq "*") {
                        ++$sourceIndex;
                        $sourceCharacter = substr($source, $sourceIndex, 1);
                        if ($sourceCharacter eq "/") {
                            --$nesting;
                            if ($nesting == 0) {
                                last;
                            }
                        }
                        else {
                            --$sourceIndex;
                        }
                    }
                    elsif ($sourceCharacter eq "/") {
                        ++$sourceIndex;
                        $sourceCharacter = substr($source, $sourceIndex, 1);
                        if ($sourceCharacter eq "*") {
                            ++$nesting;
                        }
                        else {
                            --$sourceIndex;
                        }
                    }
                }
                $source       = substr($source, 0, $commentStart) . " " . substr($source, $sourceIndex + 1);
                $sourceIndex  = 0;
                $sourceLength = length($source);
            }
            else {
                --$sourceIndex;
            }
        }
        ++$sourceIndex;
    }
    $$sourceRef = $source;
}
