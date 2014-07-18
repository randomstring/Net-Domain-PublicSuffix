use Test::More qw(no_plan);
use Net::Domain::PublicSuffix;
use strict;

my $testname = "base_domain test";
while(my $line = <DATA>) {

    chomp($line);
    if ($line =~ s/\#\s*(.*)// )
    {
        $testname = $1 || "base_domain test";
    }
    $line =~ s/\s*$//;
    $line =~ s/^\s*//;
    $line =~ s/\s+/ /g;
    next if ($line eq '');

    my($hostname,$basedomain) = split(/\s+/,$line,2);

    my $bn = Net::Domain::PublicSuffix::base_domain($hostname);
    is($bn, $basedomain, "$testname  [$hostname] -> [$bn]  EXPECT [$basedomain]")
}
exit(0);

__DATA__
www.skrenta.com skrenta.com
blog.skrenta.com skrenta.com
fa.rt.com  rt.com
sunnyvale.ca.gov ca.gov
www.ca.gov ca.gov
x.com x.com
www.com www.com
www.www.com www.com
foo.www.net www.net
www.net www.net

# .us
stleos.pvt.k12.ca.us stleos.pvt.k12.ca.us
www.stleos.pvt.k12.ca.us stleos.pvt.k12.ca.us
www.ed-data.k12.ca.us ed-data.k12.ca.us
www.score.k12.ca.us score.k12.ca.us
www.svusd.k12.ca.us svusd.k12.ca.us
www.alleghenycounty.us alleghenycounty.us
foo.alleghenycounty.us alleghenycounty.us
foo.stleos.pvt.k12.ca.us stleos.pvt.k12.ca.us
foo.ed-data.k12.ca.us ed-data.k12.ca.us
foo.score.k12.ca.us score.k12.ca.us
foo.svusd.k12.ca.us svusd.k12.ca.us
sunset.ci.sunnyvale.ca.us ci.sunnyvale.ca.us
www.90210.us 90210.us
foo.90210.us 90210.us
90210.us 90210.us
cyclelicio.us cyclelicio.us
www.cyclelicio.us cyclelicio.us
delicio.us delicio.us
www.delicio.us delicio.us
del.icio.us icio.us
www.icio.us icio.us
www.del.icio.us icio.us
foo.del.icio.us icio.us
www.mountain-village.co.us mountain-village.co.us
www.foobar.ca.us foobar.ca.us
foobar.ca.us foobar.ca.us
www.co.greene.oh.us co.greene.oh.us

#(ci|town|vil|co).<locality>.<state>.us
ci.knoxville.tn.us ci.knoxville.tn.us
www.ci.knoxville.tn.us ci.knoxville.tn.us
library.ci.knoxville.tn.us ci.knoxville.tn.us
town.knoxville.tn.us town.knoxville.tn.us
www.town.knoxville.tn.us town.knoxville.tn.us
library.town.knoxville.tn.us town.knoxville.tn.us
library.town.knoxville.ttn.us ttn.us
library.town.knoxville.tnn.us tnn.us
www.town.buzz.tn.us town.buzz.tn.us
town.sandwich.nh.us town.sandwich.nh.us
www.town.sandwich.nh.us town.sandwich.nh.us

#<org>.(state|dst|cog|pvt.k12|k12|cc|tec|lib|mus|gen).<state>.us
www.dot.state.ky.us dot.state.ky.us
foo.dot.state.ky.us dot.state.ky.us
dot.state.ky.us dot.state.ky.us
www.state.mn.us www.state.mn.us

# .ca
www.topix.ca topix.ca
www.ibm.ca ibm.ca
www.fvchs.bc.ca fvchs.bc.ca
foo.topix.ca topix.ca
foo.ibm.ca ibm.ca
foo.fvchs.bc.ca fvchs.bc.ca
foo.bar.no.ca no.ca
www.fvchs.bcc.ca bcc.ca
www.fvchs.bbc.ca bbc.ca

# make sure broken domains return something
com  com
www  www

# .jp tests
foo.city.kobe.jp  city.kobe.jp
www.foo.city.kobe.jp  city.kobe.jp

# .uk tests
www.nptcgroup.ac.uk nptcgroup.ac.uk
www.parliament.uk parliament.uk
news.parliament.uk parliament.uk
www.news.parliament.uk parliament.uk
www.scottish.parliament.uk parliament.uk
www.co.uk www.co.uk
w.m.wildcard.sch.uk m.wildcard.sch.uk
www.robinhood.ltd.uk  robinhood.ltd.uk
www.foo.robinhood.ltd.uk  robinhood.ltd.uk
www.grampiantv.co.uk grampiantv.co.uk
maps.google.co.uk google.co.uk
www.maps.google.co.uk google.co.uk

# .za
www.tjokkies.fs.school.za tjokkies.fs.school.za
baz.tjokkies.fs.school.za tjokkies.fs.school.za
www.catholicshop.co.za    catholicshop.co.za
baz.catholicshop.co.za    catholicshop.co.za

# .bb
www.foobar.com.bb foobar.com.bb
baz.foobar.com.bb foobar.com.bb
www.foobar.bb foobar.bb
www.baz.foobar.bb foobar.bb

# .bf
www.bar.baz.bf baz.bf
www.bf www.bf
www.www.bf www.bf
foo.www.bf www.bf

# ip numbers tests (non-valid public_suffix)
128.10.2.1   128.10.2.1
127.0.0.1    127.0.0.1
1.2.3.4      1.2.3.4
1.2.3.254    1.2.3.254
55.66.77.88  55.66.77.88

# bad TLDs (non-valid public_suffix)
www.foo.xx   foo.xx
www.bar.example bar.example

# badly formed domains (non-valid public_suffix)
foo.cy   foo.cy
hedmark.no  hedmark.no
www.hedmark.no  www.hedmark.no
valer.hedmark.no  valer.hedmark.no

# test for non-valid chars ! and *
!.foobar.com  foobar.com
*.foobar.com  foobar.com
www.!.com  !.com
www.*.com  *.com
