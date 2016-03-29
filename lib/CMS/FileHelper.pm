# ABSTRACT: File and directory handling helper functions
# vi: set tabstop=4 expandtab shiftwidth=4:
##############################################################################
package CMS::FileHelper;

=pod

=head1 NAME

CMS::FileHelper - Helper functions for file and directory handling

=head1 DESRIPTION

Helper functions for handling files and directories.

=cut

use strict;
use warnings;

use POSIX qw(strftime);
use File::stat;
use Sys::Syslog qw(:macros :standard);

use CMS::Trace qw(funcname);

use base qw(Exporter);
our %EXPORT_TAGS = (
    all => [ qw(getDirectoryEntries getNewestFileDate) ]
);
our @EXPORT_OK = qw(getDirectoryEntries getNewestFileDate);

our $VERSION = '0.02';

##############################################################################

=head1 FUNCTIONS

=over

=item getDirectoryEntries($dir)

Returns an array with all the files in a directory. Files with a leading
dot are skipped.

=cut

sub getDirectoryEntries {
    my $directory = shift;

    syslog(LOG_DEBUG, funcname());

    return if not defined $directory;

    opendir(my $dh, $directory)
        || die 'Unable to open ' . $directory . ': ' . $! . "\n";
    my @direntries = readdir($dh);
    closedir($dh);

    return grep { !/\..*/x } @direntries;
}

=item getNewestFileDate($dir)

Returns the last changed file in the directory

=cut

sub getNewestFileDate {
    my $directory = shift;

    syslog(LOG_DEBUG, funcname());

    return if not defined $directory;

    my $newest = -1;

    my @direntries = getDirectoryEntries($directory);

    foreach my $file (@direntries) {
        if ($file !~ /\..*/x) {
            my $moddate = (stat($directory . '/' . $file))->mtime();
            $newest = $moddate if ($moddate > $newest);
        }
    }
    return if $newest == (-1);

    my $date = strftime('%G-%m-%dT%T %z', localtime $newest);
    $date =~ s/ ([-+][0-9]{2})/$1:/gx;

    return $date;
}


1;

__END__

=back

