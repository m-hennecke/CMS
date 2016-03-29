# ABSTRACT: Fast CGI request handler
# vi: set tabstop=4 expandtab shiftwidth=4:
##############################################################################
package CMS::FCGI;

=pod

=head1 NAME

CMS::FCGI - Class encapsulating the FCGI communication via TCP or file handles

=head1 DESCRIPTION

The class provides a main() routine, which will accept FCGI requests, fork
a child that handles the request via a class derived from CMS::Handler in a
loop.
The loop may be interrupted either by sending either USR1 or TERM to the
process executing the loop.

=cut

use strict;
use warnings;

use FCGI;
use IO::Handle;
use POSIX qw(setsid :sys_wait_h);
use Sys::Syslog qw(:macros :standard);

use CMS::Daemon qw(drop_privileges change_root);
use CMS::Handler;

=head1 Class Interface ctor/dtor

=over

=item new

Create a new instance of this class.
Parameters:

=over

=item *

HANDLER: An instance derived from CMS::Handler

=item *

HOST: The listening host if FCGI is used over TCP, default is 'localhost'

=item *

PORT: When specified FCGI will use TCP for communication.

=back

=back

=cut 

sub new {
    my $class = shift;
    my $params = shift;

    my $self = {
        HANDLER      => $params->{HANDLER} || CMS::Handler->new(),
        SOCKET       => undef,
        HOST         => $params->{HOST} || 'localhost',
        PORT         => $params->{PORT},
        LAST_REQUEST => 0,
        BUSY         => 0,
        FORKS        => { },
    };

    bless($self, $class);
    return $self;
}


=head1 Member Functions

=over

=cut

# TERM handler
sub _handleTERM {
    my $self = shift;

    $self->{LAST_REQUEST} = 1;
    syslog(LOG_INFO, 'Caught signal, terminating...');
    return;
}


# CHLD handler
sub _REAPER {
    my $self = shift;
    while ((my $wpid = waitpid(-1, &WNOHANG)) > 0) {
        my $req = $self->{FORKS}->{$wpid};
        if ($req) {
            # We need to finish the request here, so that the connection is
            # closed
            $req->Attach();
            $req->Finish();
            delete $self->{FORKS}->{$wpid};
        }
    }
    $self->set_reaper();
    return;
}


=item set_reaper()

Sets the CHLD signal handler so that our reaper function is called.

=cut

sub set_reaper {
    my $self = shift;
    $SIG{CHLD} = sub { $self->_REAPER(); };
    return;
}


=item set_signal_handlers()

Sets the signal handlers so that TERM and USR1 are handled correclty.

=cut

sub set_signal_handlers {
    my $self = shift;
    $SIG{TERM} = sub { $self->_handleTERM(); };
    $SIG{USR1} = sub { $self->_handleTERM(); };
    $SIG{CHLD} = 'IGNORE';
    $SIG{PIPE} = 'IGNORE';
    $SIG{__WARN__} = sub {
        my @loc = caller(1);
        syslog(LOG_WARNING, $_[0] . ' at line ' . $loc[2] . ' in ' . $loc[1]);
        return 1;
    };
    $SIG{__DIE__} = sub {
        die @_ if $^S;

        my @loc = caller(1);
        syslog(LOG_ERR, 'Died with ' . $_[0] . ' at line ' . $loc[2] 
            . ' in ' . $loc[1]);
        die @_;
    };
    return;
}


=item handle_request($req)

Request handler.

=cut

sub handle_request {
    my $self = shift;
    my $req = shift;
    my $result = undef;

    eval {
        local $SIG{__DIE__};
        $self->{HANDLER}->handler($req);
        $self->{HANDLER}->render();
    };
    if ($@) {
        # Log the error
        syslog(LOG_ERR, 'CMS::FCGI::handle_request(): ' . $@);
    }
    return;
}


=item main()

Main loop for the FCGI handler. Will accept connections in a loop and fork
the handler to process the request.

=cut

sub main {
    my $self = shift;
    my $params = shift;

    # Flush the output buffer after each write operation
    $| = 1;

    # Create a socket if a port is given
    if (defined $self->{PORT}) {
        my $host = $self->{HOST};
        my $port = $self->{PORT};
        $self->{SOCKET} = FCGI::OpenSocket("$host:$port", 5);
    }

    # Drop privileges
    drop_privileges($params->{'runas'}, $params->{'chroot'});

    # Overwrite the DESTROY() sub routine of the request object to avoid a
    # race condition when the parent is destroying the request before the
    # child handler has finished it. This means calling Finish() is mandatory
    # in the child process.
    {
        ## no critic
        no warnings qw( redefine );
        *FCGI::DESTROY = sub { };
        ## use critic
    }

    my $request_factory = sub {
        my $in = IO::Handle->new();
        my $out = IO::Handle->new();
        my $err = IO::Handle->new();
        return FCGI::Request(
                $in, $out, $err, \%ENV,
                $self->{SOCKET} || 0, &FCGI::FAIL_ACCEPT_ON_INTR()
            );
    };
    
    $self->{BUSY} = 0;
    my $req = $request_factory->();

    $self->set_signal_handlers();
    $self->set_reaper();
    my $retry = 0;

    syslog(LOG_INFO, 'Entering main request loop...');

RETRY:
    while ($self->{BUSY} = ($req->Accept() >= 0)) {

        # Detach for the fork
        $req->Detach();

        my $pid = fork();
        if (!defined($pid)) {
            if ($params->{'processname'}) {
                $0 = $params->{'processname'};
            }
            $req->Attach();
            my ($in, $out, $err) = $req->GetHandles();
            my $crlf = "\r\n";
            print $out 'Status: 503 Service Unavailable' . $crlf;
            print $out 'Retry-After: 120' . $crlf;
            print $out $crlf;
            $req->Finish();
        }
        elsif ($pid == 0) {
            # Child

            local $SIG{CHLD} = 'IGNORE';
            setsid();
            $req->Attach();
            $req->LastCall();
            $self->handle_request(\$req);
            $req->Finish();
            # Cleanup the handler here
            $self->{HANDLER} = undef;
            exit(0);
        }
        else {
            # Parent

            $retry = 0;
            # Add the request to the forked requests list
            $self->{FORKS}->{$pid} = $req;
            # Create a new request object
            $req = $request_factory->();
        }

        last if $self->{LAST_REQUEST};
    }

    if (!$self->{LAST_REQUEST} && (++$retry < 5)) {
        goto RETRY;
    }

FINISH:
    syslog(LOG_WARNING, 'Quitting FCGI loop. LAST_REQUEST = '
        . ($self->{LAST_REQUEST} || 'undef'));
    $req->Finish();
    $self->{BUSY} = 0;
    return;
}

1;

__END__

=back

