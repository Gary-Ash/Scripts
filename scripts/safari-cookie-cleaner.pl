#!/usr/bin/env perl
#*****************************************************************************************
# safari-cookie-cleaner.pl
#
# Delete Safari website data that does not match a bookmarked website domain
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   5-Apr-2026  2:30pm
# Modified :  12-Apr-2026  6:00pm
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
use XML::LibXML;

my $SAFARI_DATA   = "$ENV{HOME}/Library/Containers/com.apple.Safari/Data/Library";
my $COOKIE_FILE   = "$SAFARI_DATA/Cookies/Cookies.binarycookies";
my $BOOKMARK_FILE = "$ENV{HOME}/Library/Safari/Bookmarks.plist";
my $OBSERVATIONS  = "$SAFARI_DATA/WebKit/WebsiteData/ResourceLoadStatistics/observations.db";
my $WEBSITE_DATA  = "$SAFARI_DATA/WebKit/WebsiteData/Default";
my $WEBKIT_CACHE  = "$SAFARI_DATA/Caches/com.apple.Safari/WebKitCache";
my $ALT_SERVICES  = "$SAFARI_DATA/Caches/WebKit/AlternativeServices/AlternativeService.sqlite";
my $URL_CACHE_DIR = "$SAFARI_DATA/Caches/com.apple.Safari/fsCachedData";
my $URL_CACHE_DB  = "$SAFARI_DATA/Caches/com.apple.Safari/Cache.db";
my $HISTORY_DB    = "$ENV{HOME}/Library/Safari/History.db";
my $CB_STATS_DB   = "$ENV{HOME}/Library/Safari/ContentBlockerStatistics.db";
my $HSTS_PLIST    = "$SAFARI_DATA/Caches/WebKit/HSTS/HSTS.plist";
my $FAVICONS_DB   = "$ENV{HOME}/Library/Safari/Favicon Cache/favicons.db";
my $KNOWLEDGE_DB  = "$ENV{HOME}/Library/Application Support/Knowledge/knowledgeC.db";
my $SAFARI_TMP    = "$ENV{HOME}/Library/Containers/com.apple.Safari/Data/tmp";
my $COOKIE_MAGIC  = 'cook';
my $PAGE_HEADER   = 0x00000100;
my $FILE_TAG      = pack('H*', '071720050000004b');

my @BLACKLIST_DOMAINS = qw(
    advancedswift.com
    barebones.com
    batman-news.com
    gamedev.city
    matteomanferdini.com
    donnywals.com
    avanderlee.com
    jessesquires.com
    t.co
    devhints.io
    iosref.com
    costco.com
    ios-factor.com
    iosfeeds.com
    qualitycoding.org
    2dgameartguru.com
    9to5mac.com
    macpaw.com
    angel.co
    blendswap.com
    codeandweb.com
    comicscontinuum.com
    emailtemp.org
    redd.it
    agner.org
    swiftpm.co
    swiftpm.com
    swiftbysundell.com
    swiftjectivec.com
    mapeditor.org
    udemy.com
    fandom.com
    wtfautolayout.com
    71squared.com
    beautifyconverter.com
    freeformatter.com
    sanctum.geek.nz
    graphicriver.net
    stclairsoft.com
    jscreenfix.com
    johncodeos.com
    opengameart.org
    sqlitebrowser.org
    pfiddlesoft.com
    geedbla.com
    gitignore.io
    packagecontrol.io
    probot.github.io
    jamendo.com
    tutsplus.com
    itch.io
    nshipster.com
    testableapple.com
    iterm2.com
    shields.io
    codewars.com
    upwork.com
    escapistmagazine.com
);

my %BLACKLIST = map { $_ => 1 } @BLACKLIST_DOMAINS;

my @WHITELIST_DOMAINS = qw(
    apple.com
    x.com
    gitlab.com
    atlassian.com
    atlassian.net
    bing.com
    live.com
    duckduckgo.com
    discord.com
    discordapp.com
    stackexchange.com
    sublimehq.com
    zenhub.com
    app.zenhub.com
    wikimedia.org
    wikipedia.org
    stackoverflow.com
    apple.stackexchange.com
    twitch.tv
    twitter.com
    superuser.com
    fuckingapproachableswiftconcurrency.com
);

my $dry_run = 0;
my $verbose = 0;

GetOptions(
    'dry-run|n' => \$dry_run,
    'verbose|v' => \$verbose,
) or die "Usage: $0 [--dry-run|-n] [--verbose|-v]\n";

check_safari_not_running();

