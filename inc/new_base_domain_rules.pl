#!/usr/bin/env perl

use Net::Domain::PublicSuffix qw( base_domain public_suffix );
use strict;

# Extract new publicsuffix rules from publicsuffix.org and generate the input
# data for the Net::Domain::PublicSufix parse TRIE.
#
# https://publicsuffix.org/list/effective_tld_names.dat
#
# 1. init public_suffix tree with only special rules
# 2. test each entry of effective_tld_names.dat
# 3. add rules that fail to the missing list of rules.
# 4. print out a missing rules, this can be cut-n-pasted into PublicSuffix.pm
#

my $END_TOK = '@';

my $tld_filename = "effective_tld_names.dat.new";

my $filename = shift @ARGV;
if (($filename eq "") || (! -f $filename))
{
    $filename = $tld_filename;
}

open (my $fh, '<', $filename) or die("cannot open TLD source file [$filename] $!");

# only load the special rules
Net::Domain::PublicSuffix::gen_basedomain_tree( special_rules_only => 1 );

# in case we ever want to see what special rules are missing...
# Net::Domain::PublicSuffix::gen_basedomain_tree( publicsuffix_rules_only => 1 );

my %missing_tlds;

my $line;
while($line = <$fh>) {

    chomp($line);
    $line =~ s/\/\/.*//;
    $line =~ s/\s*$//;
    $line =~ s/^\s*//;
    $line =~ s/\s+/ /g;
    next if ($line eq '');

    my($basedomain) = $line;
    my $hostname  = '';

    my $save_basedomain = $basedomain;

    my $bn;
    if ($save_basedomain =~ s/^\!/!./)
    {
        $basedomain = $save_basedomain;
        $basedomain =~ s/^\!\.//;
        $hostname = "www.$basedomain";
    }
    else {
        $basedomain = "foobar.$basedomain";
        $hostname = "www.$basedomain";
    }
    $bn = public_suffix($hostname);

    if ($bn ne $basedomain) {
        my @parts = ((reverse split(/\./,$save_basedomain),), $END_TOK);

        my $missing = \%missing_tlds;
        foreach my $part (@parts)
        {
            if ($part eq $END_TOK)
            {
                $missing->{$part} = 1;
            }
            else {
                $missing->{$part} = {} if (! defined $missing->{$part} );
                $missing = $missing->{$part};
            }
        }
    }
}
close($fh);

print_rules( '', \%missing_tlds);

#use Data::Dumper;
#print Data::Dumper::Dumper(\%missing_tlds);

exit(0);

sub print_rules
{
    my($prefix, $tree) = @_;

    print $prefix . " { }\n" if ($tree->{$END_TOK} && ($prefix =~ /^\S+$/));

    my @parts = sort grep {$_ !~ /$END_TOK/ } keys %$tree;

    my @terminal_parts =  grep { ref $tree && ref $tree->{$_} && $tree->{$_}->{$END_TOK} } sort @parts;
    if (@terminal_parts && ($prefix ne ''))
    {
        my $new_prefix = $prefix . ($prefix eq '' ? '' : ' ') . "{ " . join(" ", @terminal_parts) . " }";
        print $new_prefix . "\n"
    }

    foreach my $part (sort @parts)
    {
        my $new_prefix;
        if ($prefix eq '')
        {
            $new_prefix = $part;
        }
        else {
            $new_prefix = $prefix . " { $part }";
        }
        print_rules( $new_prefix, $tree->{$part});
    }
}

