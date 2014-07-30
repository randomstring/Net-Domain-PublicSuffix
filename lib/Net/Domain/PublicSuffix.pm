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

our $VERSION = '1.01';
our @ISA = qw(Exporter);

our @EXPORT_OK = qw( base_domain public_suffix has_valid_tld set_debug_level dump_tree );

use Exporter;
use XSLoader;

XSLoader::load "Net::Domain::PublicSuffix", $VERSION;

my $initialized = 0;
my @rules;       # list of domains
my %tree;        # TRIE of all domain, domains read right to left in hash
my %valid_tlds;  # hash of all public suffix/domains

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

=head2 gen_basedomain_tree()

Initialize the base domain trie. This function will get called the
first time base_domain() is called. This function is made public so
that the trie can be initialized manually before any time critical
code.

=cut
sub gen_basedomain_tree
{
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

my @special_rules = split "\n", << '_END_OF_SPECIAL_DATA_';

# .us is "special" see http://en.wikipedia.org/wiki/.us
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi }
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la ma md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi } { * } { city ci town vil village co }
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la ma md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi } { state dst cog k12 cc tec lib mus gen }
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi } { k12 } { pvt }
us { ma } { k12 } { pvt chtr paroch }
us { dni fed is-by isa kids land-4-sale nsn stuff-4-sale }
us { }

# these are left out of the publicsuffix list. I got these from the
# wikipedia and the controling NIC
ae { name pro }
au { gov } { nt }
bd { ac com edu gov net org }
bn { com gov }
br { can }
by { org }
cc { co }
cu { co }
#http://en.wikipedia.org/wiki/.cy
cy { ac net gov org pro name ekloges tm ltd biz press parliament com }
gg { gov sch }
im { gov nic }
it { barletta-andria-trani barlettaandriatrani }
je { gov sch }
jo { myname }
ke { ac co go or }
kw { com edu gov }
lk { ac }
mt { gov }
ng { ac }
ni { com edu }
no { cáhcesuolo }
np { com gov org }
nr { co }
pk { goa }
se { mil sshn }
tv { com gov net org }
# http://en.wikipedia.org/wiki/.uk
uk { ac co gov jcpc judiciary ltd me mod net nhs nic org plc police sch supremecourt }
vi { edu gov }
ye { gov }
zm { co }
zw { co }

# http://en.wikipedia.org/wiki/.za
# http://www.internet.org.za/slds.html
za { ac co edu gov law mil nom org }
za { school } { escape fs gp kzn mpm ncape lp nw wcape }
za { agric grondar inca nis }

mz { teledata } { ! }
tr { nic } { ! }
uk { bl } { ! }
uk { british-library } { ! }
uk { jet } { ! }
uk { mod } { ! }
uk { national-library-scotland } { ! }
uk { nel } { ! }
uk { nic } { ! }
uk { nls } { ! }
uk { parliament } { ! }

_END_OF_SPECIAL_DATA_

