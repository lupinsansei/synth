use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use ChordMemory qw(chord_names chord_intervals chord_frequencies);
BEGIN {
    # Synth rendering is deliberately not exercised: this test must never render or play audio.
    $INC{'MIDI/Pitch.pm'} = __FILE__;
    package MIDI::Pitch;
    sub import { no strict 'refs'; *{caller().'::name2freq'} = sub { die 'Unexpected sample generation' }; }
}
{
    package Win32::Sound::WaveOut;
    our (@created,@events,$fail_after,$fail_write);
    sub new {
        my ($class,$rate)=@_;
        die 'Simulated device limit' if defined $fail_after && @created >= $fail_after;
        my $self=bless {rate=>$rate,done=>0,paused=>0},$class;
        push @created,$self;push @events,'new'; return $self;
    }
    sub Status { $_[0]{done} || !$_[0]{writes} }
    sub Load { $_[0]{loaded}=$_[1];push @events,'load'; }
    sub Write { die 'Write failed' if $fail_write;$_[0]{writes}++;push @events,'write'; }
    sub Pause { $_[0]{paused}++; $_[0]{done}=1 }
    package TestPatch;
    sub rendered_frequency {440}
    sub rendered_sample { [[1,2,3],[1,2,3]] }
}
use Synth;
is_deeply(chord_intervals('Major 7th'),[0,4,7,11],'major seventh intervals');
is_deeply(chord_intervals('Minor 7th'),[0,3,7,10],'minor seventh intervals');
is_deeply(chord_frequencies(440,0,'Major 7th'),[440],'disabled gives single note');
ok(!eval {chord_frequencies(0,1,'Major');1},'invalid frequency rejected');
ok(!eval {chord_intervals('not a chord');1},'unknown chord rejected');
my $intervals=chord_intervals('Major'); $intervals->[0]=99;
is(chord_intervals('Major')->[0],0,'callers cannot corrupt presets');
my $synth=Synth->new(Patches=>{},chord_memory=>1);
my $patch=bless {rendered_wave=>'UNCHANGED SAMPLE'},'TestPatch';
my $voices=$synth->play_patch($patch,'C',440);
is(scalar @$voices,4,'one key triggers four independent channels');
is_deeply(\@Win32::Sound::WaveOut::events,[(('new','load') x 4),('write') x 4],'Together preloads every channel before any playback starts');
for my $i (0..3) {
 cmp_ok(abs($voices->[$i]{rate}-44100*2**([0,4,7,11]->[$i]/12)),'<',0.001,"tone $i has correct playback rate");
 is($voices->[$i]{loaded},'UNCHANGED SAMPLE','existing rendered sample reused');
}
$synth->play_patch($patch,'C',440);
is(scalar @Win32::Sound::WaveOut::created,4,'held-key repeat does not retrigger');
my $other=$synth->play_patch($patch,'D',493.883);
is(scalar @{$synth->Channels},8,'second held key does not replace first chord voices');
$synth->chord_memory(0); $synth->chord_type('Minor'); $synth->stop_patch('C');
is_deeply([map {$_->{paused}} @$voices],[1,1,1,1],'release stops original chord even after toggle/preset changes');
is_deeply([map {$_->{paused}} @$other],[0,0,0,0],'release leaves other held chord alone');
my $one=$synth->play_patch($patch,'E',330);
is(scalar @$one,1,'memory off returns to single note');
$synth->stop_patch('missing'); pass('unknown release is harmless');
# Reusing a completed slot must not cause an old key release to stop its new owner.
$one->[0]{done}=1;
my $new=$synth->play_patch($patch,'F',349);
$synth->stop_patch('E'); is($new->[0]{paused},0,'old key release cannot stop reused-slot playback');
$synth->chord_memory(1); $synth->chord_type('Major 7th');
my $before=scalar @Win32::Sound::WaveOut::created;
$Win32::Sound::WaveOut::fail_after=$before+2;
ok(!eval {$synth->play_patch($patch,'failed',440);1},'device failure is reported');
ok(!exists $synth->Keys->{'failed'},'failed chord does not leave a stuck held key');
is_deeply([map {$_->{paused}} @Win32::Sound::WaveOut::created[$before..$before+1]],[1,1],'partial chord stops on device failure');
$Win32::Sound::WaveOut::fail_after=undef;
my $chopped=$synth->play_patch($patch,'chop',440,1,1);
is($chopped->[0]{loaded},pack('vv',2,2),'sample slice reused consistently for chord tones');
is($patch->{rendered_wave},'UNCHANGED SAMPLE','playback does not rewrite patch waveform');
my $many=Synth->new(Patches=>{},chord_memory=>1);
$many->play_patch($patch,'key'.$_,440) for 1..10;
is(scalar(grep{defined $_}@{$many->Channels}),40,'active chords can grow beyond the old 32-channel wrap');
$many->stop_patch('key'.$_) for 1..10;
is(scalar(grep{defined $_}@{$many->Channels}),0,'release frees all channel slots, even if paused status is not finished');
$many->play_patch($patch,'again',440);
is($many->ChannelIndex,3,'released slots are reused instead of leaking channels each time');
# Explicit timing is in PCM silence, not timer scheduling or sleeps.
my $arp=Synth->new(Patches=>{},chord_memory=>1,chord_mode=>'Arpeggio',arpeggio_ms=>150);
my $arps=$arp->play_patch($patch,'arp',440);
for my $i (0..3) {
 my $frames=int(int($arps->[$i]{rate})*150*$i/1000+0.5);
 is(length($arps->[$i]{loaded})-length($patch->{rendered_wave}),$frames*4,"arp voice $i delay uses its own playback rate");
 is(substr($arps->[$i]{loaded},0,$frames*4),"\0" x ($frames*4),"arp voice $i starts with silence");
 is(substr($arps->[$i]{loaded},$frames*4),$patch->{rendered_wave},"arp voice $i preserves original PCM");
}
$arp->chord_mode('Together');$arp->arpeggio_ms(300);$arp->stop_patch('arp');
is_deeply([map{$_->{paused}}@$arps],[1,1,1,1],'release cancels even silent pending arp tones after mode change');
my $together=$arp->play_patch($patch,'together',440);
is_deeply([map{$_->{loaded}}@$together],[($patch->{rendered_wave}) x 4],'Together has no added stagger');
$arp->stop_patch('together');$arp->chord_mode('Arpeggio');$arp->chord_memory(0);
my $single=$arp->play_patch($patch,'single',440);
is(scalar @$single,1,'memory off remains a single note in arp mode');
is($single->[0]{loaded},$patch->{rendered_wave},'single note starts without delay');
$arp->stop_patch('single');$arp->chord_memory(1);
my $failed_before=@Win32::Sound::WaveOut::created;
$Win32::Sound::WaveOut::fail_write=1;
ok(!eval{$arp->play_patch($patch,'write-failed',440);1},'submission failure reported');
ok(!exists $arp->Keys->{'write-failed'},'submission failure leaves no held key');
is_deeply([map{$_->{paused}}@Win32::Sound::WaveOut::created[$failed_before..$#Win32::Sound::WaveOut::created]],[1,1,1,1],'submission failure releases every prepared channel');
$Win32::Sound::WaveOut::fail_write=0;
$arp->{arpeggio_ms}='bad';
ok(!eval{$arp->play_patch($patch,'invalid',440);1},'invalid typed arp timing rejected');
is($patch->{rendered_wave},'UNCHANGED SAMPLE','both modes leave the patch cache untouched');
done_testing;
