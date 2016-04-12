# vi: set tabstop=4 expandtab shiftwidth=4:
##############################################################################
package CMS;

=pod

=head1 NAME

CMS - Main FastCGI handler serving CMS pages from a CMS directory

=head1 DESCRIPTION

Full featured page generator.

=cut

use strict;
use warnings;

use Carp;

use parent 'CMS::Handler';
use CMS::Session;
use CMS::Trace qw(funcname);
use CMS::FileHelper qw(getNewestFileDate getDirectoryEntries);

use Authen::Htpasswd;
use File::Path qw(make_path);
use File::Spec;
use Sys::Hostname;
use Sys::Syslog qw(:macros :standard);
use HTML::Template;

##############################################################################

our $VERSION = '0.01';

=head1 CLASS INTERFACE

=head2 Constructor

=over

=item new(...)

Create a new instance of the class.
Additional parameters to the ones accepted by the base class are:

=over

=item * B<CMS_ROOT>:
Root directory of the CMS.

=item * B<CONFIG>:
A hash with config parameters. Is usually filled via the CMS::Config
class via the C<config.yaml> file in the C<CMS_ROOT> directory.

=back

=back

=cut

sub new {
    my $class = shift;
    my $params = shift;

    syslog(LOG_DEBUG, funcname());

    my $self = $class->SUPER::new($params);
    $self->{CONFIG} = $params->{CONFIG} || { };
    $self->{REDIRECT} = undef;        # URL of redirect if enabled
    $self->{PAGE_URI} = undef;
    $self->{PAGE_LANG} = '';
    $self->{CMS_ROOT} = $params->{CMS_ROOT} || '/var/www/cms';
    $self->{CHROOT} = $params->{CHROOT};

    # Check the config and fill in missing defaults
    my $full_path = $self->{CHROOT} || '';
    $full_path .= $self->{CMS_ROOT};
    die "CMS_ROOT does not exist\n" unless (-d $full_path);
    if (!$self->{CONFIG}->{defaults}) {
        $self->{CONFIG}->{defaults} = { };
    }
    if (!$self->{CONFIG}->{defaults}->{language}) {
        $self->{CONFIG}->{defaults}->{language} = 'en';
    }
    if (!$self->{CONFIG}->{defaults}->{page}) {
        $self->{CONFIG}->{defaults}->{page} = 'home';
    }
    if (!$self->{CONFIG}->{hostname}->{plain}) {
        $self->{CONFIG}->{hostname}->{plain} = hostname();
    }
    if (!$self->{CONFIG}->{hostname}->{ssl}) {
        $self->{CONFIG}->{hostname}->{ssl}
            = $self->{CONFIG}->{hostname}->{plain};
    }
    if (!$self->{CONFIG}->{url}->{images}) {
        $self->{CONFIG}->{url}->{images} = '/images/';
    }
    if (!$self->{CONFIG}->{session}) {
        $self->{CONFIG}->{session} = { };
    }
    if (!$self->{CONFIG}->{session}->{path}) {
        $self->{CONFIG}->{session}->{path} = '/tmp/sessions';
    }
    if (!$self->{CONFIG}->{session}->{cookiedomain}) {
        $self->{CONFIG}->{session}->{cookiedomain}
            = '.' . $self->{CONFIG}->{hostname}->{ssl};
    }
    if (!$self->{CONFIG}->{userdb}) {
        $self->{CONFIG}->{userdb} = $self->{CMS_ROOT} . '/user.db';
    }
    elsif ($self->{CONFIG}->{userdb} !~ /^\//x) {
        # Relative path, prepend it with the CMS_ROOT
        $self->{CONFIG}->{userdb} = $self->{CMS_ROOT} . '/'
            . $self->{CONFIG}->{userdb};
    }

    $self->{CONTENT_DIR} = $self->{CMS_ROOT} . '/content/';
    $self->{TEMPLATE_DIR} = $self->{CMS_ROOT} . '/templates/';

    bless($self, $class);
    return $self;
}


=head2 Member Functions

=over

=item handler($req, $params)

Request handler, will setup the base class by calling the SUPER handler
function. Parses optional parameters from POST and GET requests and tries
to build a page from the B<CMS_ROOT> directory and the query path.

=cut

sub handler {
    my $self = shift;
    my $req = shift;
    my $params = shift;

    syslog(LOG_DEBUG, funcname());

    # Setup in- and outputs via the SUPER class if handling a FCGI request
    $self->SUPER::handler($req, $params) if ($req);

    $self->{HTTPS} = $ENV{'HTTPS'};

    my $fail = not eval {
        $self->parse_params();
        $self->fetch();
        return 1;
    };
    if ($fail) {
        syslog(LOG_ERR, 'CMS::handler(): Unable to fetch page. ' . $@);
        # XXX Render error page
        $self->{STATUS} = '500 Internal Server Error';
        $self->{BODY} = '$@';
        $self->add_header('Content-type', 'plain/text');
    }
    return;
}


