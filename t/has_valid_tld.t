use Test::More qw(no_plan);
use Net::Domain::PublicSuffix;
use strict;

my $line;
while($line = <DATA>) {

    chomp($line);
    $line =~ s/\#.*//;
    $line =~ s/\s*$//;
    $line =~ s/^\s*//;
    $line =~ s/\s+/ /g;
    next if ($line eq '');

    my($hostname,$valid) = split(/\s+/,$line,2);

    my $test_valid = Net::Domain::PublicSuffix::has_valid_tld($hostname);
    is ($test_valid, $valid, "has_valid_tld [$hostname] -> [$test_valid]  EXPECT $valid");
#    ($test_valid == $valid ?  ok(1) : ok(0));
#    if ($test_valid != $valid) {
#        print "WRONG:  [$hostname] -> [$test_valid]  EXPECTED $valid\n";
#    }
}
exit(0);

__DATA__
www.skrenta.com 1
blog.skrenta.com 1
fa.rt.com  1
sunnyvale.ca.gov 1
www.ca.gov 1
x.com 1
www.com 1
www.www.com 1
foo.www.net 1
www.net 1

# .us
stleos.pvt.k12.ca.us 1
www.stleos.pvt.k12.ca.us 1
www.ed-data.k12.ca.us 1
www.score.k12.ca.us 1
www.svusd.k12.ca.us 1
www.alleghenycounty.us 1
foo.alleghenycounty.us 1
foo.stleos.pvt.k12.ca.us 1
foo.ed-data.k12.ca.us 1
foo.score.k12.ca.us 1
foo.svusd.k12.ca.us 1
sunset.ci.sunnyvale.ca.us 1
www.90210.us 1
foo.90210.us 1 
90210.us 1
del.icio.us 1
www.icio.us 1
www.del.icio.us 1
foo.del.icio.us 1
www.mountain-village.co.us  1
www.foobar.ca.us 1 
foobar.ca.us     1

#(ci|town|vil|co).<locality>.<state>.us
ci.knoxville.tn.us            1
www.ci.knoxville.tn.us        1 
library.ci.knoxville.tn.us    1
town.knoxville.tn.us          1
www.town.knoxville.tn.us      1 
library.town.knoxville.tn.us  1
library.town.knoxville.ttn.us 1
library.town.knoxville.tnn.us 1
www.town.buzz.tn.us           1

#<org>.(state|dst|cog|pvt.k12|k12|cc|tec|lib|mus|gen).<state>.us
www.dot.state.ky.us 1
foo.dot.state.ky.us 1
dot.state.ky.us     1

# .ca
www.topix.ca    1 
www.ibm.ca      1
www.fvchs.bc.ca 1
foo.topix.ca    1
foo.ibm.ca      1
foo.fvchs.bc.ca 1
foo.bar.no.ca   1
www.fvchs.bcc.ca 1
www.fvchs.bbc.ca 1


com 1
.com 1

# .uk
www.acl.icnet.uk           1
www.parliament.uk          1
news.parliament.uk         1
www.news.parliament.uk     1
www.scottish.parliament.uk 1
www.co.uk  1

# .za
www.tjokkies.fs.school.za 1
baz.tjokkies.fs.school.za 1
www.catholicshop.co.za    1
baz.catholicshop.co.za    1

# .bb
www.foobar.com.bb 1
baz.foobar.com.bb 1
www.foobar.bb     1
www.baz.foobar.bb 1

# .bf
www.bar.baz.bf 1
www.bf     1
www.www.bf 1
foo.www.bf 1

# ip numbers
128.10.2.1   0
127.0.0.1    0
1.2.3.4      0
1.2.3.254    0
55.66.77.88  0

# invalid
www 0
a 0
b 0
c 0
d 0
e 0
f 0
g 0
h 0
i 0
j 0
k 0
l 0
m 0
n 0
o 0
p 0
q 0
r 0
s 0
t 0
u 0
v 0
w 0
x 0
y 0
z 0
1 0
2 0
3 0
4 0
5 0
6 0
7 0
8 0
9 0
10 0
11 0
16 0
24 0
123  0
99999 0
a234 0
9com 0
1foonet  0
/ 0
:foo  0
foo:  0
/test  0
test/  0


com.a 0
com.b 0
com.c 0
com.d 0
com.e 0
com.f 0
com.g 0
com.h 0
com.i 0
com.j 0
com.k 0
com.l 0
com.m 0
com.n 0
com.o 0
com.p 0
com.q 0
com.r 0
com.s 0
com.t 0
com.u 0
com.v 0
com.w 0
com.x 0
com.y 0
com.z 0

# currently there is no .zb top tld
zb 	0
com.zb 	0
www.foo.zb 	0
www.foo.com.zb 	0

