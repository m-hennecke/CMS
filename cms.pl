#! /usr/bin/perl
# vi: set tabstop=4 expandtab shiftwidth=4:
##############################################################################

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Sys::Syslog qw(:standard :macros);

use CMS::FCGI;
use CMS;
use CMS::Daemon qw(daemonize);
use CMS::Config;

##############################################################################

# Parameters
my $hostname = undef;
my $cms_root = '/var/www/cms';
my $listen_addr = 'localhost';
my $listen_port = undef;
my $help = undef;
my $daemon = 1;
my $verbose = 4; # Log up to LOG_WARNING as default
my $user = 'nobody';
my $chroot;

GetOptions(
    'host|h=s'     => \$listen_addr,
    'port|p=i'     => \$listen_port,
    'cms-root|r=s' => \$cms_root,
    'help|?'       => \$help,
    'daemon!'      => \$daemon,
    'chroot|c=s'   => \$chroot,
    'verbose|v+'   => \$verbose,
    'D'            => sub { $daemon = undef },
) || pod2usage(2);
pod2usage(1) if ($help);

my @loglevels = ( LOG_EMERG, LOG_ALERT, LOG_CRIT, LOG_ERR, LOG_WARNING,
    LOG_NOTICE, LOG_INFO, LOG_DEBUG );
$verbose = scalar @loglevels if ($verbose >= scalar @loglevels);
openlog('CMS', 'nofatal,ndelay,pid', LOG_DAEMON);
setlogmask(LOG_UPTO($loglevels[$verbose]));

##############################################################################

my $cms_config = new CMS::Config(CMS_ROOT => $cms_root);

my $cms_handler = new CMS(
        CMS_ROOT    => $cms_root,
        CONFIG      => $cms_config->config(),
    );

my $fcgi_handler = new CMS::FCGI(
        HANDLER     => $cms_handler,
        PORT        => $listen_port,
        HOST        => $listen_addr,
    );

$0 = 'CMS: master process ' . $cms_root;

daemonize() if ($daemon);

$fcgi_handler->main(
    'runas'       => $user,
    'chroot'      => $chroot,
    'processname' => 'CMS: slave process ' . $cms_root,
);

__END__

=head1 NAME

Google sitemap.xml generator for the CMS system

=head1 SYNOPSIS

Sitemap.pl [options]

 Options:
   --help              brief help message
   --hostname          hostname for link generation
   --cms-root          root of the CMS data directory
   --host              listen address for the FCGI TCP listener
   --port              listen port for the FCGI TCP listener
   --nodaemon          don't daemonize

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exits.

=item B<--hostname>

Hostname used for link generation. If not specified the result of hostname()
will be used.

=item B<--cms-root>

Root directory of the CMS data. Defaults to /var/www/cms

=item B<--host>

Listen address of the FCGI TCP listener. The B<--port> option is required to
enable the TCP listener.

=item B<--port>

Port the TCP listener should use.

=item B<--nodaemon>

Stay on the terminal after start, don't daemonize.

=back

=head1 DESCRIPTION

B<Sitemap.pl> will read the contents of the CMS data directory and generate
a link list with the time of the last change to one of the linked pages in
the google sitemap format.

=cut

