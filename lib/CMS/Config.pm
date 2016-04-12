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

use File::Spec;
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
    my $params = shift;

    my $self = {
        CMS_ROOT    => $params->{CMS_ROOT} || '/var/www/cms',
    };

    die 'No CMS_ROOT directory found at "' . $self->{CMS_ROOT} . '"' . "\n"
        unless -d $self->{CMS_ROOT};


    # Set the config file
    my $config_file = $self->{CMS_ROOT};
    $config_file =~ s/\/$//x;
    $config_file .= '/config.yaml';
    $self->{CMS_CONFIG} = $config_file;

    die 'No config file found under the CMS_ROOT directory "'
            . $self->{CMS_ROOT} . '"' . "\n"
        unless -f $self->{CMS_CONFIG};

    my $config = YAML::XS::LoadFile($config_file);
    $self->{CONFIG} = $config;

    bless($self, $class);
    return $self;
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


=item translate_cmsroot($chroot)

Returns the root directory relative to the C<$chroot> parameter. If
that parameter is not defined, it will return C<< $self->{CMS_ROOT} >>.

=cut

sub translate_cmsroot {
    my $self = shift;
    my $chroot = shift || return $self->{CMS_ROOT};

    my @cms_root_path = File::Spec->splitdir($self->{CMS_ROOT});
    my @chroot_path = File::Spec->splitdir($chroot);

    while (@chroot_path) {
        my $chroot_path_part = shift @chroot_path;
        my $cmsroot_path_part = shift @cms_root_path;

        return unless defined $cmsroot_path_part;
        return unless ($chroot_path_part eq $cmsroot_path_part);
    }

    return File::Spec->catdir(@cms_root_path);
}


1;

__END__

=back

