#!/usr/bin/env perl

# run base_domain with debugging on.

use strict;
use Net::Domain::PublicSuffix qw( base_domain );

Net::Domain::PublicSuffix::set_debug_level(2);

foreach my $domain (@ARGV)
{
    print "$domain \t->\t" . base_domain($domain) . "\n";
}
