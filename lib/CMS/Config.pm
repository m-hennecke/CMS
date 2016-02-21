# ABSTRACT: Configuration wrapper
# vi: set expandtab shiftwidth=4:
##############################################################################
package CMS::Config;

=pod

=head1 NAME

CMS::Config - Config reader wrapper for the CMS config file

=head1 DESCRIPTION

Objectified config reader. Reads the config file upon creation, no other
functionality implemented yet.

=cut

use strict;
use warnings;

use YAML::XS;

##############################################################################

=head1 CLASS INTERFACE

=head2 Constructor

=over

=item new()

Create a config object and read the config file from underneath the B<CMS_ROOT>
directory on creation.
Additional parameters are:

=over

=item *

B<CMS_ROOT>: Root directory of the CMS.

=back

=back

=cut

sub new {
    my $class = shift;
    my %params = @_;

    my $self = {
        CMS_ROOT    => $params{CMS_ROOT} || '/var/www/cms',
    };

    die 'No CMS_ROOT directory found at "' . $self->{CMS_ROOT} . '"'
        unless -d $self->{CMS_ROOT};


    # Set the config file
    my $config_file = $self->{CMS_ROOT};
    $config_file =~ s/\/$//;
    $config_file .= '/config.yaml';
    $self->{CMS_CONFIG} = $config_file;

    die 'No config file found under the CMS_ROOT directory "'
            . $self->{CMS_ROOT} . '"'
        unless -f $self->{CMS_CONFIG};

    my $config = YAML::XS::LoadFile($config_file);
    $self->{CONFIG} = $config;

    bless($self, $class);
}


=head2 Member Functions

=over

=item config()

Returns the actual config hash.

=cut

sub config {
    my $self = shift;

    return $self->{CONFIG};
}

1;

__END__

=back

