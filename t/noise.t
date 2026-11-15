use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..";
use Voice;

# Silent deterministic tests of the real renderer. Keep the original random
# range's AC energy: centre it, rather than doubling its peak-to-peak span.
for my $tuned (0,1) {
    srand(4201);
    my $wave=Voice::make_noise(48000,16,1,6000,1,0.5,0,0,$tuned);
    is(scalar @{$wave->[0]},48000,"left duration, tuned=$tuned");
    is(scalar @{$wave->[1]},48000,"right duration, tuned=$tuned");
    my ($sum,$squares,$min,$max)=(0,0,1e9,-1e9);
    for my $v (@{$wave->[0]}) {
        $sum+=$v;$squares+=$v*$v;$min=$v if $v<$min;$max=$v if $v>$max;
    }
    cmp_ok($min,'<',0,"negative noise present, tuned=$tuned");
    cmp_ok($max,'>',0,"positive noise present, tuned=$tuned");
    cmp_ok($min,'>=',-16384,"conservative lower bound, tuned=$tuned");
    cmp_ok($max,'<=',16383,"conservative upper bound, tuned=$tuned");
    cmp_ok(abs($sum/48000),'<',32768*0.02,"mean is close to zero, tuned=$tuned");
    my $expected=32768/sqrt(12);
    cmp_ok(abs(sqrt($squares/48000)/$expected-1),'<',0.05,"AC RMS not doubled, tuned=$tuned");
    is_deeply($wave->[1],[map{$_*0.5}@{$wave->[0]}],"shared noise respects stereo gain, tuned=$tuned");

    # Decay must modify the same random carrier, not the sample/hold timing.
    srand(17);
    my $plain=Voice::make_noise(8000,16,0.01,1000,1,0.5,0,0,$tuned);
    srand(17);
    my $decay=Voice::make_noise(8000,16,0.01,1000,1,0.5,0,0.125,$tuned);
    for my $channel (0,1) {
        my $initial=$channel?0.5:1;
        my $gain=$initial;
        my @expected;
        for my $v (@{$plain->[$channel]}) {
            push @expected,$gain>0?$v*$gain/$initial:0;
            $gain-=0.125 if $gain>0;
        }
        is_deeply($decay->[$channel],\@expected,"channel $channel decay and silent tail, tuned=$tuned");
    }
}

srand(31);
my $held=Voice::make_noise(8000,16,0.004,1000,1,1,0,0,1);
for my $group (0..3) {
    is_deeply([@{$held->[0]}[$group*8..$group*8+7]],[($held->[0][$group*8])x8],"tuned noise holds value for group $group");
}
isnt($held->[0][0],$held->[0][8],'new tuned value at the original boundary');

# Freeze the old sample/hold trigger schedule under frequency decay. A centred
# random draw should change amplitude only, not which frames receive a new draw.
srand(53);
my @legacy;
my ($frequency,$last)=(1000,0);
for my $i (0..79) {
    $last=int(rand(32768)) unless $i % (8000/$frequency);
    push @legacy,$last-16384;
    $frequency-=0.5;
}
srand(53);
my $falling=Voice::make_noise(8000,16,0.01,1000,1,1,0.5,0,1);
is_deeply($falling->[0],\@legacy,'frequency-decay sample/hold boundaries retained');

srand(61);
my $eight=Voice::make_noise(8000,8,0.02,1000,1,1,0,0,0);
ok(!grep({$_ < -64 || $_ > 63}@{$eight->[0]}),'scaling follows the requested bit depth');
my $muted=Voice::make_noise(8000,16,0.01,1000,0,0,0,0,0);
is_deeply($muted,[[ (0)x80 ],[ (0)x80 ]],'muted channels remain silent');
my $voice=Voice->new(wave=>'noise',tuned=>1,volume_multiplier=>0.25);
srand(71);
my $rendered=$voice->render(8000,16,0.01,1000,1,0.5);
srand(71);
is_deeply($rendered,Voice::make_noise(8000,16,0.01,1000,0.25,0.125,0,0,1),'Voice dispatch applies multiplier to bipolar noise');
done_testing;
