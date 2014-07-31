#!/usr/bin/env perl

# benchmark various Perl publicsuffix/basedomain implimentations

use strict;

use Benchmark qw( cmpthese timethis timestr);
use Getopt::Long;
use UNIVERSAL::require qw();

# benchmarking against these
use Mozilla::PublicSuffix;
use Domain::PublicSuffix;
use ParseUtil::Domain qw( :parse );
use IO::Socket::SSL::PublicSuffix;

use Net::Domain::PublicSuffix qw (public_suffix base_domain);

my $domain_publicsuffix;
my $io_socket_ssl_publicsuffix;

my $benchmarks = {
    'Net::Domain::PublicSuffix (base_domain)' =>
    {
        printname => "base_domain",
        init => sub { Net::Domain::PublicSuffix::gen_basedomain_tree() },
        base_domain => sub { Net::Domain::PublicSuffix::base_domain($_[0]); },
    },
    'Net::Domain::PublicSuffix (public_suffix)' =>
    {
        printname => "public_suffix",
        init => sub { Net::Domain::PublicSuffix::gen_basedomain_tree() },
        base_domain => sub { Net::Domain::PublicSuffix::public_suffix($_[0]); },
    },
    'Mozilla::PublicSuffix' =>
    {
        printname => "Mozilla",
        init => sub { return },
        base_domain => sub { Mozilla::PublicSuffix::public_suffix($_[0]); },
    },
    'Domain::PublicSuffix' =>
    {
        printname => "Domain::PublicSuffix",
        init => sub { $domain_publicsuffix = Domain::PublicSuffix->new(); },
        base_domain => sub { $domain_publicsuffix->get_root_domain($_[0]); },
    },
    'IO::Socket::SSL::PublicSuffix' =>
    {
        printname => "SSL::PublicSuffix",
        init => sub { $io_socket_ssl_publicsuffix =  IO::Socket::SSL::PublicSuffix->default; },
        base_domain => sub { $io_socket_ssl_publicsuffix->public_suffix($_[0]); },
    },
    'ParseUtil::Domain' =>
    {
        skip => "dies on bad input and generally broken",
        printname => "ParseUtil",
        base_domain => sub {my $pu = parse_domain($_[0]); return ($pu->{name} ? $pu->{name} : $pu->{domain}  ) . $pu->{zone} },
    },
};

my $iterations = -1;   # let timethis() choose how many iterations
my $testfile = "tests.raw";
my $verbose = 0;
my $width = 0;
my @benchmark = ();
my $perf_results = {};
my $accuracy_results = {};

Getopt::Long::GetOptions(
    'tf|testfile'    => \$testfile,
    'i|iterations=i' => \$iterations,
    'v|verbose+'     => \$verbose,
    ) or die("bad arguments");

my %tests;
open(my $testfh, '<' , $testfile) or die("cannot open testfile [$testfile] $!");
foreach my $line (<$testfh>) {
    chomp($line);
    my($host,$tld) = split(/\s+/,$line);
    $tests{$host} = $tld;
}

@benchmark = keys %{ $benchmarks };

$width = width(@benchmark);

#print "\nModules\n";

foreach my $package ( @benchmark ) {

    next if ($benchmarks->{$package}->{skip});
    my $benchmark = $benchmarks->{$package};
    my $printname = $benchmarks->{$package}->{printname};
    $package =~ s/\s*\(.+\)$//;
    $package->require or next;

    my @packages  = ( $package, @{ $benchmark->{packages} || [] } );

    $benchmark->{init}() if (defined($benchmark->{init}));

    $perf_results->{$printname} = time_base_domain($benchmark->{base_domain});
    $accuracy_results->{$package} = test_base_domain($printname,$benchmark->{base_domain});

}

foreach my $printname (sort {$accuracy_results->{$b} <=> $accuracy_results->{$a}} keys %$accuracy_results)
{
    # accuracy is benchmarked against base_domain() which is more tolerant of badly formatted domains
    printf( "%-${width}s is %5.1f%% accurate\n", $printname, $accuracy_results->{$printname} * 100 );
}
print "\n";

# the perf benchmark graph
cmpthese($perf_results);

sub time_base_domain
{
    my ( $base_domain ) = @_;
    return timethis( $iterations, sub { foreach my $host (keys %tests) { &$base_domain($host) } }, '', 'none' );
}

sub test_base_domain
{
    my ( $printname, $base_domain ) = @_;
    my $correct;
    my $total;
    foreach my $host (keys %tests) {
        $total++;
        my $test_tld = &$base_domain($host) || '';
        if ($test_tld eq $tests{$host})
        {
            $correct++;
        }
        elsif ($verbose)
        {
            print "$printname: [$host] -> [$test_tld]  expected [$tests{$host}]\n";
        }

    }
    return ($correct / $total);
}

sub width
{
    return length( ( sort { length $a <=> length $b } @_ )[-1] );
}

# Results
#
# Net::Domain::PublicSuffix                 is 100.0% accurate
# Domain::PublicSuffix                      is  88.3% accurate
# IO::Socket::SSL::PublicSuffix             is   0.0% accurate
# Mozilla::PublicSuffix                     is   0.0% accurate
#
#                         Rate Domain::PublicSuffix SSL::PublicSuffix Mozilla base_domain public_suffix
# Domain::PublicSuffix 0.990/s                   --              -32%    -82%        -97%          -98%
# SSL::PublicSuffix     1.46/s                  47%                --    -74%        -96%          -96%
# Mozilla               5.61/s                 466%              284%      --        -86%          -86%
# base_domain           39.4/s                3882%             2600%    603%          --           -1%
# public_suffix         39.8/s                3920%             2627%    610%          1%            --