my @publicsuffix_rules = split "\n", << '_END_OF_PUBLICSUFFIX_DATA_';
ac { }
ac { com edu gov mil net org }
academy { }
actor { }
ad { }
ad { nom }
ae { ac co gov mil net org sch }
aero { }
aero { accident-investigation accident-prevention aerobatic aeroclub aerodrome agents air-surveillance air-traffic-control aircraft airline airport airtraffic ambulance amusement association author ballooning broker caa cargo catering certification championship charter civilaviation club conference consultant consulting control council crew design dgca educator emergency engine engineer entertainment equipment exchange express federation flight freight fuel gliding government groundhandling group hanggliding homebuilt insurance journal journalist leasing logistics magazine maintenance marketplace media microlight modelling navigation parachuting paragliding passenger-association pilot press production recreation repbody res research rotorcraft safety scientist services show skydiving software student taxi trader trading trainer union workinggroup works }
af { }
af { com edu gov net org }
ag { }
ag { co com net nom org }
agency { }
ai { }
ai { com net off org }
airforce { }
al { }
al { com edu gov mil net org }
am { }
an { }
an { com edu net org }
ao { }
ao { co ed gv it og pb }
aq { }
ar { }
ar { com edu gob int mil net org tur }
ar { com } { blogspot }
archi { }
army { }
arpa { }
arpa { e164 in-addr ip6 iris uri urn }
as { }
as { gov }
asia { }
associates { }
at { }
at { ac biz co gv info or priv }
at { co } { blogspot }
au { act asn com conf csiro edu id info net nsw nt org oz qld sa tas vic wa }
au { com } { blogspot }
au { edu } { act nsw nt qld sa tas vic wa }
au { gov } { act qld sa tas vic wa }
autos { }
aw { }
aw { com }
ax { }
axa { }
az { }
az { biz com edu gov info int mil name net org pp pro }
ba { }
ba { co com edu gov mil net org rs unbi unsa }
bar { }
bargains { }
bayern { }
bb { }
bb { biz com edu gov info net org store }
bd { * }
be { }
be { ac blogspot }
beer { }
berlin { }
best { }
bf { }
bf { gov }
bg { }
bg { 0 1 2 3 4 5 6 7 8 9 a b c d e f g h i j k l m n o p q r s t u v w x y z }
bh { }
bh { com edu gov net org }
bi { }
bi { co com edu or org }
bid { }
bike { }
bio { }
biz { }
biz { dyndns for-better for-more for-some for-the selfip webhop }
bj { }
bj { asso barreau blogspot gouv }
black { }
blackfriday { }
blue { }
bm { }
bm { com edu gov net org }
bn { * }
bo { }
bo { com edu gob gov int mil net org tv }
boo { }
boutique { }
br { adm adv agr am arq art ato b bio blog bmd cim cng cnt com coop ecn eco edu emp eng esp etc eti far flog fm fnd fot fst g12 ggf gov imb ind inf jor jus leg lel mat med mil mp mus net nom not ntr odo org ppg pro psc psi qsl radio rec slg srv taxi teo tmp trd tur tv vet vlog wiki zlg }
br { com } { blogspot }
brussels { }
bs { }
bs { com edu gov net org }
bt { }
bt { com edu gov net org }
budapest { }
build { }
builders { }
business { }
buzz { }
bv { }
bw { }
bw { co org }
by { com gov mil of }
bz { }
bz { com edu gov net org za }
bzh { }
ca { }
ca { ab bc blogspot co gc mb nb nf nl ns nt nu on pe qc sk yk }
cab { }
camera { }
camp { }
capital { }
caravan { }
cards { }
career { }
careers { }
casa { }
cash { }
cat { }
catering { }
cc { ftpaccess game-server myphotos scrapping }
cd { }
cd { gov }
center { }
ceo { }
cf { }
cf { blogspot }
cg { }
ch { }
ch { blogspot }
cheap { }
christmas { }
church { }
ci { }
ci { ac asso aéroport co com ed edu go gouv int md net or org presse }
ck { * }
ck { www } { ! }
cl { }
cl { co gob gov mil }
cleaning { }
clothing { }
club { }
cm { }
cm { gov }
cn { }
cn { ac ah bj com cq edu fj gd gov gs gx gz ha hb he hi hk hl hn jl js jx ln mil mo net nm nx org qh sc sd sh sn sx tj tw xj xz yn zj 公司 網絡 网络 }
co { }
co { arts com edu firm gov info int mil net nom org rec web }
codes { }
coffee { }
college { }
cologne { }
com { }
com { africa appspot ar betainabox blogdns blogspot br cechire cloudcontrolapp cloudcontrolled cn co codespot de dnsalias dnsdojo doesntexist dontexist doomdns dreamhosters dyn-o-saur dynalias dyndns-at-home dyndns-at-work dyndns-blog dyndns-free dyndns-home dyndns-ip dyndns-mail dyndns-office dyndns-pics dyndns-remote dyndns-server dyndns-web dyndns-wiki dyndns-work elasticbeanstalk est-a-la-maison est-a-la-masion est-le-patron est-mon-blogueur eu from-ak from-al from-ar from-ca from-ct from-dc from-de from-fl from-ga from-hi from-ia from-id from-il from-in from-ks from-ky from-ma from-md from-mi from-mn from-mo from-ms from-mt from-nc from-nd from-ne from-nh from-nj from-nm from-nv from-oh from-ok from-or from-pa from-pr from-ri from-sc from-sd from-tn from-tx from-ut from-va from-vt from-wa from-wi from-wv from-wy gb getmyip githubusercontent googleapis googlecode gotdns gr herokuapp herokussl hobby-site homelinux homeunix hu iamallama is-a-anarchist is-a-blogger is-a-bookkeeper is-a-bulls-fan is-a-caterer is-a-chef is-a-conservative is-a-cpa is-a-cubicle-slave is-a-democrat is-a-designer is-a-doctor is-a-financialadvisor is-a-geek is-a-green is-a-guru is-a-hard-worker is-a-hunter is-a-landscaper is-a-lawyer is-a-liberal is-a-libertarian is-a-llama is-a-musician is-a-nascarfan is-a-nurse is-a-painter is-a-personaltrainer is-a-photographer is-a-player is-a-republican is-a-rockstar is-a-socialist is-a-student is-a-teacher is-a-techie is-a-therapist is-an-accountant is-an-actor is-an-actress is-an-anarchist is-an-artist is-an-engineer is-an-entertainer is-certified is-gone is-into-anime is-into-cars is-into-cartoons is-into-games is-leet is-not-certified is-slick is-uberleet is-with-theband isa-geek isa-hockeynut issmarterthanyou jpn kr likes-pie likescandy mex neat-url no operaunite outsystemscloud qc rhcloud ro ru sa saves-the-whales se selfip sells-for-less sells-for-u servebbs simple-url space-to-rent teaches-yoga uk us uy withgoogle writesthisblog za }
com { amazonaws } { compute compute-1 elb s3 s3-ap-northeast-1 s3-ap-southeast-1 s3-ap-southeast-2 s3-eu-west-1 s3-fips-us-gov-west-1 s3-sa-east-1 s3-us-gov-west-1 s3-us-west-1 s3-us-west-2 s3-website-ap-northeast-1 s3-website-ap-southeast-1 s3-website-ap-southeast-2 s3-website-eu-west-1 s3-website-sa-east-1 s3-website-us-east-1 s3-website-us-gov-west-1 s3-website-us-west-1 s3-website-us-west-2 us-east-1 }
com { amazonaws } { compute } { ap-northeast-1 ap-southeast-1 ap-southeast-2 eu-west-1 sa-east-1 us-gov-west-1 us-west-1 us-west-2 }
com { amazonaws } { compute-1 } { z-1 z-2 }
community { }
company { }
computer { }
condos { }
construction { }
consulting { }
contractors { }
cooking { }
cool { }
coop { }
country { }
cr { }
cr { ac co ed fi go or sa }
cruises { }
cu { com edu gov inf net org }
cv { }
cv { blogspot }
cw { }
cw { com edu net org }
cx { }
cx { ath gov }
cy { * }
cz { }
cz { blogspot }
dabur { }
dad { }
dance { }
dating { }
day { }
de { }
de { blogspot com fuettertdasnetz isteingeek istmein lebtimnetz leitungsen traeumtgerade }
degree { }
democrat { }
desi { }
diamonds { }
digital { }
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
domains { }
dz { }
dz { art asso com edu gov net org pol }
eat { }
ec { }
ec { com edu fin gob gov info k12 med mil net org pro }
edu { }
education { }
ee { }
ee { aip com edu fie gov lib med org pri riik }
eg { }
eg { com edu eun gov mil name net org sci }
email { }
engineering { }
enterprises { }
equipment { }
er { * }
es { }
es { com edu gob nom org }
es { com } { blogspot }
estate { }
et { * }
eu { }
eus { }
events { }
exchange { }
expert { }
exposed { }
fail { }
fan { }
farm { }
feedback { }
fi { }
fi { aland blogspot iki }
financial { }
fish { }
fishing { }
fitness { }
fj { * }
fk { * }
flights { }
florist { }
fm { }
fo { }
foo { }
foundation { }
fr { }
fr { aeroport assedic asso avocat avoues blogspot cci chambagri chirurgiens-dentistes com experts-comptables geometre-expert gouv greta huissier-justice medecin nom notaires pharmacien port prd presse tm veterinaire }
frogans { }
futbol { }
ga { }
gal { }
gallery { }
gb { }
gd { }
ge { }
ge { com edu gov mil net org pvt }
gent { }
gf { }
gg { co net org }
ggee { }
gh { }
gh { com edu gov mil org }
gi { }
gi { com edu gov ltd mod org }
gift { }
gives { }
gl { }
glass { }
globo { }
gm { }
gn { }
gn { ac com edu gov net org }
gop { }
gov { }
gp { }
gp { asso com edu mobi net org }
gq { }
gr { }
gr { blogspot com edu gov net org }
graphics { }
gripe { }
gs { }
gt { }
gt { com edu gob ind mil net org }
gu { * }
guide { }
guitars { }
guru { }
gw { }
gy { }
gy { co com net }
hamburg { }
haus { }
here { }
hiphop { }
hiv { }
hk { }
hk { blogspot com edu gov idv net org 个人 個人 公司 政府 敎育 教育 箇人 組織 組织 網絡 網络 组織 组织 网絡 网络 }
hm { }
hn { }
hn { com edu gob mil net org }
holdings { }
holiday { }
homes { }
horse { }
house { }
how { }
hr { }
hr { com from iz name }
ht { }
ht { adult art asso com coop edu firm gouv info med net org perso pol pro rel shop }
hu { }
hu { 2000 agrar blogspot bolt casino city co erotica erotika film forum games hotel info ingatlan jogasz konyvelo lakas media news org priv reklam sex shop sport suli szex tm tozsde utazas video }
id { }
id { ac biz co desa go mil my net or sch web }
ie { }
ie { blogspot gov }
ifm { }
il { * }
il { co } { blogspot }
im { ac co com net org tt tv }
im { co } { ltd plc }
immobilien { }
in { }
in { ac blogspot co edu firm gen gov ind mil net nic org res }
industries { }
info { }
info { barrel-of-knowledge barrell-of-knowledge dyndns for-our groks-the groks-this here-for-more knowsitall selfip webhop }
ing { }
ink { }
institute { }
int { }
int { eu }
international { }
io { }
io { com github }
iq { }
iq { com edu gov mil net org }
ir { }
ir { ac co gov id net org sch ايران ایران }
is { }
is { com cupcake edu gov int net org }
it { abr abruzzo ag agrigento al alessandria alto-adige altoadige an ancona andria-barletta-trani andria-trani-barletta andriabarlettatrani andriatranibarletta ao aosta aosta-valley aostavalley aoste ap aq aquila ar arezzo ascoli-piceno ascolipiceno asti at av avellino ba balsan bari barletta-trani-andria barlettatraniandria bas basilicata belluno benevento bergamo bg bi biella bl blogspot bn bo bologna bolzano bozen br brescia brindisi bs bt bz ca cagliari cal calabria caltanissetta cam campania campidano-medio campidanomedio campobasso carbonia-iglesias carboniaiglesias carrara-massa carraramassa caserta catania catanzaro cb ce cesena-forli cesenaforli ch chieti ci cl cn co como cosenza cr cremona crotone cs ct cuneo cz dell-ogliastra dellogliastra edu emilia-romagna emiliaromagna emr en enna fc fe fermo ferrara fg fi firenze florence fm foggia forli-cesena forlicesena fr friuli-v-giulia friuli-ve-giulia friuli-vegiulia friuli-venezia-giulia friuli-veneziagiulia friuli-vgiulia friuliv-giulia friulive-giulia friulivegiulia friulivenezia-giulia friuliveneziagiulia friulivgiulia frosinone fvg ge genoa genova go gorizia gov gr grosseto iglesias-carbonia iglesiascarbonia im imperia is isernia kr la-spezia laquila laspezia latina laz lazio lc le lecce lecco li lig liguria livorno lo lodi lom lombardia lombardy lt lu lucania lucca macerata mantova mar marche massa-carrara massacarrara matera mb mc me medio-campidano mediocampidano messina mi milan milano mn mo modena mol molise monza monza-brianza monza-e-della-brianza monzabrianza monzaebrianza monzaedellabrianza ms mt na naples napoli no novara nu nuoro og ogliastra olbia-tempio olbiatempio or oristano ot pa padova padua palermo parma pavia pc pd pe perugia pesaro-urbino pesarourbino pescara pg pi piacenza piedmont piemonte pisa pistoia pmn pn po pordenone potenza pr prato pt pu pug puglia pv pz ra ragusa ravenna rc re reggio-calabria reggio-emilia reggiocalabria reggioemilia rg ri rieti rimini rm rn ro roma rome rovigo sa salerno sar sardegna sardinia sassari savona si sic sicilia sicily siena siracusa so sondrio sp sr ss suedtirol sv ta taa taranto te tempio-olbia tempioolbia teramo terni tn to torino tos toscana tp tr trani-andria-barletta trani-barletta-andria traniandriabarletta tranibarlettaandria trapani trentino trentino-a-adige trentino-aadige trentino-alto-adige trentino-altoadige trentino-s-tirol trentino-stirol trentino-sud-tirol trentino-sudtirol trentino-sued-tirol trentino-suedtirol trentinoa-adige trentinoaadige trentinoalto-adige trentinoaltoadige trentinos-tirol trentinostirol trentinosud-tirol trentinosudtirol trentinosued-tirol trentinosuedtirol trento treviso trieste ts turin tuscany tv ud udine umb umbria urbino-pesaro urbinopesaro va val-d-aosta val-daosta vald-aosta valdaosta valle-aosta valle-d-aosta valle-daosta valleaosta valled-aosta valledaosta vallee-aoste valleeaoste vao varese vb vc vda ve ven veneto venezia venice verbania vercelli verona vi vibo-valentia vibovalentia vicenza viterbo vr vs vt vv }
je { co net org }
jetzt { }
jm { * }
jo { com edu gov mil name net org sch }
jobs { }
jp { }
jp { ac ad aichi akita aomori blogspot chiba co ed ehime fukui fukuoka fukushima gifu go gr gunma hiroshima hokkaido hyogo ibaraki ishikawa iwate kagawa kagoshima kanagawa kochi kumamoto kyoto lg mie miyagi miyazaki nagano nagasaki nara ne niigata oita okayama okinawa or osaka saga saitama shiga shimane shizuoka tochigi tokushima tokyo tottori toyama wakayama yamagata yamaguchi yamanashi }
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
jp { kitakyushu } { * }
jp { kobe } { * }
jp { kawasaki } { city } { ! }
jp { kitakyushu } { city } { ! }
jp { kobe } { city } { ! }
jp { nagoya } { city } { ! }
jp { sapporo } { city } { ! }
jp { sendai } { city } { ! }
jp { yokohama } { city } { ! }
jp { kochi } { aki geisei hidaka higashitsuno ino kagami kami kitagawa kochi mihara motoyama muroto nahari nakamura nankoku nishitosa niyodogawa ochi okawa otoyo otsuki sakawa sukumo susaki tosa tosashimizu toyo tsuno umaji yasuda yusuhara }
jp { kumamoto } { amakusa arao aso choyo gyokuto hitoyoshi kamiamakusa kashima kikuchi kosa kumamoto mashiki mifune minamata minamioguni nagasu nishihara oguni ozu sumoto takamori uki uto yamaga yamato yatsushiro }
jp { kyoto } { ayabe fukuchiyama higashiyama ide ine joyo kameoka kamo kita kizu kumiyama kyotamba kyotanabe kyotango maizuru minami minamiyamashiro miyazu muko nagaokakyo nakagyo nantan oyamazaki sakyo seika tanabe uji ujitawara wazuka yamashina yawata }
jp { mie } { asahi inabe ise kameyama kawagoe kiho kisosaki kiwa komono kumano kuwana matsusaka meiwa mihama minamiise misugi miyama nabari shima suzuka tado taiki taki tamaki toba tsu udono ureshino watarai yokkaichi }
jp { miyagi } { furukawa higashimatsushima ishinomaki iwanuma kakuda kami kawasaki kesennuma marumori matsushima minamisanriku misato murata natori ogawara ohira onagawa osaki rifu semine shibata shichikashuku shikama shiogama shiroishi tagajo taiwa tome tomiya wakuya watari yamamoto zao }
jp { miyazaki } { aya ebino gokase hyuga kadogawa kawaminami kijo kitagawa kitakata kitaura kobayashi kunitomi kushima mimata miyakonojo miyazaki morotsuka nichinan nishimera nobeoka saito shiiba shintomi takaharu takanabe takazaki tsuno }
jp { nagano } { achi agematsu anan aoki asahi azumino chikuhoku chikuma chino fujimi hakuba hara hiraya iida iijima iiyama iizuna ikeda ikusaka ina karuizawa kawakami kiso kisofukushima kitaaiki komagane komoro matsukawa matsumoto miasa minamiaiki minamimaki minamiminowa minowa miyada miyota mochizuki nagano nagawa nagiso nakagawa nakano nozawaonsen obuse ogawa okaya omachi omi ookuwa ooshika otaki otari sakae sakaki saku sakuho shimosuwa shinanomachi shiojiri suwa suzaka takagi takamori takayama tateshina tatsuno togakushi togura tomi ueda wada yamagata yamanouchi yasaka yasuoka }
jp { nagasaki } { chijiwa futsu goto hasami hirado iki isahaya kawatana kuchinotsu matsuura nagasaki obama omura oseto saikai sasebo seihi shimabara shinkamigoto togitsu tsushima unzen }
jp { nagoya } { * }
jp { nara } { ando gose heguri higashiyoshino ikaruga ikoma kamikitayama kanmaki kashiba kashihara katsuragi kawai kawakami kawanishi koryo kurotaki mitsue miyake nara nosegawa oji ouda oyodo sakurai sango shimoichi shimokitayama shinjo soni takatori tawaramoto tenkawa tenri uda yamatokoriyama yamatotakada yamazoe yoshino }
jp { niigata } { aga agano gosen itoigawa izumozaki joetsu kamo kariwa kashiwazaki minamiuonuma mitsuke muika murakami myoko nagaoka niigata ojiya omi sado sanjo seiro seirou sekikawa shibata tagami tainai tochio tokamachi tsubame tsunan uonuma yahiko yoita yuzawa }
jp { oita } { beppu bungoono bungotakada hasama hiji himeshima hita kamitsue kokonoe kuju kunisaki kusu oita saiki taketa tsukumi usa usuki yufu }
jp { okayama } { akaiwa asakuchi bizen hayashima ibara kagamino kasaoka kibichuo kumenan kurashiki maniwa misaki nagi niimi nishiawakura okayama satosho setouchi shinjo shoo soja takahashi tamano tsuyama wake yakage }
jp { okinawa } { aguni ginowan ginoza gushikami haebaru higashi hirara iheya ishigaki ishikawa itoman izena kadena kin kitadaito kitanakagusuku kumejima kunigami minamidaito motobu nago naha nakagusuku nakijin nanjo nishihara ogimi okinawa onna shimoji taketomi tarama tokashiki tomigusuku tonaki urasoe uruma yaese yomitan yonabaru yonaguni zamami }
jp { osaka } { abeno chihayaakasaka chuo daito fujiidera habikino hannan higashiosaka higashisumiyoshi higashiyodogawa hirakata ibaraki ikeda izumi izumiotsu izumisano kadoma kaizuka kanan kashiwara katano kawachinagano kishiwada kita kumatori matsubara minato minoh misaki moriguchi neyagawa nishi nose osakasayama sakai sayama sennan settsu shijonawate shimamoto suita tadaoka taishi tajiri takaishi takatsuki tondabayashi toyonaka toyono yao }
jp { saga } { ariake arita fukudomi genkai hamatama hizen imari kamimine kanzaki karatsu kashima kitagata kitahata kiyama kouhoku kyuragi nishiarita ogi omachi ouchi saga shiroishi taku tara tosu yoshinogari }
jp { saitama } { arakawa asaka chichibu fujimi fujimino fukaya hanno hanyu hasuda hatogaya hatoyama hidaka higashichichibu higashimatsuyama honjo ina iruma iwatsuki kamiizumi kamikawa kamisato kasukabe kawagoe kawaguchi kawajima kazo kitamoto koshigaya kounosu kuki kumagaya matsubushi minano misato miyashiro miyoshi moroyama nagatoro namegawa niiza ogano ogawa ogose okegawa omiya otaki ranzan ryokami saitama sakado satte sayama shiki shiraoka soka sugito toda tokigawa tokorozawa tsurugashima urawa warabi yashio yokoze yono yorii yoshida yoshikawa yoshimi }
jp { sapporo } { * }
jp { sendai } { * }
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
kaufen { }
ke { * }
kg { }
kg { com edu gov mil net org }
kh { * }
ki { }
ki { biz com edu gov info net org }
kim { }
kitchen { }
kiwi { }
km { }
km { ass asso com coop edu gouv gov medecin mil nom notaires org pharmaciens prd presse tm veterinaire }
kn { }
kn { edu gov net org }
kp { }
kp { com edu gov org rep tra }
kr { }
kr { ac blogspot busan chungbuk chungnam co daegu daejeon es gangwon go gwangju gyeongbuk gyeonggi gyeongnam hs incheon jeju jeonbuk jeonnam kg mil ms ne or pe re sc seoul ulsan }
krd { }
kred { }
kw { * }
ky { }
ky { com edu gov net org }
kz { }
kz { com edu gov mil net org }
la { }
la { c com edu gov info int net org per }
lacaixa { }
land { }
lb { }
lb { com edu gov net org }
lc { }
lc { co com edu gov net org }
lease { }
li { }
life { }
lighting { }
limited { }
limo { }
link { }
lk { assn com edu gov grp hotel int ltd net ngo org sch soc web }
london { }
lr { }
lr { com edu gov net org }
ls { }
ls { co org }
lt { }
lt { gov }
lu { }
luxe { }
luxury { }
lv { }
lv { asn com conf edu gov id mil net org }
ly { }
ly { com edu gov id med net org plc sch }
ma { }
ma { ac co gov net org press }
maison { }
management { }
mango { }
market { }
marketing { }
mc { }
mc { asso tm }
md { }
me { }
me { ac co edu gov its net org priv }
media { }
meet { }
meme { }
menu { }
mg { }
mg { com edu gov mil nom org prd tm }
mh { }
miami { }
mil { }
mini { }
mk { }
mk { com edu gov inf name net org }
ml { }
ml { com edu gouv gov net org presse }
mm { * }
mn { }
mn { edu gov nyc org }
mo { }
mo { com edu gov net org }
mobi { }
moda { }
moe { }
monash { }
mormon { }
moscow { }
motorcycles { }
mov { }
mp { }
mq { }
mr { }
mr { blogspot gov }
ms { }
ms { com edu gov net org }
mt { com edu net org }
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
na { }
na { ca cc co com dr in info mobi mx name or org pro school tv us ws }
nagoya { }
name { }
name { her } { forgot }
name { his } { forgot }
navy { }
nc { }
nc { asso }
ne { }
net { }
net { at-band-camp azure-mobile azurewebsites blogdns broke-it buyshouses cloudapp cloudfront dnsalias dnsdojo does-it dontexist dynalias dynathome endofinternet from-az from-co from-la from-ny gb gets-it ham-radio-op homeftp homeip homelinux homeunix hu in in-the-band is-a-chef is-a-geek isa-geek jp kicks-ass office-on-the podzone scrapper-site se selfip sells-it servebbs serveftp thruhere uk webhop za }
net { fastly } { prod } { a global }
net { fastly } { ssl } { a b global }
network { }
neustar { }
new { }
nf { }
nf { arts com firm info net other per rec store web }
ng { com edu gov mil mobi name net org sch }
ngo { }
nhk { }
ni { * }
ninja { }
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
np { * }
nr { biz com edu gov info net org }
nrw { }
nu { }
nu { merseine mine shacknet }
nyc { }
nz { * }
nz { co } { blogspot }
okinawa { }
om { }
om { co com edu gov med museum net org pro }
ong { }
onl { }
org { }
org { ae blogdns blogsite boldlygoingnowhere dnsalias dnsdojo doesntexist dontexist doomdns dvrdns dynalias dyndns endofinternet endoftheinternet from-me game-host gotdns hobby-site homedns homeftp homelinux homeunix is-a-bruinsfan is-a-candidate is-a-celticsfan is-a-chef is-a-geek is-a-knight is-a-linux-user is-a-patsfan is-a-soxfan is-found is-lost is-saved is-very-bad is-very-evil is-very-good is-very-nice is-very-sweet isa-geek kicks-ass misconfused podzone readmyblog selfip sellsyourhome servebbs serveftp servegame stuff-4-sale us webhop za }
org { dyndns } { go home }
otsuka { }
ovh { }
pa { }
pa { abo ac com edu gob ing med net nom org sld }
paris { }
partners { }
parts { }
pe { }
pe { com edu gob mil net nom org }
pf { }
pf { com edu org }
pg { * }
ph { }
ph { com edu gov i mil net ngo org }
photo { }
photography { }
photos { }
pics { }
pictures { }
pink { }
pk { biz com edu fam gob gok gon gop gos gov info net org web }
pl { }
pl { 6bone agro aid art atm augustow auto babia-gora bedzin beskidy bialowieza bialystok bielawa bieszczady biz boleslawiec bydgoszcz bytom cieszyn co com czeladz czest dlugoleka edu elblag elk gda gdansk gdynia gliwice glogow gmina gniezno gorlice gov grajewo gsm ilawa info irc jaworzno jelenia-gora jgora kalisz karpacz kartuzy kaszuby katowice kazimierz-dolny kepno ketrzyn klodzko kobierzyce kolobrzeg konin konskowola krakow kutno lapy lebork legnica lezajsk limanowa lomza lowicz lubin lukow mail malbork malopolska mazowsze mazury mbone med media miasta mielec mielno mil mragowo naklo net ngo nieruchomosci nom nowaruda nysa olawa olecko olkusz olsztyn opoczno opole org ostroda ostroleka ostrowiec ostrowwlkp pc pila pisz podhale podlasie polkowice pomorskie pomorze powiat poznan priv prochowice pruszkow przeworsk pulawy radom rawa-maz realestate rel rybnik rzeszow sanok sejny sex shop siedlce sklep skoczow slask slupsk sopot sos sosnowiec stalowa-wola starachowice stargard suwalki swidnica swiebodzin swinoujscie szczecin szczytno szkola targi tarnobrzeg tgory tm tourism travel turek turystyka tychy usenet ustka walbrzych warmia warszawa waw wegrow wielun wlocl wloclawek wodzislaw wolomin wroc wroclaw zachpomor zagan zakopane zarow zgora zgorzelec }
pl { gov } { pa po so sr starostwo ug um upow uw }
plumbing { }
pm { }
pn { }
pn { co edu gov net org }
post { }
pr { }
pr { ac biz com edu est gov info isla name net org pro prof }
praxi { }
pro { }
pro { aca bar cpa eng jur law med }
prod { }
productions { }
properties { }
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
re { }
re { asso blogspot com nom }
recipes { }
red { }
rehab { }
reise { }
reisen { }
ren { }
rentals { }
repair { }
report { }
rest { }
reviews { }
rich { }
rio { }
ro { }
ro { arts blogspot com firm info nom nt org rec store tm www }
rocks { }
rodeo { }
rs { }
rs { ac co edu gov in org }
ru { }
ru { ac adygeya altai amur amursk arkhangelsk astrakhan baikal bashkiria belgorod bir bryansk buryatia cbg chel chelyabinsk chita chukotka chuvashia cmw com dagestan dudinka e-burg edu fareast gov grozny int irkutsk ivanovo izhevsk jamal jar joshkar-ola k-uralsk kalmykia kaluga kamchatka karelia kazan kchr kemerovo khabarovsk khakassia khv kirov kms koenig komi kostroma krasnoyarsk kuban kurgan kursk kustanai kuzbass lipetsk magadan magnitka mari mari-el marine mil mordovia mosreg msk murmansk mytis nakhodka nalchik net nkz nnov norilsk nov novosibirsk nsk omsk orenburg org oryol oskol palana penza perm pp pskov ptz pyatigorsk rnd rubtsovsk ryazan sakhalin samara saratov simbirsk smolensk snz spb stavropol stv surgut syzran tambov tatarstan test tom tomsk tsaritsyn tsk tula tuva tver tyumen udm udmurtia ulan-ude vdonsk vladikavkaz vladimir vladivostok volgograd vologda voronezh vrn vyatka yakutia yamal yaroslavl yekaterinburg yuzhno-sakhalinsk zgrad }
ruhr { }
rw { }
rw { ac co com edu gouv gov int mil net }
ryukyu { }
sa { }
sa { com edu gov med net org pub sch }
saarland { }
sb { }
sb { com edu gov net org }
sc { }
sc { com edu gov net org }
sca { }
scb { }
schule { }
scot { }
sd { }
sd { com edu gov info med net org tv }
se { a ac b bd blogspot brand c d e f fh fhsk fhv g h i k komforb kommunalforbund komvux l lanbib m n naturbruksgymn o org p parti pp press r s t tm u w x y z }
services { }
sexy { }
sg { }
sg { blogspot com edu gov net org per }
sh { }
sh { com gov mil net org }
shiksha { }
shoes { }
shriram { }
si { }
singles { }
sj { }
sk { }
sk { blogspot }
sl { }
sl { com edu gov net org }
sm { }
sn { }
sn { art com edu gouv org perso univ }
so { }
so { com net org }
social { }
sohu { }
solar { }
solutions { }
soy { }
spiegel { }
sr { }
st { }
st { co com consulado edu embaixada gov mil net org principe saotome store }
su { }
supplies { }
supply { }
support { }
suzuki { }
sv { }
sv { com edu gob org red }
sx { }
sx { gov }
sy { }
sy { com edu gov mil net org }
systems { }
sz { }
sz { ac co org }
tattoo { }
tc { }
td { }
td { blogspot }
technology { }
tel { }
tf { }
tg { }
th { }
th { ac co go in mi net or }
tienda { }
tips { }
tj { }
tj { ac biz co com edu go gov int mil name net nic org test web }
tk { }
tl { }
tl { gov }
tm { }
tm { co com edu gov mil net nom org }
tn { }
tn { agrinet com defense edunet ens fin gov ind info intl mincom nat net org perso rnrt rns rnu tourism turen }
to { }
to { com edu gov mil net org }
today { }
tokyo { }
tools { }
town { }
toys { }
tp { }
tr { * }
tr { nc } { gov }
trade { }
training { }
travel { }
tt { }
tt { aero biz co com coop edu gov info int jobs mobi museum name net org pro travel }
tv { better-than dyndns on-the-web worse-than }
tw { }
tw { blogspot club com ebiz edu game gov idv mil net org 商業 組織 網路 }
tz { }
tz { ac co go hotel info me mil mobi ne or sc tv }
ua { }
ua { cherkassy cherkasy chernigov chernihiv chernivtsi chernovtsy ck cn co com cr crimea cv dn dnepropetrovsk dnipropetrovsk dominic donetsk dp edu gov if in ivano-frankivsk kh kharkiv kharkov kherson khmelnitskiy khmelnytskyi kiev kirovograd km kr krym ks kv kyiv lg lt lugansk lutsk lv lviv mk mykolaiv net nikolaev od odesa odessa org pl poltava pp rivne rovno rv sb sebastopol sevastopol sm sumy te ternopil uz uzhgorod vinnica vinnytsia vn volyn yalta zaporizhzhe zaporizhzhia zhitomir zhytomyr zp zt }
ug { }
ug { ac co com go ne or org sc }
uk { * }
uk { co } { blogspot }
uk { sch } { * }
university { }
uno { }
uy { }
uy { com edu gub mil net org }
uz { }
uz { co com net org }
va { }
vacations { }
vc { }
vc { com edu gov mil net org }
ve { }
ve { co com e12 edu gov info mil net org web }
vegas { }
ventures { }
vet { }
vg { }
vi { co com k12 net org }
viajes { }
villas { }
vision { }
vlaanderen { }
vn { }
vn { ac biz com edu gov health info int name net org pro }
vodka { }
vote { }
voting { }
voto { }
voyage { }
vu { }
wang { }
watch { }
webcam { }
wed { }
wf { }
whoswho { }
wien { }
wiki { }
williamhill { }
wme { }
work { }
works { }
ws { }
ws { com dyndns edu gov mypets net org }
wtc { }
wtf { }
xxx { }
xyz { }
yachts { }
ye { * }
yokohama { }
yt { }
za { * }
zm { * }
zone { }
zw { * }
дети { }
мон { }
москва { }
онлайн { }
орг { }
рус { }
рф { }
сайт { }
срб { }
укр { }
қаз { }
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
بھارت { }
تونس { }
سوريا { }
سورية { }
شبكة { }
عمان { }
فلسطين { }
قطر { }
مصر { }
مليسيا { }
موقع { }
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
ไทย { }
გე { }
みんな { }
世界 { }
中信 { }
中国 { }
中國 { }
中文网 { }
企业 { }
佛山 { }
八卦 { }
公司 { }
公益 { }
台湾 { }
台灣 { }
商城 { }
商店 { }
商标 { }
在线 { }
广东 { }
我爱你 { }
手机 { }
政务 { }
政府 { }
新加坡 { }
机构 { }
游戏 { }
移动 { }
组织机构 { }
网址 { }
网络 { }
臺灣 { }
集团 { }
香港 { }
삼성 { }
한국 { }
_END_OF_PUBLICSUFFIX_DATA_

