# ABSTRACT: Google Sitemap related code
# vi: set expandtab shiftwidth=4:
#############################################################################
package CMS::Sitemap;

=pod

=head1 NAME

CMS::Sitemap - Class that is capable of generating a google sitemap from
the CMS directory

=head1 DESCRIPTION

The handler of this CGI class reads all the files from the CMS directory
and generates a list of files with the date of the last modification. This
is put into a XML suitable for google sitemap service.

=cut

use strict;
use warnings;

use parent 'CMS::Handler';
use CMS::Trace qw(funcname);
use CMS::FileHelper qw(getNewestFileDate getDirectoryEntries);

use Sys::Hostname;
use Sys::Syslog qw(:macros :standard);
use Compress::Zlib;

=head1 CLASS INTERFACE

=head2 Constructor

=over

=item new()

Create a new instance of this class.
Additional parameters to the parameters passed to the ctor of CMS::Handler
are:

=over

=item * B<CMS_ROOT>:
Root directory of the CMS

=item * B<HOSTNAME>:
Hostname used in the generated links. Default uses L<hostname()|hostname>

=back

=back

=cut

sub new {
    my $class = shift;
    my $params = shift;

    syslog(LOG_DEBUG, funcname());

    my $self = $class->SUPER::new($params);
    $self->{CMS_ROOT} = $params->{CMS_ROOT} || '/var/www/cms';
    $self->{CHROOT} = $params->{CHROOT};
    $self->{HOSTNAME} = $params->{HOSTNAME} || hostname();
    $self->{SSLHOSTNAME} = $params->{SSLHOSTNAME} || $self->{HOSTNAME};

    my $full_path = $self->{CHROOT} || '';
    $full_path .= $self->{CMS_ROOT};
    die "CMS_ROOT $self->{CMS_ROOT} does not exist.\n" unless (-d $full_path);

    # Remove the trailing slash from the CMS_ROOT if present
    $self->{CMS_ROOT} =~ s/\/$//x;

    $self->{GZIP_DONE} = undef;

    bless($self, $class);
    return $self;
}


=head2 Member Functions

=over

=item handler($req, $params)

See L<CMS::Handler|CMS::Handler> for SUPER functions behaviour.
Creates the XML suitable for google sitemap service without zipping it and
stores the result in the C<< $self->{BODY} >> member variable.

=cut

sub handler {
    my $self = shift;
    my $req = shift;
    my $params = shift;

    syslog(LOG_DEBUG, funcname());

    # Setup input and outputs via the SUPER class if we are handling a FCGI
    # request
    $self->SUPER::handler($req, $params) if ($req);

    my $content_dir = $self->{CMS_ROOT} . '/content/';
    my @languages = getDirectoryEntries($content_dir);
    my $xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n"
        . '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
        . 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        . 'xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9'
        . "\n" . 'http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd">'
        . "\n";

    foreach my $language (@languages) {
        my $directory = $content_dir . $language;
        my @pages = getDirectoryEntries($directory);

        foreach my $page (@pages) {
            my $url = 'http';
            my $ssl = $content_dir . '/' . $language . '/' . $page . '/SSL';
            if (-e $ssl) {
                $url .= 's://' . $self->{SSLHOSTNAME};
            }
            else {
                $url .= '://' . $self->{HOSTNAME};
            }
            $url .= '/' . $page . '_' . $language . '.html';
    
            $xml .= ' <url>' . "\n";
            $xml .= '  <loc>' . $url . '</loc>' . "\n";
            $xml .= '  <lastmod>' 
                . getNewestFileDate($directory . '/' . $page) 
                . '</lastmod>' . "\n";
            $xml .= ' </url>' . "\n";
        }
    }

    $xml .= '</urlset>' . "\n";
    $self->{BODY} = $xml;
    $self->{GZIP_DONE} = undef;
    return;
}


=item render()

Renders the page, in our case it will create a gzipped xml file. The output
is done via the SUPER::render() function.

=cut

sub render {
    my $self = shift;

    syslog(LOG_DEBUG, funcname());

    if (! $self->{GZIP_DONE}) {
        my $gzip_xml = Compress::Zlib::memGzip($self->{BODY});
        $self->{BODY} = $gzip_xml;
        $self->add_header('Content-type', 'application/xml');
        $self->add_header('Content-encoding', 'x-gzip');
        $self->{GZIP_DONE} = 1;
    }

    $self->SUPER::render();
    return;
}


1;

__END__

=back

