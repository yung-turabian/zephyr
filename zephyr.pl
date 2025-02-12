#!/usr/bin/perl

# TODO Handle creation of new files.
# NOTE Kill port with: fuser -k 8080/tcp

use File::Find;
use File::Basename;
use strict;
use warnings;
use Firefox::Marionette();
print "Firefox::Marionette version: $Firefox::Marionette::VERSION\n";
use Try::Tiny;


my $root = '.';
my $configFile = -1;
my $port = 8080; #default
my %files;
find ({
    wanted => sub { catchFiles($root); },
    no_chdir => 1,
      }, $root);

my $numOfFiles = keys %files;

my $got_signal;
local $SIG{INT} = sub {
    #print "DEBUG Caught: @_";
    $got_signal = 1;
};

my %actions = ( links => \&callLinksNoConfig,
    );

if ( $configFile eq -1 ) {
    print "If you have a config file name it `config` or edit this exe's config\n";
} else {
    print "Found a links config file here: $configFile\n";
    $actions{"links"} = \&callLinks;
    parseConfig($configFile);
    if ($port ne "8080") {print "Set port to $port\n"; }

}

my $url = "http://localhost:$port";


my $browser = Firefox::Marionette->new(visible => 1);

$actions{"links"}->();


try {
    $browser->go($url);
} catch {
    warn "Error navigating to URL: $_";
};


for ( ; ; ) {
    if ($got_signal) {
        system("fuser -k $port/tcp");
        exit;
    }

    my $is_open = 1; # Assume Browser is open
    try {
        $browser->title;
    } catch {
        $is_open = 0;
    };

    if (not($is_open)) {
        system("fuser -k $port/tcp");
        exit;
    }

    keys %files;
    while (my($f, $t) = each %files) {
        my $stat = callStat($f);
        if ($t eq $stat) {
            ;
        } elsif ( $t eq -1 ) {
            ; # FIXME If not found, often just still being update
        } else {
            $files{$f} = $stat; # Update mod time
            print "DEBUG $f updated.\n";
            $actions{"links"}->();
        }
    }
}

exit;

sub callLinks {
    # HACK Use forking!
    system("fuser -k $port/tcp & links --session-exceptions --path=core/ --config=config main.links  &");
    # HACK Assuming files are in `core` and file is main.
    # HACK A pretty gnarly race condition.
    sleep(1);
    $browser->refresh();
}
sub callLinksNoConfig {
    system('links --session-exceptions --path=core/  main.links  &');
    # HACK Assuming files are in `core` and file is main.
}



sub catchFiles {
    my $fname = $File::Find::name;
    if ( $fname =~ /\.git/ || $fname eq '.' ) {
        ;
    } else {
        if ( basename($fname) eq "config" ) {
            $configFile = $fname;
        }
        $files{$fname} = callStat($fname);
    }

    return;
}

sub printFiles {
    keys %files;
    while (my($f, $t) = each %files) {
        print "$f -> $t\n";
    }
    return;
}

sub callStat {
    my $n = scalar(@_);

    if ( $n > 1 || $n < 1 ) {
        print "Error in callStat argument passing\n";
    }

    (my($device, $inode, $mode, $nlink, $uid, $gid, $rdev,
        $size, $atime, $mtime, $ctime, $blksize, $blocks)) = stat("$_[0]");

    unless (defined $mtime) {
        return -1;
    }

    return $mtime;
}

# Read the Links config file, if it exists.
sub parseConfig {

    my $fname = $_[0];

    open('fh', $fname) or die "File '$fname' can't be opened";

    while ( <fh> ) {
        chomp $_;

        my($key, $val) = split /\s*=\s*/, $_;

        next if !defined $key;

        ($key eq "port")? $port = $val : $port=$port;

        # Now split the IP list. Be sure to account for whitespace.
        #my @ips = split /\s*,\s*/, $val;

        #say "Allowed Hosts: @ips";
    }


    return;
}
