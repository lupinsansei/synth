use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use MiniSequencer;
my $n=0;
my $seq=MiniSequencer->new(rng=>sub{(($n++*7)%31)/31});
is(scalar @{$seq->steps},16,'sixteen steps');
my $first=join(',',map{defined $_?$_:'rest'}@{$seq->steps});
$seq->randomise;
isnt(join(',',map{defined $_?$_:'rest'}@{$seq->steps}),$first,'another click produces another phrase');
for my $scale (@{MiniSequencer->scales}) {
 $seq->scale($scale); $seq->randomise;
 my %allowed=map{$_=>1}($scale eq 'Major'?(0,2,4,5,7,9,11):$scale eq 'Minor'?(0,2,3,5,7,8,10):(0,3,5,7,10));
 ok(!grep({defined $_ && !$allowed{$_%12}}@{$seq->steps}),"notes stay in $scale");
 cmp_ok(scalar(grep{defined $_}@{$seq->steps}),'>=',4,'always has notes, not a silent random loop');
}
my $root=MiniSequencer->new(rng=>sub{0});
is($root->frequency(0,69),440,'MIDI pitch to frequency');
is($root->label(0,48),'C3','readable note names');
is($root->label(1,48),'--','rest label');
$root->toggle(0); ok(!defined $root->frequency(0,48),'click can mute a step');
$root->toggle(0); is($root->frequency(0,69),440,'click restores a scale note');
my $copy=$root->steps; $copy->[0]=99;
is($root->midi(0,48),48,'returned pattern cannot mutate model');
ok(!eval{$root->toggle(16);1},'invalid step rejected');
ok(!eval{$root->scale('invalid');1},'invalid scale rejected');
done_testing;