@rules = (@special_rules, @publicsuffix_rules);

#
# These rules were hand currated from various sources, including
# wikipedia and the controling NICs for each tld. These are partially
# out of date, but also include some sub domains that are not included
# with the publicsuffix list. Left as a reference.
#
my @data_old;
@data_old = split "\n", << '_END_OF_DATA_';
# top level domains with no (known) subdomains
am { }
aq { }
asia { }
ax { }
biz { }
cat { }
cf { }
cg { }
ch { }
ck { }
coop { }
cv { }
cz { }
dj { }
dk { }
edu { }
eu { }
fk { }
fm { }
fo { }
ga { }
gd { }
gf { }
gl { }
gm { }
gov { }
gq { }
gs { }
gu { }
gw { }
hm { }
info { }
jobs { }
li { }
local { }
lu { }
md { }
mh { }
mil { }
mm { }
mobi { }
mp { }
mq { }
ms { }
name { }
ne { }
nu { }
si { }
sk { }
sm { }
sr { }
su { }
td { }
tel { }
tf { }
tg { }
tk { }
travel { }
va { }
vg { }

# .us is special
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la ma md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi } { * } { city ci town vil village co }
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la ma md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi } { state dst cog k12 cc tec lib mus gen }
us { ak al ar az ca co ct de fl ga hi ia id il in ks ky la md me mi mn mo ms mt nc nd ne nh nj nm nv ny oh ok or pa ri sc sd tn tx ut va vt wa wi wv wy as dc gu pr vi } { k12 } { pvt }
us { ma } { k12 } { pvt chtr paroch }
us { nsn kids isa fed dni }
us { }

