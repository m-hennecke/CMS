#!perl -T

use strict;
use warnings;

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

use Test::More tests => scalar @perl_files;
eval 'use Test::Perl::Critic';
plan skip_all => 'Test::Perl::Critic required' if $@;

foreach my $file (@perl_files) {
    critic_ok($file);
}

