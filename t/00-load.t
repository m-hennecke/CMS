#!perl -T
# vi: set tabstop=4 expandtab shiftwidth=4:

use strict;
use warnings;

use ExtUtils::Manifest qw/maniread/;
use Test::More;

delete $ENV{PATH};

my @modules;

BEGIN {
    my $manifest = maniread();
    die 'Unable to read MANIFEST' unless $manifest;

    foreach my $file (keys %$manifest) {
        if ($file =~ m/^lib\/.*\.pm$/x) {
            my $module = $file;
            $module =~ s/^lib\///x;
            $module =~ s/\.pm$//x;
            $module =~ s/\//::/gx;

            push @modules, ($module);

        }
    }
}

plan(tests => scalar @modules);
foreach my $module (sort @modules) {
    use_ok($module) || die "Bail out!\n";
}

diag( "Testing CMS $CMS::VERSION, Perl $], $^X" );
