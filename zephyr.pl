#!/usr/bin/perl
=begin comment
=
= A Links Development tool.
=
= Written by yung-turabian (Henry Wandover)
=
= Last updated Feb142025
=
= TODO Handle creation of new files.
= Do so by seperating files and directores, when directories are modified either they were renamed
= Or a new file was added.
=
=end comment
=cut

use File::Find;
use File::Basename;
use strict;
use warnings;
use Net::EmptyPort qw<check_port>;
use Firefox::Marionette();
use Try::Tiny;
use Getopt::Std;

$Getopt::Std::STANDARD_HELP_VERSION = 1;

our $VERSION = "0.0.2";
my %opts;
getopts('vh', \%opts) or abort();
sub abort {print get_help_message();exit 1;}
sub get_help_message {return "zephyr [-h or --help] [-v or --version] \n";}
sub get_about_message {return "A live reload tool for Links development.\n";}
if (defined $opts{v}) {VERSION_MESSAGE();}
if (defined $opts{h}) {abort();}
sub HELP_MESSAGE {print get_help_message();}
sub VERSION_MESSAGE {print "Version $VERSION\n";}

print "Firefox::Marionette version: $Firefox::Marionette::VERSION\n";

my $linksBin;

if ( `which links` ne "" ) {
    $linksBin = "links";
} elsif ( `which linx` ne "" ) {
    $linksBin = "linx";
} else {
    # Premature exit if links/linx was not found on '$PATH'
    print "Links wasn't discovered as valid binary.\nHINT: Add links to your path!\n";
    exit;
}

sub array2String {
    my $n = scalar(@_);

    if ( $n == 0 ) { return ""; }
    elsif ( $n == 1 ) { return basename($_[0]); }

    my $prettyString = "";

    foreach my $it (@_) {
        $prettyString = $prettyString . basename($it) . ",";
    }

    return $prettyString;
}

my $root = '.';
my $configFile;
my $mainFile;
my $port = 8080; #default
my %files;
my %directories;
find ({
    wanted => sub { globFiles($root); },
    no_chdir => 1,
      }, $root);

my @tmp = keys %directories;
my $linksPaths = array2String( (keys %directories) );

my $numOfFiles = keys %files;

my $got_signal;
local $SIG{INT} = sub {
    #print "DEBUG Caught: @_";
    $got_signal = 1;
};

my %actions = ( links => \&callLinks,
    );


checkFoundFiles();

my $url = "http://localhost:$port";

my $parent_pid = "$$";
defined( my $pid = fork() ) or die "failed to fork: $!";

if ( $pid == 0 ) {
    $actions{"links"}->();
    exit;
}

my $browser = Firefox::Marionette->new(sleep_time_in_ms => 5, visible => 1);

try {
    $browser->go($url);
} catch {
    warn "Error navigating to URL: $_";
};

use Fcntl qw(:seek); # For SEEK_SET

open(my $fh, '.links_output.log') or die "File '.links_output.log' can't be opened";

my $confirming_links_started = 1;
my $found_keyword = 0;

for ( ; ; ) {
    if ($got_signal) {
        last;
    } elsif (not( isBrowserOpen() )) {
        last;
    }

    if ( $confirming_links_started ) {
        while (my $line = <$fh>) {
            if ($line =~ /\QStarting server (2)?\E/) {
                $found_keyword = 1;
                last;
            }
        }

        if ( $found_keyword ) {
            if ( isBrowserOpen() ) {
                print "New content!\n";
                $browser->refresh();
            }

            $confirming_links_started = 0;
            $found_keyword = 0;
        }
    }

    keys %files;
    while (my($f, $t) = each %files) {
        my $stat = callStat($f);
        if ($t eq $stat) {
            ;
        } elsif ( $t eq -1 ) {
            ; # FIXME If not found, often just still being update, could be handled better.
        } else {
            kill 'TERM', $pid;
            waitpid $pid, 0;
            $files{$f} = $stat; # Update mod time
            print "DEBUG $f updated.\n";
            defined( $pid = fork() ) or die "failed to fork: $!";

            if ( $pid == 0 ) {
                $actions{"links"}->();
                exit;
            }

            # Reset fh
            seek $fh, 0, 0 or die "Could not seek: $!";
            truncate('.links_output.log', 0) or die "Failed to truncate: $!";
            $confirming_links_started = 1;
        }
    }
}

system("fuser -k $port/tcp");
close($fh);

exit;

sub isBrowserOpen {
    my $is_open = 1; # Assume Browser is open
    try {
        $browser->title;
    } catch {
        $is_open = 0;
    };

    return $is_open;
}

sub callLinks {
    # HACK Assuming files are in `core`.
    system("fuser -k $port/tcp"); # Kill other process if on port

    open(my $log_fh, '>', ".links_output.log") or die "Failed to open log file: $!";

    open(STDOUT, '>&', $log_fh);
    open(STDERR, '>&', $log_fh);

    if (defined $configFile) {
        exec($linksBin, '--debug', '--session-exceptions', "--path=$linksPaths", "--config=$configFile",
                $mainFile) or die "Failed to exec: $!";
    } else {
        exec($linksBin, '--debug', '--session-exceptions', "--path=$linksPaths",
                $mainFile) or die "Failed to exec: $!";
    }

    return;
}

sub globFiles {
    my $fname = $File::Find::name;
    if (-d $fname) {
        ; # Ignore
    }
    elsif (-e $fname) {
        my $dirname = dirname( $fname );
        if ( $dirname eq '.' ) {
            $dirname = undef;
        }
        my $basefname = basename( $fname );

        if ( $basefname eq "config" ) {
            $configFile = $fname;
        } elsif ( $basefname =~ /^\./ ) {
           return;
        } elsif ( $basefname =~ /\.links$/ ) { # Searching for a main links file.
            open( my $fh, '<', $fname) or die "Failed to open file: $!\n";

            while(my $line = <$fh>) {
                if ($line =~ /servePages\(\)/) {
                    $mainFile = $fname;
                }
            }
            close($fh);

            if ( defined $dirname ) {
                $directories{$dirname} = callStat($dirname);
            }
        }

        $files{$fname} = callStat($fname);

        print "FILE: $fname\n";
    }
    else {
        print "ERR: Unexpected type of file.\n";
        exit;
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

sub checkFoundFiles {
    unless (defined $configFile ) {
        print "If you have a config file name it `config` or edit this exe's config\n";
    } else {
        print "Found a links config file here: $configFile\n";
        parseConfig($configFile);
        if ($port ne "8080") {print "Set port to $port\n"; }

    }

    if ( $mainFile eq -1 ) {
        print "No main file was discovered, try creating a file with `servePages()` in a main loop\n.";
    } else {
        print "Found a links driver/main file here: $mainFile\n";
    }


    return;
}
