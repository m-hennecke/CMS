#!perl -T
# vi: set tabstop=4 expandtab shiftwidth=4:

use strict;
use warnings;

use Test::More;
use ExtUtils::Manifest qw/maniread/;

delete $ENV{PATH};

my @perl_files;

BEGIN {
    my $manifest = maniread();
    die 'Unable to read MANIFEST' unless $manifest;

    foreach my $file (keys %$manifest) {
        if ($file =~ m/.*\.p[ml]$/x) {
            push @perl_files, ($file);
        }
    }
}

unless ($ENV{RELEASE_TESTING}) {
    plan(skip_all => 'Author tests not required for installation');
}
else {
    eval { require Test::Perl::Critic; };
    if ($@) {
        plan(skip_all => 'Test::Perl::Critic required');
    }
    else {
        Test::Perl::Critic->import(
            -severity => 4,
            -exclude  => 'Variables::RequireLocalizedPunctuationVars'
        );
        plan(tests => scalar @perl_files);
    }
}

foreach my $file (sort @perl_files) {
    critic_ok($file);
}

