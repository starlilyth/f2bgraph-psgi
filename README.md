# f2bgraph
fail2ban graphing

f2bgraph is a simple statistics RRDtool frontend for fail2ban that produces daily, weekly, monthly and yearly graphs for all configured fail2ban jails.

It is based on mailgraph by David Schweikert <david@schweikert.ch>, and functions similarly.

Required Modules
----------------

- rrdtool and it's perl module (RRDs) -> http://oss.oetiker.ch/rrdtool/

- Plack::Request

Note that several Linux distributions will already have these modules as packages (e.g. 'perl-Plack').

Usage
-----

f2bgraph is made of two scripts:

- f2bgraph.pl

  This script polls 'fail2ban-client' and updates RRD databases in /var/log.

  Use & to put it in the background if you start it from a shell, or start it from systemd using the sample service file.

  usage: f2bgraph.pl [*options*]
```
  -h, --help         display this help and exit
  -v, --verbose      be verbose about what you do
  -V, --version      output version information and exit
```

- f2bgraph.psgi

  This is a standalone psgi app that generates graphics from the RRD database and writes the HTML page.

  Change $rrdpath to point to where the RRD databases are if you are not using the default location.

Installation
------------

See the file f2bgraph.service for an example systemd script that you can use to start f2bgraph.pl at system boot.

You can serve f2bgraph.psgi to a web server with an app server like Nginx Unit, Starman, or just plackup. See README-PSGI for more details.

