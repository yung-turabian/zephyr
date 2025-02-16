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
use File::Path qw( make_path );
use strict;
use warnings;
use Getopt::Std; 
$Getopt::Std::STANDARD_HELP_VERSION = 1;

# External dependencies
use Net::EmptyPort qw<check_port>;
use Log::Log4perl;
use Firefox::Marionette();
use Try::Tiny;

make_path(".zephyr");

my $conf = q (
		log4perl.category.Zephyr.Logger    = INFO, Logfile, Screen

		log4perl.appender.Logfile          = Log::Log4perl::Appender::File
		log4perl.appender.Logfile.filename = .zephyr/zephyr.log
		log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Logfile.layout.ConversionPattern = [%r] %F %L %m%n

		log4perl.appender.Screen         = Log::Log4perl::Appender::Screen
		log4perl.appender.Screen.stderr  = 0
		log4perl.appender.Screen.layout  = Log::Log4perl::Layout::SimpleLayout
);

our $VERSION = "0.0.2";
my %opts;
getopts('vhd', \%opts) or abort();
sub abort {print get_help_message();exit 1;}
sub get_help_message {return "zephyr [-h or --help] [-v or --version] \n";}
sub get_about_message {return "A live reload tool for Links development.\n";}
sub SetLoggerLevel {$conf =~ s/INFO/TRACE/;}
if (defined $opts{v}) {VERSION_MESSAGE();exit 1;}
if (defined $opts{h}) {abort();}
if (defined $opts{d}) {SetLoggerLevel();}
sub HELP_MESSAGE {print get_help_message();}
sub VERSION_MESSAGE {print "Version $VERSION\n";}

print "Firefox::Marionette version: $Firefox::Marionette::VERSION\n";

Log::Log4perl::init( \$conf );

my $linksBin = FindLinksBin();


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
		my $log = Log::Log4perl::get_logger("Zephyr::Logger");
    $log->trace("Caught: @_");
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
}

my $browser = Firefox::Marionette->new(sleep_time_in_ms => 5, visible => 1);

try {
    $browser->go($url);
} catch {
    warn "Error navigating to URL: $_";
};

my $log = Log::Log4perl::get_logger("Zephyr::Logger");

my $get;
my $pageLoaded = 1;

for ( ; ; ) {
    if ($got_signal) {
        last;
    } elsif (not( isBrowserOpen() )) {
        last;
    }
		
		if ( not $pageLoaded ) {
				my $curl_result = system("curl -s -o /dev/null localhost:$port");
				if ( $curl_result == 0 && isBrowserOpen() ) {
						$log->info("refreshed page with updated content");
						$browser->refresh();
						$pageLoaded = 1;
				}
		}


    keys %files;
    while (my($f, $t) = each %files) {
        my $stat = callStat($f);
				if ( $t ne $stat ) {
						kill 'TERM', $pid;
						waitpid $pid, 0;
            $files{$f} = $stat; # Update mod time
						$log->info("$f updated. Restarting server and reloading browser.");
						$pageLoaded = 0;

						defined( $pid = fork() ) or die "failed to fork: $!";
						if ( $pid == 0 ) {
								$actions{"links"}->();
						}
        } else {
						;
				}
    }
}

system("fuser -k $port/tcp");

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
		my $log = Log::Log4perl::get_logger("Zephyr::Logger");

		# TODO fails to report errors from Links.
    system("fuser -k $port/tcp"); # Kill other process if on port

		my $call = "$linksBin --session-exceptions --path=$linksPaths";

    if (defined $configFile) {
				$call .= " --config=$configFile";
    } 

		$call .= " $mainFile";

		$log->debug("calling Links as: $call");

		exec($call) or die "Failed to exec: $!";

    exit;
}

sub globFiles {
		my $log = Log::Log4perl::get_logger("Zephyr::Logger");

    my $fname = $File::Find::name;
    if (-d $fname) {
        ; # Ignore, for, will need to TODO handle new files and stating directories is a good indicator
    }
    elsif (-e $fname) {
        my $dirname = dirname( $fname );
				if ( $dirname =~ /\.git/ ) { # Skip all hidden files?
						$log->trace("skipping git file: $fname");
						return;
				}
				if ( $dirname =~ /\.zephyr/ ) {
						$log->trace("skipping zephyr file: $fname");
						return;
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

            $directories{$dirname} = callStat($dirname);
						$log->trace("adding directory to watchlist: $dirname");
        }

        $files{$fname} = callStat($fname);

				$log->trace("adding file to watchlist: $fname");
    }
    else {
				$log->error("unexpected type of file: $fname");
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
		my $log = Log::Log4perl::get_logger("Zephyr::Logger");
    unless (defined $configFile ) {
        print "If you have a config file name it `config` or edit this exe's config\n";
    } else {
        print "Found a links config file here: $configFile\n";
        parseConfig($configFile);
        if ($port ne "8080") {print "Set port to $port\n"; }

    }

    if ( defined( $mainFile ) ) {
        print "Found a links driver/main file here: $mainFile\n";
				return;
		} else {
				$log->fatal("No main file was discovered, try creating a file with `servePages()` in a main loop.");
				exit;
    }
}

sub FindLinksBin {
		my $log = Log::Log4perl::get_logger("Zephyr::Logger");
		my $linksBin;

		my $out = `which links || which linx`;
		chomp($out);
		$out = basename($out);
		if ( $out eq "links" ) {
				$linksBin = "links";
		} elsif ( $out eq "linx" ) {
				$linksBin = "linx";
		} else {
				$log->fatal("Links wasn't discovered as valid binary.\nHINT: Add links to your path!");
				exit;
		}

		return $linksBin;
}


sub getloggerLevel {
		my $log = Log::Log4perl::get_logger("Zephyr::Logger");
		my $level = 0;

		if ( $log->is_trace() ) {
				$level++;
		} elsif ( $log->is_debug() ) {
				$level++;
		} elsif ( $log->is_info () ) {
				$level++;
		} elsif ( $log->is_warn () ) {
				$level++;
		} elsif ( $log->is_error () ) {
				$level++;
		} elsif ( $log->is_fatal () ) {
				$level++;
		}

		return $level;
}
