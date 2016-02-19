#!perl -T

use Test::More tests => 8;

BEGIN {
    use_ok( 'CMS' ) || print "Bail out!
";
    use_ok( 'CMS::Config' ) || print "Bail out!
";
    use_ok( 'CMS::Daemon' ) || print "Bail out!
";
    use_ok( 'CMS::FCGI' ) || print "Bail out!
";
    use_ok( 'CMS::FileHelper' ) || print "Bail out!
";
    use_ok( 'CMS::Handler' ) || print "Bail out!
";
    use_ok( 'CMS::Sitemap' ) || print "Bail out!
";
    use_ok( 'CMS::Trace' ) || print "Bail out!
";
}

diag( "Testing CMS $CMS::VERSION, Perl $], $^X" );
