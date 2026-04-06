#!/usr/bin/env perl
#*****************************************************************************************
# safari-cookie-cleaner.pl
#
# Delete Safari website data that does not match a bookmarked website domain
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   5-Apr-2026  2:30pm
# Modified :   5-Apr-2026  4:45pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************
use strict;
use warnings;
use v5.34;
use feature 'signatures';
no warnings 'experimental::signatures';

use Getopt::Long;
use File::Copy;
use File::Path qw(remove_tree);
use File::Temp qw(tempfile);
use POSIX      qw(strftime);

my $SAFARI_DATA   = "$ENV{HOME}/Library/Containers/com.apple.Safari/Data/Library";
my $COOKIE_FILE   = "$SAFARI_DATA/Cookies/Cookies.binarycookies";
my $BOOKMARK_FILE = "$ENV{HOME}/Library/Safari/Bookmarks.plist";
my $OBSERVATIONS  = "$SAFARI_DATA/WebKit/WebsiteData/ResourceLoadStatistics/observations.db";
my $WEBSITE_DATA  = "$SAFARI_DATA/WebKit/WebsiteData/Default";
my $WEBKIT_CACHE  = "$SAFARI_DATA/Caches/com.apple.Safari/WebKitCache";
my $ALT_SERVICES  = "$SAFARI_DATA/Caches/WebKit/AlternativeServices/AlternativeService.sqlite";
my $URL_CACHE_DIR = "$SAFARI_DATA/Caches/com.apple.Safari/fsCachedData";
my $URL_CACHE_DB  = "$SAFARI_DATA/Caches/com.apple.Safari/Cache.db";
my $KNOWLEDGE_DB  = "$ENV{HOME}/Library/Application Support/Knowledge/knowledgeC.db";
my $SAFARI_TMP    = "$ENV{HOME}/Library/Containers/com.apple.Safari/Data/tmp";
my $COOKIE_MAGIC  = 'cook';
my $PAGE_HEADER   = 0x00000100;
my $FILE_TAG      = pack('H*', '071720050000004b');

my $dry_run = 0;
my $verbose = 0;

GetOptions(
    'dry-run|n' => \$dry_run,
    'verbose|v' => \$verbose,
) or die "Usage: $0 [--dry-run|-n] [--verbose|-v]\n";

check_safari_not_running();

my $bookmark_domains = extract_bookmark_domains();
die "No bookmarked domains found\n" unless keys %$bookmark_domains;

printf "Found %d bookmarked domains\n", scalar keys %$bookmark_domains if $verbose;

if (-f $COOKIE_FILE) {
    my ($pages, $policy_plist) = parse_binary_cookies($COOKIE_FILE);

    my $total_before = 0;
    my $total_after  = 0;
    my @filtered_pages;

    for my $page (@$pages) {
        my @kept;
        for my $cookie (@$page) {
            $total_before++;
            if (domain_matches_bookmarks($cookie->{domain}, $bookmark_domains)) {
                push @kept, $cookie;
                $total_after++;
            } else {
                printf "  DELETE: %-40s  %s=%s\n", $cookie->{domain}, $cookie->{name}, substr($cookie->{value}, 0, 30)
                    if $verbose;
            }
        }
        push @filtered_pages, \@kept if @kept;
    }

    my $removed = $total_before - $total_after;
    printf "%s %d of %d cookies (%d kept)\n",
        $dry_run ? 'Would remove' : 'Removing',
        $removed, $total_before, $total_after;

    if (!$dry_run && $removed > 0) {
        my $backup = "$COOKIE_FILE.bak";
        copy($COOKIE_FILE, $backup) or die "Backup failed: $!\n";
        printf "Backup saved to %s\n", $backup if $verbose;
        write_binary_cookies($COOKIE_FILE, \@filtered_pages, $policy_plist);
        say "Cookies file updated.";
    }
} else {
    say "No cookies file found, skipping";
}

clean_observations_db($bookmark_domains);
clean_website_data($bookmark_domains);
clean_alt_services($bookmark_domains);
clean_url_cache();
clean_screen_time($bookmark_domains);
clean_webkit_cache();

#----- subroutines -----------------------------------------------------------------------

