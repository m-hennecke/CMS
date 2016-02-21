# ABSTRACT: Base class for a content request handler
# vi: set expandtab shiftwidth=4:
##############################################################################
package CMS::Handler;

=pod

=head1 NAME

CMS::Handler - Base class for HTTP handler for CGI or FastCGI usage.

=head1 DESCRIPTION

Base class for FCGI handlers.

=cut

use strict;
use warnings;

use CMS::Trace qw(funcname);
use Sys::Syslog qw(:macros :standard);

##############################################################################

=head1 CLASS INTERFACE

=head2 Constructor

=over

=item new(...)

Create a new instance of this class.
Additional parameters are:

=over

=item * B<IN>:
Input file handle, defaults to STDIN

=item * B<OUT>:
Output file handle, defaults to STDIN

=item * B<ERR>:
Error file handle, defaults to STDERR

=back

=back

=cut

sub new {
    my $class = shift;
    my %params = @_;

    syslog(LOG_DEBUG, funcname());

    my $self = {
        HEADER         => { },
        REQUEST_HEADER => { },
        BODY           => '',
        STATUS         => '200 OK',
        STDIN          => $params{IN}  || *STDIN,
        STDOUT         => $params{OUT} || *STDOUT,
        STDERR         => $params{ERR} || *STDERR,
    };

    bless($self, $class);
}

=head2 Member Functions

=over

=item handler($req, $params)

Request handler, will set the STDIN, STDOUT and STDERR file handles from the
request. This base implementation does nothing. It is recommended to call
this function via the SUPER class in derived objects.

=cut

sub handler {
    my $self = shift;
    my $req = shift;
    my $params = shift;

    syslog(LOG_DEBUG, funcname());

    my ($in, $out, $err) = $$req->GetHandles();
    $self->{STDIN} = $in;
    $self->{STDOUT} = $out;
    $self->{STDERR} = $err;

    $self->{REQUEST_TYPE} = undef;
    $self->{PARAMS} = { };

    #$self->get_request_header();
    #$self->parse_params();
}


=item render()

Renders the request result, that means it will print out the headers and
the body to the C<$self-E<gt>{STDOUT}> file handle.

=cut

sub render {
    my $self = shift;
    my $out = $self->{STDOUT};

    syslog(LOG_DEBUG, funcname());

    use bytes;

    $self->add_header('Content-type', 'text/plain') 
      unless exists $self->{HEADER}->{'Content-type'};
    $self->add_header('Content-length', length($self->{BODY}));

    print $out 'Status: ' . $self->{STATUS} . "\r\n";
    foreach my $headerkey (keys %{$self->{HEADER}}) {
        print $out $headerkey . ': ' . $self->{HEADER}->{$headerkey} . "\r\n";
    }
    print $out "\r\n";

    my $method = $ENV{'REQUEST_METHOD'};
    print $out $self->{BODY} unless ($method eq 'HEAD');
}


=item add_header($key, $value)

Adds an header entry, that will be put out when the render() function is
called.

=cut

sub add_header {
    my $self = shift;
    my $key = shift;
    my $value = shift;

    $self->{HEADER}->{$key} = $value;
}


=item get_request_header()

Sets up the C<$self-E<gt>{REQUEST_HEADER}> hash. This function is called from
the handler() function.

=cut

sub get_request_header {
    my $self = shift;

    syslog(LOG_DEBUG, funcname());

    my %header = map { $_ =~ /^HTTP(?:_|$)/ ? ($_, $ENV{$_}) : () } keys %ENV;
    $self->{REQUEST_HEADER} = \%header;
    return $self->{REQUEST_HEADER};
}


=item parse_params()

Reads in the POST/GET parameters either from C<$ENV{'QUERY_STRING'}> or from
C<$self-E<gt>{IN}> and fills the C<$self-E<gt>{PARAMS}> hash with the input
data.

=cut

sub parse_params {
    my $self = shift;

    syslog(LOG_DEBUG, funcname());

    my @variables = ();
    my %params = ();
    my $method = $ENV{'REQUEST_METHOD'};

    return unless $method;

    if (($method eq 'GET') || ($method eq 'HEAD')) {
        @variables = split(/&/, $ENV{'QUERY_STRING'});
    }
    elsif ($method eq 'POST') {
        read($self->{STDIN}, my $pdata, $ENV{'CONTENT_LENGTH'});
        @variables = split(/&/, $pdata);

        if ($ENV{'QUERY_STRING'}) {
            my @getvariables = split(/&/, $ENV{'QUERY_STRING'});
            push @variables, @getvariables;
        }
    }
    else {
        syslog(LOG_WARNING, 'Unknown request method: ' . $method);
        return;
    }

    foreach my $var (@variables) {
        next unless ($var && ($var =~ /\=/));
        my ($name, $value) = split(/\=/, $var);

        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;

        $value =~ s/<!--(.|\n)*-->//g;

        if ($params{$name}) {
            $params{$name} .= "\0$value";
        }
        else {
            $params{$name} = $value;
        }
    }

    $self->{PARAMS} = \%params;
}


=item redirect($url)

Sends a redirect response. Either status code 302 for HTTP/1.0 requests or
status code 307 for HTTP/1.1 requests are send. The body is empty.
Note: This function will call C<$self-E<gt>render()>, there must not be any
further output.

=cut

sub redirect {
    my $self = shift;
    my $url = shift;

    syslog(LOG_DEBUG, funcname());
 
    $self->add_header('Location', $url);
    # Set status to 302 if HTTP/1.0 or 307 if HTTP/1.1
    if ($ENV{'SERVER_PROTOCOL'} eq 'HTTP/1.0') {
        $self->{STATUS} = '302 Found';
    }
    else {
        $self->{STATUS} = '307 Temporary Redirect';
    }
    $self->{BODY} = '';
    return $self->CMS::Handler::render();
}


1;

__END__

=back