my $bookmark_domains = extract_bookmark_domains();
die "No bookmarked domains found\n" unless keys %$bookmark_domains;
$bookmark_domains->{$_} = 1 for @WHITELIST_DOMAINS;

printf "Found %d bookmarked domains (incl. %d whitelisted)\n",
    scalar keys %$bookmark_domains, scalar @WHITELIST_DOMAINS if $verbose;

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
clean_history_db($bookmark_domains);
clean_content_blocker_stats($bookmark_domains);
clean_hsts($bookmark_domains);
clean_favicons($bookmark_domains);
clean_screen_time($bookmark_domains);
clean_webkit_cache();

#----- subroutines -----------------------------------------------------------------------

sub check_safari_not_running {
    # Safari itself must be quit by the user — we refuse to kill the UI app.
    my $safari_pid = `pgrep -x Safari 2>/dev/null`;
    chomp $safari_pid;
    if ($safari_pid =~ /\d/) {
        die "Safari is running (pid $safari_pid). Please quit Safari first.\n";
    }

    # WebKit XPC helpers linger after Safari quits and rewrite cache/alt_services
    # on their own schedule. Kill them so our edits stick.
    my @helpers = (
        'com.apple.WebKit.Networking',
        'com.apple.WebKit.WebContent',
        'com.apple.WebKit.GPU',
        'SafariBookmarksSyncAgent',
        'com.apple.Safari.History',
        'SafariPlatformSupport.Helper',
        'SafariNotificationAgent',
        'SafariLaunchAgent',
    );
    for my $h (@helpers) {
        my $pids = `pgrep -f '\Q$h\E' 2>/dev/null`;
        chomp $pids;
        next unless $pids =~ /\d/;
        my @pids = split /\s+/, $pids;
        printf "Killing %s (%s)\n", $h, join(',', @pids) if $verbose;
        kill 'TERM', @pids;
    }

    # Give them a moment to exit, then SIGKILL stragglers.
    sleep 1;
    for my $h (@helpers) {
        my $pids = `pgrep -f '\Q$h\E' 2>/dev/null`;
        chomp $pids;
        next unless $pids =~ /\d/;
        kill 'KILL', split(/\s+/, $pids);
    }
}

sub stop_knowledge_daemons {
    # knowledgeC.db is held open by knowledge-agent and ContextStoreAgent.
    # Kicking them releases the WAL so our writes can land. launchd will
    # relaunch them automatically.
    my $uid = $<;
    for my $svc (qw(
        com.apple.knowledge-agent
        com.apple.CoreDuet.knowledgeC.syncService
        com.apple.contextstoreagent
    )) {
        system('launchctl', 'kickstart', '-k', "gui/$uid/$svc");
    }
    sleep 1;
}

sub run_sqlite ($db, $sql) {
    my $rc = system('sqlite3', $db, $sql);
    if ($rc != 0) {
        warn "sqlite3 failed on $db (rc=$rc): $sql\n";
        return 0;
    }
    return 1;
}

sub extract_bookmark_domains {
    # Walk the Bookmarks.plist DOM and collect only WebBookmarkTypeLeaf
    # URLs that live outside the com.apple.ReadingList subtree. The old
    # regex-over-XML approach grabbed every URL in the file — including
    # reading-list items and embedded CDN references — which made the
    # keep-list so broad that nothing ever got deleted.
    my $xml = `plutil -convert xml1 -o - "$BOOKMARK_FILE" 2>/dev/null`;
    die "Cannot read bookmarks plist\n" unless length $xml;

    my $doc = eval { XML::LibXML->load_xml(string => $xml) };
    die "Failed to parse bookmarks XML: $@\n" if $@;

    my %domains;
    my $root_dict = ($doc->findnodes('/plist/dict'))[0];
    walk_bookmark_dict($root_dict, \%domains) if $root_dict;

    return \%domains;
}

