# Copyright (C) 2014 Blekko, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=head1 NAME

Net::Domain::PublicSuffix - Fast XS implementation of public_suffix and base_domain

=head1 SYNOPSIS

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


=head1 DESCRIPTION

Net::Domain::PublicSuffix finds the public suffix, or top level domain
(TLD), of a given hostname name.

=head2 public_suffix()

$public_suffix = public_suffix($hostname)

Given a hostname return the TLD (top level domain). Returns the empty
string for hostnames with an invalid public suffix.

public_suffix() is not an exact replacement for
L<Mozilla::PublicSuffix>. See the tests run in publicsuffix.t for
noteable differences. I think some of thes test from publicsuffix.org
are just wrong. For instance, publicsuffix.org thing that
"example.example" (a non-existance TLD) should pass, but "test.om" (a
non-existant second level domain for the valid TLD om) should not.

=head2 base_domain()

$tld = base_domain($hostname)

Given a hostname return the TLD (top level domain).

This function is more permissive than L<public_suffix> in that it will
always try to return a reasonable answer. public_suffix returns an
answer even when the given hostname does not have a valid TLD (for
example www.foo.xx returns foo.xx) or is missing a required sub domain
(for example ak.cy returns the incomplete ak.cy).

base_domain() will treat truncated TLDs as valid. For instance
base_domain("com.bd") will return "com.bd" but public_suffix("com.bd")
will return "" (empty string) because the TLD rules stipulate there
should be a third level (i.e. "foo.com.bd") to be valid.

=cut

package Net::Domain::PublicSuffix;

use strict;

our $VERSION = '1.03';
our @ISA = qw(Exporter);

our @EXPORT_OK = qw( base_domain public_suffix has_valid_tld set_debug_level dump_tree );

use Exporter;
use XSLoader;

XSLoader::load "Net::Domain::PublicSuffix", $VERSION;

my $initialized = 0;
my @default_rules; # list of domains
my %tree;          # TRIE of all domain, domains read right to left in hash
my %valid_tlds;    # hash of all public suffix/domains

=head2 has_valid_tld()

$bool = has_valid_tld($hostname)

Returns true if the domain of the provided string exists in the list
of valid top level domains. The list of valid domains is constructed
from the list of public_suffix rules.

=cut
sub has_valid_tld
{
    my ($domain) = @_;

    gen_basedomain_tree() if (!$initialized);

    my $tld = lc($domain);
    if ($tld =~ /([^\.]+)$/) {
        $tld = $1;
    }

    return (exists $valid_tlds{$tld} ? 1 : 0);
}

=head2 all_valid_tlds()

@tld_list = all_valid_tlds();

Return a list of all valid top level domains.

=cut
sub all_valid_tlds
{
    gen_basedomain_tree() if (!$initialized);

    return keys %valid_tlds;
}

my @special_rules;
my @publicsuffix_rules;

=head2 gen_basedomain_tree()

Initialize the base domain trie. This function will get called the
first time base_domain() is called. This function is made public so
that the trie can be initialized manually before any time critical
code.

