# ABSTRACT: Module definitions
# vi: set tabstop=4 expandtab shiftwidth=4:

use strict;
use warnings;

use ExtUtils::MakeMaker;

sub MY::libscan {
    my $mm = shift;
    my $path = shift;

    if ($path =~ m{\$\(INST_LIB\)}x) {
        warn "$path\n";
    }
    return $path if -d $path;
    return $path if $path =~ /\.pm$/;
    return '';
}


WriteMakefile(
    NAME                => 'CMS',
    AUTHOR              => q{Markus Hennecke <markus-hennecke@markus-hennecke.de>},
    VERSION_FROM        => 'lib/CMS.pm',
    ABSTRACT_FROM       => 'lib/CMS.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'bsd')
      : ()),
    EXE_FILES => [ qw/cms.pl sitemap.pl/ ],
    PREREQ_PM => {
        'Cache::Cache'     => '1.08',
        'Data::Uniqid'     => '0.12',
        'Authen::Htpasswd' => '0.161',
        'FCGI'             => '0.67',
        'HTML::Template'   => '2.9',
        'HTTP::Date'       => '6.02',
        'YAML::XS'         => '0.59',
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'CMS-*' },
);