sub walk_bookmark_dict ($dict, $domains) {
    # In a plist <dict>, children alternate: <key>k</key>, <value-node>...
    # Collect keys → value nodes for this dict.
    my %fields;
    my $pending_key;
    for my $child ($dict->childNodes) {
        next unless $child->nodeType == XML_ELEMENT_NODE;
        if ($child->nodeName eq 'key') {
            $pending_key = $child->textContent;
        } else {
            $fields{$pending_key} = $child if defined $pending_key;
            undef $pending_key;
        }
    }

    # Skip the entire Reading List subtree.
    my $title = $fields{Title} ? $fields{Title}->textContent : '';
    return if $title eq 'com.apple.ReadingList';

    my $type = $fields{WebBookmarkType} ? $fields{WebBookmarkType}->textContent : '';
    if ($type eq 'WebBookmarkTypeLeaf' && $fields{URLString}) {
        my $url = $fields{URLString}->textContent;
        if ($url =~ m{^https?://([^/]+)}i) {
            my $host = lc $1;
            $host =~ s/^www\.//;
            $host =~ s/:\d+$//;
            my @labels = split /\./, $host;
            if (@labels >= 2) {
                my $domain;
                if (@labels >= 3 && $labels[-2] =~ /^(co|com|org|net|gov|edu|ac)$/ && length($labels[-1]) == 2) {
                    $domain = join('.', @labels[-3 .. -1]);
                } else {
                    $domain = join('.', @labels[-2 .. -1]);
                }
                $domains->{$domain} = 1;
            }
        }
    }

    # Recurse into Children (an <array> of <dict> nodes).
    if ($fields{Children} && $fields{Children}->nodeName eq 'array') {
        for my $child ($fields{Children}->childNodes) {
            next unless $child->nodeType == XML_ELEMENT_NODE;
            next unless $child->nodeName eq 'dict';
            walk_bookmark_dict($child, $domains);
        }
    }
}

sub domain_matches_bookmarks ($cookie_domain, $bookmark_domains) {
    my $cd = lc $cookie_domain;
    $cd =~ s/^\.//;

    # blacklist overrides everything
    return 0 if $BLACKLIST{$cd};

    # suffix match: extract registrable domain from cookie domain
    my @labels = split /\./, $cd;
    my $reg;
    if (@labels >= 2) {
        if (@labels >= 3 && $labels[-2] =~ /^(co|com|org|net|gov|edu|ac)$/ && length($labels[-1]) == 2) {
            $reg = join('.', @labels[-3 .. -1]);
        } else {
            $reg = join('.', @labels[-2 .. -1]);
        }
        return 0 if defined $reg && $BLACKLIST{$reg};
    }

    # direct match
    return 1 if $bookmark_domains->{$cd};
    return 1 if defined $reg && $bookmark_domains->{$reg};

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
    if ($pos + 12 <= length($data)) {
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
    my @lines = split /\n/, $rows;
    for my $line (@lines) {
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
        scalar @lines;

    if ($verbose) {
        printf "  DELETE: %s\n", $_->{domain} for @to_delete;
    }

    unless ($dry_run) {
        my $ids = join(',', map { $_->{id} } @to_delete);
        run_sqlite($OBSERVATIONS,
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

    # Check if anything actually needs removal (for dry-run reporting).
    my $rows = `sqlite3 "$ALT_SERVICES" "SELECT host FROM alt_services;" 2>/dev/null`;
    my $total = 0;
    my $would_keep = 0;
    for my $host (split /\n/, $rows) {
        next unless length $host;
        $total++;
        $would_keep++ if domain_matches_bookmarks($host, $bookmark_domains);
    }
    return unless $total;

    my $to_remove = $total - $would_keep;
    return unless $to_remove;

    # alt_services is a pure HTTP alt-svc cache. WebKit respawns its XPC
    # helper on demand and flushes in-memory state back to this file, so
    # selective DELETEs race. Nuking the file is reliable — Safari rebuilds
    # it as sites advertise alt-svc on next visit.
    printf "%s HTTP Alternative Service cache (%d entries, %d would re-populate on use)\n",
        $dry_run ? 'Would wipe' : 'Wiping',
        $total, $would_keep;

    unless ($dry_run) {
        for my $f ($ALT_SERVICES, "$ALT_SERVICES-wal", "$ALT_SERVICES-shm") {
            unlink $f if -f $f;
        }
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
            run_sqlite($URL_CACHE_DB,
                "DELETE FROM cfurl_cache_response; DELETE FROM cfurl_cache_blob_data; DELETE FROM cfurl_cache_receiver_data;");
        }
        printf "Cleared %d URL cache files\n", scalar @files;
    }
}

sub clean_history_db ($bookmark_domains) {
    return unless -f $HISTORY_DB;

    my $total = `sqlite3 "$HISTORY_DB" "SELECT COUNT(*) FROM history_items;" 2>/dev/null`;
    chomp $total;
    return unless $total && $total > 0;

    printf "%s all %d Safari history items\n",
        $dry_run ? 'Would remove' : 'Removing', $total;

    return if $dry_run;

    run_sqlite($HISTORY_DB,
        "DELETE FROM history_visits; "
      . "DELETE FROM history_items; "
      . "DELETE FROM history_tombstones; "
      . "VACUUM;");

    my $remaining = `sqlite3 "$HISTORY_DB" "SELECT COUNT(*) FROM history_items;"`;
    chomp $remaining;
    if ($remaining && $remaining > 0) {
        warn "History.db still has $remaining rows after DELETE — com.apple.Safari.History helper may have respawned.\n";
    }
}

sub clean_content_blocker_stats ($bookmark_domains) {
    return unless -f $CB_STATS_DB;

    my %to_delete;    # firstPartyDomainID => domain
    my %to_delete_3p; # thirdPartyDomainID => domain

    my $rows = `sqlite3 "$CB_STATS_DB" "SELECT firstPartyDomainID, domain FROM FirstPartyDomains;" 2>/dev/null`;
    my $total_1p = 0;
    for my $line (split /\n/, $rows) {
        my ($id, $domain) = split /\|/, $line, 2;
        next unless defined $domain && length $domain;
        $total_1p++;
        unless (domain_matches_bookmarks($domain, $bookmark_domains)) {
            $to_delete{$id} = $domain;
        }
    }

    my $rows3 = `sqlite3 "$CB_STATS_DB" "SELECT thirdPartyDomainID, domain FROM ThirdPartyDomains;" 2>/dev/null`;
    my $total_3p = 0;
    for my $line (split /\n/, $rows3) {
        my ($id, $domain) = split /\|/, $line, 2;
        next unless defined $domain && length $domain;
        $total_3p++;
        unless (domain_matches_bookmarks($domain, $bookmark_domains)) {
            $to_delete_3p{$id} = $domain;
        }
    }

    return unless %to_delete || %to_delete_3p;

    printf "%s %d/%d first-party + %d/%d third-party ContentBlocker entries\n",
        $dry_run ? 'Would remove' : 'Removing',
        scalar(keys %to_delete),    $total_1p,
        scalar(keys %to_delete_3p), $total_3p;

    if ($verbose) {
        printf "  DELETE 1P: %s\n", $to_delete{$_}    for sort { $to_delete{$a}    cmp $to_delete{$b}    } keys %to_delete;
        printf "  DELETE 3P: %s\n", $to_delete_3p{$_} for sort { $to_delete_3p{$a} cmp $to_delete_3p{$b} } keys %to_delete_3p;
    }

    return if $dry_run;

    my @sql;
    if (%to_delete) {
        my $ids = join(',', keys %to_delete);
        push @sql,
            "DELETE FROM BlockedResources WHERE firstPartyDomainID IN ($ids);",
            "DELETE FROM FirstPartyDomains WHERE firstPartyDomainID IN ($ids);";
    }
    if (%to_delete_3p) {
        my $ids = join(',', keys %to_delete_3p);
        push @sql,
            "DELETE FROM BlockedResources WHERE thirdPartyDomainID IN ($ids);",
            "DELETE FROM ThirdPartyDomains WHERE thirdPartyDomainID IN ($ids);";
    }
    run_sqlite($CB_STATS_DB, join(' ', @sql));
}

sub clean_hsts ($bookmark_domains) {
    return unless -f $HSTS_PLIST;

    my $xml = `plutil -convert xml1 -o - "$HSTS_PLIST" 2>/dev/null`;
    return unless length $xml;

    my $doc = eval { XML::LibXML->load_xml(string => $xml) };
    if ($@) { warn "Failed to parse HSTS plist: $@\n"; return; }

    # Structure: <plist><dict><key>com.apple.CFNetwork.defaultStorageSession</key>
    #   <dict><key>host1</key><dict>...</dict><key>host2</key>... </dict> </dict></plist>
    my ($session) = $doc->findnodes(
        '/plist/dict/key[text()="com.apple.CFNetwork.defaultStorageSession"]/following-sibling::dict[1]'
    );
    return unless $session;

    # Walk alternating <key>/<dict> pairs.
    my @removed;
    my $total = 0;
    my @children = grep { $_->nodeType == XML_ELEMENT_NODE } $session->childNodes;
    for (my $i = 0; $i < @children; $i += 2) {
        my $key_node = $children[$i];
        my $val_node = $children[$i + 1];
        next unless $key_node && $key_node->nodeName eq 'key';
        my $host = $key_node->textContent;
        $total++;
        next if domain_matches_bookmarks($host, $bookmark_domains);

        push @removed, $host;
        $session->removeChild($key_node);
        $session->removeChild($val_node) if $val_node;
    }

    return unless @removed;

    printf "%s %d of %d HSTS entries\n",
        $dry_run ? 'Would remove' : 'Removing',
        scalar @removed, $total;

    if ($verbose) {
        printf "  DELETE: %s\n", $_ for @removed;
    }

    return if $dry_run;

    my ($tmp_fh, $tmp_file) = tempfile();
    print $tmp_fh $doc->toString;
    close $tmp_fh;
    system('plutil', '-convert', 'binary1', $tmp_file) == 0
        or do { warn "plutil convert failed\n"; unlink $tmp_file; return; };
    rename $tmp_file, $HSTS_PLIST or warn "HSTS rename failed: $!\n";
}

sub clean_favicons ($bookmark_domains) {
    return unless -f $FAVICONS_DB;

    my %page_delete;    # uuid => host (for page_url table)
    my @reject_delete;  # page_url rows to remove from rejected_resources

    my $rows = `sqlite3 "$FAVICONS_DB" "SELECT url, uuid FROM page_url;" 2>/dev/null`;
    my $total_page = 0;
    for my $line (split /\n/, $rows) {
        my ($url, $uuid) = split /\|/, $line, 2;
        next unless defined $url && length $url;
        $total_page++;
        my $host = url_host($url);
        next unless defined $host;
        unless (domain_matches_bookmarks($host, $bookmark_domains)) {
            $page_delete{$uuid} = $host;
        }
    }

    my $rej = `sqlite3 "$FAVICONS_DB" "SELECT page_url FROM rejected_resources;" 2>/dev/null`;
    my $total_rej = 0;
    for my $url (split /\n/, $rej) {
        next unless length $url;
        $total_rej++;
        my $host = url_host($url);
        next unless defined $host;
        unless (domain_matches_bookmarks($host, $bookmark_domains)) {
            push @reject_delete, $url;
        }
    }

    return unless %page_delete || @reject_delete;

    printf "%s %d/%d favicon page rows + %d/%d rejected_resources rows\n",
        $dry_run ? 'Would remove' : 'Removing',
        scalar(keys %page_delete), $total_page,
        scalar(@reject_delete),    $total_rej;

    return if $dry_run;

    my @sql;
    if (%page_delete) {
        my $uuids = join(',', map { "'$_'" } keys %page_delete);
        push @sql,
            "DELETE FROM page_url  WHERE uuid IN ($uuids);",
            "DELETE FROM icon_info WHERE uuid IN ($uuids);";
    }
    if (@reject_delete) {
        my $urls = join(',', map { my $u = $_; $u =~ s/'/''/g; "'$u'" } @reject_delete);
        push @sql, "DELETE FROM rejected_resources WHERE page_url IN ($urls);";
    }
    run_sqlite($FAVICONS_DB, join(' ', @sql));
}

sub url_host ($url) {
    return undef unless $url =~ m{^https?://([^/]+)}i;
    my $host = lc $1;
    $host =~ s/^www\.//;
    $host =~ s/:\d+$//;
    return $host;
}

sub clean_screen_time ($bookmark_domains) {
    return unless -f $KNOWLEDGE_DB;

    # Query ZSTRUCTUREDMETADATA directly so orphaned rows (no ZOBJECT
    # reference) are also caught. We'll cascade-delete ZOBJECT rows that
    # point at the metadata we're removing.
    my $rows = `sqlite3 "$KNOWLEDGE_DB" "SELECT Z_PK, Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN FROM ZSTRUCTUREDMETADATA WHERE Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL;" 2>/dev/null`;

    my @to_delete;
    my $total = 0;
    for my $line (split /\n/, $rows) {
        my ($pk, $domain) = split /\|/, $line, 2;
        next unless defined $domain && length $domain;
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
        my $sql = "DELETE FROM ZOBJECT WHERE ZSTRUCTUREDMETADATA IN ($pks); "
                . "DELETE FROM ZSTRUCTUREDMETADATA WHERE Z_PK IN ($pks);";

        my $count_sql = "SELECT COUNT(*) FROM ZSTRUCTUREDMETADATA WHERE Z_PK IN ($pks);";

        run_sqlite($KNOWLEDGE_DB, $sql);
        my $remaining = `sqlite3 "$KNOWLEDGE_DB" "$count_sql"`;
        chomp $remaining;

        if ($remaining && $remaining > 0) {
            printf "knowledgeC.db blocked (%d rows remain), kicking daemons and retrying\n", $remaining
                if $verbose;
            stop_knowledge_daemons();
            run_sqlite($KNOWLEDGE_DB, $sql);
            $remaining = `sqlite3 "$KNOWLEDGE_DB" "$count_sql"`;
            chomp $remaining;
            if ($remaining && $remaining > 0) {
                warn "knowledgeC.db still has $remaining target rows after daemon restart. Screen Time cleanup failed.\n";
            }
        }
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
