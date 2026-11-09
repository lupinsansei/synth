use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Audio::Wav;
use Patch;
use Voice;

# Generate a tiny fictional stereo fixture; no recordings or audio device needed.
my $dir=tempdir(CLEANUP=>1);
my $path="$dir/constant.wav";
my $wav=Audio::Wav->new;
my $writer=$wav->write($path,{bits_sample=>16,sample_rate=>8000,channels=>2});
$writer->write(1000,-2000) for 1..24;
$writer->finish;

for my $modulated (0,1) {
 for my $decay (0,0.0625) {
  my $label="decay=$decay, modulators=$modulated";
  my %args=(wave=>'file',file=>$path,volume_multiplier=>0.5,volume_decay=>$decay);
  $args{modulators}=[Voice->new(freq_multiplier=>2,volume_multiplier=>0.001)] if $modulated;
  my $voice=Voice->new(%args);
  my (@warnings,$wave);
  my $ok=eval{local $SIG{__WARN__}=sub{push @warnings,@_};$wave=$voice->render(8000,16,16/8000,440,1,0.5);1};
  ok($ok,"WAV voice renders with $label") or diag($@);
  is_deeply(\@warnings,[],"no parameter type/buffer warnings with $label");
  SKIP: {
   skip 'Render failed; no sample buffer to inspect',4 unless $ok;
   is(scalar @{$wave->[0]},16,"left sample count with $label");
   is(scalar @{$wave->[1]},16,"right sample count with $label");
   # Existing WAV playback reads samples sequentially: this checks that a
   # modulator buffer does not accidentally become the amplitude decay scalar.
   # It does not claim that WAV frequency modulation/resampling is implemented.
   my @left=map{1000*max_zero(0.5-$_*$decay)}0..15;
   my @right=map{-2000*max_zero(0.25-$_*$decay)}0..15;
   is_deeply($wave->[0],\@left,"left amplitude decay applied correctly with $label");
   is_deeply($wave->[1],\@right,"right amplitude decay applied correctly with $label");
  }
 }
}
sub max_zero {$_[0]>0?$_[0]:0}
done_testing;
