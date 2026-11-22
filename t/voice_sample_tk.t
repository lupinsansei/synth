use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use Test::More;
use File::Temp qw(tempdir);
use Audio::Wav;
BEGIN {$INC{'MIDI/Pitch.pm'}=__FILE__;package MIDI::Pitch;sub import{no strict 'refs';*{caller().'::name2freq'}=sub{130.81278265};}}
use Tk;
use Synth;
use Voice;
use Patch;
use PatchBank;
use VoiceSample::Tk;
my $dir=tempdir(CLEANUP=>1);
my $path="$dir/a-fictional-sample-with-a-long-name.wav";
my $writer=Audio::Wav->new->write($path,{bits_sample=>16,sample_rate=>8000,channels=>2});
$writer->write(1000,-1000) for 1..32;$writer->finish;
my $window=MainWindow->new;
my $voice=Voice->new(volume_multiplier=>0.1);
my $patch=Patch->new(length=>0.002,voices=>[$voice]);
my $synth=Synth->new(Patches=>{fixture=>$patch},samplerate=>8000);
$synth->render_patch_as_middle_c($patch);
my($chosen,$renders,$before,$recovery,$fail_render,$reenter,@errors);
my $ui;
$ui=VoiceSample::Tk->new(parent=>$window,voice=>$voice,patch=>$patch,synth=>sub{$synth},
 choose_open=>sub{ok(!$ui->choose,'nested chooser ignored while dialog is active') if $reenter;return $chosen;},
 before=>sub{$before++},
 render=>sub{$renders++;$synth->render_patch_as_middle_c($patch);die 'Simulated renderer failure' if $fail_render;},
 recover=>sub{$recovery++},error=>sub{push @errors,$_[0]});
$ui->widget->pack;$window->update;
ok(!$ui->{file_frame}->ismapped,'sample controls hidden for generated waveform');
# Selecting file without a sample opens the chooser before changing the voice.
$ui->{menu}->cget('-menu')->invoke('file');$window->update;
is($voice->wave,'sine','cancelling initial sample choice preserves waveform');
is($ui->{wave},'sine','wave menu resets after cancellation');
is($renders||0,0,'cancel performs no render');is($before||0,0,'cancel never stops transport');
$chosen=$path;$reenter=1;
$ui->{menu}->cget('-menu')->invoke('file');$window->update;$reenter=0;
is($voice->wave,'file','file choice activates the waveform');
is($voice->file,$path,'chosen file referenced');ok($ui->{choose_button}->ismapped,'Choose WAV button visible');
like($ui->{filename},qr/\.\.\./,'long basename is compact');unlike($ui->{filename},qr/\Q$dir\E/,'filename label does not expose whole path');
is($renders,1,'one render per successful choice');
my $good=$patch->rendered_wave;my $good_sample=$patch->rendered_sample;
$chosen=undef;$ui->{choose_button}->invoke;
is($renders,1,'cancel replacement does not render');is($patch->rendered_wave,$good,'cancel keeps PCM');
$chosen="$dir/missing.wav";$ui->{choose_button}->invoke;
is(scalar @errors,1,'invalid file gives one visible error callback');
is($voice->file,$path,'invalid selection keeps previous path');is($patch->rendered_wave,$good,'invalid selection keeps previous sound');
$chosen=$path;$fail_render=1;$ui->{choose_button}->invoke;$fail_render=0;
is(scalar @errors,2,'render failure gives one additional error');
is($recovery,2,'error paths call UI recovery');
is($patch->rendered_sample,$good_sample,'partial render restores sample reference');is($patch->rendered_wave,$good,'partial render restores PCM');
is($voice->file,$path,'partial render restores sample reference');
is_deeply($synth->Channels,[],'UI never allocates audio devices');is_deeply($synth->Keys,{},'UI never triggers playback');
# The standard bank writer remains the sole persistence path, without embedded audio.
my $bank="$dir/settings.synth.json";PatchBank->save_file($bank,$synth,selected_patch=>'fixture');
open my $fh,'<',$bank or die $!;local $/;my $json=<$fh>;close $fh;
like($json,qr/a-fictional-sample-with-a-long-name\.wav/,'bank persists sample reference');
unlike($json,qr/rendered_wave|rendered_sample/,'bank contains settings, not embedded audio');
my $loaded=PatchBank->read_file($bank);
is($loaded->{patches}{fixture}->voices->[0]->file,$path,'bank reload restores selected file');
$ui->{menu}->cget('-menu')->invoke('sine');$window->update;
is($voice->wave,'sine','generated waveform remains available');ok(!$ui->{file_frame}->ismapped,'file controls disappear when switching away');
is($voice->file,$path,'switching away retains reusable reference');
$ui->{menu}->cget('-menu')->invoke('file');$window->update;
is($voice->file,$path,'switching back reuses sample without a dialog');
$window->destroy;
done_testing;
