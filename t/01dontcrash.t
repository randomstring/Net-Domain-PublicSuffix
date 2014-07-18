use Test::More qw(no_plan);
use Net::Domain::PublicSuffix;
use strict;

# test that high bit chars don't crash Basedomain
my $bn = Net::Domain::PublicSuffix::base_domain("\372\137\305\351\124\62\41\350\64\220\241\260\127\234\367\367");
(defined $bn ? ok(1) : ok(0));

# test that null bytes don't crash basedomain
$bn = Net::Domain::PublicSuffix::base_domain("\0\0\0\0\0\0");
(defined $bn ? ok(1) : ok(0));
$bn = Net::Domain::PublicSuffix::base_domain("\0\0\0\0\0.com");
(defined $bn ? ok(1) : ok(0));
$bn = Net::Domain::PublicSuffix::base_domain("www.foobar\0.com");
(defined $bn ? ok(1) : ok(0));
$bn = Net::Domain::PublicSuffix::base_domain("www.foobar.com\0.com");
(defined $bn ? ok(1) : ok(0));

exit(0);
