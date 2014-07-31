#!/usr/bin/env perl

# run public_suffix with debugging on

use strict;
use Net::Domain::PublicSuffix qw( public_suffix );

Net::Domain::PublicSuffix::set_debug_level(2);

foreach my $domain (@ARGV)
{
    print "$domain \t->\t" . public_suffix($domain) . "\n";
}