# http://en.wikipedia.org/wiki/.za
za { ac co edu gov law mil nom org }
za { school } { escape fs gp kzn mpm ncape lp nw wcape }

# level 3,4  domains
au { com net org edu gov asn id act nsw nt qld sa tas vic wa info conf oz }
au { gov } { act nt qld sa tas vic wa }
au { edu } { act nsw nt qld sa tas vic wa }

# 3 level domains
ad { nom }
uk { co ac gov ltd me mod net nic nhs org plc police sch icnet bl jet nls parliament }
ac { com edu gov net mil org }
ac { }
ae { co net gov ac sch org mil pro name }
aero {accident-investigation accident-prevention aerobatic aeroclub aerodrome agents aircraft airline airport air-surveillance airtraffic air-traffic-control ambulance amusement association author ballooning broker caa cargo catering certification championship charter civilaviation club conference consultant consulting control council crew design dgca educator emergency engine engineer entertainment equipment exchange express federation flight freight fuel gliding government groundhandling group hanggliding homebuilt insurance journal journalist leasing logistics magazine maintenance marketplace media microlight modelling navigation parachuting paragliding passenger-association pilot press production recreation repbody res research rotorcraft safety scientist services show skydiving software student taxi trader trading trainer union workinggroup works }
af { com edu gov net org law tv music hotel bank }
ag { com org net co nom }
ai { com off net org }
al { com edu gov mil net org }
an { com net org edu }
ao { ed gv og co pb it }
ar { com edu gov int mil net org gob }
arpa { e164 in-addr ip6 iris uri urn }
as { gov }
at { ac biz co gv info or priv }
aw { com }
az { com net int gov org edu info pp mil name pro biz }
ba { com co gov org net edu mil unsa untz unbi rs }
bb { biz com edu gov info net org store }                                # allows 2 level
bd { com edu ac net gov org mil }
be { ac }
bf { gov }
bh { com info cc edu biz net org gov }
bi { com co edu or org }
bj { asso barreau gouv }
bg { a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 }
bm { com edu gov net org }
bn { com edu ort net gov }
bo { com net org tv mil int gob gov edu }
br { adm adv agr am arq art ato bio blog bmd can cim cng cnt com coop ecn eco edu eng esp etc eti far flog fm fnd fot fst ggf gov imb ind inf jor jus leg lel mat med mil mus net nom not ntr odo org ppg pro psc psi qsl rec slg srv tmp trd tur tv vet vlog wiki zlg g12 teo taxi radio emp b }
bs { com net org edu gov }
bt { com edu gov net org }
bw { co org }
by { com gov mil of org }
bz { com net org edu gov }
ca { ab bc mb nb nf nl ns nt nu on pe qc sk yk gc co }
cc { cz co cc uni }
cd { gov }
ci { org or com co edu ed ac net go asso int presse md gouv }
cl { gov gob co mil }
cm { gov }
cn { ac com edu gov net org mil ah bj cq fj gd gs gz gx ha hb he hi hk hl hn jl js jx ln mo nm nx qh sc sd sh sn sx tj tw xj xz yn zj }
co { com org edu gov net mil nom arts firm info int rec web }
com { ar br cn de eu gb gr hu jpn kr no qc ru sa se uk us uy za } # https://www.centralnic.com/names/domains
com { }
cr { ac co ed fi go or sa }
cu { com edu org net gov inf co }
cx { gov }
cy { ac net gov org pro name ekloges tm ltd biz press parliament com }
de { com }
dm { com net org edu gov }
do { edu gob gov com sld org net web mil art }
dz { com org net gov edu asso pol art }
ec { com info net fin med pro org edu gov mil k12 gob}            # allows 2 level
ee { com org fie pri edu gov riik lib med aip }
eg { eun edu sci gov com org name net mil }
er { com edu gov mil net org ind rochest w }
es { com nom org gob edu }
et { com net gov edu org }                                 # 2nd level = SPAM
fi { aland iki }
fj { ac biz com info mil name net org pro }
fr { com asso nom prd presse tm aeroport assedic avocat avoues cci chambagri chirurgiens-dentistes experts-comptables geometre-expert gouv greta huissier-justice medecin notaires pharmacien port veterinaire }
ge { com edu gov org mil net pvt }
gg { co org net sch gov }              # http://www.channelisles.net/applic/avextn.shtml
gh { com edu gov org mil }
gi { com ltd gov mod edu org }                             # http://www.nic.gi/
gn { ac com edu gov org net }
gp { com net mobi edu org asso }
gr { com edu net org gov }             # https://grweb.ics.forth.gr/english/brief_instructions.html
gt { com edu net gob org mil ind }
gy { co com net }
hk { com edu gov idv net org cuhk hku ust }
hn { com edu org net mil gob }
hr { iz from name com }
ht { com shop firm info adult net pro org med art coop pol asso edu rel gouv perso }
hu { co info org priv sport tm 2000 agrar bolt casino city erotica erotika film forum games hotel ingatlan jogasz konyvelo lakas media news reklam sex shop suli szex tozsde utazas video }
id { ac co net or web sch mil go }
ie { gov }
il { ac co org net k12 gov muni idf  }
im { co net gov org nic ac }
im { co } { ltd plc }
in { co firm net org gen ind ac edu res ernet gov mil nic }
io { com }
int { eu }
iq { gov edu mil com org net }
ir { ac co gov id net org sch }
is { net com edu gov org int }
it { gov edu agrigento ag alessandria al ancona an aosta aoste ao arezzo ar piceno ascolipiceno ap asti at avellino av bari ba barlettaandriatrani trani belluno bl benevento bn bergamo bg biella bi bologna bo bolzano bozen balsan adige altoadige suedtirol bz brescia bs brindisi br cagliari ca caltanissetta cl campobasso cb caserta ce catania ct catanzaro cz chieti ch como co cosenza cs cremona cr crotone kr cuneo cn enna en fermo ferrara fe firenze florence fi foggia fg cesena forlicesena fc frosinone fr genova genoa ge gorizia go grosseto gr imperia im isernia is laquila aquila aq spezia laspezia sp latina lt lecce le lecco lc livorno li lodi lo lucca lu macerata mc mantova mn carrara massacarrara ms matera mt messina me milano milan mi modena mo monza napoli naples na novara no nuoro nu oristano or padova padua pd palermo pa parma pr pavia pv perugia pg pescara pe urbino pesarourbino pu piacenza pc pisa pi pistoia pt pordenone pn potenza pz prato po ragusa rg ravenna ra calabria reggiocalabria rc emilia reggioemilia re rieti ri rimini rn roma rome rm rovigo ro salerno sa sassari ss savona sv siena si siracusa sr sondrio so taranto ta teramo te terni tempio-olbia tempioolbia olbia-tempio olbiatempio ot tr torino turin to trapani tp trento trentino tn treviso tv trieste ts udine ud varese va venezia venice ve verbania vb vercelli vc verona vr valentia vibovalentia vv vicenza vi viterbo vt ascoli-piceno barletta-andria-trani alto-adige forli-cesena la-spezia massa-carrara pesaro-urbino reggio-calabria reggio-emilia urbino-pesaro urbinopesaro vibo-valentia mb monzaedellabrianza monza-e-della-brianza monza-brianza campidanomedio vs campidano-medio mediocampidano medio-campidano carraramassa carrara-massa cesena-forli cesenaforli cesena-forli fm ogliastra og dellogliastra dell-ogliastra ci iglesiascarbonia iglesias-carbonia carbonia-iglesias carboniaiglesias bt traniandriabarletta trani-andria-barletta andriatranibarletta andria-trani-barletta barlettatraniandria barletta-trani-andria tranibarlettaandria trani-barletta-andria andriabarlettatrani andria-barletta-trani monzaebrianza monzabrianza }
je { co org net sch gov }              # http://www.channelisles.net/applic/avextn.shtml
jm { com net org edu gov mil }
jo { com net org edu gov mil name sch myname }
jp { ac ad co ed go gr lg ne or }                          # allows 2 level
jp { aichi akita aomori chiba ehime fukui fukuoka fukushima gifu gunma hiroshima hokkaido hyogo ibaraki ishikawa iwate kagawa kagoshima kanagawa kawasaki kitakyushu kobe kochi kumamoto kyoto mie miyagi miyazaki nagano nagasaki nagoya nara niigata oita okayama okinawa osaka saga saitama sapporo sendai shiga shimane shizuoka tochigi tokushima tokyo tottori toyama wakayama yamagata yamaguchi yamanashi yokohama }
jp { aichi } { aisai ama anjo asuke chiryu chita fuso gamagori handa hazu hekinan higashiura ichinomiya inazawa inuyama isshiki iwakura kanie kariya kasugai kira kiyosu komaki konan kota mihama miyoshi nagakute nishio nisshin obu oguchi oharu okazaki owariasahi seto shikatsu shinshiro shitara tahara takahama tobishima toei togo tokai tokoname toyoake toyohashi toyokawa toyone toyota tsushima yatomi }
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
jp { iwate } { fudai fujisawa hanamaki hiraizumi hirono ichinohe ichinoseki iwaizumi iwate joboji kamaishi kanegasaki karumai kawai kitakami kuji kunohe kuzumaki miyako mizusawa morioka ninohe noda ofunato oshu otsuchi rikuzentakata shiwa shizukuishi sumita takizawa tanohata tono yahaba yamada }
jp { kagawa } { ayagawa higashikagawa kanonji kotohira manno marugame mitoyo naoshima sanuki tadotsu takamatsu tonosho uchinomi utazu zentsuji }
jp { kagoshima } { akune amami hioki isa isen izumi kagoshima kanoya kawanabe kinko kouyama makurazaki matsumoto minamitane nakatane nishinoomote satsumasendai soo tarumizu yusui }
jp { kanagawa } { aikawa atsugi ayase chigasaki ebina fujisawa hadano hakone hiratsuka isehara kaisei kamakura kiyokawa matsuda minamiashigara miura nakai ninomiya odawara oi oiso sagamihara samukawa tsukui yamakita yamato yokosuka yugawara zama zushi }
jp { kochi } { aki geisei hidaka higashitsuno ino kagami kami kitagawa kochi mihara motoyama muroto nahari nakamura nankoku nishitosa niyodogawa ochi okawa otoyo otsuki sakawa sukumo susaki tosa tosashimizu toyo tsuno umaji yasuda yusuhara }
jp { kumamoto } { amakusa arao aso choyo gyokuto hitoyoshi kamiamakusa kashima kikuchi kosa kumamoto mashiki mifune minamata minamioguni nagasu nishihara oguni ozu sumoto takamori uki uto yamaga yamato yatsushiro }
jp { kyoto } { ayabe fukuchiyama higashiyama ide ine joyo kameoka kamo kita kizu kumiyama kyotamba kyotanabe kyotango maizuru minami minamiyamashiro miyazu muko nagaokakyo nakagyo nantan oyamazaki sakyo seika tanabe uji ujitawara wazuka yamashina yawata }
jp { mie } { asahi inabe ise kameyama kawagoe kiho kisosaki kiwa komono kumano kuwana matsusaka meiwa mihama minamiise misugi miyama nabari shima suzuka tado taiki taki tamaki toba tsu udono ureshino watarai yokkaichi }
jp { miyagi } { furukawa higashimatsushima ishinomaki iwanuma kakuda kami kawasaki kesennuma marumori matsushima minamisanriku misato murata natori ogawara ohira onagawa osaki rifu semine shibata shichikashuku shikama shiogama shiroishi tagajo taiwa tome tomiya wakuya watari yamamoto zao }
jp { miyazaki } { aya ebino gokase hyuga kadogawa kawaminami kijo kitagawa kitakata kitaura kobayashi kunitomi kushima mimata miyakonojo miyazaki morotsuka nichinan nishimera nobeoka saito shiiba shintomi takaharu takanabe takazaki tsuno }
jp { nagano } { achi agematsu anan aoki asahi azumino chikuhoku chikuma chino fujimi hakuba hara hiraya iida iijima iiyama iizuna ikeda ikusaka ina karuizawa kawakami kiso kisofukushima kitaaiki komagane komoro matsukawa matsumoto miasa minamiaiki minamimaki minamiminowa minowa miyada miyota mochizuki nagano nagawa nagiso nakagawa nakano nozawaonsen obuse ogawa okaya omachi omi ookuwa ooshika otaki otari sakae sakaki saku sakuho shimosuwa shinanomachi shiojiri suwa suzaka takagi takamori takayama tateshina tatsuno togakushi togura tomi ueda wada yamagata yamanouchi yasaka yasuoka }
jp { nagasaki } { chijiwa futsu goto hasami hirado iki isahaya kawatana kuchinotsu matsuura nagasaki obama omura oseto saikai sasebo seihi shimabara shinkamigoto togitsu tsushima unzen }
jp { nara } { ando gose heguri higashiyoshino ikaruga ikoma kamikitayama kanmaki kashiba kashihara katsuragi kawai kawakami kawanishi koryo kurotaki mitsue miyake nara nosegawa oji ouda oyodo sakurai sango shimoichi shimokitayama shinjo soni takatori tawaramoto tenkawa tenri uda yamatokoriyama yamatotakada yamazoe yoshino }
jp { niigata } { aga agano gosen itoigawa izumozaki joetsu kamo kariwa kashiwazaki minamiuonuma mitsuke muika murakami myoko nagaoka niigata ojiya omi sado sanjo seiro seirou sekikawa shibata tagami tainai tochio tokamachi tsubame tsunan uonuma yahiko yoita yuzawa }
jp { oita } { beppu bungoono bungotakada hasama hiji himeshima hita kamitsue kokonoe kuju kunisaki kusu oita saiki taketa tsukumi usa usuki yufu }
jp { okayama } { akaiwa asakuchi bizen hayashima ibara kagamino kasaoka kibichuo kumenan kurashiki maniwa misaki nagi niimi nishiawakura okayama satosho setouchi shinjo shoo soja takahashi tamano tsuyama wake yakage }
jp { okinawa } { aguni ginowan ginoza gushikami haebaru higashi hirara iheya ishigaki ishikawa itoman izena kadena kin kitadaito kitanakagusuku kumejima kunigami minamidaito motobu nago naha nakagusuku nakijin nanjo nishihara ogimi okinawa onna shimoji taketomi tarama tokashiki tomigusuku tonaki urasoe uruma yaese yomitan yonabaru yonaguni zamami }
jp { osaka } { abeno chihayaakasaka chuo daito fujiidera habikino hannan higashiosaka higashisumiyoshi higashiyodogawa hirakata ibaraki ikeda izumi izumiotsu izumisano kadoma kaizuka kanan kashiwara katano kawachinagano kishiwada kita kumatori matsubara minato minoh misaki moriguchi neyagawa nishi nose osakasayama sakai sayama sennan settsu shijonawate shimamoto suita tadaoka taishi tajiri takaishi takatsuki tondabayashi toyonaka toyono yao }
jp { saga } { ariake arita fukudomi genkai hamatama hizen imari kamimine kanzaki karatsu kashima kitagata kitahata kiyama kouhoku kyuragi nishiarita ogi omachi ouchi saga shiroishi taku tara tosu yoshinogari }
jp { saitama } { arakawa asaka chichibu fujimi fujimino fukaya hanno hanyu hasuda hatogaya hatoyama hidaka higashichichibu higashimatsuyama honjo ina iruma iwatsuki kamiizumi kamikawa kamisato kasukabe kawagoe kawaguchi kawajima kazo kitamoto koshigaya kounosu kuki kumagaya matsubushi minano misato miyashiro miyoshi moroyama nagatoro namegawa niiza ogano ogawa ogose okegawa omiya otaki ranzan ryokami saitama sakado satte sayama shiki shiraoka soka sugito toda tokigawa tokorozawa tsurugashima urawa warabi yashio yokoze yono yorii yoshida yoshikawa yoshimi }
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
jp { }
ke { co or ne go ac sc }
kg { org net com edu gov mil }
kh { per com edu gov mil net org }
ki { edu biz net org gov info com }
km { org nom gov prd tm edu mil ass com coop asso presse medecin notaires pharmaciens veterinaire gouv }
kn { net org edu gov }
kp { com edu gov org rep tra }
kr { co ne or re pe go mil ac hs ms es sc kg seoul busan daegu incheon gwangju daejeon ulsan gyeonggi gangwon chungbuk chungnam jeonbuk jeonnam gyeongbuk gyeongnam jeju }
kw { edu com net org gov }
ky { edu gov com org net }
kz { org edu net gov mil com }
la { int net info edu gov per com org c }
lb { com edu gov net org }
lc { co com net org edu gov net }
lk { gov sch net int com org edu ngo soc web ltd assn grp hotel ac }
lr { com edu gov org net }
ls { co org }
lt { gov }
lv { com edu gov org mil id net asn conf }
ly { com net gov plc edu sch med org id }
ma { net ac org gov press co }                             # allows 2 level
mc { tm asso }
me { co net org edu ac gov its priv }
mg { org nom gov prd tm edu mil com }
mk { com org gov net edu inf name }
ml { com edu gouv gov net org presse }
mn { gov edu org }
mo { com net org edu gov}
mr { gov }
mt { com org net edu gov }
mx { com net org edu gob }                                 # allows 2 level
mu { com net org gov ac co or }
museum { academy agriculture air airguard alabama alaska amber ambulance american americana americanantiques americanart amsterdam and annefrank anthro anthropology antiques aquarium arboretum archaeological archaeology architecture art artanddesign artcenter artdeco arteducation artgallery arts artsandcrafts asmatart assassination assisi association astronomy atlanta austin australia automotive aviation axis badajoz baghdad bahn bale baltimore barcelona baseball basel baths bauern beauxarts beeldengeluid bellevue bergbau berkeley berlin bern bible bilbao bill birdart birthplace bonn boston botanical botanicalgarden botanicgarden botany brandywinevalley brasil bristol british britishcolumbia broadcast brunel brussel brussels bruxelles building burghof bus bushey cadaques california cambridge can canada capebreton carrier cartoonart casadelamoneda castle castres celtic center chattanooga cheltenham chesapeakebay chicago children childrens childrensgarden chiropractic chocolate christiansburg cincinnati cinema circus civilisation civilization civilwar clinton clock coal coastaldefence cody coldwar collection colonialwilliamsburg coloradoplateau columbia columbus communication communications community computer computerhistory contemporary contemporaryart convent copenhagen corporation corvette costume countryestate county crafts cranbrook creation cultural culturalcenter culture cyber cymru dali dallas database ddr decorativearts delaware delmenhorst denmark depot design detroit dinosaur discovery dolls donostia durham eastafrica eastcoast education educational egyptian eisenbahn elburg elvendrell embroidery encyclopedic england entomology environment environmentalconservation epilepsy essex estate ethnology exeter exhibition family farm farmequipment farmers farmstead field figueres filatelia film fineart finearts finland flanders florida force fortmissoula fortworth foundation francaise frankfurt franziskaner freemasonry freiburg fribourg frog fundacio furniture gallery garden gateway geelvinck gemological geology georgia giessen glas glass gorge grandrapids graz guernsey halloffame hamburg handson harvestcelebration hawaii health heimatunduhren hellas helsinki hembygdsforbund heritage histoire historical historicalsociety historichouses historisch historisches history historyofscience horology house humanities illustration imageandsound indian indiana indianapolis indianmarket intelligence interactive iraq iron isleofman jamison jefferson jerusalem jewelry jewish jewishart jfk journalism judaica judygarland juedisches juif karate karikatur kids koebenhavn koeln kunst kunstsammlung kunstunddesign labor labour lajolla lancashire landes lans larsson lewismiller lincoln linz living livinghistory localhistory london losangeles louvre loyalist lucerne luxembourg luzern mad madrid mallorca manchester mansion mansions manx marburg maritime maritimo maryland marylhurst media medical medizinhistorisches meeres memorial mesaverde michigan midatlantic military mill miners mining minnesota missile missoula modern moma money monmouth monticello montreal moscow motorcycle muenchen muenster mulhouse muncie museet museumcenter museumvereniging music national nationalfirearms nationalheritage nativeamerican naturalhistory naturalhistorymuseum naturalsciences nature naturhistorisches natuurwetenschappen naumburg naval nebraska neues newhampshire newjersey newmexico newport newspaper newyork niepce norfolk north nrw nuernberg nuremberg nyc nyny oceanographic oceanographique omaha online ontario openair oregon oregontrail otago oxford pacific paderborn palace paleo palmsprings panama paris pasadena pharmacy philadelphia philadelphiaarea philately phoenix photography pilots pittsburgh planetarium plantation plants plaza portal portland portlligat posts-and-telecommunications preservation presidio press project public pubol quebec railroad railway research resistance riodejaneiro rochester rockart roma russia saintlouis salem salvadordali salzburg sandiego sanfrancisco santabarbara santacruz santafe saskatchewan satx savannahga schlesisches schoenbrunn schokoladen school schweiz science scienceandhistory scienceandindustry sciencecenter sciencecenters science-fiction sciencehistory sciences sciencesnaturelles scotland seaport settlement settlers shell sherbrooke sibenik silk ski skole society sologne soundandvision southcarolina southwest space spy square stadt stalbans starnberg state stateofdelaware station steam steiermark stjohn stockholm stpetersburg stuttgart suisse surgeonshall surrey svizzera sweden sydney tank tcm technology telekommunikation television texas textile theater time timekeeping topology torino touch town transport tree trolley trust trustee uhren ulm undersea university usa usantiques usarts uscountryestate usculture usdecorativearts usgarden ushistory ushuaia uslivinghistory utah uvic valley vantaa versailles viking village virginia virtual virtuel vlaanderen volkenkunde wales wallonie war washingtondc watchandclock watch-and-clock western westfalen whaling wildlife williamsburg windmill workshop york yorkshire yosemite youth zoological zoology }
mv { aero biz com coop edu gov info int mil museum name net org pro }
mw { ac biz co com coop edu gov int museum net org }
my { com net org gov edu mil name }                        # allows 2 level
mz { co org gov edu }
na { ca co com info pro name school or dr us mx co in cc tv ws mobi org }
nc { asso }
net { gb hu jp se uk za }
nf { com net per rec web arts firm info other store }
ng { com org gov edu net sch name mobi biz mil ac }
ni { gob co ac org nom net mil com edu }
nl { bv co }
# no : http://www.norid.no/regelverk/index.en ml
no { co fhs vgs fylkesbibl folkebibl museum idrett mil stat dep kommune herad priv }
# no : geographical names : http://www.norid.no/regelverk/vedlegg-b.en ml
no { aa ah bu fm hl hm jan-mayen mr nl nt of ol oslo rl sf st svalbard tm tr va vf }
no { aa ah bu fm hl hm jan-mayen mr nl nt of ol oslo rl sf st svalbard tm tr va vf } { gs }
# no : city/county/region names.
no { akrehamn algard arna brumunddal bryne bronnoysund drobak egersund fetsund floro fredrikstad hokksund honefoss jessheim jorpeland kirkenes kopervik krokstadelva langevag leirvik mjondalen mosjoen nesoddtangen orkanger osoyro raholt sandnessjoen skedsmokorset slattum spjelkavik stathelle stavern stjordalshalsen tananger tranby vossevangen afjord agdenes al alesund alstahaug alta alaheadju alvdal amli amot andebu andoy andasuolo ardal aremark arendal aseral asker askim askvoll askoy asnes audnedaln aukra aure aurland austevoll austrheim averoy balestrand ballangen balat balsfjord bahccavuotna bamble bardu beardu beiarn bajddar baidar berg bergen berlevag bearalvahki bindal birkenes bjarkoy bjerkreim bjugn bodo badaddja budejju bokn bremanger bronnoy bygland bykle barum bo bievat bomlo batsfjord bahcavuotna dovre drammen drangedal dyroy donna eid eidfjord eidsberg eidskog eidsvoll eigersund elverum enebakk engerdal etne etnedal evenes evenassi farsund fauske fuossko fuoisku fedje fet finnoy fitjar fjaler fjell flakstad flatanger flekkefjord flesberg flora fla folldal forsand fosnes frei frogn froland frosta frana froya fusa fyresdal forde gamvik gangaviika gaular gausdal gildeskal giske gjemnes gjerdrum gjerstad gjesdal gjovik gloppen gol gran grane granvin gratangen grimstad grong kraanghke grue gulen hadsel halden halsa hamar hamaroy habmer hapmir hammerfest hammarfeasta haram hareid harstad hasvik aknoluokta hattfjelldal aarborte haugesund hemne hemnes hemsedal heroy hitra hjartdal hjelmeland hobol hof hol hole holmestrand holtalen hornindal horten hurdal hurum hvaler hyllestad hagebostad hoyanger hoylandet ha ibestad inderoy iveland jevnaker jondal jolster karasjok karasjohka karlsoy galsa karmoy kautokeino guovdageaidnu klepp klabu kongsberg kongsvinger kragero kristiansand kristiansund krodsherad kvalsund rahkkeravju kvam kvinesdal kvinnherad kviteseid kvitsoy kvafjord giehtavuoatna kvanangen navuotna kafjord gaivuotna larvik lavangen lavagis loabat lebesby davvesiida leikanger leirfjord leka leksvik lenvik leangaviika lesja levanger lier lierne lillehammer lillesand lindesnes lindas lom loppa lahppi lund lunner luroy luster lyngdal lyngen ivgu lardal lerdal lodingen lorenskog loten malvik masoy muosat mandal marker marnardal masfjorden meland meldal melhus meloy meraker moareke midsund modalen modum molde moskenes moss mosvik malselv malatvuopmi namdalseid aejrie namsos namsskogan naamesjevuemie laakesvuemie nannestad narvik narviika naustdal nesna nesodden nesseby unjarga nesset nissedal nittedal norddal nordkapp davvenjarga nordreisa raisa notodden naroy notteroy odda oksnes oppdal oppegard orkdal orland orskog orsta osen osteroy overhalla oyer oygarden porsanger porsangu porsgrunn radoy rakkestad rana ruovat randaberg rauma rendalen rennebu rennesoy rindal ringebu ringerike ringsaker rissa risor roan rollag rygge ralingen rodoy romskog roros rost royken royrvik rade salangen siellak saltdal samnanger sandefjord sandnes sandoy sarpsborg sauda sauherad sel selbu selje seljord sigdal siljan sirdal skaun skedsmo ski skien skiptvet skjervoy skierva skjak skodje skanland skanit smola snillfjord snasa snoasa snaase sogndal sokndal sola solund songdalen sortland spydeberg stange stavanger steigen steinkjer stjordal stokke stord stordal storfjord omasvuotna strand stranda stryn sula suldal sund sunndal surnadal sveio svelvik sykkylven sogne somna sorfold sorreisa sorum tana deatnu time tingvoll tinn tjeldsund dielddanuorri tjome tokke tolga torsken tranoy tromso tromsa romsa trondheim troandin trysil trana trogstad tvedestrand tydal tynset tysfjord divtasvuodna divttasvuotna tysnes tysvar tonsberg ullensaker ullensvang ulvik utsira vadso cahcesuolo vaksdal valle vang vanylven vardo varggat vefsn vaapste vega vegarshei vennesla verdal verran vestby vestnes vestvagoy vevelstad vik vikna vindafjord volda voss varoy vagan voagat vagsoy vaga odda oksnes oppdal oppegard orkdal orland orskog orsta osen osteroy overhalla oyer oygarden porsanger porsangu porsgrunn radoy rakkestad rana ruovat randaberg rauma rendalen rennebu rennesoy rindal ringebu ringerike ringsaker rissa risor roan rollag rygge ralingen rodoy romskog roros rost royken royrvik rade salangen siellak saltdal samnanger sandefjord sandnes sandoy sarpsborg sauda sauherad sel selbu selje seljord sigdal siljan sirdal skaun skedsmo ski skien skiptvet skjervoy skierva skjak skodje skanland skanit smola snillfjord snasa snoasa snaase sogndal sokndal sola solund songdalen sortland spydeberg stange stavanger steigen steinkjer stjordal stokke stord stordal storfjord omasvuotna strand stranda stryn sula suldal sund sunndal surnadal sveio svelvik sykkylven sogne somna sorfold sorreisa sorum tana deatnu time tingvoll tinn tjeldsund dielddanuorri tjome tokke tolga torsken tranoy tromso tromsa romsa trondheim troandin trysil trana trogstad tvedestrand tydal tynset tysfjord divtasvuodna divttasvuotna tysnes tysvar tonsberg ullensaker ullensvang ulvik utsira vadso cahcesuolo vaksdal valle vang vanylven vardo varggat vefsn vaapste vega vegarshei vennesla verdal verran vestby vestnes vestvagoy vevelstad vik vikna vindafjord volda voss varoy vagan voagat vagsoy vaga mo-i-rana aurskog-holand aurskog-holand evje-og-hornnes stor-elvdal sondre-land sor-odal sor-aurdal sor-fron vestre-slidre sor-varanger matta-varjjat oystre-slidre midtre-gauldal nedre-eiker nord-aurdal nord-odal nordre-land nore-og-uvdal ostre-toten ovre-eiker vestre-toten nord-fron salat }
no { telemark nordland } { bo }
no { more-og-romsdal nordland } { heroy }
no { hedmark hordaland } { os  }
no { akershus buskerud } { nes }
no { hedmark ostfold } { valer }
no { more-og-romsdal vestfold } { sande }
np { com org edu net gov mil }
nr { biz info gov edu org net com co }
nz { cri govt iwi parliament mil ac co geek gen maori net org school }
om { com co edu ac sch gov net org mil museum biz pro med }
om { }
org { ae us za }
pa { ac gob com org sld edu net ing abo med nom }
pe { edu gob nom mil sid org com net }                     # allows 2 level
pf { com org edu }
pg { com net ac gov mil org }
ph { com net org i gov mil edu ngo }                       # allows 2 level
pk { com net edu org fam biz web gov gob gok gon gop gos info goa }
pl { aid agro atm auto biz co com edu gmina gsm info mail miasta media mil net nieruchomosci nom org pc powiat priv realestate rel sex shop sklep sos szkola targi tm tourism travel turystyka art mbone gov }
pl { gov } { uw um ug upow starostwo so sr po pa }
pl { 6bone med ngo irc usenet augustow bedzin beskidy bialowieza bialystok bielawa bieszczady boleslawiec bydgoszcz bytom cieszyn czeladz czest dlugoleka elblag elk glogow gniezno gorlice grajewo ilawa jaworzno jgora kalisz karpacz kartuzy kaszuby katowice kepno ketrzyn klodzko kobierzyce kolobrzeg konin konskowola kutno lapy lebork legnica lezajsk limanowa lomza lowicz lubin lukow malbork malopolska mazowsze mazury mielec mielno mragowo naklo nowaruda nysa olawa olecko olkusz olsztyn opoczno opole ostroda ostroleka ostrowiec ostrowwlkp pila pisz podhale podlasie polkowice pomorze pomorskie prochowice pruszkow przeworsk pulawy radom rybnik rzeszow sanok sejny siedlce slask slupsk sosnowiec skoczow starachowice stargard suwalki swidnica swiebodzin swinoujscie szczecin szczytno tarnobrzeg tgory turek tychy ustka walbrzych warmia warszawa waw wegrow wielun wlocl wloclawek wodzislaw wolomin wroclaw zachpomor zagan zarow zgora zgorzelec gda gdansk gdynia sopot gliwice krakow poznan wroc zakopane babia-gora jelenia-gora kazimierz-dolny rawa-maz stalowa-wola }
pn { gov co org edu net }
pr { com net org gov edu isla pro biz info name est prof ac }
pro { aca bar cpa jur law med eng }
ps { edu gov sec plo com org net }
pt { net gov org edu pt int publ com nome}
pw { co ne or ed go belau }
py { com coop edu mil gov net org una }
qa { com edu net gov net org mil name sch }               # allows few 2 level
re { com asso nom }
ro { com org tm nt nom info rec arts firm store www }
rs { co org edu ac gov in }
ru { ac com edu int net org pp adygeya altai amur arkhangelsk astrakhan bashkiria belgorod bir bryansk buryatia cbg chel chelyabinsk chita chukotka chuvashia dagestan dudinka e-burg grozny irkutsk ivanovo izhevsk jar joshkar-ola kalmykia kaluga kamchatka karelia kazan kchr kemerovo khabarovsk khakassia khv kirov koenig komi kostroma krasnoyarsk kuban kurgan kursk lipetsk magadan mari mari-el marine mordovia mosreg msk murmansk nalchik nnov nov novosibirsk nsk omsk orenburg oryol palana penza perm pskov ptz rnd ryazan sakhalin samara saratov simbirsk smolensk spb stavropol stv surgut tambov tatarstan tom tomsk tsaritsyn tsk tula tuva tver tyumen udm udmurtia ulan-ude vladikavkaz vladimir vladivostok volgograd vologda voronezh vrn vyatka yakutia yamal yaroslavl yekaterinburg yuzhno-sakhalinsk amursk baikal cmw fareast jamal kms k-uralsk kustanai kuzbass magnitka mytis nakhodka nkz norilsk oskol pyatigorsk rubtsovsk snz syzran vdonsk zgrad gov mil test }
rw { gov net edu ac com co int mil gouv }
sa { com edu sch med gov net org pub }
sb { com edu gov net org}
sc { com gov net org edu }
sd { com net org edu med tv gov info }
se { org pp tm parti press mil a b c d e f g h i k m n o s t u w x y z ac bd brand komforb kommunalforbund komvux lanbib naturbruksgymn fh fhsk  fhv l p r sshn }
sg { com edu net org gov per idn }                          # allows 2 level
sh { com net gov org mil }
sl { com net org edu gov }
sn { art com edu gouv org perso univ }
so { com net org }
st { co com consulado edu embaixada gov mil net org principe saotome store }
sv { com edu gob org red }
sx { gov }
sy { com edu gov net mil org  }
sz { co ac org }                  # http://www.sispa.org.sz/
tc { biz net eu us pro de at it ru se dk be no int pl bg cz mx br hk kr th ph }
tc { at } { co }  # http://www.smartdots.com/
th { co ac in go mi or net }
tj { ac biz co com edu go gov int mil name net nic org test web }
tl { gov }
tm { com co org net nom gov mil edu }
tn { com ens fin gov ind intl nat net org info perso tourism edunet rnrt rns rnu mincom agrinet defense turen } # allows 2 level
to { co edu com gov net org mil }
tr { nc com gen org biz info av dr pol bel mil bbs k12 edu name net gov web tel tv }
tr { nc } { gov }
tt { co com org net biz info pro int coop jobs mobi travel museum aero name gov edu }
tv { com net org gov }
tw { com edu gov mil net org idv game ebiz club }
tz { ac co go mil ne or sc }
ua { com edu gov org net in kv co pp }                       # allows 2 level
ua { cherkassy cherkasy chernigov chernihiv chernivtsi chernovtsy ck cn cr crimea cv dn dnepropetrovsk dnipropetrovsk dominic donetsk dp if kh kharkiv kharkov kherson khmelnytskyi kiev kirovograd km kr krym ks kv kyiv lg lt lugansk lutsk lv lviv mk mykolaiv nikolaev od odesa odessa pl poltava rivne rovno rv sb sebastopol sevastopol sm sumy te ternopil uz vinnica vinnytsia vn volyn yalta zaporizhzhe zaporizhzhia zhitomir zhytomyr zp uz uzhgorod zt ivano-frankivsk khmelnitskiy }
ug { co ac sc go ne or com org }
uz { com co net org }
uy { com edu gub net mil org }
vc { com edu mil gov org net }
ve { com e12 edu gob gov mil net org info co web }
vi { com org edu gov net k12 co }
vn { com net edu org gov biz int ac pro info health name } # allows 2 level
vu { com net edu org gov }
ws { com net org gov edu }
yu { ac edu org co gov cg }
ye { com co ltd me net org pic gov }
zm { ac co com edu gov net org sch }
zw { co ac org }