=cut
sub gen_basedomain_tree
{
    my (%opts) = @_;

    my @rules;
    if ( $opts{special_rules_only} )
    {
        @rules = @special_rules;
    }
    elsif ( $opts{publicsuffix_rules_only} )
    {
        @rules = @publicsuffix_rules;
    }
    else
    {
        @rules = @default_rules;
    }
    return warn('@rules is empty') if !@rules;
    return \%tree if $initialized;

    for my $line (@rules)
    {
        $line =~ s/\#.*//;
        $line =~ s/\s*$//;
        $line =~ s/^\s*//;
        $line =~ s/\s+/ /g;
        next if ($line eq '');

        #
        # parse
        #

        my($toplevel,$rest) = split(/\s+/,$line,2);

        $valid_tlds{$toplevel} = 1;

        my @levels;
        push(@levels,[ $toplevel ]);

        while ($rest =~ s/^\s*\.?\s*\{\s*(.+?)\s*\}\s*//) {
            my @words = sort split(/\s+/,$1);
            last if ($#words < 0);
            push(@levels,\@words);
            if ($#levels > 5) { warn("too many levels in the config"); last; }
        }

        warn "Badly formatted config line [$toplevel] Rest= $rest\n" if ($rest);

        #
        # build
        #

        gen_tree(\@levels);
    }

    $initialized = 1;
    return \%tree;

}

1;

=head1 Rule Data

The list of TLD rules is generated primarily from the Public Suffic
list from publicsuffix.org and can be found at
L<https://publicsuffix.org/list/effective_tld_names.dat>

Previously rules were generated from the list in the Mozilla source
L<http://lxr.mozilla.org/mozilla/source/netwerk/dns/src/effective_tld_names.dat>
The publicsuffix.org list now supersceeds the Mozilla list.

Additional research was done via the Wikipedia (for example
L<http://en.wikipedia.org/wiki/.uk>) and by consulting the actual NICs
that assign domains (for example L<http://www.kenic.or.ke/>).

=head2 .us rules

The United States of America has some unique rule formats (see
L<http://en.wikipedia.org/wiki/.us>). Including wildcards in the middle
of the TLD. For example in the pattern ci.<locality>.<state>.us,
<state> is one of a fixed set of valid state abreviations, but
<locality> is effectively a wildcard city/town/county/etc, followed by
a fixed list of oranizational types (ci, town, vil, co).

The Mozilla Public Suffix implementation ignores these patterns and
just adds all the known combinations via brute force. This package
honors wildcards mid-pattern.

=head2 Differences with Mozilla's PublicSuffix

There are some rules that Net::Domain::PublicSuffix has added to the
list of rules from publicsuffix.org. These rules are the result of
additional research. For instance L<http://en.wikipedia.org/wiki/.mt>
lists gov.mt as a valid TLD, but it is missing from the
publicsuffix.org list.

These rule lists are kept seperate in the code to make future upgrades
easier. There are two lists: @publicsuffix_rules that are
autogenerated from the publicsuffix.org list and @special_rules for
these additional missing rules.

Net::Domain::PublicSuffix does not support punycode
hostnames. Hostnames need to be decoded before calling base_domain().

=cut

# weird level 2,4,5 domains
# blicio.us, 94087.us (2)
# ci.sunnyvale.ca.us (4)
# pvt.k12.ca.us (4)
#
# Sources:
# http://en.wikipedia.org/
# http://lxr.mozilla.org/mozilla/source/netwerk/dns/src/effective_tld_names.dat?raw=1
# https://publicsuffix.org/list/effective_tld_names.dat
#
# default is two level domains, no need to specify.
# http://www.information.aero/registration/policies/Release_of_reserved_names

@special_rules = split "\n", << '_END_OF_SPECIAL_DATA_';
# .us is "special" see http://en.wikipedia.org/wiki/.us
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la ma md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi }
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la ma md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi } { * } { city ci town vil village co }
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la ma md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi } { state dst cog k12 cc tec lib mus gen }
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi } { k12 } { pvt }
us { ma } { k12 } { pvt chtr paroch }
us { dni fed is-by isa kids land-4-sale nsn stuff-4-sale }
us { }

#
# these are left out of the publicsuffix list. I got these from the
# wikipedia and the controling NIC
#
# can.br are for canidates in elections, maybe ephemeral
br { can }
# can't find indication that org.by is reserved, but seems to be used as a 2nd level domain in practice
by { org }
# cc : http://en.wikipedia.org/wiki/.cc
cc { com net edu org cc co cu }
# can't find refernce to it, but seems to have a number of legacy 2 level domains on co.cu
cu { co }
#http://en.wikipedia.org/wiki/.cy
cy { ac net gov org pro name ekloges tm ltd biz press parliament com }
# evidence of legacy sch.gg https://www.google.com/search?q=site%3Asch.gg
gg { sch }
# http://en.wikipedia.org/wiki/.it
# cannot find a conprehensive list, maybe wildcard rules would be better?
# it { * } { comune provincia regione }
it { barletta-andria-trani }
# both of these exist in the wild
je { gov sch }
# publicsuffix is missing ac.lk rule
lk { ac }
# publicsuffix is missing gov.mt rule
mt { gov }
# publicsuffix is missing co.nr rule
nr { co }
# missing .ru rule
ru { pskov }
# missing .vi rules. .gov.vi is used
vi { edu gov }
# http://en.wikipedia.org/wiki/.za
# http://www.internet.org.za/slds.html
# covered by *.za rule
# za { ac co edu gov law mil nom org agric grondar inca nis }
# missing school.za rule
za { school } { ! }
za { school } { escape fs gp kzn mpm ncape lp nw wcape }
_END_OF_SPECIAL_DATA_

@publicsuffix_rules = split "\n", << '_END_OF_PUBLICSUFFIX_DATA_';
abb { }
abbott { }
abogado { }
ac { }
ac { com edu gov mil net org }
academy { }
accenture { }
accountant { }
accountants { }
aco { }
active { }
actor { }
ad { }
ad { nom }
ads { }
adult { }
ae { }
ae { ac blogspot co gov mil net org sch }
aero { }
aero { accident-investigation accident-prevention aerobatic aeroclub aerodrome agents air-surveillance air-traffic-control aircraft airline airport airtraffic ambulance amusement association author ballooning broker caa cargo catering certification championship charter civilaviation club conference consultant consulting control council crew design dgca educator emergency engine engineer entertainment equipment exchange express federation flight freight fuel gliding government groundhandling group hanggliding homebuilt insurance journal journalist leasing logistics magazine maintenance marketplace media microlight modelling navigation parachuting paragliding passenger-association pilot press production recreation repbody res research rotorcraft safety scientist services show skydiving software student taxi trader trading trainer union workinggroup works }
af { }
af { com edu gov net org }
afl { }
africa { }
ag { }
ag { co com net nom org }
agency { }
ai { }
ai { com net off org }
aig { }
airforce { }
airtel { }
al { }
al { com edu gov mil net org }
alibaba { }
alipay { }
allfinanz { }
alsace { }
am { }
amsterdam { }
an { }
an { com edu net org }
analytics { }
android { }
anquan { }
ao { }
ao { co ed gv it og pb }
apartments { }
aq { }
aquarelle { }
ar { }
ar { com edu gob gov int mil net org tur }
ar { com } { blogspot }
aramco { }
archi { }
army { }
arpa { }
arpa { e164 in-addr ip6 iris uri urn }
arte { }
as { }
as { gov }
asia { }
associates { }
at { }
at { ac biz co gv info or priv }
at { co } { blogspot }
attorney { }
au { }
au { act asn com conf edu gov id info net nsw nt org oz qld sa tas vic wa }
au { com } { blogspot }
au { edu } { act nsw nt qld sa tas vic wa }
au { gov } { qld sa tas vic wa }
auction { }
audio { }
author { }
auto { }
autos { }
avianca { }
aw { }
aw { com }
ax { }
axa { }
az { }
az { biz com edu gov info int mil name net org pp pro }
azure { }
ba { }
ba { co com edu gov mil net org rs unbi unsa }
baidu { }
band { }
bank { }
bar { }
barcelona { }
barclaycard { }
barclays { }
bargains { }
bauhaus { }
bayern { }
bb { }
bb { biz co com edu gov info net org store tv }
bbc { }
bbva { }
bcn { }
bd { * }
be { }
be { ac blogspot }
beer { }
bentley { }
berlin { }
best { }
bf { }
bf { gov }
bg { }
bg { 0 1 2 3 4 5 6 7 8 9 a b c d e f g h i j k l m n o p q r s t u v w x y z }
bh { }
bh { com edu gov net org }
bharti { }
bi { }
bi { co com edu or org }
bible { }
bid { }
bike { }
bing { }
bingo { }
bio { }
biz { }
biz { dyndns for-better for-more for-some for-the selfip webhop }
bj { }
bj { asso barreau blogspot gouv }
black { }
blackfriday { }
bloomberg { }
blue { }
bm { }
bm { com edu gov net org }
bms { }
bmw { }
bn { * }
bnl { }
bnpparibas { }
bo { }
bo { com edu gob gov int mil net org tv }
boats { }
bom { }
bond { }
boo { }
boots { }
bot { }
boutique { }
br { }
br { adm adv agr am arq art ato b bio blog bmd cim cng cnt com coop ecn eco edu emp eng esp etc eti far flog fm fnd fot fst g12 ggf gov imb ind inf jor jus leg lel mat med mil mp mus net not ntr odo org ppg pro psc psi qsl radio rec slg srv taxi teo tmp trd tur tv vet vlog wiki zlg }
br { com } { blogspot }
br { nom } { * }
bradesco { }
bridgestone { }
broadway { }
broker { }
brussels { }
bs { }
bs { com edu gov net org }
bt { }
bt { com edu gov net org }
budapest { }
build { }
builders { }
business { }
buy { }
buzz { }
bv { }
bw { }
bw { co org }
by { }
by { com gov mil of }
bz { }
bz { com edu gov net org za }
bzh { }
ca { }
ca { ab bc blogspot co gc mb nb nf nl ns nt nu on pe qc sk yk }
cab { }
cal { }
call { }
camera { }
camp { }
cancerresearch { }
canon { }
capetown { }
capital { }
car { }
caravan { }
cards { }
care { }
career { }
careers { }
cars { }
cartier { }
casa { }
cash { }
casino { }
cat { }
catering { }
cba { }
cbn { }
cc { }
cc { ftpaccess game-server myphotos scrapping }
cd { }
cd { gov }
center { }
ceo { }
cern { }
cf { }
cf { blogspot }
cfa { }
cfd { }
cg { }
ch { }
ch { blogspot }
channel { }
chat { }
cheap { }
chloe { }
christmas { }
chrome { }
church { }
ci { }
ci { ac asso aéroport co com ed edu go gouv int md net or org presse }
circle { }
cisco { }
citic { }
city { }
cityeats { }
ck { * }
ck { www } { ! }
cl { }
cl { co gob gov mil }
claims { }
cleaning { }
click { }
clinic { }
clothing { }
club { }
cm { }
cm { co com gov net }
cn { }
cn { ac ah bj com cq edu fj gd gov gs gx gz ha hb he hi hk hl hn jl js jx ln mil mo net nm nx org qh sc sd sh sn sx tj tw xj xz yn zj 公司 網絡 网络 }
cn { amazonaws } { compute }
cn { amazonaws } { compute } { cn-north-1 }
co { }
co { arts com edu firm gov info int mil net nom org rec web }
coach { }
codes { }
coffee { }
college { }
cologne { }
com { }
com { africa appspot ar betainabox blogdns blogspot br cechire cloudcontrolapp cloudcontrolled cn co codespot de dnsalias dnsdojo doesntexist dontexist doomdns dreamhosters dyn-o-saur dynalias dyndns-at-home dyndns-at-work dyndns-blog dyndns-free dyndns-home dyndns-ip dyndns-mail dyndns-office dyndns-pics dyndns-remote dyndns-server dyndns-web dyndns-wiki dyndns-work elasticbeanstalk est-a-la-maison est-a-la-masion est-le-patron est-mon-blogueur eu firebaseapp flynnhub from-ak from-al from-ar from-ca from-ct from-dc from-de from-fl from-ga from-hi from-ia from-id from-il from-in from-ks from-ky from-ma from-md from-mi from-mn from-mo from-ms from-mt from-nc from-nd from-ne from-nh from-nj from-nm from-nv from-oh from-ok from-or from-pa from-pr from-ri from-sc from-sd from-tn from-tx from-ut from-va from-vt from-wa from-wi from-wv from-wy gb getmyip githubusercontent googleapis googlecode gotdns gr herokuapp herokussl hk hobby-site homelinux homeunix hu iamallama is-a-anarchist is-a-blogger is-a-bookkeeper is-a-bulls-fan is-a-caterer is-a-chef is-a-conservative is-a-cpa is-a-cubicle-slave is-a-democrat is-a-designer is-a-doctor is-a-financialadvisor is-a-geek is-a-green is-a-guru is-a-hard-worker is-a-hunter is-a-landscaper is-a-lawyer is-a-liberal is-a-libertarian is-a-llama is-a-musician is-a-nascarfan is-a-nurse is-a-painter is-a-personaltrainer is-a-photographer is-a-player is-a-republican is-a-rockstar is-a-socialist is-a-student is-a-teacher is-a-techie is-a-therapist is-an-accountant is-an-actor is-an-actress is-an-anarchist is-an-artist is-an-engineer is-an-entertainer is-certified is-gone is-into-anime is-into-cars is-into-cartoons is-into-games is-leet is-not-certified is-slick is-uberleet is-with-theband isa-geek isa-hockeynut issmarterthanyou jpn kr likes-pie likescandy mex neat-url nfshost no operaunite outsystemscloud pagespeedmobilizer qc rhcloud ro ru sa saves-the-whales se selfip sells-for-less sells-for-u servebbs simple-url space-to-rent teaches-yoga uk us uy withgoogle writesthisblog yolasite za }
com { amazonaws } { compute compute-1 elb s3 s3-ap-northeast-1 s3-ap-southeast-1 s3-ap-southeast-2 s3-eu-west-1 s3-fips-us-gov-west-1 s3-sa-east-1 s3-us-gov-west-1 s3-us-west-1 s3-us-west-2 s3-website-ap-northeast-1 s3-website-ap-southeast-1 s3-website-ap-southeast-2 s3-website-eu-west-1 s3-website-sa-east-1 s3-website-us-east-1 s3-website-us-gov-west-1 s3-website-us-west-1 s3-website-us-west-2 us-east-1 }
com { amazonaws } { compute } { ap-northeast-1 ap-southeast-1 ap-southeast-2 eu-central-1 eu-west-1 sa-east-1 us-gov-west-1 us-west-1 us-west-2 }
com { amazonaws } { compute-1 } { z-1 z-2 }
commbank { }
community { }
company { }
computer { }
comsec { }
condos { }
construction { }
consulting { }
contact { }
contractors { }
cooking { }
cool { }
coop { }
corsica { }
country { }
courses { }
cr { }
cr { ac co ed fi go or sa }
credit { }
creditcard { }
creditunion { }
cricket { }
crown { }
crs { }
cruises { }
csc { }
cu { }
cu { com edu gov inf net org }
cuisinella { }
cv { }
cv { blogspot }
cw { }
cw { com edu net org }
cx { }
cx { ath gov }
cy { * }
cymru { }
cyou { }
cz { }
cz { blogspot }
dabur { }
dad { }
dance { }
date { }
dating { }
datsun { }
day { }
dclk { }
de { }
de { blogspot com fuettertdasnetz isteingeek istmein lebtimnetz leitungsen traeumtgerade }
dealer { }
deals { }
degree { }
delivery { }
dell { }
democrat { }
dental { }
dentist { }
desi { }
design { }
dev { }
diamonds { }
diet { }
digital { }
direct { }
directory { }
discount { }
dj { }
dk { }
dk { blogspot }
dm { }
dm { com edu gov net org }
dnp { }
do { }
do { art com edu gob gov mil net org sld web }
docs { }
dog { }
doha { }
domains { }
doosan { }
download { }
dubai { }
durban { }
dvag { }
dz { }
dz { art asso com edu gov net org pol }
earth { }
eat { }
ec { }
ec { com edu fin gob gov info k12 med mil net org pro }
edeka { }
edu { }
education { }
ee { }
ee { aip com edu fie gov lib med org pri riik }
eg { }
eg { com edu eun gov mil name net org sci }
email { }
emerck { }
energy { }
engineer { }
engineering { }
enterprises { }
epson { }
equipment { }
er { * }
erni { }
es { }
es { com edu gob nom org }
es { com } { blogspot }
esq { }
estate { }
et { }
et { biz com edu gov info name org }
eu { }
eurovision { }
eus { }
events { }
everbank { }
exchange { }
expert { }
exposed { }
fage { }
fail { }
fairwinds { }
faith { }
fan { }
fans { }
farm { }
fashion { }
fast { }
feedback { }
ferrero { }
fi { }
fi { aland blogspot iki }
film { }
final { }
finance { }
financial { }
firestone { }
firmdale { }
fish { }
fishing { }
fit { }
fitness { }
fj { * }
fk { * }
flights { }
florist { }
flowers { }
flsmidth { }
fly { }
fm { }
fo { }
foo { }
football { }
ford { }
forex { }
forsale { }
foundation { }
fr { }
fr { aeroport assedic asso avocat avoues blogspot cci chambagri chirurgiens-dentistes com experts-comptables geometre-expert gouv greta huissier-justice medecin nom notaires pharmacien port prd presse tm veterinaire }
frl { }
frogans { }
fund { }
furniture { }
futbol { }
ga { }
gal { }
gallery { }
garden { }
gb { }
gbiz { }
gd { }
gdn { }
ge { }
ge { com edu gov mil net org pvt }
gea { }
gent { }
gf { }
gg { }
gg { co net org }
ggee { }
gh { }
gh { com edu gov mil org }
gi { }
gi { com edu gov ltd mod org }
gift { }
gifts { }
gives { }
giving { }
gl { }
glass { }
gle { }
global { }
globo { }
gm { }
gmail { }
gmo { }
gmx { }
gn { }
gn { ac com edu gov net org }
gold { }
goldpoint { }
golf { }
goo { }
goog { }
google { }
gop { }
got { }
gov { }
gp { }
gp { asso com edu mobi net org }
gq { }
gr { }
gr { blogspot com edu gov net org }
graphics { }
gratis { }
green { }
gripe { }
group { }
gs { }
gt { }
gt { com edu gob ind mil net org }
gu { * }
gucci { }
guge { }
guide { }
guitars { }
guru { }
gw { }
gy { }
gy { co com net }
hamburg { }
hangout { }
haus { }
healthcare { }
help { }
here { }
hermes { }
hiphop { }
hitachi { }
hiv { }
hk { }
hk { blogspot com edu gov idv inc ltd net org 个人 個人 公司 政府 敎育 教育 箇人 組織 組织 網絡 網络 组織 组织 网絡 网络 }
hm { }
hn { }
hn { com edu gob mil net org }
holdings { }
holiday { }
homes { }
honda { }
horse { }
host { }
hosting { }
hotmail { }
house { }
how { }
hr { }
hr { com from iz name }
hsbc { }
ht { }
ht { adult art asso com coop edu firm gouv info med net org perso pol pro rel shop }
hu { }
hu { 2000 agrar blogspot bolt casino city co erotica erotika film forum games hotel info ingatlan jogasz konyvelo lakas media news org priv reklam sex shop sport suli szex tm tozsde utazas video }
ibm { }
ice { }
icu { }
id { }
id { ac biz co desa go mil my net or sch web }
ie { }
ie { blogspot gov }
ifm { }
iinet { }
il { * }
il { co } { blogspot }
im { }
im { ac co com net org tt tv }
im { co } { ltd plc }
immo { }
immobilien { }
in { }
in { ac blogspot co edu firm gen gov ind mil net nic org res }
industries { }
infiniti { }
info { }
info { barrel-of-knowledge barrell-of-knowledge dyndns for-our groks-the groks-this here-for-more knowsitall selfip webhop }
ing { }
ink { }
institute { }
insure { }
int { }
int { eu }
international { }
investments { }
io { }
io { com github nid }
ipiranga { }
iq { }
iq { com edu gov mil net org }
ir { }
ir { ac co gov id net org sch ايران ایران }
irish { }
is { }
is { com cupcake edu gov int net org }
ist { }
istanbul { }
it { }
it { abr abruzzo ag agrigento al alessandria alto-adige altoadige an ancona andria-barletta-trani andria-trani-barletta andriabarlettatrani andriatranibarletta ao aosta aosta-valley aostavalley aoste ap aq aquila ar arezzo ascoli-piceno ascolipiceno asti at av avellino ba balsan bari barletta-trani-andria barlettatraniandria bas basilicata belluno benevento bergamo bg bi biella bl blogspot bn bo bologna bolzano bozen br brescia brindisi bs bt bz ca cagliari cal calabria caltanissetta cam campania campidano-medio campidanomedio campobasso carbonia-iglesias carboniaiglesias carrara-massa carraramassa caserta catania catanzaro cb ce cesena-forli cesenaforli ch chieti ci cl cn co como cosenza cr cremona crotone cs ct cuneo cz dell-ogliastra dellogliastra edu emilia-romagna emiliaromagna emr en enna fc fe fermo ferrara fg fi firenze florence fm foggia forli-cesena forlicesena fr friuli-v-giulia friuli-ve-giulia friuli-vegiulia friuli-venezia-giulia friuli-veneziagiulia friuli-vgiulia friuliv-giulia friulive-giulia friulivegiulia friulivenezia-giulia friuliveneziagiulia friulivgiulia frosinone fvg ge genoa genova go gorizia gov gr grosseto iglesias-carbonia iglesiascarbonia im imperia is isernia kr la-spezia laquila laspezia latina laz lazio lc le lecce lecco li lig liguria livorno lo lodi lom lombardia lombardy lt lu lucania lucca macerata mantova mar marche massa-carrara massacarrara matera mb mc me medio-campidano mediocampidano messina mi milan milano mn mo modena mol molise monza monza-brianza monza-e-della-brianza monzabrianza monzaebrianza monzaedellabrianza ms mt na naples napoli no novara nu nuoro og ogliastra olbia-tempio olbiatempio or oristano ot pa padova padua palermo parma pavia pc pd pe perugia pesaro-urbino pesarourbino pescara pg pi piacenza piedmont piemonte pisa pistoia pmn pn po pordenone potenza pr prato pt pu pug puglia pv pz ra ragusa ravenna rc re reggio-calabria reggio-emilia reggiocalabria reggioemilia rg ri rieti rimini rm rn ro roma rome rovigo sa salerno sar sardegna sardinia sassari savona si sic sicilia sicily siena siracusa so sondrio sp sr ss suedtirol sv ta taa taranto te tempio-olbia tempioolbia teramo terni tn to torino tos toscana tp tr trani-andria-barletta trani-barletta-andria traniandriabarletta tranibarlettaandria trapani trentino trentino-a-adige trentino-aadige trentino-alto-adige trentino-altoadige trentino-s-tirol trentino-stirol trentino-sud-tirol trentino-sudtirol trentino-sued-tirol trentino-suedtirol trentinoa-adige trentinoaadige trentinoalto-adige trentinoaltoadige trentinos-tirol trentinostirol trentinosud-tirol trentinosudtirol trentinosued-tirol trentinosuedtirol trento treviso trieste ts turin tuscany tv ud udine umb umbria urbino-pesaro urbinopesaro va val-d-aosta val-daosta vald-aosta valdaosta valle-aosta valle-d-aosta valle-daosta valleaosta valled-aosta valledaosta vallee-aoste valleeaoste vao varese vb vc vda ve ven veneto venezia venice verbania vercelli verona vi vibo-valentia vibovalentia vicenza viterbo vr vs vt vv }
itau { }
iwc { }
jaguar { }
java { }
jcb { }
je { }
je { co net org }
jetzt { }
jlc { }
jm { * }
jo { }
jo { com edu gov mil name net org sch }
jobs { }
joburg { }
jot { }
joy { }
jp { }
jp { ac ad aichi akita aomori blogspot chiba co ed ehime fukui fukuoka fukushima gifu go gr gunma hiroshima hokkaido hyogo ibaraki ishikawa iwate kagawa kagoshima kanagawa kochi kumamoto kyoto lg mie miyagi miyazaki nagano nagasaki nara ne niigata oita okayama okinawa or osaka saga saitama shiga shimane shizuoka tochigi tokushima tokyo tottori toyama wakayama yamagata yamaguchi yamanashi 三重 京都 佐賀 兵庫 北海道 千葉 和歌山 埼玉 大分 大阪 奈良 宮城 宮崎 富山 山口 山形 山梨 岐阜 岡山 岩手 島根 広島 徳島 愛媛 愛知 新潟 東京 栃木 沖縄 滋賀 熊本 石川 神奈川 福井 福岡 福島 秋田 群馬 茨城 長崎 長野 青森 静岡 香川 高知 鳥取 鹿児島 }
jp { aichi } { aisai ama anjo asuke chiryu chita fuso gamagori handa hazu hekinan higashiura ichinomiya inazawa inuyama isshiki iwakura kanie kariya kasugai kira kiyosu komaki konan kota mihama miyoshi nishio nisshin obu oguchi oharu okazaki owariasahi seto shikatsu shinshiro shitara tahara takahama tobishima toei togo tokai tokoname toyoake toyohashi toyokawa toyone toyota tsushima yatomi }
jp { akita } { akita daisen fujisato gojome hachirogata happou higashinaruse honjo honjyo ikawa kamikoani kamioka katagami kazuno kitaakita kosaka kyowa misato mitane moriyoshi nikaho noshiro odate oga ogata semboku yokote yurihonjo }
jp { aomori } { aomori gonohe hachinohe hashikami hiranai hirosaki itayanagi kuroishi misawa mutsu nakadomari noheji oirase owani rokunohe sannohe shichinohe shingo takko towada tsugaru tsuruta }
jp { chiba } { abiko asahi chonan chosei choshi chuo funabashi futtsu hanamigawa ichihara ichikawa ichinomiya inzai isumi kamagaya kamogawa kashiwa katori katsuura kimitsu kisarazu kozaki kujukuri kyonan matsudo midori mihama minamiboso mobara mutsuzawa nagara nagareyama narashino narita noda oamishirasato omigawa onjuku otaki sakae sakura shimofusa shirako shiroi shisui sodegaura sosa tako tateyama togane tohnosho tomisato urayasu yachimata yachiyo yokaichiba yokoshibahikari yotsukaido }
jp { ehime } { ainan honai ikata imabari iyo kamijima kihoku kumakogen masaki matsuno matsuyama namikata niihama ozu saijo seiyo shikokuchuo tobe toon uchiko uwajima yawatahama }
jp { fukui } { echizen eiheiji fukui ikeda katsuyama mihama minamiechizen obama ohi ono sabae sakai takahama tsuruga wakasa }
jp { fukuoka } { ashiya buzen chikugo chikuho chikujo chikushino chikuzen chuo dazaifu fukuchi hakata higashi hirokawa hisayama iizuka inatsuki kaho kasuga kasuya kawara keisen koga kurate kurogi kurume minami miyako miyama miyawaka mizumaki munakata nakagawa nakama nishi nogata ogori okagaki okawa oki omuta onga onojo oto saigawa sasaguri shingu shinyoshitomi shonai soeda sue tachiarai tagawa takata toho toyotsu tsuiki ukiha umi usui yamada yame yanagawa yukuhashi }
jp { fukushima } { aizubange aizumisato aizuwakamatsu asakawa bandai date fukushima furudono futaba hanawa higashi hirata hirono iitate inawashiro ishikawa iwaki izumizaki kagamiishi kaneyama kawamata kitakata kitashiobara koori koriyama kunimi miharu mishima namie nango nishiaizu nishigo okuma omotego ono otama samegawa shimogo shirakawa showa soma sukagawa taishin tamakawa tanagura tenei yabuki yamato yamatsuri yanaizu yugawa }
jp { gifu } { anpachi ena gifu ginan godo gujo hashima hichiso hida higashishirakawa ibigawa ikeda kakamigahara kani kasahara kasamatsu kawaue kitagata mino minokamo mitake mizunami motosu nakatsugawa ogaki sakahogi seki sekigahara shirakawa tajimi takayama tarui toki tomika wanouchi yamagata yaotsu yoro }
jp { gunma } { annaka chiyoda fujioka higashiagatsuma isesaki itakura kanna kanra katashina kawaba kiryu kusatsu maebashi meiwa midori minakami naganohara nakanojo nanmoku numata oizumi ora ota shibukawa shimonita shinto showa takasaki takayama tamamura tatebayashi tomioka tsukiyono tsumagoi ueno yoshioka }
jp { hiroshima } { asaminami daiwa etajima fuchu fukuyama hatsukaichi higashihiroshima hongo jinsekikogen kaita kui kumano kure mihara miyoshi naka onomichi osakikamijima otake saka sera seranishi shinichi shobara takehara }
jp { hokkaido } { abashiri abira aibetsu akabira akkeshi asahikawa ashibetsu ashoro assabu atsuma bibai biei bifuka bihoro biratori chippubetsu chitose date ebetsu embetsu eniwa erimo esan esashi fukagawa fukushima furano furubira haboro hakodate hamatonbetsu hidaka higashikagura higashikawa hiroo hokuryu hokuto honbetsu horokanai horonobe ikeda imakane ishikari iwamizawa iwanai kamifurano kamikawa kamishihoro kamisunagawa kamoenai kayabe kembuchi kikonai kimobetsu kitahiroshima kitami kiyosato koshimizu kunneppu kuriyama kuromatsunai kushiro kutchan kyowa mashike matsumae mikasa minamifurano mombetsu moseushi mukawa muroran naie nakagawa nakasatsunai nakatombetsu nanae nanporo nayoro nemuro niikappu niki nishiokoppe noboribetsu numata obihiro obira oketo okoppe otaru otobe otofuke otoineppu oumu ozora pippu rankoshi rebun rikubetsu rishiri rishirifuji saroma sarufutsu shakotan shari shibecha shibetsu shikabe shikaoi shimamaki shimizu shimokawa shinshinotsu shintoku shiranuka shiraoi shiriuchi sobetsu sunagawa taiki takasu takikawa takinoue teshikaga tobetsu tohma tomakomai tomari toya toyako toyotomi toyoura tsubetsu tsukigata urakawa urausu uryu utashinai wakkanai wassamu yakumo yoichi }
jp { hyogo } { aioi akashi ako amagasaki aogaki asago ashiya awaji fukusaki goshiki harima himeji ichikawa inagawa itami kakogawa kamigori kamikawa kasai kasuga kawanishi miki minamiawaji nishinomiya nishiwaki ono sanda sannan sasayama sayo shingu shinonsen shiso sumoto taishi taka takarazuka takasago takino tamba tatsuno toyooka yabu yashiro yoka yokawa }
jp { ibaraki } { ami asahi bando chikusei daigo fujishiro hitachi hitachinaka hitachiomiya hitachiota ibaraki ina inashiki itako iwama joso kamisu kasama kashima kasumigaura koga miho mito moriya naka namegata oarai ogawa omitama ryugasaki sakai sakuragawa shimodate shimotsuma shirosato sowa suifu takahagi tamatsukuri tokai tomobe tone toride tsuchiura tsukuba uchihara ushiku yachiyo yamagata yawara yuki }
jp { ishikawa } { anamizu hakui hakusan kaga kahoku kanazawa kawakita komatsu nakanoto nanao nomi nonoichi noto shika suzu tsubata tsurugi uchinada wajima }
jp { iwate } { fudai fujisawa hanamaki hiraizumi hirono ichinohe ichinoseki iwaizumi iwate joboji kamaishi kanegasaki karumai kawai kitakami kuji kunohe kuzumaki miyako mizusawa morioka ninohe noda ofunato oshu otsuchi rikuzentakata shiwa shizukuishi sumita tanohata tono yahaba yamada }
jp { kagawa } { ayagawa higashikagawa kanonji kotohira manno marugame mitoyo naoshima sanuki tadotsu takamatsu tonosho uchinomi utazu zentsuji }
jp { kagoshima } { akune amami hioki isa isen izumi kagoshima kanoya kawanabe kinko kouyama makurazaki matsumoto minamitane nakatane nishinoomote satsumasendai soo tarumizu yusui }
jp { kanagawa } { aikawa atsugi ayase chigasaki ebina fujisawa hadano hakone hiratsuka isehara kaisei kamakura kiyokawa matsuda minamiashigara miura nakai ninomiya odawara oi oiso sagamihara samukawa tsukui yamakita yamato yokosuka yugawara zama zushi }
jp { kawasaki } { * }
jp { kawasaki } { city } { ! }
jp { kitakyushu } { * }
jp { kitakyushu } { city } { ! }
jp { kobe } { * }
jp { kobe } { city } { ! }
jp { kochi } { aki geisei hidaka higashitsuno ino kagami kami kitagawa kochi mihara motoyama muroto nahari nakamura nankoku nishitosa niyodogawa ochi okawa otoyo otsuki sakawa sukumo susaki tosa tosashimizu toyo tsuno umaji yasuda yusuhara }
jp { kumamoto } { amakusa arao aso choyo gyokuto hitoyoshi kamiamakusa kashima kikuchi kosa kumamoto mashiki mifune minamata minamioguni nagasu nishihara oguni ozu sumoto takamori uki uto yamaga yamato yatsushiro }
jp { kyoto } { ayabe fukuchiyama higashiyama ide ine joyo kameoka kamo kita kizu kumiyama kyotamba kyotanabe kyotango maizuru minami minamiyamashiro miyazu muko nagaokakyo nakagyo nantan oyamazaki sakyo seika tanabe uji ujitawara wazuka yamashina yawata }
jp { mie } { asahi inabe ise kameyama kawagoe kiho kisosaki kiwa komono kumano kuwana matsusaka meiwa mihama minamiise misugi miyama nabari shima suzuka tado taiki taki tamaki toba tsu udono ureshino watarai yokkaichi }
jp { miyagi } { furukawa higashimatsushima ishinomaki iwanuma kakuda kami kawasaki kesennuma marumori matsushima minamisanriku misato murata natori ogawara ohira onagawa osaki rifu semine shibata shichikashuku shikama shiogama shiroishi tagajo taiwa tome tomiya wakuya watari yamamoto zao }
jp { miyazaki } { aya ebino gokase hyuga kadogawa kawaminami kijo kitagawa kitakata kitaura kobayashi kunitomi kushima mimata miyakonojo miyazaki morotsuka nichinan nishimera nobeoka saito shiiba shintomi takaharu takanabe takazaki tsuno }
jp { nagano } { achi agematsu anan aoki asahi azumino chikuhoku chikuma chino fujimi hakuba hara hiraya iida iijima iiyama iizuna ikeda ikusaka ina karuizawa kawakami kiso kisofukushima kitaaiki komagane komoro matsukawa matsumoto miasa minamiaiki minamimaki minamiminowa minowa miyada miyota mochizuki nagano nagawa nagiso nakagawa nakano nozawaonsen obuse ogawa okaya omachi omi ookuwa ooshika otaki otari sakae sakaki saku sakuho shimosuwa shinanomachi shiojiri suwa suzaka takagi takamori takayama tateshina tatsuno togakushi togura tomi ueda wada yamagata yamanouchi yasaka yasuoka }
jp { nagasaki } { chijiwa futsu goto hasami hirado iki isahaya kawatana kuchinotsu matsuura nagasaki obama omura oseto saikai sasebo seihi shimabara shinkamigoto togitsu tsushima unzen }
jp { nagoya } { * }
jp { nagoya } { city } { ! }
jp { nara } { ando gose heguri higashiyoshino ikaruga ikoma kamikitayama kanmaki kashiba kashihara katsuragi kawai kawakami kawanishi koryo kurotaki mitsue miyake nara nosegawa oji ouda oyodo sakurai sango shimoichi shimokitayama shinjo soni takatori tawaramoto tenkawa tenri uda yamatokoriyama yamatotakada yamazoe yoshino }
jp { niigata } { aga agano gosen itoigawa izumozaki joetsu kamo kariwa kashiwazaki minamiuonuma mitsuke muika murakami myoko nagaoka niigata ojiya omi sado sanjo seiro seirou sekikawa shibata tagami tainai tochio tokamachi tsubame tsunan uonuma yahiko yoita yuzawa }
jp { oita } { beppu bungoono bungotakada hasama hiji himeshima hita kamitsue kokonoe kuju kunisaki kusu oita saiki taketa tsukumi usa usuki yufu }
jp { okayama } { akaiwa asakuchi bizen hayashima ibara kagamino kasaoka kibichuo kumenan kurashiki maniwa misaki nagi niimi nishiawakura okayama satosho setouchi shinjo shoo soja takahashi tamano tsuyama wake yakage }
jp { okinawa } { aguni ginowan ginoza gushikami haebaru higashi hirara iheya ishigaki ishikawa itoman izena kadena kin kitadaito kitanakagusuku kumejima kunigami minamidaito motobu nago naha nakagusuku nakijin nanjo nishihara ogimi okinawa onna shimoji taketomi tarama tokashiki tomigusuku tonaki urasoe uruma yaese yomitan yonabaru yonaguni zamami }
jp { osaka } { abeno chihayaakasaka chuo daito fujiidera habikino hannan higashiosaka higashisumiyoshi higashiyodogawa hirakata ibaraki ikeda izumi izumiotsu izumisano kadoma kaizuka kanan kashiwara katano kawachinagano kishiwada kita kumatori matsubara minato minoh misaki moriguchi neyagawa nishi nose osakasayama sakai sayama sennan settsu shijonawate shimamoto suita tadaoka taishi tajiri takaishi takatsuki tondabayashi toyonaka toyono yao }
jp { saga } { ariake arita fukudomi genkai hamatama hizen imari kamimine kanzaki karatsu kashima kitagata kitahata kiyama kouhoku kyuragi nishiarita ogi omachi ouchi saga shiroishi taku tara tosu yoshinogari }
jp { saitama } { arakawa asaka chichibu fujimi fujimino fukaya hanno hanyu hasuda hatogaya hatoyama hidaka higashichichibu higashimatsuyama honjo ina iruma iwatsuki kamiizumi kamikawa kamisato kasukabe kawagoe kawaguchi kawajima kazo kitamoto koshigaya kounosu kuki kumagaya matsubushi minano misato miyashiro miyoshi moroyama nagatoro namegawa niiza ogano ogawa ogose okegawa omiya otaki ranzan ryokami saitama sakado satte sayama shiki shiraoka soka sugito toda tokigawa tokorozawa tsurugashima urawa warabi yashio yokoze yono yorii yoshida yoshikawa yoshimi }
jp { sapporo } { * }
jp { sapporo } { city } { ! }
jp { sendai } { * }
jp { sendai } { city } { ! }
jp { shiga } { aisho gamo higashiomi hikone koka konan kosei koto kusatsu maibara moriyama nagahama nishiazai notogawa omihachiman otsu ritto ryuoh takashima takatsuki torahime toyosato yasu }
jp { shimane } { akagi ama gotsu hamada higashiizumo hikawa hikimi izumo kakinoki masuda matsue misato nishinoshima ohda okinoshima okuizumo shimane tamayu tsuwano unnan yakumo yasugi yatsuka }
jp { shizuoka } { arai atami fuji fujieda fujikawa fujinomiya fukuroi gotemba haibara hamamatsu higashiizu ito iwata izu izunokuni kakegawa kannami kawanehon kawazu kikugawa kosai makinohara matsuzaki minamiizu mishima morimachi nishiizu numazu omaezaki shimada shimizu shimoda shizuoka susono yaizu yoshida }
jp { tochigi } { ashikaga bato haga ichikai iwafune kaminokawa kanuma karasuyama kuroiso mashiko mibu moka motegi nasu nasushiobara nikko nishikata nogi ohira ohtawara oyama sakura sano shimotsuke shioya takanezawa tochigi tsuga ujiie utsunomiya yaita }
jp { tokushima } { aizumi anan ichiba itano kainan komatsushima matsushige mima minami miyoshi mugi nakagawa naruto sanagochi shishikui tokushima wajiki }
jp { tokyo } { adachi akiruno akishima aogashima arakawa bunkyo chiyoda chofu chuo edogawa fuchu fussa hachijo hachioji hamura higashikurume higashimurayama higashiyamato hino hinode hinohara inagi itabashi katsushika kita kiyose kodaira koganei kokubunji komae koto kouzushima kunitachi machida meguro minato mitaka mizuho musashimurayama musashino nakano nerima ogasawara okutama ome oshima ota setagaya shibuya shinagawa shinjuku suginami sumida tachikawa taito tama toshima }
jp { tottori } { chizu hino kawahara koge kotoura misasa nanbu nichinan sakaiminato tottori wakasa yazu yonago }
jp { toyama } { asahi fuchu fukumitsu funahashi himi imizu inami johana kamiichi kurobe nakaniikawa namerikawa nanto nyuzen oyabe taira takaoka tateyama toga tonami toyama unazuki uozu yamada }
jp { wakayama } { arida aridagawa gobo hashimoto hidaka hirogawa inami iwade kainan kamitonda katsuragi kimino kinokawa kitayama koya koza kozagawa kudoyama kushimoto mihama misato nachikatsuura shingu shirahama taiji tanabe wakayama yuasa yura }
jp { yamagata } { asahi funagata higashine iide kahoku kaminoyama kaneyama kawanishi mamurogawa mikawa murayama nagai nakayama nanyo nishikawa obanazawa oe oguni ohkura oishida sagae sakata sakegawa shinjo shirataka shonai takahata tendo tozawa tsuruoka yamagata yamanobe yonezawa yuza }
jp { yamaguchi } { abu hagi hikari hofu iwakuni kudamatsu mitou nagato oshima shimonoseki shunan tabuse tokuyama toyota ube yuu }
jp { yamanashi } { chuo doshi fuefuki fujikawa fujikawaguchiko fujiyoshida hayakawa hokuto ichikawamisato kai kofu koshu kosuge minami-alps minobu nakamichi nanbu narusawa nirasaki nishikatsura oshino otsuki showa tabayama tsuru uenohara yamanakako yamanashi }
jp { yokohama } { * }
jp { yokohama } { city } { ! }
jprs { }
juegos { }
kaufen { }
kddi { }
ke { * }
kfh { }
kg { }
kg { com edu gov mil net org }
kh { * }
ki { }
ki { biz com edu gov info net org }
kim { }
kinder { }
kitchen { }
kiwi { }
km { }
km { ass asso com coop edu gouv gov medecin mil nom notaires org pharmaciens prd presse tm veterinaire }
kn { }
kn { edu gov net org }
koeln { }
komatsu { }
kp { }
kp { com edu gov org rep tra }
kpn { }
kr { }
kr { ac blogspot busan chungbuk chungnam co daegu daejeon es gangwon go gwangju gyeongbuk gyeonggi gyeongnam hs incheon jeju jeonbuk jeonnam kg mil ms ne or pe re sc seoul ulsan }
krd { }
kred { }
kw { * }
ky { }
ky { com edu gov net org }
kyoto { }
kz { }
kz { com edu gov mil net org }
la { }
la { c com edu gov info int net org per }
lacaixa { }
land { }
landrover { }
lat { }
latrobe { }
law { }
lawyer { }
lb { }
lb { com edu gov net org }
lc { }
lc { co com edu gov net org }
lds { }
lease { }
leclerc { }
legal { }
lgbt { }
li { }
liaison { }
lidl { }
life { }
lifeinsurance { }
lifestyle { }
lighting { }
like { }
limited { }
limo { }
lincoln { }
linde { }
link { }
live { }
lk { }
lk { assn com edu gov grp hotel int ltd net ngo org sch soc web }
loan { }
loans { }
london { }
lotte { }
lotto { }
love { }
lr { }
lr { com edu gov net org }
ls { }
ls { co org }
lt { }
lt { gov }
ltd { }
ltda { }
lu { }
lupin { }
luxe { }
luxury { }
lv { }
lv { asn com conf edu gov id mil net org }
ly { }
ly { com edu gov id med net org plc sch }
ma { }
ma { ac co gov net org press }
madrid { }
maif { }
maison { }
makeup { }
man { }
management { }
mango { }
market { }
marketing { }
markets { }
marriott { }
mc { }
mc { asso tm }
md { }
me { }
me { ac co edu gov its net org priv }
media { }
meet { }
melbourne { }
meme { }
memorial { }
menu { }
meo { }
mg { }
mg { com edu gov mil nom org prd tm }
mh { }
miami { }
microsoft { }
mil { }
mini { }
mk { }
mk { com edu gov inf name net org }
ml { }
ml { com edu gouv gov net org presse }
mm { * }
mma { }
mn { }
mn { edu gov nyc org }
mo { }
mo { com edu gov net org }
mobi { }
mobily { }
moda { }
moe { }
moi { }
monash { }
money { }
montblanc { }
mormon { }
mortgage { }
moscow { }
motorcycles { }
mov { }
movistar { }
mp { }
mq { }
mr { }
mr { blogspot gov }
ms { }
ms { com edu gov net org }
mt { }
mt { com edu net org }
mtn { }
mtpc { }
mu { }
mu { ac co com gov net or org }
museum { }
museum { academy agriculture air airguard alabama alaska amber ambulance american americana americanantiques americanart amsterdam and annefrank anthro anthropology antiques aquarium arboretum archaeological archaeology architecture art artanddesign artcenter artdeco arteducation artgallery arts artsandcrafts asmatart assassination assisi association astronomy atlanta austin australia automotive aviation axis badajoz baghdad bahn bale baltimore barcelona baseball basel baths bauern beauxarts beeldengeluid bellevue bergbau berkeley berlin bern bible bilbao bill birdart birthplace bonn boston botanical botanicalgarden botanicgarden botany brandywinevalley brasil bristol british britishcolumbia broadcast brunel brussel brussels bruxelles building burghof bus bushey cadaques california cambridge can canada capebreton carrier cartoonart casadelamoneda castle castres celtic center chattanooga cheltenham chesapeakebay chicago children childrens childrensgarden chiropractic chocolate christiansburg cincinnati cinema circus civilisation civilization civilwar clinton clock coal coastaldefence cody coldwar collection colonialwilliamsburg coloradoplateau columbia columbus communication communications community computer computerhistory comunicações contemporary contemporaryart convent copenhagen corporation correios-e-telecomunicações corvette costume countryestate county crafts cranbrook creation cultural culturalcenter culture cyber cymru dali dallas database ddr decorativearts delaware delmenhorst denmark depot design detroit dinosaur discovery dolls donostia durham eastafrica eastcoast education educational egyptian eisenbahn elburg elvendrell embroidery encyclopedic england entomology environment environmentalconservation epilepsy essex estate ethnology exeter exhibition family farm farmequipment farmers farmstead field figueres filatelia film fineart finearts finland flanders florida force fortmissoula fortworth foundation francaise frankfurt franziskaner freemasonry freiburg fribourg frog fundacio furniture gallery garden gateway geelvinck gemological geology georgia giessen glas glass gorge grandrapids graz guernsey halloffame hamburg handson harvestcelebration hawaii health heimatunduhren hellas helsinki hembygdsforbund heritage histoire historical historicalsociety historichouses historisch historisches history historyofscience horology house humanities illustration imageandsound indian indiana indianapolis indianmarket intelligence interactive iraq iron isleofman jamison jefferson jerusalem jewelry jewish jewishart jfk journalism judaica judygarland juedisches juif karate karikatur kids koebenhavn koeln kunst kunstsammlung kunstunddesign labor labour lajolla lancashire landes lans larsson lewismiller lincoln linz living livinghistory localhistory london losangeles louvre loyalist lucerne luxembourg luzern läns mad madrid mallorca manchester mansion mansions manx marburg maritime maritimo maryland marylhurst media medical medizinhistorisches meeres memorial mesaverde michigan midatlantic military mill miners mining minnesota missile missoula modern moma money monmouth monticello montreal moscow motorcycle muenchen muenster mulhouse muncie museet museumcenter museumvereniging music national nationalfirearms nationalheritage nativeamerican naturalhistory naturalhistorymuseum naturalsciences nature naturhistorisches natuurwetenschappen naumburg naval nebraska neues newhampshire newjersey newmexico newport newspaper newyork niepce norfolk north nrw nuernberg nuremberg nyc nyny oceanographic oceanographique omaha online ontario openair oregon oregontrail otago oxford pacific paderborn palace paleo palmsprings panama paris pasadena pharmacy philadelphia philadelphiaarea philately phoenix photography pilots pittsburgh planetarium plantation plants plaza portal portland portlligat posts-and-telecommunications preservation presidio press project public pubol quebec railroad railway research resistance riodejaneiro rochester rockart roma russia saintlouis salem salvadordali salzburg sandiego sanfrancisco santabarbara santacruz santafe saskatchewan satx savannahga schlesisches schoenbrunn schokoladen school schweiz science science-fiction scienceandhistory scienceandindustry sciencecenter sciencecenters sciencehistory sciences sciencesnaturelles scotland seaport settlement settlers shell sherbrooke sibenik silk ski skole society sologne soundandvision southcarolina southwest space spy square stadt stalbans starnberg state stateofdelaware station steam steiermark stjohn stockholm stpetersburg stuttgart suisse surgeonshall surrey svizzera sweden sydney tank tcm technology telekommunikation television texas textile theater time timekeeping topology torino touch town transport tree trolley trust trustee uhren ulm undersea university usa usantiques usarts uscountryestate usculture usdecorativearts usgarden ushistory ushuaia uslivinghistory utah uvic valley vantaa versailles viking village virginia virtual virtuel vlaanderen volkenkunde wales wallonie war washingtondc watch-and-clock watchandclock western westfalen whaling wildlife williamsburg windmill workshop york yorkshire yosemite youth zoological zoology иком ירושלים }
mv { }
mv { aero biz com coop edu gov info int mil museum name net org pro }
mw { }
mw { ac biz co com coop edu gov int museum net org }
mx { }
mx { blogspot com edu gob net org }
my { }
my { com edu gov mil name net org }
mz { * }
mz { teledata } { ! }
na { }
na { ca cc co com dr in info mobi mx name or org pro school tv us ws }
nadex { }
nagoya { }
name { }
name { her } { forgot }
name { his } { forgot }
navy { }
nc { }
nc { asso }
ne { }
nec { }
net { }
net { at-band-camp azure-mobile azurewebsites blogdns broke-it buyshouses cloudapp cloudfront dnsalias dnsdojo does-it dontexist dynalias dynathome endofinternet from-az from-co from-la from-ny gb gets-it ham-radio-op homeftp homeip homelinux homeunix hu in in-the-band is-a-chef is-a-geek isa-geek jp kicks-ass office-on-the podzone scrapper-site se selfip sells-it servebbs serveftp thruhere uk webhop za }
net { fastly } { prod } { a global }
net { fastly } { ssl } { a b global }
netbank { }
network { }
neustar { }
new { }
news { }
nexus { }
nf { }
nf { arts com firm info net other per rec store web }
ng { }
ng { com edu gov mil mobi name net org sch }
ngo { }
nhk { }
ni { * }
nico { }
ninja { }
nissan { }
nl { }
nl { blogspot bv co }
no { }
no { aa aarborte aejrie afjord agdenes ah aknoluokta akrehamn al alaheadju alesund algard alstahaug alta alvdal amli amot andasuolo andebu andoy andøy ardal aremark arendal arna aseral asker askim askoy askvoll askøy asnes audnedaln aukra aure aurland aurskog-holand aurskog-høland austevoll austrheim averoy averøy badaddja bahcavuotna bahccavuotna baidar bajddar balat balestrand ballangen balsfjord bamble bardu barum batsfjord bearalvahki bearalváhki beardu beiarn berg bergen berlevag berlevåg bievat bievát bindal birkenes bjarkoy bjarkøy bjerkreim bjugn blogspot bodo bodø bokn bomlo bremanger bronnoy bronnoysund brumunddal bryne brønnøy brønnøysund bu budejju bygland bykle báhcavuotna báhccavuotna báidár bájddar bálát bådåddjå båtsfjord bærum bømlo cahcesuolo co davvenjarga davvenjárga davvesiida deatnu dep dielddanuorri divtasvuodna divttasvuotna donna dovre drammen drangedal drobak drøbak dyroy dyrøy dønna egersund eid eidfjord eidsberg eidskog eidsvoll eigersund elverum enebakk engerdal etne etnedal evenassi evenes evenášši evje-og-hornnes farsund fauske fedje fet fetsund fhs finnoy finnøy fitjar fjaler fjell fla flakstad flatanger flekkefjord flesberg flora floro florø flå fm folkebibl folldal forde forsand fosnes frana fredrikstad frei frogn froland frosta froya fræna frøya fuoisku fuossko fusa fylkesbibl fyresdal førde gaivuotna galsa gamvik gangaviika gaular gausdal giehtavuoatna gildeskal gildeskål giske gjemnes gjerdrum gjerstad gjesdal gjovik gjøvik gloppen gol gran grane granvin gratangen grimstad grong grue gulen guovdageaidnu gáivuotna gálsá gáŋgaviika ha habmer hadsel hagebostad halden halsa hamar hamaroy hammarfeasta hammerfest hapmir haram hareid harstad hasvik hattfjelldal haugesund hemne hemnes hemsedal herad hitra hjartdal hjelmeland hl hm hobol hobøl hof hokksund hol hole holmestrand holtalen holtålen honefoss hornindal horten hoyanger hoylandet hurdal hurum hvaler hyllestad hábmer hámmárfeasta hápmir hå hægebostad hønefoss høyanger høylandet ibestad idrett inderoy inderøy iveland ivgu jan-mayen jessheim jevnaker jolster jondal jorpeland jølster jørpeland kafjord karasjohka karasjok karlsoy karmoy karmøy kautokeino kirkenes klabu klepp klæbu kommune kongsberg kongsvinger kopervik kraanghke kragero kragerø kristiansand kristiansund krodsherad krokstadelva kråanghke krødsherad kvafjord kvalsund kvam kvanangen kvinesdal kvinnherad kviteseid kvitsoy kvitsøy kvæfjord kvænangen kárášjohka kåfjord laakesvuemie lahppi langevag langevåg lardal larvik lavagis lavangen leangaviika leaŋgaviika lebesby leikanger leirfjord leirvik leka leksvik lenvik lerdal lesja levanger lier lierne lillehammer lillesand lindas lindesnes lindås loabat loabát lodingen lom loppa lorenskog loten lund lunner luroy lurøy luster lyngdal lyngen láhppi lærdal lødingen lørenskog løten malatvuopmi malselv malvik mandal marker marnardal masfjorden masoy matta-varjjat meland meldal melhus meloy meløy meraker meråker midsund midtre-gauldal mil mjondalen mjøndalen mo-i-rana moareke modalen modum molde mosjoen mosjøen moskenes moss mosvik moåreke mr muosat muosát museum málatvuopmi mátta-várjjat målselv måsøy naamesjevuemie namdalseid namsos namsskogan nannestad naroy narviika narvik naustdal navuotna nedre-eiker nesna nesodden nesoddtangen nesseby nesset nissedal nittedal nl nord-aurdal nord-fron nord-odal norddal nordkapp nordre-land nordreisa nore-og-uvdal notodden notteroy nt návuotna nååmesjevuemie nærøy nøtterøy odda of oksnes ol omasvuotna oppdal oppegard oppegård orkanger orkdal orland orskog orsta osen oslo osoyro osteroy osterøy ostre-toten osøyro overhalla ovre-eiker oyer oygarden oystre-slidre porsanger porsangu porsgrunn porsáŋgu priv rade radoy radøy rahkkeravju raholt raisa rakkestad ralingen rana randaberg rauma rendalen rennebu rennesoy rennesøy rindal ringebu ringerike ringsaker risor rissa risør rl roan rodoy rollag romsa romskog roros rost royken royrvik ruovat rygge ráhkkerávju ráisa råde råholt rælingen rødøy rømskog røros røst røyken røyrvik salangen salat saltdal samnanger sandefjord sandnes sandnessjoen sandnessjøen sandoy sandøy sarpsborg sauda sauherad sel selbu selje seljord sf siellak sigdal siljan sirdal skanit skanland skaun skedsmo skedsmokorset ski skien skierva skiervá skiptvet skjak skjervoy skjervøy skjåk skodje skánit skånland slattum smola smøla snaase snasa snillfjord snoasa snåase snåsa sogndal sogne sokndal sola solund somna sondre-land songdalen sor-aurdal sor-fron sor-odal sor-varanger sorfold sorreisa sortland sorum spjelkavik spydeberg st stange stat stathelle stavanger stavern steigen steinkjer stjordal stjordalshalsen stjørdal stjørdalshalsen stokke stor-elvdal stord stordal storfjord strand stranda stryn sula suldal sund sunndal surnadal svalbard sveio svelvik sykkylven sálat sálát søgne sømna søndre-land sør-aurdal sør-fron sør-odal sør-varanger sørfold sørreisa sørum tana tananger time tingvoll tinn tjeldsund tjome tjøme tm tokke tolga tonsberg torsken tr trana tranby tranoy tranøy troandin trogstad tromsa tromso tromsø trondheim trysil træna trøgstad tvedestrand tydal tynset tysfjord tysnes tysvar tysvær tønsberg ullensaker ullensvang ulvik unjarga unjárga utsira va vaapste vadso vadsø vaga vagan vagsoy vaksdal valle vang vanylven vardo vardø varggat varoy vefsn vega vegarshei vegårshei vennesla verdal verran vestby vestnes vestre-slidre vestre-toten vestvagoy vestvågøy vevelstad vf vgs vik vikna vindafjord voagat volda voss vossevangen várggát vågan vågsøy vågå værøy ákŋoluokta álaheadju áltá åfjord åkrehamn ål ålesund ålgård åmli åmot årdal ås åseral åsnes øksnes ørland ørskog ørsta østre-toten øvre-eiker øyer øygarden øystre-slidre čáhcesuolo }
no { aa } { gs }
no { ah } { gs }
no { akershus } { nes }
no { bu } { gs }
no { buskerud } { nes }
no { fm } { gs }
no { hedmark } { os valer våler }
no { hl } { gs }
no { hm } { gs }
no { hordaland } { os }
no { jan-mayen } { gs }
no { more-og-romsdal } { heroy sande }
no { mr } { gs }
no { møre-og-romsdal } { herøy sande }
no { nl } { gs }
no { nordland } { bo bø heroy herøy }
no { nt } { gs }
no { of } { gs }
no { ol } { gs }
no { oslo } { gs }
no { ostfold } { valer }
no { rl } { gs }
no { sf } { gs }
no { st } { gs }
no { svalbard } { gs }
no { telemark } { bo bø }
no { tm } { gs }
no { tr } { gs }
no { va } { gs }
no { vestfold } { sande }
no { vf } { gs }
no { østfold } { våler }
nokia { }
norton { }
nowruz { }
np { * }
nr { }
nr { biz com edu gov info net org }
nra { }
nrw { }
ntt { }
nu { }
nu { merseine mine shacknet }
nyc { }
nz { }
nz { ac co cri geek gen govt health iwi kiwi maori mil māori net org parliament school }
nz { co } { blogspot }
obi { }
okinawa { }
om { }
om { co com edu gov med museum net org pro }
omega { }
one { }
ong { }
onl { }
online { }
ooo { }
oracle { }
org { }
org { ae blogdns blogsite boldlygoingnowhere dnsalias dnsdojo doesntexist dontexist doomdns dvrdns dynalias dyndns endofinternet endoftheinternet from-me game-host gotdns hk hobby-site homedns homeftp homelinux homeunix is-a-bruinsfan is-a-candidate is-a-celticsfan is-a-chef is-a-geek is-a-knight is-a-linux-user is-a-patsfan is-a-soxfan is-found is-lost is-saved is-very-bad is-very-evil is-very-good is-very-nice is-very-sweet isa-geek kicks-ass misconfused podzone readmyblog selfip sellsyourhome servebbs serveftp servegame stuff-4-sale us webhop za }
org { dyndns } { go home }
organic { }
osaka { }
otsuka { }
ovh { }
pa { }
pa { abo ac com edu gob ing med net nom org sld }
page { }
panerai { }
paris { }
pars { }
partners { }
parts { }
party { }
pe { }
pe { com edu gob mil net nom org }
pf { }
pf { com edu org }
pg { * }
ph { }
ph { com edu gov i mil net ngo org }
pharmacy { }
philips { }
photo { }
photography { }
photos { }
physio { }
piaget { }
pics { }
pictet { }
pictures { }
pid { }
pin { }
pink { }
pizza { }
pk { }
pk { biz com edu fam gob gok gon gop gos gov info net org web }
pl { }
pl { agro aid art atm augustow auto babia-gora bedzin beskidy bialowieza bialystok bielawa bieszczady biz boleslawiec bydgoszcz bytom cieszyn co com czeladz czest dlugoleka edu elblag elk gda gdansk gdynia gliwice glogow gmina gniezno gorlice gov grajewo gsm ilawa info jaworzno jelenia-gora jgora kalisz karpacz kartuzy kaszuby katowice kazimierz-dolny kepno ketrzyn klodzko kobierzyce kolobrzeg konin konskowola krakow kutno lapy lebork legnica lezajsk limanowa lomza lowicz lubin lukow mail malbork malopolska mazowsze mazury med media miasta mielec mielno mil mragowo naklo net nieruchomosci nom nowaruda nysa olawa olecko olkusz olsztyn opoczno opole org ostroda ostroleka ostrowiec ostrowwlkp pc pila pisz podhale podlasie polkowice pomorskie pomorze powiat poznan priv prochowice pruszkow przeworsk pulawy radom rawa-maz realestate rel rybnik rzeszow sanok sejny sex shop sklep skoczow slask slupsk sopot sos sosnowiec stalowa-wola starachowice stargard suwalki swidnica swiebodzin swinoujscie szczecin szczytno szkola targi tarnobrzeg tgory tm tourism travel turek turystyka tychy ustka walbrzych warmia warszawa waw wegrow wielun wlocl wloclawek wodzislaw wolomin wroc wroclaw zachpomor zagan zakopane zarow zgora zgorzelec }
pl { gov } { pa po so sr starostwo ug um upow uw }
place { }
plumbing { }
pm { }
pn { }
pn { co edu gov net org }
pohl { }
poker { }
porn { }
post { }
pr { }
pr { ac biz com edu est gov info isla name net org pro prof }
praxi { }
press { }
pro { }
pro { aca bar cpa eng jur law med }
prod { }
productions { }
prof { }
promo { }
properties { }
property { }
ps { }
ps { com edu gov net org plo sec }
pt { }
pt { blogspot com edu gov int net nome org publ }
pub { }
pw { }
pw { belau co ed go ne or }
py { }
py { com coop edu gov mil net org }
qa { }
qa { com edu gov mil name net org sch }
qpon { }
quebec { }
racing { }
re { }
re { asso blogspot com nom }
read { }
realtor { }
recipes { }
red { }
redstone { }
rehab { }
reise { }
reisen { }
reit { }
ren { }
rent { }
rentals { }
repair { }
report { }
republican { }
rest { }
restaurant { }
review { }
reviews { }
rich { }
ricoh { }
rio { }
rip { }
ro { }
ro { arts blogspot com firm info nom nt org rec store tm www }
rocher { }
rocks { }
rodeo { }
room { }
rs { }
rs { ac co edu gov in org }
rsvp { }
ru { }
ru { ac adygeya altai amur amursk arkhangelsk astrakhan baikal bashkiria belgorod bir blogspot bryansk buryatia cbg chel chelyabinsk chita chukotka chuvashia cmw com dagestan dudinka e-burg edu fareast gov grozny int irkutsk ivanovo izhevsk jamal jar joshkar-ola k-uralsk kalmykia kaluga kamchatka karelia kazan kchr kemerovo khabarovsk khakassia khv kirov kms koenig komi kostroma krasnoyarsk kuban kurgan kursk kustanai kuzbass lipetsk magadan magnitka mari mari-el marine mil mordovia msk murmansk mytis nakhodka nalchik net nkz nnov norilsk nov novosibirsk nsk omsk orenburg org oryol oskol palana penza perm pp ptz pyatigorsk rnd rubtsovsk ryazan sakhalin samara saratov simbirsk smolensk snz spb stavropol stv surgut syzran tambov tatarstan test tom tomsk tsaritsyn tsk tula tuva tver tyumen udm udmurtia ulan-ude vdonsk vladikavkaz vladimir vladivostok volgograd vologda voronezh vrn vyatka yakutia yamal yaroslavl yekaterinburg yuzhno-sakhalinsk zgrad }
ruhr { }
rw { }
rw { ac co com edu gouv gov int mil net }
ryukyu { }
sa { }
sa { com edu gov med net org pub sch }
saarland { }
safe { }
safety { }
sakura { }
sale { }
salon { }
samsung { }
sandvik { }
sandvikcoromant { }
sanofi { }
sap { }
sapo { }
sarl { }
saxo { }
sb { }
sb { com edu gov net org }
sbs { }
sc { }
sc { com edu gov net org }
sca { }
scb { }
schmidt { }
scholarships { }
school { }
schule { }
schwarz { }
science { }
scor { }
scot { }
sd { }
sd { com edu gov info med net org tv }
se { }
se { a ac b bd blogspot brand c com d e f fh fhsk fhv g h i k komforb kommunalforbund komvux l lanbib m n naturbruksgymn o org p parti pp press r s t tm u w x y z }
seat { }
seek { }
sener { }
services { }
sew { }
sex { }
sexy { }
sg { }
sg { blogspot com edu gov net org per }
sh { }
sh { com gov mil net org }
sh { platform } { * }
sharp { }
shia { }
shiksha { }
shoes { }
shouji { }
shriram { }
si { }
singles { }
site { }
sj { }
sk { }
sk { blogspot }
skin { }
sky { }
skype { }
sl { }
sl { com edu gov net org }
sm { }
smile { }
sn { }
sn { art com edu gouv org perso univ }
so { }
so { com net org }
social { }
software { }
sohu { }
solar { }
solutions { }
sony { }
soy { }
space { }
spiegel { }
spreadbetting { }
sr { }
st { }
st { co com consulado edu embaixada gov mil net org principe saotome store }
stada { }
star { }
statoil { }
stc { }
stcgroup { }
stockholm { }
storage { }
study { }
style { }
su { }
sucks { }
supplies { }
supply { }
support { }
surf { }
surgery { }
suzuki { }
sv { }
sv { com edu gob org red }
swatch { }
swiss { }
sx { }
sx { gov }
sy { }
sy { com edu gov mil net org }
sydney { }
symantec { }
systems { }
sz { }
sz { ac co org }
tab { }
taipei { }
taobao { }
tatar { }
tattoo { }
tax { }
tc { }
tci { }
td { }
td { blogspot }
technology { }
tel { }
telefonica { }
temasek { }
tennis { }
tf { }
tg { }
th { }
th { ac co go in mi net or }
tienda { }
tips { }
tires { }
tirol { }
tj { }
tj { ac biz co com edu go gov int mil name net nic org test web }
tk { }
tl { }
tl { gov }
tm { }
tm { co com edu gov mil net nom org }
tmall { }
tn { }
tn { agrinet com defense edunet ens fin gov ind info intl mincom nat net org perso rnrt rns rnu tourism turen }
to { }
to { com edu gov mil net org }
today { }
tokyo { }
tools { }
top { }
toray { }
toshiba { }
tours { }
town { }
toys { }
tp { }
tr { }
tr { av bbs bel biz com dr edu gen gov info k12 kep mil name nc net org pol tel tv web }
tr { com } { blogspot }
tr { nc } { gov }
trade { }
trading { }
training { }
travel { }
trust { }
tt { }
tt { aero biz co com coop edu gov info int jobs mobi museum name net org pro travel }
tui { }
tushu { }
tv { }
tv { better-than dyndns on-the-web worse-than }
tw { }
tw { blogspot club com ebiz edu game gov idv mil net org 商業 組織 網路 }
tz { }
tz { ac co go hotel info me mil mobi ne or sc tv }
ua { }
ua { cherkassy cherkasy chernigov chernihiv chernivtsi chernovtsy ck cn co com cr crimea cv dn dnepropetrovsk dnipropetrovsk dominic donetsk dp edu gov if in ivano-frankivsk kh kharkiv kharkov kherson khmelnitskiy khmelnytskyi kiev kirovograd km kr krym ks kv kyiv lg lt lugansk lutsk lv lviv mk mykolaiv net nikolaev od odesa odessa org pl poltava pp rivne rovno rv sb sebastopol sevastopol sm sumy te ternopil uz uzhgorod vinnica vinnytsia vn volyn yalta zaporizhzhe zaporizhzhia zhitomir zhytomyr zp zt }
ubs { }
ug { }
ug { ac co com go ne or org sc }
uk { }
uk { ac co gov ltd me net nhs org plc police }
uk { co } { blogspot }
uk { gov } { service }
uk { sch } { * }
university { }
uno { }
uol { }
uy { }
uy { com edu gub mil net org }
uz { }
uz { co com net org }
va { }
vacations { }
vana { }
vc { }
vc { com edu gov mil net org }
ve { }
ve { arts co com e12 edu firm gob gov info int mil net org rec store tec web }
vegas { }
ventures { }
vermögensberater { }
vermögensberatung { }
versicherung { }
vet { }
vg { }
vi { }
vi { co com k12 net org }
viajes { }
video { }
villas { }
vip { }
virgin { }
vision { }
vista { }
vistaprint { }
viva { }
vlaanderen { }
vn { }
vn { ac biz com edu gov health info int name net org pro }
vodka { }
vote { }
voting { }
voto { }
voyage { }
vu { }
vu { com edu net org }
wales { }
walter { }
wang { }
wanggou { }
watch { }
watches { }
weather { }
webcam { }
website { }
wed { }
wedding { }
wf { }
whoswho { }
wien { }
wiki { }
williamhill { }
win { }
windows { }
wme { }
work { }
works { }
world { }
ws { }
ws { com dyndns edu gov mypets net org }
wtc { }
wtf { }
xbox { }
xerox { }
xihuan { }
xin { }
xxx { }
xyz { }
yachts { }
yamaxun { }
yandex { }
ye { * }
yodobashi { }
yoga { }
yokohama { }
youtube { }
yt { }
yun { }
za { * }
zara { }
zero { }
zip { }
zm { * }
zone { }
zuerich { }
zw { * }
дети { }
ком { }
мон { }
москва { }
онлайн { }
орг { }
рус { }
рф { }
сайт { }
срб { }
срб { ак обр од орг пр упр }
укр { }
қаз { }
קום { }
ارامكو { }
الاردن { }
الجزائر { }
السعودية { }
السعوديه { }
السعودیة { }
السعودیۃ { }
المغرب { }
اليمن { }
امارات { }
ايران { }
ایران { }
بازار { }
بيتك { }
بھارت { }
تونس { }
سوريا { }
سورية { }
شبكة { }
عمان { }
فلسطين { }
قطر { }
كوم { }
مصر { }
مليسيا { }
موبايلي { }
موقع { }
همراه { }
कॉम { }
नेट { }
भारत { }
संगठन { }
বাংলা { }
ভারত { }
ਭਾਰਤ { }
ભારત { }
இந்தியா { }
இலங்கை { }
சிங்கப்பூர் { }
భారత్ { }
ලංකා { }
คอม { }
ไทย { }
გე { }
みんな { }
グーグル { }
コム { }
ポイント { }
世界 { }
中信 { }
中国 { }
中國 { }
中文网 { }
企业 { }
佛山 { }
信息 { }
健康 { }
八卦 { }
公司 { }
公益 { }
台湾 { }
台灣 { }
商城 { }
商店 { }
商标 { }
在线 { }
大拿 { }
娱乐 { }
广东 { }
慈善 { }
我爱你 { }
手机 { }
手表 { }
政务 { }
政府 { }
新加坡 { }
新闻 { }
时尚 { }
机构 { }
淡马锡 { }
游戏 { }
点看 { }
珠宝 { }
移动 { }
组织机构 { }
网址 { }
网店 { }
网站 { }
网络 { }
臺灣 { }
诺基亚 { }
谷歌 { }
集团 { }
飞利浦 { }
餐厅 { }
香港 { }
닷넷 { }
닷컴 { }
삼성 { }
한국 { }

_END_OF_PUBLICSUFFIX_DATA_

@default_rules = (@publicsuffix_rules, @special_rules);


=head1 AUTHOR

 Blekko.com

=head1 SEE ALSO

L<Mozilla::PublicSuffix>,
L<Domain::PublicSuffix>,
L<IO::Socket::SSL::PublicSuffix>,
L<ParseUtil::Domain>,
L<Net::Domain::Match>

Of which L<Domain::PublicSuffix> gets the answers right most of the time. The rest do not work for much more than the examples they provide, if any.

L<Net::IDN::Punycode>,
L<Net::IDN::Encode>,
L<IDNA::Punycode>,

=cut

