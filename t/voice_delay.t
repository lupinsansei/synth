use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..";
use File::Temp qw(tempdir);
use Audio::Wav;
use Patch;
use Voice;

sub shifted {
    my ($wave,$offset)=@_;
    return [map {my @v=@$_; splice @v,@v-$offset,$offset; [(0)x$offset,@v]} @$wave];
}
sub render_voice { $_[0]->render($_[1],16,$_[2],440,1,0.5) }

for my $rate (8000,10000,44100) {
    for my $kind ('sine','noise') {
        my $voice=Voice->new(wave=>$kind,volume_decay=>0.0001);
        srand(123);
        my $plain=render_voice($voice,$rate,0.1);
        $voice->delay(50);
        srand(123);
        my $delayed=render_voice($voice,$rate,0.1);
        my $offset=int($rate*0.05+0.5);
        is_deeply($delayed,shifted($plain,$offset),"$kind at $rate Hz: stereo silence, onset, decay and trimmed tail");
        is(scalar @{$delayed->[0]},int($rate*0.1),"$kind at $rate Hz: render window unchanged");
        $voice->delay(0);
        srand(123);
        is_deeply(render_voice($voice,$rate,0.1),$plain,"$kind at $rate Hz: zero delay unchanged");
    }
}
my $voice=Voice->new;
my $plain=render_voice($voice,10000,0.01);
$voice->delay(0.15);
is_deeply(render_voice($voice,10000,0.01),shifted($plain,2),'fractional milliseconds round to nearest frame');
$voice->delay(0.01);
is_deeply(render_voice($voice,10000,0.01),$plain,'sub-half-frame delay rounds to zero');
for my $delay (10,11,1e100) {
    $voice->delay($delay);
    is_deeply(render_voice($voice,10000,0.01),[[(0)x100],[(0)x100]],"delay $delay at/beyond window is bounded stereo silence");
}
is_deeply(render_voice($voice,10000,0),[[],[]],'empty render window stays empty');

# File voices retain their natural duration for length=0, or the explicit window.
my $dir=tempdir(CLEANUP=>1);
my $file="$dir/fictional.wav";
my $writer=Audio::Wav->new->write($file,{bits_sample=>16,sample_rate=>8000,channels=>2});
$writer->write(1000,-2000) for 1..40;
$writer->finish;
for my $length (0,0.003) {
    my $file_voice=Voice->new(wave=>'file',file=>$file,volume_decay=>0.025);
    my $original=render_voice($file_voice,8000,$length);
    $file_voice->delay(1);
    is_deeply(render_voice($file_voice,8000,$length),shifted($original,8),"WAV stereo and decay shifted within window (length=$length)");
}

# Each child has its own delay. A parent's delay then shifts the whole subtree,
# rather than consuming modulation or oscillator phase during the silent prefix.
my $inner=Voice->new(freq_multiplier=>3,volume_multiplier=>0.01,delay=>1);
my $mod=Voice->new(freq_multiplier=>2,volume_multiplier=>0.1,delay=>2,modulators=>[$inner]);
my $carrier=Voice->new(modulators=>[$mod]);
my $inner_plain=Voice::make_sine(10000,16,0.01,440*3,0.01,0.01,0,undef,0);
my $inner_expected=shifted($inner_plain,10);
my $mod_expected=shifted(Voice::make_sine(10000,16,0.01,440*2,0.1,0.1,0,$inner_expected,0),20);
is_deeply($mod->render(10000,16,0.01,440,1,1),$mod_expected,'nested modulator delays are relative to parent onset');
my $expected=Voice::make_sine(10000,16,0.01,440,1,0.5,0,$mod_expected,0);
is_deeply(render_voice($carrier,10000,0.01),$expected,'delayed modulation leaves carrier active until FM begins');
$carrier->delay(3);
is_deeply(render_voice($carrier,10000,0.01),shifted($expected,30),'parent delay shifts complete FM subtree');
$inner->delay(100);
is_deeply($inner->render(10000,16,0.01,440,1,1),[[(0)x100],[(0)x100]],'modulator beyond window supplies zeros, not a short buffer');

for my $bad (-1,'NaN','Inf') {
    ok(!eval{Voice->new(delay=>$bad);1},"constructor rejects delay $bad");
    ok(!eval{$voice->delay($bad);1},"accessor rejects delay $bad");
    my $raw=Voice->new;
    $raw->{delay}=$bad;
    ok(!eval{render_voice($raw,10000,0.01);1},"renderer rejects backing-hash delay $bad");
    like($@,qr/delay must be finite and non-negative/,'useful render validation error');
}

# Mixing delayed and immediate voices does not move the other layer or extend it.
my $first=Voice->new;
my $second=Voice->new(freq_multiplier=>2,delay=>3);
my $patch=Patch->new(length=>0.01,attack=>0,decay=>1,voices=>[$first,$second]);
my $patch_expected=Patch::mix_samples([map {Patch::envelope($_->render(10000,16,0.01,440,1,1),0,1,10000)} ($first,$second)]);
my $actual=$patch->render(440,10000,16);
for my $ch (0,1) {
    my ($got,$want)=($actual->[$ch],$patch_expected->[$ch]);
    is(scalar @$got, scalar @$want, "layered channel $ch preserves render length");
    my $max_error=0;
    for my $i (0..$#$want) {
        my $error=abs($got->[$i]-$want->[$i]);
        $max_error=$error if $error>$max_error;
    }
    cmp_ok($max_error,'<',1e-6,"layered channel $ch preserves delay and envelope at every frame");
    ok(pack('s<*',@$got) eq pack('s<*',@$want),"layered channel $ch matches every 16-bit sample");
}
done_testing;
