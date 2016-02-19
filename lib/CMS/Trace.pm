# $Id$
# vi: set tabstop=4 expandtab shiftwidth=4:
##############################################################################
package CMS::Trace;

=pod

=head1 NAME

CMS::Trace - Helper functions to trace execution

=head1 DESCRIPTION

Helper functions for execution trace and logging.

=cut

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our %EXPORT_TAGS = (
    all => [ qw(funcname) ]
);
our @EXPORT_OK = qw(funcname);
our @EXPORT = ();

our $VERSION = '0.01';

##############################################################################

=head1 FUNCTIONS

=over

=item funcname()

Returns the callers function name.

=cut

sub funcname {
    return (caller(1))[3];
}

1;

__END__

=back

