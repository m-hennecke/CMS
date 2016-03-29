#!perl -T

use strict;
use warnings;

use Test::More;
use ExtUtils::Manifest qw/maniread/;

my @perl_files;

BEGIN {
    my $manifest = maniread();
    die 'Unable to read MANIFEST' unless $manifest;

    foreach my $file (keys %$manifest) {
        if ($file =~ m/.*\.pm$/) {
            push @perl_files, ($file);
        }
    }
}

unless ($ENV{RELEASE_TESTING}) {
    plan(skip_all => 'Author tests not required for installation');
}
else {
    eval { use Test::Perl::Critic (-severity => 5); };
    if ($@) {
        plan(skip_all => 'Test::Perl::Critic required');
    }
    else {
        plan(tests => scalar @perl_files);
    }
}

foreach my $file (@perl_files) {
    critic_ok($file);
}

