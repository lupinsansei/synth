use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use Test::More;
use File::Temp qw(tempdir);
use Audio::Wav;
BEGIN {
    $INC{'MIDI/Pitch.pm'} = __FILE__;
    package MIDI::Pitch;
    sub import {
        my $caller = caller; no strict 'refs';
        *{$caller.'::name2freq'} = sub { 130.81278265 };
        *{$caller.'::pitch2name'} = sub { 'c3' };
        *{$caller.'::name2pitch'} = sub { 48 };
    }
}
use Synth;
use Patch;
use Voice;
use WavExport;
use WavExport::Tk;
my $dir = tempdir(CLEANUP=>1);
sub contents { open my $f, '<:raw', $_[0] or die $!; local $/; return <$f>; }

for my $rate (8000, 22050, 44100, 48000, 96000) {
    # A fictional deterministic oscillator fixture, never a recording.
    my $patch = Patch->new(name=>'Export fixture', length=>0.02, decay=>0.01,
        voices=>[Voice->new(wave=>'sine', volume_multiplier=>0.1)]);
    my $synth = Synth->new(Patches=>{fixture=>$patch}, samplerate=>$rate, chord_memory=>1);
    my $path = "$dir/$rate.wav";
    ok(WavExport->export_patch($path,$synth,$patch), "exports at $rate Hz without audio backend");
    my $bytes = contents($path);
    is(substr($bytes,0,4),'RIFF',"RIFF signature at $rate");
    is(unpack('V',substr($bytes,4,4)),length($bytes)-8,"RIFF size at $rate");
    is(substr($bytes,8,4),'WAVE',"WAVE type at $rate");
    is(substr($bytes,44),$patch->rendered_wave,"exact playback PCM retained at $rate");
    my $reader = Audio::Wav->new->read($path);
    my $details = $reader->details;
    is($details->{sample_rate},$rate,"independent reader sample rate at $rate");
    is($details->{channels},2,"independent reader stereo at $rate");
    is($details->{bits_sample},16,"independent reader 16 bits at $rate");
    my $frames = @{$patch->rendered_sample->[0]};
    cmp_ok(abs($reader->length_seconds - $frames/$rate),'<',1/$rate,"duration matches frames at $rate");
    my $decoded='';
    while (my @frame = $reader->read) { $decoded .= pack('vv',@frame); }
    is($decoded,$patch->rendered_wave,"independent reader sample round trip at $rate");
    is_deeply($synth->Keys,{},"export does not start chord playback at $rate");
    is_deeply($synth->Channels,[],"no audio channels allocated at $rate");
}
my $pcm = pack('v*',0,65535,32767,32768);
my $known = WavExport->wav_bytes($pcm,44100);
is_deeply([unpack('vvVVvv',substr($known,20,16))],[1,2,44100,176400,4,16],'PCM header format, byte rate and alignment');
is(substr($known,44),$pcm,'signed extremes retained byte-for-byte');
for my $bad (0,-1,1.5,'oops',undef,1073741824) {
    ok(!eval{WavExport->wav_bytes($pcm,$bad);1},'invalid rate rejected');
}
for my $bad ('','abc',undef,[]) {
    ok(!eval{WavExport->wav_bytes($bad,44100);1},'invalid/empty/misaligned PCM rejected');
}
my $patch = Patch->new(name=>'Fixture',length=>0.01,voices=>[Voice->new]);
my $synth = Synth->new(Patches=>{fixture=>$patch});
my $path = "$dir/preserve.wav";
open my $f,'>:raw',$path or die $!; print {$f} 'original'; close $f;
$synth->bits(8);
ok(!eval{WavExport->export_patch($path,$synth,$patch);1},'unsupported bit depth rejected');
is(contents($path),'original','unsupported format preserves existing file');
$synth->bits(16); $synth->channels(1);
ok(!eval{WavExport->export_patch($path,$synth,$patch);1},'mono export rejected');
is(contents($path),'original','unsupported channels preserve file');
$synth->channels(2);
my $missing = Patch->new(name=>'Missing',voices=>[Voice->new(wave=>'file',file=>"$dir/missing.wav")]);
ok(!eval{WavExport->export_patch($path,$synth,$missing);1},'render failure reported');
is(contents($path),'original','render failure preserves destination');
mkdir "$dir/destination" or die $!;
ok(!eval{WavExport->export_patch("$dir/destination",$synth,$patch);1},'replacement failure reported');
ok(-d "$dir/destination",'failed replacement keeps destination');
is_deeply([glob("$dir/.synth-wav-*")],[],'failed replacement cleans temporary file');
ok(WavExport->export_patch($path,$synth,$patch),'successful export replaces existing file');
is(substr(contents($path),0,4),'RIFF','successful replacement is WAV');

# Exercise the UI controller without opening a dialog or audio device.
my (@errors,$captures); my $chosen;
my $ui = WavExport::Tk->new(parent=>1,choose_save=>sub{$chosen},
    capture=>sub{$captures++;return($synth,$patch)},error=>sub{push @errors,$_[0]});
ok(!$ui->export,'cancel does nothing');
ok(!$captures,'cancel does not render/capture sound');
$chosen = "$dir/ui.wav";
ok($ui->export,'UI exports selected sound');
is(substr(contents($chosen),0,4),'RIFF','UI writes real WAV');
$synth->bits(8);
ok(!$ui->export,'UI handles failure');
is(scalar @errors,1,'UI reports failure once');
is(substr(contents($chosen),0,4),'RIFF','UI failure preserves previous sound file');
done_testing;
