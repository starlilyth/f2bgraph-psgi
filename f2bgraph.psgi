#!/usr/bin/env plackup

use strict;
use warnings;
use RRDs;
use POSIX qw(uname);
use Plack::Request;

my $rrdpath = '/var/log'; # path to where the RRD databases are
my $tmp_dir = '/tmp'; # temporary directory where the images are stored

my $version = "20230222";
my $host = (POSIX::uname())[1];
my $scriptname = 'f2bgraph.psgi';
my $xpoints = 540;
my $points_per_sample = 3;
my $ypoints = 160;
my $ypoints_tot = 96;

my $jaillist = `cat $rrdpath/f2bgraph-jails.txt`;
die "ERROR: no jail list\n" if (! $jaillist);
chomp $jaillist;
my @jails = split(' ', $jaillist);
my @checked = @jails;

my $content;

my @graphs = (
	{ title => 'Last Day',   seconds => 3600*24,     },
	{ title => 'Last Week',  seconds => 3600*24*7,   },
	{ title => 'Last Month', seconds => 3600*24*31,  },
	{ title => 'Last Year',  seconds => 3600*24*365, },
);

my %color = (
	0 => 'f46a9b',
	1 => 'e60049',
	2 => '0bb4ff',
	3 => '1a53ff',
	4 => '32CD32',
	5 => '008000',
	6 => 'b33dc6',
	7 => '9b19f5',
	8 => 'e6d800',
	9 => 'ffa300'
);

sub rrd_graph(@) {
	my ($range, $file, $ypoints, @rrdargs) = @_;
	my $step = $range*$points_per_sample/$xpoints;
	# choose carefully the end otherwise rrd will maybe pick the wrong RRA:
	my $end  = time; $end -= $end % $step;
	my $date = localtime(time);
	$date =~ s|:|\\:|g;
	my ($graphret,$xs,$ys) = RRDs::graph($file,
		'--imgformat', 'PNG',
		'--width', $xpoints,
		'--height', $ypoints,
		'--start', "-$range",
		'--end', $end,
		'--lower-limit', 0,
		'--units-exponent', 0, # don't show milli-messages/s
		'--color', 'SHADEA#ffffff',
		'--color', 'SHADEB#ffffff',
		'--color', 'BACK#ffffff',
    '--slope-mode',
		@rrdargs,
		'COMMENT:['.$date.']\r',
	);
	my $ERR=RRDs::error;
	die "ERROR: $ERR\n" if $ERR;
}

sub graph($$) {
	my ($range, $file) = @_;
	my $step = $range*$points_per_sample/$xpoints;
	my @rrdargs;
	my $cval = 0;
	foreach my $rawjail (@checked) {
		my $jail = substr( $rawjail, 0, 4 );
		my $rrd = "$rrdpath/f2bgraph-$rawjail.rrd";
		push @rrdargs, (
		"DEF:$jail-curf=$rrd:curf:LAST",
		"DEF:$jail-mcurf=$rrd:curf:MAX",
		"VDEF:$jail-1=$jail-curf,LAST",
		"VDEF:$jail-2=$jail-mcurf,MAXIMUM",
		"LINE2:$jail-curf#$color{$cval}:$jail failed",
		'GPRINT:'.$jail.'-1:\: %8.0lf',
		'GPRINT:'.$jail.'-2:Max\: %8.0lf',
		);
		$cval++;
		push @rrdargs, (
		"DEF:$jail-curb=$rrd:curb:LAST",
		"DEF:$jail-mcurb=$rrd:curb:MAX",
		"VDEF:$jail-3=$jail-curb,LAST",
		"VDEF:$jail-4=$jail-mcurb,MAXIMUM",
		"LINE2:$jail-curb#$color{$cval}:$jail banned",
		'GPRINT:'.$jail.'-3:\: %8.0lf',
		'GPRINT:'.$jail.'-4:Max\: %8.0lf\l',
		);
		$cval++;
	}
	push @rrdargs, ('--vertical-label', 'Current',);
	rrd_graph($range, $file, $ypoints, @rrdargs);
}

sub graph_tot($$) {
	my ($range, $file) = @_;
	my $step = $range*$points_per_sample/$xpoints;
	my @rrdargs;
	my $cval = 0;
	foreach my $rawjail (@checked) {
		my $jail = substr( $rawjail, 0, 4 );
		my $rrd = "$rrdpath/f2bgraph-$rawjail.rrd";
		push @rrdargs, (
			"DEF:$jail-totf=$rrd:totf:LAST",
			"DEF:$jail-mtotf=$rrd:totf:MAX",
			"VDEF:$jail-5=$jail-totf,LAST",
			"VDEF:$jail-6=$jail-totf,MAXIMUM",
			"LINE2:$jail-totf#$color{$cval}:$jail failed",
			'GPRINT:'.$jail.'-5:\: %8.0lf',
			'GPRINT:'.$jail.'-6:Max\: %8.0lf',
		);
		$cval++;
		push @rrdargs, (
			"DEF:$jail-totb=$rrd:totb:LAST",
			"DEF:$jail-mtotb=$rrd:totb:MAX",
			"VDEF:$jail-7=$jail-totb,LAST",
			"VDEF:$jail-8=$jail-totb,MAXIMUM",
			"LINE2:$jail-totb#$color{$cval}:$jail banned",
			'GPRINT:'.$jail.'-7:\: %8.0lf',
			'GPRINT:'.$jail.'-8:Max\: %8.0lf\l',
		);
		$cval++;
	}
	push @rrdargs, ('--vertical-label', 'Total',);
	rrd_graph($range, $file, $ypoints_tot, @rrdargs);
}

