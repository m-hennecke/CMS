#! /usr/bin/perl
# vi: set tabstop=4 expandtab shiftwidth=4:
##############################################################################

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Sys::Syslog qw(:standard :macros);

use CMS::FCGI;
use CMS::Sitemap;
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
my $user = 'nobody';
my $chroot;

GetOptions(
    'host|h=s'     => \$listen_addr,
    'port|p=i'     => \$listen_port,
    'cms-root|r=s' => \$cms_root,
    'help|?'       => \$help,
    'daemon!'      => \$daemon,
    'chroot|c=s'   => \$chroot,
    'D'            => sub { $daemon = undef },
) || pod2usage(2);
pod2usage(1) if ($help);

##############################################################################

my $cms_config = CMS::Config->new({CMS_ROOT => $cms_root});

my $sitemap_handler = CMS::Sitemap->new({
        CMS_ROOT    => $cms_root,
        HOSTNAME    => $cms_config->config()->{hostname}->{plain},
        SSLHOSTNAME => $cms_config->config()->{hostname}->{ssl},
    });

my $fcgi_handler = CMS::FCGI->new({
        HANDLER     => $sitemap_handler,
        PORT        => $listen_port,
        HOST        => $listen_addr,
    });

$0 = 'Sitemap: master process ' . $cms_root;

daemonize() if ($daemon);

openlog('Sitemap', 'nofatal,ndelay,pid', LOG_DAEMON);

$fcgi_handler->main({
    'runas'       => $user,
    'chroot'      => $chroot,
    'processname' => 'Sitemap: slave process ' . $cms_root,
});

__END__

=pod

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
   --nodaemon          don't daemonize, -D is an alias for this option
   --chroot            chroot into the given directory

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exits.

=item B<--cms-root>

Root directory of the CMS data. Defaults to /var/www/cms

=item B<--host>

Listen address of the FCGI TCP listener. The B<--port> option is required to
enable the TCP listener.

=item B<--port>

Port the TCP listener should use.

=item B<--nodaemon>

Stay on the terminal after start, don't daemonize.

=item B<--chroot>

Change the root directory upon start. Note that the path of B<--cms-root> has
to be relative to this directory.

=back

=head1 DESCRIPTION

B<Sitemap.pl> will read the contents of the CMS data directory and generate
a link list with the time of the last change to one of the linked pages in
the google sitemap format.

=cut

