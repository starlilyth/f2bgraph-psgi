#!/usr/bin/perl
# f2bgraph -- an rrdtool frontend for fail2ban statistics

use strict;
use warnings;
use Getopt::Long;
use RRDs;

my $version = "20230220";

my $rrdpath = "/var/log";
my $f2bcmd = '/bin/fail2ban-client status';
my $pidfile = '/run/f2bgraph.pid';
my $continue = 1;

sub usage {
  my $opthelp = qq( Command line usage:
  f2bgraph --help
  f2bgraph --verbose
  f2bgraph --version);
  print "$opthelp\n";
  exit;
}

sub main {
  # options
  my %opt = ();
  Getopt::Long::Configure('gnu_getopt');
  GetOptions(\%opt, 'help|h', 'verbose|v', 'version|V');

  # help
  usage if $opt{help};

  # version
  if($opt{version}) {
    print "f2bgraph vers. $version by github.com/starlilyth\n";
    exit;
  }
  print "f2bgraph vers. $version by github.com/starlilyth\n" if $opt{verbose};

  # do the work
  # check if we are already running
  if (-f $pidfile) {
    print "already running!\n";
    exit;
  } else {
    `echo $$ > $pidfile`;
  }

  # get the jail list
  my @f2bdata = `$f2bcmd`;
  my $jaillist;
  foreach my $line (@f2bdata) {
    if ($line =~ /Jail list:(.*)/) {
     $jaillist = $1;
    }
  }
  # make it an array and clean it up
  my @jails = split(/,/, $jaillist);
  s{^\s+|\s+$}{}g foreach @jails;
  print "jail list: @jails\n" if $opt{verbose};

  # write it to a file for the web page
  my $jailfile = "$rrdpath/f2bgraph-jails.txt";
  open(my $fh, '>', $jailfile) or die "Could not open file '$jailfile' $!";
  print $fh "@jails\n";
  close $fh;

  # Start the main loop
  $SIG{INT}  = \&signal_handler;
  $SIG{TERM} = \&signal_handler;
  while ($continue) {
    # loop through each jail
    foreach my $jail (@jails) {

      # get the jail data
      my @jaildata = `$f2bcmd $jail`;
      my %sum = ( curf => 0,  totf=> 0, curb => 0, totb => 0 );
      foreach my $jline (@jaildata) {
        $sum{curf} = $1 if ($jline =~ /Currently failed:\s+(\d+)/);
        $sum{curb} = $1 if ($jline =~ /Currently banned:\s+(\d+)/);
        $sum{totf} = $1 if ($jline =~ /Total failed:\s+(\d+)/);
        $sum{totb} = $1 if ($jline =~ /Total banned:\s+(\d+)/);
      }

      # set up the RRD
      my $jdb = "$rrdpath/f2bgraph-$jail.rrd";
      if (! -f $jdb) {
        init_rrd($jail);
        print "RRD for $jail created\n" if $opt{verbose};
      }

      # update the RRD
      RRDs::update ($jdb, "N:$sum{curf}:$sum{curb}:$sum{totf}:$sum{totb}");
      print "update $jail: CurF:$sum{curf} CurB:$sum{curb} TotF:$sum{totf} TotB:$sum{totb}\n" if $opt{verbose};
    }

    # wait a minute and loop again
    sleep 60;
  }
}

sub init_rrd($) {
  my $jail = shift;
  my $jdb = "$rrdpath/f2bgraph-$jail.rrd";
  my $rrdstep = 60;
  my $xpoints = 540;
  my $points_per_sample = 3;
  my $rows = $xpoints/$points_per_sample;
  my $realrows = int($rows*1.1); # ensure that the full range is covered
  my $day_steps = int(3600*24 / ($rrdstep*$rows));
  # use multiples, otherwise rrdtool could choose the wrong RRA
  my $week_steps = $day_steps*7;
  my $month_steps = $week_steps*5;
  my $year_steps = $month_steps*12;
  RRDs::create($jdb, '--step', $rrdstep,
      'DS:curf:GAUGE:600:0:U',
      'DS:curb:GAUGE:600:0:U',
      'DS:totf:GAUGE:600:0:U',
      'DS:totb:GAUGE:600:0:U',
      "RRA:LAST:0.5:$day_steps:$realrows",   # day
      "RRA:LAST:0.5:$week_steps:$realrows",  # week
      "RRA:LAST:0.5:$month_steps:$realrows", # month
      "RRA:LAST:0.5:$year_steps:$realrows",  # year
      "RRA:MAX:0.5:$day_steps:$realrows",   # day
      "RRA:MAX:0.5:$week_steps:$realrows",  # week
      "RRA:MAX:0.5:$month_steps:$realrows", # month
      "RRA:MAX:0.5:$year_steps:$realrows",  # year
  );
}

sub signal_handler {
  $continue = 0;
  unlink $pidfile;
}

main;

