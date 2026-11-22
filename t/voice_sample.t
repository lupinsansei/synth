use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use Test::More;
use File::Temp qw(tempdir);
use Audio::Wav;
BEGIN {
    $INC{'MIDI/Pitch.pm'}=__FILE__;
    package MIDI::Pitch;
    sub import { no strict 'refs'; *{caller().'::name2freq'}=sub{130.81278265}; }
}
use Synth;
use Patch;
use Voice;
use VoiceSample;
my $dir=tempdir(CLEANUP=>1);
sub fixture {
    my ($name,$rate,$bits,$channels)=@_;
    my $path="$dir/$name";
    my $writer=Audio::Wav->new->write($path,{bits_sample=>$bits,sample_rate=>$rate,channels=>$channels});
    $writer->write((1000)x$channels) for 1..32;
    $writer->finish;
    return $path;
}
my $valid=fixture('fictional-stereo.WAV',8000,16,2);
my $voice=Voice->new(volume_multiplier=>0.1);
my $patch=Patch->new(name=>'Fictional sample test',length=>0.002,voices=>[$voice]);
my $synth=Synth->new(Patches=>{fixture=>$patch},samplerate=>8000);
$synth->render_patch_as_middle_c($patch);
my $original=$patch->rendered_wave;
my $before=0;
my %args=(synth=>$synth,patch=>$patch,voice=>$voice,wave=>'file',path=>$valid,
    before=>sub{$before++},render=>sub{$synth->render_patch_as_middle_c($patch)});
ok(VoiceSample->apply(%args),'real valid WAV selection renders silently');
is($voice->file,$valid,'selected file is referenced, not copied');
is($voice->wave,'file','file waveform selected');
isnt($patch->rendered_wave,$original,'new cached audio available');
is($before,1,'transport callback once before rendering');
is_deeply($synth->Channels,[],'no playback devices allocated');
is_deeply($synth->Keys,{},'selection never starts a key');
my $good_wave=$patch->rendered_wave;
my $good_sample=$patch->rendered_sample;
my $good_frequency=$patch->rendered_frequency;
my @bad=("$dir/missing.wav", fixture('mono.wav',8000,16,1), fixture('wrong-rate.wav',16000,16,2),fixture('eight-bit.wav',8000,8,2));
open my $text,'>',"$dir/not-a-wave.wav" or die $!;print {$text} 'Not a WAV';close $text;
push @bad,"$dir/not-a-wave.wav";
for my $path(@bad){
    ok(!eval{VoiceSample->apply(%args,path=>$path);1},'missing/invalid/unsupported file rejected');
    is($voice->file,$valid,'failed validation keeps previous sample');
    is($patch->rendered_wave,$good_wave,'failed validation keeps audio cache');
}
is($before,1,'validation failures do not stop transport or render');
my $other=fixture('replacement.wav',8000,16,2);
ok(!eval{VoiceSample->apply(%args,path=>$other,render=>sub{
    $patch->rendered_frequency(999);$patch->rendered_wave('partial');$patch->rendered_sample([[99],[99]]);die "Simulated render failure\n";
});1},'partial render failure reported');
is($voice->file,$valid,'render failure restores previous path');
is($voice->wave,'file','render failure restores waveform');
is($patch->rendered_sample,$good_sample,'previous sample reference restored');
is($patch->rendered_wave,$good_wave,'previous PCM restored exactly');
is($patch->rendered_frequency,$good_frequency,'previous transpose reference restored');
ok(VoiceSample->apply(%args,wave=>'noise'),'switching to generated waveform works');
is($voice->file,$valid,'switching away retains the selected reference for later');
# Choosing a nested modulator changes only that voice, not its parent or siblings.
my $child=Voice->new(volume_multiplier=>0.001);
my $parent=Voice->new(volume_multiplier=>0.1,modulators=>[$child]);
my $nested=Patch->new(length=>0.002,voices=>[$parent]);
ok(VoiceSample->apply(%args,patch=>$nested,voice=>$child,render=>sub{$synth->render_patch_as_middle_c($nested)}),'nested voice sample renders');
is($child->file,$valid,'modulator receives selected sample');
is($parent->wave,'sine','parent waveform unchanged');
is($parent->file,'','parent sample path unchanged');
my $uncached=Patch->new(voices=>[Voice->new]);
ok(!eval{VoiceSample->apply(%args,patch=>$uncached,voice=>$uncached->voices->[0],render=>sub{$uncached->rendered_frequency(440);$uncached->rendered_wave('partial');die 'failed';});1},'uncached failure handled');
ok(!exists $uncached->{rendered_frequency} && !exists $uncached->{rendered_wave},'new partial cache keys removed on rollback');
is($uncached->voices->[0]->wave,'sine','uncached waveform rolled back');
done_testing;
