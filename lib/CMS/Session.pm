# ABSTRACT: Session management
# vi: set expandtab shiftwidth=4:
##############################################################################
package CMS::Session;

=pod

=head1 NAME

CMS::Session - Session implementation using C<Cache::Cache>

=head1 DESCRIPTION

Session implementation.

=cut

use strict;
use warnings;

use CMS::Trace qw(funcname);
use Data::Uniqid qw(uniqid);
use Cache::FileCache;
use Sys::Syslog qw(:macros :standard);

##############################################################################

=head1 CLASS INTERFACE

=head2 Constructor

=over

=item new($session_id, $cache_root)

Creates a session object, either from an existing session id or a new id
will be generated.
The C<$session_id> and C<$cache_root> parameters are optional. If the
C<$cache_root> parameter is not passed, the default from C<Cache::FileCache>
is used.

=back

=cut

sub new {
    my $class = shift;
    my $session_id = shift;
    my $cache_root = shift;
    # uncoverable condition right
    my $namespace = shift || 'CMS';

    syslog(LOG_DEBUG, funcname());

    my $filecache_params = {
       directory_umask    => 077,
       namespace          => $namespace,
       default_expires_in => 1800,
    };
    $filecache_params->{cache_root} = $cache_root if $cache_root;

    my $cache = new Cache::FileCache($filecache_params);
    my $self = {
	CACHE          => $cache,
    };

    my $data = $cache->get($session_id) if $session_id;
    if (!$data) {
        if (!$session_id) {
            # Create a new one.
            $session_id = uniqid();
            $data = { };
            $cache->set($session_id, $data);
        }
        else {
            return undef;
        }
    }

    $self->{SESSION_ID} = $session_id;
    $self->{DATA} = $data;
    bless($self, $class);
    return $self;
}


sub DESTROY {
    my $self = shift;

    $self->store();
}

=head2 Member Functions

=over

=item id()

Returns the session id associated with this object.

=cut

sub id {
    my $self = shift;

    return $self->{SESSION_ID};
}


=item data([$hashref])

Getter/Setter for the associated session data.

=cut

sub data {
    my $self = shift;

    if (@_) {
        my $data = shift;
        die 'Require a hash reference.' unless ref($data) eq 'HASH';
        $self->{DATA} = $data;
    }
    return $self->{DATA};
}


=item store()

Stores the data in the cache.

=cut

sub store {
    my $self = shift;

    if ($self->id()) {
        $self->{CACHE}->set($self->id(), $self->data());
    }
}


=item delete()

Removes the session data from the cache.

=cut

sub delete {
    my $self = shift;

    $self->{CACHE}->remove($self->id()) if $self->id();
    $self->{SESSION_ID} = undef;
}


=item get($key)

Returns the data referenced by the key from the session object.

=cut

sub get {
    my $self = shift;
    my $key = shift;

    syslog(LOG_DEBUG, funcname());

    return $self->{DATA}->{$key};
}


=item set($key, $data)

Stores the key value pair in the session data.

=cut

sub set {
    my $self = shift;
    my $key = shift;
    my $data = shift;

    syslog(LOG_DEBUG, funcname());

    $self->{DATA}->{$key} = $data;
}


1;

__END__

=back