=item fetch()

Fetches the page.

=cut

sub fetch {
    my $self = shift;

    syslog(LOG_DEBUG, funcname());

    # Set defaults
    $self->{PAGE_LANG} = $self->{CONFIG}->{defaults}->{language};

    # Retrieve the last part of the URI, to translate the path to the CMS
    # structure
    my $page = $ENV{'DOCUMENT_URI'} || '/index.html';
    my $req_uri = $page;
    $req_uri =~ s/\/[^\/]+$//x;
    $self->{REQUEST_PATH} = $req_uri;
    $page =~ s/^.*\///x;
    $self->{PAGE_URI} = $page;

    # Show the default page if the index.html page is requested
    if ($page eq 'index.html') {
        $page = $self->{CONFIG}->{defaults}->{page}
            . '_' . $self->{CONFIG}->{defaults}->{language} . '.html';
        $self->{PAGE_URI} = $page; # So that we don't generate a redirect
    }

    # The language is embedded in the last part of the page e.g. "_en.html"
    my $lang = $page;
    if ($lang =~ s/^.*_(..)\.html$/$1/x) {
        $self->{PAGE_LANG} = $lang;
    }

    # Split off the part with the language and the suffix to get the
    # page name
    $page =~ s/(_..)?\.html$//x;
    $self->{PAGE} = $page;

    # Try to set the language, or set the default language if nothing matches
    $self->set_language();

    # Create the response body from the template
    $self->create_document();
    return;
}


=item set_language()

The function checks the previously set C<$self-E<gt>{PAGE_LANG}> member
variable for an existing directory if defined. If it is not defined or
the directory is not set the HTTP_ACCEPT_LANGUAGE header will be used
to find an acceptable language.

=cut

sub set_language {
    my $self = shift;

    syslog(LOG_DEBUG, funcname());
    
    my $lang = $self->{PAGE_LANG};
    $lang = undef if (! -d $self->{CONTENT_DIR} . $lang);

    if (not defined $lang) {
        my $accept_lang = $ENV{'HTTP_ACCEPT_LANGUAGE'};
        if ($accept_lang) {
            my @languages = split ',', $accept_lang;

            foreach (@languages) {
                s/;.*//gx;
                s/-.*//gx;
                if (-d $self->{CONTENT_DIR} . $_) {
                    $lang = $_;
                    last;
                }
            }
        }
        $lang = $self->{CONFIG}->{defaults}->{language} unless $lang;
    }

    # Now we should have a language, die if the language directory does
    # not exist
    die 'No content found: ' . "$self->{CONTENT_DIR}\n"
        unless (-d $self->{CONTENT_DIR} . $lang);

    $self->{PAGE_LANG} = $lang;
    return;
}


=item create_document()

Puts everything together.
At the end a filled in page body is stored in C<$self-E<gt>{BODY}>.

=cut

