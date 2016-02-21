# ABSTRACT: Daemon related functions
# vi: set tabstop=4 expandtab shiftwidth=4:
##############################################################################
package CMS::Daemon;

=pod

=head1 NAME

CMS::Daemon - Functions for daemon creation

=head1 DESRIPTION

Functions that encapsulate most of the work that has to be done to create
a daemon.

=cut

use strict;
use warnings;
use English;

use POSIX qw(setsid);
use Sys::Syslog qw(:macros :standard);

require Exporter;
our @ISA = qw(Exporter);
our %EXPORT_TAGS = (
    all => [ qw(daemonize drop_privileges change_root) ]
);
our @EXPORT = qw(daemonize drop_privileges change_root);

our $VERSION = '0.02';

##############################################################################

=head1 FUNCTIONS

=over

=item daemonize()

Does everything to detach the process from the console it was started from.

=cut

sub daemonize {
    # Flush the buffer
    $| = 1;

    chdir '/' or die "Can't chdir to /: $!";
    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
    open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
    defined(my $pid = fork()) or die "Can't fork: $!";
    exit if ($pid);
    setsid or die "Can't start a new session: $!";
    umask 022;
}


=item change_root($rootdirectory)

Calls chroot and does a chdir() to the directory afterwards.
Requires UID to be 0 (root).

=cut

sub change_root {
    my $new_root = shift;

    return if ($UID != 0);
    chroot($new_root);
    chdir('/');
}


=item drop_privileges ($user, $chroot)

Drops the privileges from root to the specified user.
If a chroot is requested, it is done right before the privileges are dropped
so that we have access to /etc for getpwnam() and getgrent() calls.

=cut

sub drop_privileges {
    my $user = shift;
    my $chroot = shift;

    return if (($UID != 0) && ($EUID != 0));

    if (! $user) {
        # Change the root directory anyway, even if privilege dropping is not
        # done
        change_root($chroot) if $chroot;
        return;
    }

    # Get the user from /etc/passwd
    my ($uid, $gid, $home, $shell) = (getpwnam($user))[2, 3, 7, 8];
    if (!defined($uid) || !defined($gid)) {
        syslog(LOG_ERR, 'Unable to find uid and gid for user ' . $user);
        return;
    }

    # Get all the groups for this user
    my @groups;
    while (my ($name, $comment, $ggid, $mstr) = getgrent()) {
        my %membership = map { $_ => 1 } split(/\s/, $mstr);
        if (exists $membership{$user}) {
            push(@groups, $ggid) if ($ggid != 0);
        }
    }

    # Cleanup our environment
    $ENV{USER} = $user;
    $ENV{LOGNAME} = $user;
    $ENV{HOME} = $home;
    $ENV{SHELL} = $shell;

    my $_drop_uidgid = sub {
        my ($uid, $gid, $groups) = @_;

        my %groupHash = map { $_ => 1 } ($gid, @$groups);
        my $newgid = "$gid " . join(' ', sort { $a <=> $b } (keys %groupHash));

        $GID = $EGID = $newgid;
        $UID = $EUID = $uid;

        # Sort the output so we can compare it
        my %GIDHash = map { $_ => 1 } ($gid, split(/\s/, $GID));
        my $cgid = int($GID) . ' '
            . join(' ', sort { $a <=> $b } (keys %GIDHash));
        my %EGIDHash = map { $_ => 1 } ($gid, split(/\s/, $EGID));
        my $cegid = int($EGID) . ' '
        . join(' ', sort { $a <=> $b } (keys %EGIDHash));

        # Check that we did actually drop the privileges
        if (($UID != $uid) || ($EUID != $uid) || ($cgid ne $newgid)
            || ($cegid ne $newgid)) {
            syslog(LOG_ERR, 'Could not drop privileges to uid: '
                . $uid . ', gid:' . $newgid . "\n");
            syslog(LOG_ERR, 'Currently is: UID:' . $UID . ', EUID=' . $EUID
                . ', GID=' . $cgid . ', EGID=' . $cegid . "\n");
        }
    };

    change_root($chroot) if ($chroot);

    $_drop_uidgid->($uid, $gid, \@groups);

    return ($uid, $gid, \@groups);
}


1;

__END__

=back