ac 	1
ad 	1
ae 	1
aero 	1
af 	1
ag 	1
ai 	1
al 	1
an 	1
ao 	1
ar 	1
arpa 	1
as 	1
at 	1
au 	1
aw 	1
az 	1
ba 	1
bb 	1
bd 	1
be 	1
bf 	1
bg 	1
bh 	1
bi 	1
bj 	1
bm 	1
bn 	1
bo 	1
br 	1
bs 	1
bw 	1
by 	1
bz 	1
ca 	1
cc 	1
cd 	1
ci 	1
cl 	1
cm 	1
cn 	1
co 	1
com 	1
cr 	1
cu 	1
cx 	1
cy 	1
dm 	1
do 	1
dz 	1
ec 	1
ee 	1
eg 	1
er 	1
es 	1
et 	1
fi 	1
fj 	1
fr 	1
ge 	1
gg 	1
gh 	1
gi 	1
gn 	1
gp 	1
gr 	1
gt 	1
gy 	1
hk 	1
hn 	1
hr 	1
ht 	1
hu 	1
id 	1
ie 	1
il 	1
im 	1
in 	1
int 	1
io 	1
iq 	1
ir 	1
is 	1
it 	1
je 	1
jm 	1
jo 	1
jp 	1
ke 	1
kg 	1
kh 	1
ki 	1
km 	1
kn 	1
kr 	1
kw 	1
ky 	1
kz 	1
la 	1
lb 	1
lc 	1
lk 	1
lr 	1
ls 	1
lt 	1
lv 	1
ly 	1
ma 	1
mc 	1
me 	1
mg 	1
mk 	1
ml 	1
mn 	1
mo 	1
mr 	1
mt 	1
mu 	1
museum 	1
mv 	1
mw 	1
mx 	1
my 	1
mz 	1
na 	1
nc 	1
net 	1
nf 	1
ng 	1
ni 	1
no 	1
np 	1
nr 	1
nz 	1
om 	1
org 	1
pa 	1
pe 	1
pf 	1
pg 	1
ph 	1
pk 	1
pl 	1
pn 	1
pr 	1
pro 	1
ps 	1
pt 	1
pw 	1
py 	1
qa 	1
re 	1
ro 	1
rs 	1
ru 	1
rw 	1
sa 	1
sb 	1
sc 	1
sd 	1
se 	1
sg 	1
sl 	1
sn 	1
st 	1
sv 	1
sy 	1
sz 	1
tc 	1
th 	1
tj 	1
tl 	1
tn 	1
to 	1
tr 	1
tt 	1
tv 	1
tw 	1
tz 	1
ua 	1
ug 	1
uk 	1
us 	1
uy 	1
uz 	1
vc 	1
ve 	1
vi 	1
vn 	1
vu 	1
ws 	1
ye 	1
za 	1
zm 	1
zw 	1

ae  	1
af  	1
ar  	1
au  	1
ba  	1
bb  	1
bo  	1
br  	1
bt  	1
by  	1
ca  	1
cn  	1
co  	1
cr  	1
cy  	1
ec  	1
eg  	1
et  	1
fj  	1
gh  	1
hk  	1
id  	1
il  	1
in  	1
jm  	1
jo  	1
jp  	1
kh  	1
kr  	1
lb  	1
ma  	1
mk  	1
mx  	1
my  	1
mz  	1
na  	1
ni  	1
nz  	1
pe  	1
pg  	1
ph  	1
pk  	1
py  	1
qa  	1
sa  	1
sg  	1
sv  	1
th  	1
tn  	1
tr  	1
tw  	1
ua  	1
uk  	1
uy  	1
ve  	1
vn  	1
vu  	1
za  	1
bf  	1
bh  	1
bt  	1
gy  	1
ir  	1
lc  	1
ac  	1
ad  	1
ag  	1
ai  	1
al  	1
am  	1
an  	1
ao  	1
aq  	1
as  	1
at  	1
aw  	1
ax  	1
az  	1
bd  	1
be  	1
bg  	1
bi  	1
bj  	1
bm  	1
bn  	1
bs  	1
bw  	1
bz  	1
cc  	1
cd  	1
cf  	1
cg  	1
ch  	1
ci  	1
ck  	1
cl  	1
cm  	1
cu  	1
cv  	1
cx  	1
cz  	1
de  	1
dj  	1
dk  	1
dm  	1
do  	1
dz  	1
ee  	1
er  	1
es  	1
eu  	1
fi  	1
fk  	1
fm  	1
fo  	1
fr  	1
ga  	1
gd  	1
ge  	1
gf  	1
gg  	1
gi  	1
gl  	1
gm  	1
gn  	1
gp  	1
gq  	1
gr  	1
gs  	1
gt  	1
gu  	1
gw  	1
hm  	1
hn  	1
hr  	1
ht  	1
hu  	1
ie  	1
im  	1
io  	1
iq  	1
is  	1
it  	1
je  	1
ke  	1
kg  	1
ki  	1
km  	1
kn  	1
kp  	1
kw  	1
ky  	1
kz  	1
la  	1
li  	1
lk  	1
lr  	1
ls  	1
lt  	1
lu  	1
lv  	1
ly  	1
mc  	1
md  	1
me  	1
mg  	1
mh  	1
ml  	1
mm  	1
mn  	1
mo  	1
mp  	1
mq  	1
mr  	1
ms  	1
mt  	1
mu  	1
mv  	1
mw  	1
nc  	1
ne  	1
nf  	1
ng  	1
nl  	1
no  	1
np  	1
nr  	1
nu  	1
om  	1
pa  	1
pf  	1
pl  	1
pn  	1
pr  	1
ps  	1
pt  	1
pw  	1
re  	1
ro  	1
rs  	1
ru  	1
rw  	1
sb  	1
sc  	1
sd  	1
se  	1
sh  	1
si  	1
sk  	1
sl  	1
sm  	1
sn  	1
so  	1
sr  	1
st  	1
su  	1
sy  	1
sz  	1
tc  	1
td  	1
tf  	1
tg  	1
tj  	1
tk  	1
tl  	1
tm  	1
to  	1
tt  	1
tv  	1
tz  	1
ug  	1
us  	1
uz  	1
va  	1
vc  	1
vg  	1
vi  	1
ws  	1
ye  	1
zm  	1
zw  	1