sub create_document {
    my $self = shift;

    syslog(LOG_DEBUG, funcname());
    
    # Read all available language directories
    my @languages = sort (getDirectoryEntries($self->{CONTENT_DIR}));

    # Check if the page exists, if not set the status to 404 and return
    my $page_dir = $self->{CONTENT_DIR} . $self->{PAGE_LANG} . '/'
        . $self->{PAGE};
    my $page_uri = $self->{PAGE} . '_' . $self->{PAGE_LANG} . '.html';
    if ((! -d $page_dir) || ($page_uri ne $self->{PAGE_URI})) {
        $self->{STATUS} = '404 Not Found';
        $self->{BODY} = '';
        return;
    }

    # Redirect if we require SSL view of the page
    my $need_ssl_file = $page_dir . '/SSL';
    if (-e $need_ssl_file && !($self->{HTTPS})) {
        my $hostname_ssl = $self->{CONFIG}->{hostname}->{ssl};
        my $path = $self->{REQUEST_PATH};
        $path =~ s/^\/+//x;
        $self->{REDIRECT} = 'https://' . $hostname_ssl . '/' 
            . $path . '/' . $page_uri;
        return;
    }
    
    # Create the content array
    my @topics = sort 
        (getDirectoryEntries($self->{CONTENT_DIR} . $self->{PAGE_LANG}));

    # Create links to other languages
    my @languagelinks;
    foreach (@languages) {
        if ((-e $self->{CONTENT_DIR} . $_)
                && ($_ ne '.') && ($_ ne '..')) {
            my %language_data;
            my $link = '<a href="' . $self->{REQUEST_PATH} . '/' 
                . $self->{PAGE} . '_' . $_ . '.html"><img src="'
                . $self->{CONFIG}->{url}->{images} . 'flag_' . $_ . '.png"'
                . ' alt="' . $_ . '"/></a>';
            $language_data{LANGUAGE_LINK} = $link;
            push @languagelinks, \%language_data;
        }
    }

    # Read the template for the page
    my $template = HTML::Template->new(
        filename => 'page.tmpl',
        path     => [ $self->{TEMPLATE_DIR} ],
        cache    => 1,
    );
    croak 'Unable to load template file from directory ' . $self->{TEMPLATE_DIR}
        unless $template;

    # Fill in the language variable
    $template->param(LANGUAGE => $self->{PAGE_LANG});

    # Fetch the session, if there is one
    $self->fetch_session();

    # Remove the session if we are to log out
    my $action = $self->{PARAMS}->{action};
    if ($action && ($action eq 'logout')) {
        $self->destroy_session();
    }

    # Read all the CMS files that will create the page
    my $title_file = $page_dir . '/TITLE';
    if (-e $title_file) {
        $template->param(TITLE => $self->read_file($title_file));
    }

    my $descr_file = $page_dir . '/DESCR';
    if (-e $descr_file) {
        $template->param(DESCR => $self->read_file($descr_file));
    }

    my $style_file = $page_dir . '/STYLE';
    if (-e  $style_file) {
        $template->param(STYLE => $self->read_file($style_file));
    }

    my $script_file = $page_dir . '/SCRIPT';
    if (-e $script_file) {
        $template->param(SCRIPT => $self->read_file($script_file));
    }

    my $login_file = $page_dir . '/LOGIN';
    my $content_file = $page_dir . '/CONTENT';

    # Replace the content with the login page, so that we can authenticate
    # the user if the page requires a login and we have not authenticated
    # via the session
    if (-e $login_file) {
        # Do the session and log on magic
        $self->create_session() unless $self->{SESSION};
        my $session = $self->{SESSION};
        my $userdb = Authen::Htpasswd->new($self->{CONFIG}->{userdb});

        # Get the username and password from the POST or GET data
        my $username = $self->{PARAMS}->{username} || '';
        my $password = $self->{PARAMS}->{password} || '';

        if ($username eq '') {
            if ($session && $session->get('loggedin')) {
                if ($session->get('loggedin') != 1) {
                    $session->set('loggedin', 0);
                    $content_file = $login_file;
                }
            }
            else {
                $content_file = $login_file;
            }
        }
        elsif (! $userdb->lookup_user($username)) {
            $content_file = $login_file;
            $session->set('loggedin', 0);
        }
        elsif (! $userdb->check_user_password($username, $password)) {
            $content_file = $login_file;
            $session->set('loggedin', 0);
        }
        else {
            $session->set('username', $username);
            $session->set('loggedin', 1);
        }
    }

    if (-e $content_file) {
        # Parse the content file as a template, so that we can include files
        my $content = HTML::Template->new(
            filename => $content_file,
            cache    => 0,
        );
        die 'Unable to include template file "' . $content_file . '"' . "\n"
            unless $content;

        if ($content->query(name => 'CURRENT_PAGE')) {
            $content->param(CURRENT_PAGE => $page_uri);
        }
        $template->param(CONTENT => $content->output());
    }
    else {
        die 'No content file available for page "' . $self->{PAGE}
            . '" and language "' . $self->{PAGE_LANG} . '"' . "\n";
    }

    # Create links
    my @templinks = $self->create_links(\@topics, 1);
    my @links = sort { $a->{NR} <=> $b->{NR} } @templinks;

    $template->param(LINK_LOOP => \@links);
    $template->param(LANGUAGE_LINKS => \@languagelinks);

    # Add helpful header
    $self->add_header('Content-Language', $self->{PAGE_LANG})
        if $self->{PAGE_LANG};

    # Create the (X)HTML payload
    $self->{BODY} = $template->output();

    my $lastchange = getNewestFileDate($page_dir);
    $self->add_header('Last-Modified', $lastchange) if $lastchange;
    return;
}


=item render()

Page renderer. Will set the header for the optional cookie if available and
either redirect if C<$self-E<gt>{REDIRECT}> is defined or output the page
from C<$self-E<gt>{BODY}>.

=cut

sub render {
    my $self = shift;

    syslog(LOG_DEBUG, funcname());
    
    # Handle Cookies
    $self->set_session_cookie();

    # Handle Redirects
    return $self->redirect($self->{REDIRECT}) if ($self->{REDIRECT});

    # Handle MSIE document type
    my $ua = $ENV{'HTTP_USER_AGENT'};
    if ($ua && ($ua !~ /MSIE/)) {
        $self->add_header('Content-type', 'application/xhtml+xml');
    }
    else {
        $self->add_header('Content-type', 'text/html');
    }

    return $self->SUPER::render();
}


