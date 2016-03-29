#!perl -T
# vi: set tabstop=4 expandtab shiftwidth=4:

use Test::More tests => 11;

use strict;
use warnings;

my $namespace = 'TestCMS';
my $cache;
my $def_root;

BEGIN {
    use_ok('Cache::FileCache') || print "Bail out!\n";
    use_ok('CMS::Session') || print "Bail out!\n";
    $cache = new Cache::FileCache({
            namespace => $namespace,
        }
    );
    $def_root = $cache->get_cache_root();
}

END {
    $cache->clear() if $cache;
}

ok(!new CMS::Session('no_valid_id', undef, $namespace), 'Invalid session.');
my $session = new CMS::Session(undef, undef, $namespace);
ok(ref($session) eq 'CMS::Session', 'Valid session.');
my $id = $session->id();
ok($id, 'Got session id.');
$session->set('test', '1,2,3 Test');
undef $session;
$session = new CMS::Session($id, $def_root, $namespace);
ok(ref($session) eq 'CMS::Session', 'Reattach session.');
ok($session->get('test') eq '1,2,3 Test', 'Retrieve value.');
my $data = { 'test' => 'X' };
$session->data($data);
undef $session;
$session = new CMS::Session($id, $def_root, $namespace);
ok($session && $session->get('test') eq 'X', 'Set hashref.');
eval {
    $session->data(\'Invalid Argument');
};
ok($@, 'Die by passing wrong argument to data()');
like($@, qr/^Require a hash reference./, '... and throws the right exception.');
$session->remove();
# Delete twice to cover the condition of a valid session id
$session->remove();
undef $session;
$session = new CMS::Session($id, $def_root, $namespace);
ok(!defined($session), 'Session removed.');