sub check_safari_not_running {
    my $pids = `pgrep -x Safari 2>/dev/null`;
    if ($pids && $pids =~ /\d/) {
        die "Safari is running. Please quit Safari first.\n";
    }
}

sub extract_bookmark_domains {
    my %domains;
    open my $fh, '-|', 'plutil', '-convert', 'xml1', '-o', '-', $BOOKMARK_FILE
        or die "Cannot read bookmarks plist: $!\n";

    while (my $line = <$fh>) {
        while ($line =~ m{https?://([^/<"]+)}g) {
            my $host = lc $1;
            $host =~ s/^www\.//;
            # extract registrable domain (last two or three labels)
            my @labels = split /\./, $host;
            if (@labels >= 2) {
                # handle common two-part TLDs like co.uk, com.au
                my $domain;
                if (@labels >= 3 && $labels[-2] =~ /^(co|com|org|net|gov|edu|ac)$/ && length($labels[-1]) == 2) {
                    $domain = join('.', @labels[-3 .. -1]);
                } else {
                    $domain = join('.', @labels[-2 .. -1]);
                }
                $domains{$domain} = 1;
            }
        }
    }
    close $fh;
    return \%domains;
}

sub domain_matches_bookmarks ($cookie_domain, $bookmark_domains) {
    my $cd = lc $cookie_domain;
    $cd =~ s/^\.//;

    # direct match
    return 1 if $bookmark_domains->{$cd};

    # suffix match: extract registrable domain from cookie domain
    my @labels = split /\./, $cd;
    if (@labels >= 2) {
        my $reg;
        if (@labels >= 3 && $labels[-2] =~ /^(co|com|org|net|gov|edu|ac)$/ && length($labels[-1]) == 2) {
            $reg = join('.', @labels[-3 .. -1]);
        } else {
            $reg = join('.', @labels[-2 .. -1]);
        }
        return 1 if $bookmark_domains->{$reg};
    }

    return 0;
}

sub parse_binary_cookies ($file) {
    open my $fh, '<:raw', $file or die "Cannot open $file: $!\n";
    my $data;
    {
        local $/;
        $data = <$fh>;
    }
    close $fh;

    my $pos = 0;

    # header
    my ($magic, $num_pages) = unpack('a4N', substr($data, $pos, 8));
    die "Not a binary cookies file (bad magic)\n" unless $magic eq $COOKIE_MAGIC;
    $pos += 8;

    # page sizes
    my @page_sizes = unpack("N$num_pages", substr($data, $pos, $num_pages * 4));
    $pos += $num_pages * 4;

    # parse each page
    my @all_pages;
    for my $ps (@page_sizes) {
        my $page_data = substr($data, $pos, $ps);
        $pos += $ps;

        my $num_cookies = unpack('V', substr($page_data, 4, 4));
        my @offsets = unpack("V$num_cookies", substr($page_data, 8, $num_cookies * 4));

        my @cookies;
        for my $off (@offsets) {
            my $cookie = parse_cookie($page_data, $off);
            push @cookies, $cookie;
        }
        push @all_pages, \@cookies;
    }

    # everything after pages is: 4-byte checksum + 8-byte tag + policy plist
    my $policy_plist = '';
    if ($pos + 12 < length($data)) {
        $policy_plist = substr($data, $pos + 12);    # skip checksum + tag
    }

    return (\@all_pages, $policy_plist);
}

sub parse_cookie ($page_data, $off) {
    my ($size, $flags, $unknown1, $unknown2,
        $url_off, $name_off, $path_off, $value_off) =
        unpack('VVVVVVVV', substr($page_data, $off, 32));

    my $comment_bytes = substr($page_data, $off + 32, 8);
    my $expiry        = unpack('d', substr($page_data, $off + 40, 8));
    my $creation      = unpack('d', substr($page_data, $off + 48, 8));

    my $domain = read_cstring($page_data, $off + $url_off);
    my $name   = read_cstring($page_data, $off + $name_off);
    my $path   = read_cstring($page_data, $off + $path_off);
    my $value  = read_cstring($page_data, $off + $value_off);

    return {
        raw_data => substr($page_data, $off, $size),
        size     => $size,
        flags    => $flags,
        unknown1 => $unknown1,
        unknown2 => $unknown2,
        domain   => $domain,
        name     => $name,
        path     => $path,
        value    => $value,
        comment  => $comment_bytes,
        expiry   => $expiry,
        creation => $creation,
    };
}

sub read_cstring ($data, $offset) {
    my $end = index($data, "\0", $offset);
    $end = length($data) if $end < 0;
    return substr($data, $offset, $end - $offset);
}

sub write_binary_cookies ($file, $pages, $policy_plist) {
    my @page_blobs;
    for my $page (@$pages) {
        next unless @$page;
        push @page_blobs, build_page($page);
    }

    die "No pages to write\n" unless @page_blobs;

    my $num_pages = scalar @page_blobs;
    my @page_sizes = map { length($_) } @page_blobs;

    my $out = $COOKIE_MAGIC;
    $out .= pack('N', $num_pages);
    $out .= pack('N*', @page_sizes);
    $out .= $_ for @page_blobs;

    $out .= pack('N', compute_checksum(\@page_blobs));
    $out .= $FILE_TAG;
    $out .= $policy_plist if defined $policy_plist && length $policy_plist;

    my ($tmp_fh, $tmp_file) = tempfile(DIR => "$ENV{HOME}/Library/Containers/com.apple.Safari/Data/Library/Cookies");
    binmode $tmp_fh;
    print $tmp_fh $out;
    close $tmp_fh;

    rename $tmp_file, $file or die "Failed to replace cookie file: $!\n";
    chmod 0644, $file;
}

sub build_page ($cookies) {
    my $num = scalar @$cookies;

    # header area size: 4 (page header) + 4 (count) + num*4 (offsets) + 4 (end marker)
    my $header_size = 12 + $num * 4;

    # compute cookie offsets and collect raw data
    my @offsets;
    my $cookie_data = '';
    for my $c (@$cookies) {
        push @offsets, $header_size + length($cookie_data);
        $cookie_data .= $c->{raw_data};
    }

    my $page = pack('N', $PAGE_HEADER);
    $page .= pack('V', $num);
    $page .= pack('V*', @offsets);
    $page .= pack('V', 0);    # end marker
    $page .= $cookie_data;

    return $page;
}

sub clean_observations_db ($bookmark_domains) {
    return unless -f $OBSERVATIONS;

    my @to_delete;
    my $rows = `sqlite3 "$OBSERVATIONS" "SELECT domainID, registrableDomain FROM ObservedDomains;" 2>/dev/null`;
    for my $line (split /\n/, $rows) {
        my ($id, $domain) = split /\|/, $line, 2;
        next unless defined $domain && length $domain;
        unless (domain_matches_bookmarks($domain, $bookmark_domains)) {
            push @to_delete, { id => $id, domain => $domain };
        }
    }

    return unless @to_delete;

    printf "%s %d of %d entries from observations.db\n",
        $dry_run ? 'Would remove' : 'Removing',
        scalar @to_delete,
        scalar(split /\n/, $rows);

    if ($verbose) {
        printf "  DELETE: %s\n", $_->{domain} for @to_delete;
    }

    unless ($dry_run) {
        my $ids = join(',', map { $_->{id} } @to_delete);
        system('sqlite3', $OBSERVATIONS,
            "PRAGMA foreign_keys = ON; DELETE FROM ObservedDomains WHERE domainID IN ($ids);");
    }
}

sub clean_website_data ($bookmark_domains) {
    return unless -d $WEBSITE_DATA;

    my @to_delete;
    opendir my $dh, $WEBSITE_DATA or return;
    while (my $entry = readdir $dh) {
        next if $entry =~ /^\./;
        my $origin_file = "$WEBSITE_DATA/$entry/$entry/origin";
        next unless -f $origin_file;

        open my $fh, '<', $origin_file or next;
        my $content = do { local $/; <$fh> };
        close $fh;

        # origin file contains domain name(s) — extract the first recognizable one
        my $domain;
        if ($content =~ /\b([a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+)\b/i) {
            $domain = $1;
        }
        next unless defined $domain;

        unless (domain_matches_bookmarks($domain, $bookmark_domains)) {
            push @to_delete, { dir => "$WEBSITE_DATA/$entry", domain => $domain };
        }
    }
    closedir $dh;

    return unless @to_delete;

    printf "%s %d LocalStorage directories\n",
        $dry_run ? 'Would remove' : 'Removing',
        scalar @to_delete;

    if ($verbose) {
        printf "  DELETE: %s\n", $_->{domain} for @to_delete;
    }

    unless ($dry_run) {
        remove_tree($_->{dir}) for @to_delete;
    }
}

sub clean_alt_services ($bookmark_domains) {
    return unless -f $ALT_SERVICES;

    my $rows = `sqlite3 "$ALT_SERVICES" "SELECT rowid, host FROM alt_services;" 2>/dev/null`;
    my @to_delete;
    my $total = 0;
    for my $line (split /\n/, $rows) {
        my ($rowid, $host) = split /\|/, $line, 2;
        next unless defined $host;
        $total++;
        unless (domain_matches_bookmarks($host, $bookmark_domains)) {
            push @to_delete, { id => $rowid, host => $host };
        }
    }

    return unless @to_delete;

    printf "%s %d of %d HTTP Alternative Service entries\n",
        $dry_run ? 'Would remove' : 'Removing',
        scalar @to_delete, $total;

    if ($verbose) {
        printf "  DELETE: %s\n", $_->{host} for @to_delete;
    }

    unless ($dry_run) {
        my $ids = join(',', map { $_->{id} } @to_delete);
        system('sqlite3', $ALT_SERVICES, "DELETE FROM alt_services WHERE rowid IN ($ids);");
    }
}

sub clean_url_cache {
    return unless -d $URL_CACHE_DIR;

    my @files = glob("$URL_CACHE_DIR/*");
    return unless @files;

    if ($dry_run) {
        printf "Would clear %d URL cache files\n", scalar @files;
    } else {
        unlink @files;
        # Also clear the Cache.db entries
        if (-f $URL_CACHE_DB) {
            system('sqlite3', $URL_CACHE_DB,
                "DELETE FROM cfurl_cache_response; DELETE FROM cfurl_cache_blob_data; DELETE FROM cfurl_cache_receiver_data;");
        }
        printf "Cleared %d URL cache files\n", scalar @files;
    }
}

sub clean_screen_time ($bookmark_domains) {
    return unless -f $KNOWLEDGE_DB;

    my $rows = `sqlite3 "$KNOWLEDGE_DB" "SELECT o.Z_PK, sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN FROM ZOBJECT o JOIN ZSTRUCTUREDMETADATA sm ON o.ZSTRUCTUREDMETADATA = sm.Z_PK WHERE o.ZSTREAMNAME = '/app/webUsage' AND sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL;" 2>/dev/null`;

    my @to_delete;
    my $total = 0;
    for my $line (split /\n/, $rows) {
        my ($pk, $domain) = split /\|/, $line, 2;
        next unless defined $domain;
        $total++;
        unless (domain_matches_bookmarks($domain, $bookmark_domains)) {
            push @to_delete, { pk => $pk, domain => $domain };
        }
    }

    return unless @to_delete;

    printf "%s %d of %d Screen Time web usage entries\n",
        $dry_run ? 'Would remove' : 'Removing',
        scalar @to_delete, $total;

    if ($verbose) {
        printf "  DELETE: %s\n", $_->{domain} for @to_delete;
    }

    unless ($dry_run) {
        my $pks = join(',', map { $_->{pk} } @to_delete);
        system('sqlite3', $KNOWLEDGE_DB, "DELETE FROM ZOBJECT WHERE Z_PK IN ($pks);");
    }
}

sub clean_webkit_cache {
    my @dirs = ($WEBKIT_CACHE, "$SAFARI_TMP/WebKit/MediaCache");

    for my $dir (@dirs) {
        next unless -d $dir;
        if ($dry_run) {
            say "Would clear $dir";
        } else {
            remove_tree($dir, { keep_root => 1 });
            printf "%s cleared\n", $dir;
        }
    }
}

sub compute_checksum ($page_blobs) {
    my $checksum = 0;
    for my $page (@$page_blobs) {
        for (my $i = 0; $i < length($page); $i += 4) {
            $checksum += ord(substr($page, $i, 1));
        }
    }
    return $checksum;
}