sub print_html() {
	$content = <<HEADER;
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>fail2ban statistics for $host</title>
<meta http-equiv="Refresh" content="300" />
<meta http-equiv="Pragma" content="no-cache" />
<style>
*     { margin: 0; padding: 0 }
body  { width: 630px; background-color: white;
	font-family: sans-serif;
	font-size: 12pt;
	margin: 5px }
h1    { margin-top: 20px; margin-bottom: 30px;
        text-align: center }
h2    { background-color: #ddd;
	padding: 2px 0 2px 4px }
hr    { height: 1px;
	border: 0;
	border-top: 1px solid #aaa }
table { border: 0px; width: 100% }
img   { border: 0 }
a     { text-decoration: none; color: #00e }
a:hover  { text-decoration: underline; }
#jump    { margin: 0 0 10px 4px }
#jump li { list-style: none; display: inline;
           font-size: 90%; }
#jump li:after            { content: "|"; }
#jump li:last-child:after { content: ""; }
input[type=submit]   {float: right;}
</style>
</head>
<body>
HEADER

	$content .= "<h1>Fail2Ban statistics for $host</h1>";
	$content .= "<form method=\"post\"><h2>Jail list: ";
	for my $j (@jails) {
		$content .= "<label for=\"$j\"> $j</label><input type=\"checkbox\" name=\"$j-check\"";
		my $checklist = join(',', @checked);
		if ($checklist =~ /$j/) {
			$content .= " checked>";
		} else {
			$content .= " >";
		}
	}
	$content .= '<input type="submit" name="\select\" value="Select">';
	$content .= "</h2></form><br>";
	$content .= "<ul id=\"jump\">";
	for my $n (0..$#graphs) {
		$content .= "  <li><a href=\"#G$n\">$graphs[$n]{title}</a>&nbsp;</li>";
	}
	$content .= "</ul>";
	for my $n (0..$#graphs) {
		$content .=  "<h2 id=\"G$n\">$graphs[$n]{title}</h2>";
		$content .=  "<p><img src=\"$scriptname?${n}-c\" alt=\"f2bgraph\"/><br/>";
		$content .=  "<img src=\"$scriptname?${n}-t\" alt=\"f2bgraph\"/></p>";
	}

	$content .=  <<FOOTER;
<hr/>
<table><tr>
<td>f2bgraph version $version by <a href="https://github.com/starlilyth/f2bgraph-psgi">Lily Star</a></td>
</tr></table>
</body></html>
FOOTER

	return $content;
}

sub send_image($) {
	my ($file)= @_;
	my $size = -s $file;
	open(IMG, $file) or die;
	my $data;
	$content = $data while read(IMG, $data, $size)>0;
	return $content;
}

sub main($$) {
	my ($req_uri, $qry_str) = @_;
	my $uri = $req_uri || '';
	# trim off query strings
	$uri =~ s/\/[^\/]+$//;
	# trim off leading/trailing slash
	$uri =~ s/^\///;
	$uri =~ s/\/$//;
	# change path slashes to dashes
	$uri =~ s/\//-/g;
	# convert tildes to a word
	$uri =~ s/(\~|\%7E)/tilde-/g;
	mkdir $tmp_dir, 0755 unless -d $tmp_dir;
	mkdir "$tmp_dir/$uri", 0755 unless -d "$tmp_dir/$uri";
	if (defined $qry_str and $qry_str =~ /^(\d+)-(c|t)$/) {
		if ($qry_str =~ /^(\d+)-c$/) {
			my $file = "$tmp_dir/$uri/f2bgraph_$1_cur.png";
			graph($graphs[$1]{seconds}, $file);
			send_image($file);
		} elsif ($qry_str =~ /^(\d+)-t$/) {
			my $file = "$tmp_dir/$uri/f2bgraph_$1_tot.png";
			graph_tot($graphs[$1]{seconds}, $file);
			send_image($file);
		}	else {
			die "ERROR: invalid image argument\n";
		}
	}
	else {
		print_html;
	}
}

my $app = sub {
  my $env = shift;
  my $req = Plack::Request->new($env);
  my $req_uri = $req->request_uri;
  my $qry_str = $req->query_string;
  if ($req->method eq "POST") {
		@checked = ();
	  foreach my $jail (@jails) {
		  push @checked, ($jail) if ($req->param("$jail-check"));
		}
	}
	main($req_uri, $qry_str);
  my $res = $req->new_response(200);
  if (defined $qry_str and $qry_str =~ /^(\d+)-(c|t)$/) {
	  $res->content_type('image/png');
  } else {
	  $res->content_type('text/html');
  }
  $res->body($content);
  return $res->finalize;
};
