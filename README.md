# NAME

Net::Domain::PublicSuffix - Fast XS implementation of public\_suffix and base\_domain

# SYNOPSIS

    use Net::Domain::PublicSuffix qw(base_domain public_suffix);

    my $d0 = public_suffix("www.foo.com");
    my $d1 = base_domain("www.foo.com");
    # $d0 and $d1 equal "foo.com"

    my $d2 = public_suffix("www.smms.pvt.k12.ca.us");
    my $d3 = base_domain("www.smms.pvt.k12.ca.us");
    # $d2 and $d3 equal "smms.pvt.k12.ca.us"

    my $d4 = public_suffix("www.whitbread.co.uk");
    my $d5 = base_domain("www.whitbread.co.uk");
    # $d4 and $d5 equal "whitbread.co.uk"

    my $d6 = public_suffix("www.foo.zz");
    my $d7 = base_domain("www.foo.zz");
    # $d6 eq "" because .zz is not a valid TLD
    # $d7 eq "foo.zz"

# DESCRIPTION

Net::Domain::PublicSuffix finds the public suffix, or top level domain
(TLD), of a given hostname name.

## public\_suffix()

$public\_suffix = public\_suffix($hostname)

Given a hostname return the TLD (top level domain). Returns the empty
string for hostnames with an invalid public suffix.

public\_suffix() is not an exact replacement for
[Mozilla::PublicSuffix](https://metacpan.org/pod/Mozilla::PublicSuffix). See the tests run in publicsuffix.t for
notable differences. I think some of the test from publicsuffix.org
are just wrong. For instance, publicsuffix.org thing that
"example.example" (a non-existance TLD) should pass, but "test.om" (a
non-existent second level domain for the valid TLD om) should not.

## base\_domain()

$tld = base\_domain($hostname)

Given a hostname return the TLD (top level domain).

This function is more permissive than [public\_suffix](https://metacpan.org/pod/public_suffix) in that it will
always try to return a reasonable answer. public\_suffix returns an
answer even when the given hostname does not have a valid TLD (for
example www.foo.xx returns foo.xx) or is missing a required sub domain
(for example ak.cy returns the incomplete ak.cy).

base\_domain() will treat truncated TLDs as valid. For instance
base\_domain("com.bd") will return "com.bd" but public\_suffix("com.bd")
will return "" (empty string) because the TLD rules stipulate there
should be a third level (i.e. "foo.com.bd") to be valid.

## has\_valid\_tld()

$bool = has\_valid\_tld($hostname)

Returns true if the domain of the provided string exists in the list
of valid top level domains. The list of valid domains is constructed
from the list of public\_suffix rules.

## all\_valid\_tlds()

@tld\_list = all\_valid\_tlds();

Return a list of all valid top level domains.

## gen\_basedomain\_tree()

Initialize the base domain trie. This function will get called the
first time base\_domain() is called. This function is made public so
that the trie can be initialized manually before any time critical
code.

# Rule Data

The list of TLD rules is generated primarily from the Public Suffic
list from publicsuffix.org and can be found at
[https://publicsuffix.org/list/effective\_tld\_names.dat](https://publicsuffix.org/list/effective_tld_names.dat)

Previously rules were generated from the list in the Mozilla source
[http://lxr.mozilla.org/mozilla/source/netwerk/dns/src/effective\_tld\_names.dat](http://lxr.mozilla.org/mozilla/source/netwerk/dns/src/effective_tld_names.dat)
The publicsuffix.org list now supersceeds the Mozilla list.

Additional research was done via the Wikipedia (for example
[http://en.wikipedia.org/wiki/.uk](http://en.wikipedia.org/wiki/.uk)) and by consulting the actual NICs
that assign domains (for example [http://www.kenic.or.ke/](http://www.kenic.or.ke/)).

## .us rules

The United States of America has some unique rule formats (see
[http://en.wikipedia.org/wiki/.us](http://en.wikipedia.org/wiki/.us)). Including wildcards in the middle
of the TLD. For example in the pattern ci.<locality>.<state>.us,
<state> is one of a fixed set of valid state abbreviations, but
<locality> is effectively a wildcard city/town/county/etc, followed by
a fixed list of oranizational types (ci, town, vil, co).

The Mozilla Public Suffix implementation ignores these patterns and
just adds all the known combinations via brute force. This package
honors wildcards mid-pattern.

## Differences with Mozilla's PublicSuffix

There are some rules that Net::Domain::PublicSuffix has added to the
list of rules from publicsuffix.org. These rules are the result of
additional research. For instance [http://en.wikipedia.org/wiki/.mt](http://en.wikipedia.org/wiki/.mt)
lists gov.mt as a valid TLD, but it is missing from the
publicsuffix.org list.

These rule lists are kept separate in the code to make future upgrades
easier. There are two lists: @publicsuffix\_rules that are
autogenerated from the publicsuffix.org list and @special\_rules for
these additional missing rules.

Net::Domain::PublicSuffix does not support punycode
hostnames. Hostnames need to be decoded before calling base\_domain().

# AUTHOR

    Blekko.com

# SEE ALSO

[Mozilla::PublicSuffix](https://metacpan.org/pod/Mozilla::PublicSuffix),
[Domain::PublicSuffix](https://metacpan.org/pod/Domain::PublicSuffix),
[IO::Socket::SSL::PublicSuffix](https://metacpan.org/pod/IO::Socket::SSL::PublicSuffix),
[ParseUtil::Domain](https://metacpan.org/pod/ParseUtil::Domain),
[Net::Domain::Match](https://metacpan.org/pod/Net::Domain::Match)

Of which [Domain::PublicSuffix](https://metacpan.org/pod/Domain::PublicSuffix) gets the answers right most of the time. The rest do not work for much more than the examples they provide, if any.

[Net::IDN::Punycode](https://metacpan.org/pod/Net::IDN::Punycode),
[Net::IDN::Encode](https://metacpan.org/pod/Net::IDN::Encode),
[IDNA::Punycode](https://metacpan.org/pod/IDNA::Punycode),
