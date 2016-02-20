use strict;
use warnings;
use ExtUtils::MakeMaker;

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
	'Apache::Session::File' => 0,
	'Authen::Htpasswd' => 0,
	'FCGI' => 0,
	'HTML::Template' => 0,
	'HTTP::Date' => 0,
	'YAML::XS' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'CMS-*' },
);