=item read_file($filename)

Reads a whole file into a scalar and returns the scalar. If opening the file
fails the function will die.

=cut

sub read_file {
    my $self = shift;
    my $filename = shift;
 
    syslog(LOG_DEBUG, funcname());
 
    my $content;

    if (open(my $fh, '<', $filename)) {
        local $/ = undef;
        $content = <$fh>;
        close($fh);
    }
    else {
        die('Unable to open file "' . $filename . '": ' . $! . "\n");
    }

    return $content;
}


=item create_links($topics, $sublevel) 

Creates a link structure from the content directory layout

=cut

sub create_links {
    my $self = shift;
    my $topics = shift;
    my $sublevel = shift;

    syslog(LOG_DEBUG, funcname());
 
    my $lang = $self->{PAGE_LANG};
    my $page = $self->{PAGE};

    my (@templinks, @subpages);

    while (@$topics) {
        my %link_data;
        my $topic = shift @$topics;

        # Create the filenames from the topic
        my $topic_dir = $self->{CONTENT_DIR} . $lang . '/' . $topic;
        my $link_file = $topic_dir . '/LINK';
        my $sort_file = $topic_dir . '/SORT';
        my $sub_file = $topic_dir . '/SUB';
        my $ssl_file = $topic_dir . '/SSL';

        if ((-e $link_file) && (-e $sort_file)) {
            # Read the title and the sort order from the files
            my $title = $self->read_file($link_file);
            my $nr    = $self->read_file($sort_file);

            # Check if this link is a sub link to another
            $link_data{SUB} = (-e $sub_file);

            # Create the link
            my $link = $self->{REQUEST_PATH} . '/' . $topic . '_' . $lang
                . '.html';
            if ($self->{HTTPS} || (-e $ssl_file)) {
                $link =~ s/^\///x;
                $link = 'https://' . $self->{CONFIG}->{hostname}->{ssl} . '/' 
                    . $link;
            }
            $link_data{LINK} = '<a href="' . $link . '">' . $title . '</a>';
            $link_data{JSLINK} = 'onclick="javascript:location.replace(\''
                . $link . '\')"';
            $link_data{NR} = $nr;

            if ($topic eq $page) {
                # Mark the page as selected
                $link_data{SELECTED} = 1;

                # If selected, show all sub pages
                my $subpagesdir = $topic_dir . '/SUBPAGES';
                if (-d $subpagesdir) {
                    if (opendir(my $dh, $subpagesdir)) {
                        @subpages = sort readdir($dh);
                        closedir($dh);
                    }
                    else {
                        syslog(LOG_ERR, 'CMS::create_links(): Unable to open '
                            . 'SUBPAGES directory: ' . $subpagesdir);
                    }
                    push @templinks,
                         $self->create_links(\@subpages, $sublevel + 1);
                }
            }
            else {
                $link_data{SELECTED} = 0;
            }

            push @templinks, \%link_data;
        }
    }

    # Remove sublinks, that are not in the selection scope
    my @newlinks = ();
    my $lastrootmenu = 0;
    my $submenu_selected = undef;
    my $i = 0;

    while (defined $templinks[$i]) {
        if (! defined $templinks[$i]->{SUB}) {
            push @newlinks, $templinks[$i];
            $lastrootmenu = $i;
            $submenu_selected = $templinks[$i]->{SELECTED};
        }
        else {
            if ($submenu_selected) {
                push @newlinks, $templinks[$i];
            }
            else {
                # Check if the submenu is selected
                if ($templinks[$i]->{SELECTED}) {
                    # Copy from $submenu_selected to here
                    while ($lastrootmenu < $i) {
                        push @newlinks, $templinks[++$lastrootmenu];
                    }
                    # Mark as selected
                    $submenu_selected = 1;
                }
            }
        }
        $i++;
    }

    # Add a logout link if we have a valid login session
    if ($self->{SESSION} && $self->{SESSION}->get('loggedin')
            && ($self->{SESSION}->get('loggedin') == 1) && ($sublevel == 1)) {
        my $logout_link = $self->{PAGE_URI} . '?action=logout';
        push @newlinks, {
            SUB      => 0,
            SELECTED => 0,
            LINK     => '<a href="' . $logout_link . '">Logout</a>',
            JSLINK   => 'onclick="javascript:location.replace(\''
                . $logout_link . '\')"',
            NR       => 1000,
        };
    }

    return @newlinks;
}


1;

__END__

=back

