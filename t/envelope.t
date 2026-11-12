use strict;
use warnings;
use Test::More;
use Digest::SHA qw(sha256_hex);
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use Patch;

# A constant stereo signal makes envelope timing measurable without playing
# audio or confusing it with oscillator zero crossings. The real Patch::render
# still dispatches and mixes these real Voice subclasses through both branches.
{
 package EnvelopeFixtureVoice;
 use Moose;
 extends 'Voice';
 sub render {
  my($self,$rate,$bits,$length)=@_;
  my $count=int($rate*$length);
  return [[(1000)x$count],[(-500)x$count]];
 }
}
for my $rate (8000,22050,44100,48000,96000) {
 for my $voices (1,2) {
  my $label="$rate Hz, $voices voice(s)";
  my $patch=Patch->new(name=>'Envelope fixture',length=>1.5,attack=>0.25,decay=>1,
    voices=>[map{EnvelopeFixtureVoice->new}1..$voices]);
  my $wave=$patch->render(440,$rate,16);
  is(scalar @{$wave->[0]},int(1.5*$rate),"duration unchanged: $label");
  is(scalar @{$wave->[1]},scalar @{$wave->[0]},"stereo lengths match: $label");
  is($wave->[0][0],0,"attack starts silent: $label");
  my($peak,$peak_index,$last_nonzero)=(-1,0,0);
  for my $i(0..$#{$wave->[0]}) {
   my $value=$wave->[0][$i];
   if($value>$peak){$peak=$value;$peak_index=$i;}
   $last_nonzero=$i if $value>0;
  }
  cmp_ok(abs($peak_index/$rate-0.25),'<=',1/$rate,"attack peak at 0.25s within one sample: $label");
  cmp_ok(abs(($last_nonzero+1)/$rate-1.25),'<=',1/$rate,"one-second decay ends at 1.25s within one sample: $label");
  my $middle=int(0.75*$rate);
  cmp_ok(abs($wave->[0][$middle]-500),'<=',1000/$rate,"halfway through decay is half amplitude: $label");
  cmp_ok(abs($wave->[1][$middle]+250),'<=',500/$rate,"right channel has identical timing: $label");
  is($wave->[0][-1],0,"silent tail: $label");
 }
}
# Freeze the previous 44.1kHz result, including its fractional-sample behaviour.
my $input=[[(1000)x176],[(-500)x176]];
my $old_rate=Patch::envelope($input,0.001,0.002,44100);
is(sha256_hex(pack('d<*',@{$old_rate->[0]},@{$old_rate->[1]})),
 '9a71224267709973614c0179ebc14e2518093b0e1aaa6973a8059a905907be02',
 '44.1kHz fractional-envelope samples exactly match the pre-fix baseline');
is_deeply(Patch::envelope($input,0.001,0.002),$old_rate,'legacy three-argument calls still default to 44.1kHz');
for my $voices (1,2) {
 my $patch=Patch->new(name=>'Legacy timing fixture',length=>176/44100,attack=>0.001,decay=>0.002,
  voices=>[map{EnvelopeFixtureVoice->new}1..$voices]);
 is_deeply($patch->render(440,44100,16),$old_rate,"44.1kHz render branch with $voices voice(s) unchanged");
}
my $flat=[[(1)x48001],[(-1)x48001]];
my $decay=Patch::envelope($flat,0,1,48000);
is($decay->[0][0],1,'zero attack starts at full volume');
is($decay->[0][24000],0.5,'one-second decay is halfway at half a second');
is($decay->[0][48000],0,'one-second decay is silent at one second');
is_deeply(Patch::envelope([[1,1],[-1,-1]],0,0,48000),[[0,0],[0,0]],'zero-length attack and decay stay silent without dividing by zero');
is_deeply($input,[[(1000)x176],[(-500)x176]],'envelope does not mutate its input');
done_testing;
