use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use FMPatchExplorer;
use Patch;
use Voice;
use Storable qw(dclone);
use POSIX qw(isfinite);
my $seed=17;
my $explorer=FMPatchExplorer->new(rng=>sub{$seed=(1103515245*$seed+12345)%2147483648;return $seed/2147483648});
my $patch=Patch->new(name=>'Public test fixture',length=>0.4,attack=>0.01,decay=>0.3,voices=>[Voice->new(freq_multiplier=>1,volume_multiplier=>0.3)]);
my $original=$explorer->snapshot($patch);
for my $family (@{FMPatchExplorer->families}) {
 for my $wildness (0,100) {
  $explorer->new_sound($patch,family=>$family,wildness=>$wildness);
  my $carrier=$patch->voices->[0];my $mod=$carrier->modulators->[0];
  is($carrier->freq_decay,0,"$family has stable carrier pitch at wildness $wildness");
  is($patch->chord,0,'FM generation stays separate from playback harmony');
  cmp_ok($mod->volume_multiplier,'>',0,'modulator has a useful nonzero level');
  cmp_ok($mod->volume_multiplier,'<',1,'modulator deviation bounded');
  cmp_ok($patch->length,'<',3,'bounded render duration');
  if($wildness==0 && $family ne 'Bell' && $family ne 'Texture') {
   my $ratio=$mod->freq_multiplier/$carrier->freq_multiplier;
   is($ratio,int($ratio),'tonal family uses an exact simple ratio at low wildness');
  }
  my @warnings;
  local $SIG{__WARN__}=sub{push @warnings,@_};
  my $wave=$patch->render(130.81278265,44100,16);
  is(scalar @warnings,0,'fractional durations do not read past modulator buffers');
  my ($peak,$squares,$bad)=(0,0,0);
  for my $v (@{$wave->[0]}) {
   if(!isfinite($v)) {$bad++;next;}
   $peak=abs($v) if abs($v)>$peak;$squares+=$v*$v;
  }
  is($bad,0,'real renderer yields finite samples');
  cmp_ok($peak,'<',32768,'real render avoids clipping');
  cmp_ok(sqrt($squares/@{$wave->[0]}),'>',100,'real render is not silent');
  is($wave->[0][-1],0,'envelope ends with a silent tail');
 }
}
$explorer->new_sound($patch,family=>'Pluck',wildness=>0);
$explorer->keep($patch);my $keeper=$explorer->snapshot($patch);
for(1..20) {
 $explorer->variation($patch);
 my $data=$explorer->snapshot($patch);
 is($data->{voices}[0]{freq_multiplier},$keeper->{voices}[0]{freq_multiplier},'variation preserves carrier');
 is($data->{voices}[0]{modulators}[0]{freq_multiplier},$keeper->{voices}[0]{modulators}[0]{freq_multiplier},'variation preserves modulator ratio');
 cmp_ok($data->{voices}[0]{modulators}[0]{volume_multiplier},'<=',$keeper->{voices}[0]{modulators}[0]{volume_multiplier}*1.150001,'repeated variations do not drift above keeper range');
 cmp_ok($data->{voices}[0]{modulators}[0]{volume_multiplier},'>=',$keeper->{voices}[0]{modulators}[0]{volume_multiplier}*0.849999,'repeated variations do not drift below keeper range');
}
my $before=$explorer->snapshot($patch);my $depth=$explorer->can_undo($patch);
$patch->{rendered_wave}='FICTIONAL CACHE';
ok(!eval{$explorer->new_sound($patch,family=>'Bass',preview=>sub{die 'fixture render failure'});1},'failed render is reported');
is_deeply($explorer->snapshot($patch),$before,'failed render restores all sound parameters');
is($patch->{rendered_wave},'FICTIONAL CACHE','failed render restores previous playable cache');
is($explorer->can_undo($patch),$depth,'failed render does not consume undo history');
$explorer->new_sound($patch,family=>'Bell');$explorer->undo($patch);
is_deeply($explorer->snapshot($patch),$before,'Undo restores exact previous sound');
my $other=Patch->new(name=>'Other fictional patch',voices=>[Voice->new(freq_multiplier=>2)]);
ok(!$explorer->undo($other),'undo isolated by patch');
for(1..40){$explorer->new_sound($other,family=>'Bass');}
is($explorer->can_undo($other),32,'undo history bounded without audio blobs');
ok(!exists $explorer->snapshot($patch)->{rendered_sample},'history excludes rendered data');
ok(!eval{$explorer->generate(family=>'Unknown');1},'invalid family rejected');
ok(!eval{$explorer->generate(wildness=>101);1},'invalid wildness rejected');
# Musical quality needs listening; these checks only establish intended structure and signal sanity.
done_testing;