# special google domains
ar { com } { blogspot }
at { co } { blogspot }
au { com } { blogspot }
be { blogspot }
bj { blogspot }
br { com } { blogspot }
ca { blogspot }
cf { blogspot }
ch { blogspot }
com { appspot blogspot codespot googleapis googlecode }
cv { blogspot }
cz { blogspot }
de { blogspot }
dk { blogspot }
es { com } { blogspot }
fi { blogspot }
fr { blogspot }
gr { blogspot }
hk { blogspot }
hu { blogspot }
ie { blogspot }
il { co } { blogspot }
in { blogspot }
it { blogspot }
jp { blogspot }
kr { blogspot }
mr { blogspot }
mx { blogspot }
nl { blogspot }
no { blogspot }
nz { co } { blogspot }
pt { blogspot }
re { blogspot }
ro { blogspot }
se { blogspot }
sg { blogspot }
sk { blogspot }
td { blogspot }
tw { blogspot }
uk { co } { blogspot }

# special requested domains Opera, Redhat, etc
com { betainabox dreamhosters operaunite rhcloud }

# new auto generated rules
academy { }
actor { }
agency { }
airforce { }
ar { tur }
archi { }
army { }
associates { }
au { csiro }
autos { }
axa { }
bar { }
bargains { }
bayern { }
beer { }
berlin { }
best { }
bid { }
bike { }
bio { }
biz { dyndns for-better for-more for-some for-the selfip webhop }
black { }
blackfriday { }
blue { }
boo { }
boutique { }
br { mp }
brussels { }
budapest { }
build { }
builders { }
business { }
buzz { }
bv { }
bz { za }
bzh { }
cab { }
camera { }
camp { }
capital { }
caravan { }
cards { }
career { }
careers { }
casa { }
cash { }
catering { }
cc { ftpaccess game-server myphotos scrapping }
center { }
ceo { }
cheap { }
christmas { }
church { }
cleaning { }
clothing { }
club { }
codes { }
coffee { }
college { }
cologne { }
com { africa blogdns cechire cloudcontrolapp cloudcontrolled co dnsalias dnsdojo doesntexist dontexist doomdns dyn-o-saur dynalias dyndns-at-home dyndns-at-work dyndns-blog dyndns-free dyndns-home dyndns-ip dyndns-mail dyndns-office dyndns-pics dyndns-remote dyndns-server dyndns-web dyndns-wiki dyndns-work elasticbeanstalk est-a-la-maison est-a-la-masion est-le-patron est-mon-blogueur from-ak from-al from-ar from-ca from-ct from-dc from-de from-fl from-ga from-hi from-ia from-id from-il from-in from-ks from-ky from-ma from-md from-mi from-mn from-mo from-ms from-mt from-nc from-nd from-ne from-nh from-nj from-nm from-nv from-oh from-ok from-or from-pa from-pr from-ri from-sc from-sd from-tn from-tx from-ut from-va from-vt from-wa from-wi from-wv from-wy getmyip githubusercontent gotdns herokuapp herokussl hobby-site homelinux homeunix iamallama is-a-anarchist is-a-blogger is-a-bookkeeper is-a-bulls-fan is-a-caterer is-a-chef is-a-conservative is-a-cpa is-a-cubicle-slave is-a-democrat is-a-designer is-a-doctor is-a-financialadvisor is-a-geek is-a-green is-a-guru is-a-hard-worker is-a-hunter is-a-landscaper is-a-lawyer is-a-liberal is-a-libertarian is-a-llama is-a-musician is-a-nascarfan is-a-nurse is-a-painter is-a-personaltrainer is-a-photographer is-a-player is-a-republican is-a-rockstar is-a-socialist is-a-student is-a-teacher is-a-techie is-a-therapist is-an-accountant is-an-actor is-an-actress is-an-anarchist is-an-artist is-an-engineer is-an-entertainer is-certified is-gone is-into-anime is-into-cars is-into-cartoons is-into-games is-leet is-not-certified is-slick is-uberleet is-with-theband isa-geek isa-hockeynut issmarterthanyou likes-pie likescandy mex neat-url outsystemscloud ro saves-the-whales selfip sells-for-less sells-for-u servebbs simple-url space-to-rent teaches-yoga withgoogle writesthisblog }
com { amazonaws } { compute compute-1 elb s3 s3-ap-northeast-1 s3-ap-southeast-1 s3-ap-southeast-2 s3-eu-west-1 s3-fips-us-gov-west-1 s3-sa-east-1 s3-us-gov-west-1 s3-us-west-1 s3-us-west-2 s3-website-ap-northeast-1 s3-website-ap-southeast-1 s3-website-ap-southeast-2 s3-website-eu-west-1 s3-website-sa-east-1 s3-website-us-east-1 s3-website-us-gov-west-1 s3-website-us-west-1 s3-website-us-west-2 us-east-1 }
com { amazonaws } { compute } { ap-northeast-1 ap-southeast-1 ap-southeast-2 eu-west-1 sa-east-1 us-gov-west-1 us-west-1 us-west-2 }
com { amazonaws } { compute-1 } { z-1 z-2 }
community { }
company { }
computer { }
condos { }
construction { }
consulting { }
contractors { }
cooking { }
cool { }
country { }
cruises { }
cw { }
cw { com edu net org }
cx { ath }
dabur { }
dad { }
dance { }
dating { }
day { }
de { fuettertdasnetz isteingeek istmein lebtimnetz leitungsen traeumtgerade }
degree { }
democrat { }
desi { }
diamonds { }
digital { }
directory { }
discount { }
dnp { }
domains { }
eat { }
education { }
email { }
engineering { }
enterprises { }
equipment { }
estate { }
eus { }
events { }
exchange { }
expert { }
exposed { }
fail { }
fan { }
farm { }
feedback { }
financial { }
fish { }
fishing { }
fitness { }
flights { }
florist { }
foo { }
foundation { }
frogans { }
futbol { }
gal { }
gallery { }
gb { }
gent { }
ggee { }
gift { }
gives { }
glass { }
globo { }
gop { }
graphics { }
gripe { }
guide { }
guitars { }
guru { }
hamburg { }
haus { }
here { }
hiphop { }
hiv { }
holdings { }
holiday { }
homes { }
horse { }
house { }
how { }
id { biz desa my }
ifm { }
im { com tt tv }
immobilien { }
industries { }
info { barrel-of-knowledge barrell-of-knowledge dyndns for-our groks-the groks-this here-for-more knowsitall selfip webhop }
ing { }
ink { }
institute { }
international { }
io { github }
is { cupcake }
it { abr abruzzo aosta-valley aostavalley bas basilicata cal cam campania emilia-romagna emiliaromagna emr friuli-v-giulia friuli-ve-giulia friuli-vegiulia friuli-venezia-giulia friuli-veneziagiulia friuli-vgiulia friuliv-giulia friulive-giulia friulivegiulia friulivenezia-giulia friuliveneziagiulia friulivgiulia fvg laz lazio lig liguria lom lombardia lombardy lucania mar marche mol molise piedmont piemonte pmn pug puglia sar sardegna sardinia sic sicilia sicily taa tos toscana trentino-a-adige trentino-aadige trentino-alto-adige trentino-altoadige trentino-s-tirol trentino-stirol trentino-sud-tirol trentino-sudtirol trentino-sued-tirol trentino-suedtirol trentinoa-adige trentinoaadige trentinoalto-adige trentinoaltoadige trentinos-tirol trentinostirol trentinosud-tirol trentinosudtirol trentinosued-tirol trentinosuedtirol tuscany umb umbria val-d-aosta val-daosta vald-aosta valdaosta valle-aosta valle-d-aosta valle-daosta valleaosta valled-aosta valledaosta vallee-aoste valleeaoste vao vda ven veneto }
jetzt { }
kaufen { }
kim { }
kitchen { }
kiwi { }
krd { }
kred { }
lacaixa { }
land { }
lease { }
life { }
lighting { }
limited { }
limo { }
link { }
london { }
luxe { }
luxury { }
maison { }
management { }
mango { }
market { }
marketing { }
media { }
meet { }
meme { }
menu { }
miami { }
mini { }
mn { nyc }
moda { }
moe { }
monash { }
mormon { }
moscow { }
motorcycles { }
mov { }
ms { com edu gov net org }
nagoya { }
name { her } { forgot }
name { his } { forgot }
navy { }
net { at-band-camp azure-mobile azurewebsites blogdns broke-it buyshouses cloudapp cloudfront dnsalias dnsdojo does-it dontexist dynalias dynathome endofinternet from-az from-co from-la from-ny gets-it ham-radio-op homeftp homeip homelinux homeunix in in-the-band is-a-chef is-a-geek isa-geek kicks-ass office-on-the podzone scrapper-site selfip sells-it servebbs serveftp thruhere webhop }
net { fastly } { prod } { a global }
net { fastly } { ssl } { a b global }
network { }
neustar { }
new { }
ngo { }
nhk { }
ninja { }
nrw { }
nu { merseine mine shacknet }
nyc { }
okinawa { }
ong { }
onl { }
org { blogdns blogsite boldlygoingnowhere dnsalias dnsdojo doesntexist dontexist doomdns dvrdns dynalias dyndns endofinternet endoftheinternet from-me game-host gotdns hobby-site homedns homeftp homelinux homeunix is-a-bruinsfan is-a-candidate is-a-celticsfan is-a-chef is-a-geek is-a-knight is-a-linux-user is-a-patsfan is-a-soxfan is-found is-lost is-saved is-very-bad is-very-evil is-very-good is-very-nice is-very-sweet isa-geek kicks-ass misconfused podzone readmyblog selfip sellsyourhome servebbs serveftp servegame stuff-4-sale webhop }
org { dyndns } { go home }
otsuka { }
ovh { }
paris { }
partners { }
parts { }
photo { }
photography { }
photos { }
pics { }
pictures { }
pink { }
plumbing { }
pm { }
post { }
praxi { }
prod { }
productions { }
properties { }
pub { }
qpon { }
quebec { }
recipes { }
red { }
rehab { }
reise { }
reisen { }
ren { }
rentals { }
repair { }
report { }
rest { }
reviews { }
rich { }
rio { }
rocks { }
rodeo { }
ruhr { }
ryukyu { }
saarland { }
sca { }
scb { }
schule { }
scot { }
services { }
sexy { }
shiksha { }
shoes { }
shriram { }
singles { }
sj { }
social { }
sohu { }
solar { }
solutions { }
soy { }
spiegel { }
supplies { }
supply { }
support { }
suzuki { }
systems { }
tattoo { }
technology { }
tienda { }
tips { }
today { }
tokyo { }
tools { }
town { }
toys { }
tp { }
trade { }
training { }
tv { better-than dyndns on-the-web worse-than }
tz { hotel info me mobi tv }
university { }
uno { }
vacations { }
vegas { }
ventures { }
vet { }
viajes { }
villas { }
vision { }
vlaanderen { }
vodka { }
vote { }
voting { }
voto { }
voyage { }
wang { }
watch { }
webcam { }
wed { }
wf { }
whoswho { }
wien { }
wiki { }
williamhill { }
wme { }
work { }
works { }
ws { dyndns mypets }
wtc { }
wtf { }
xxx { }
xyz { }
yachts { }
yokohama { }
yt { }
zone { }

_END_OF_DATA_

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

