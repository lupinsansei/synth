use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
BEGIN {
    $INC{'MIDI/Pitch.pm'} = __FILE__;
    package MIDI::Pitch;
    sub import {
        no strict 'refs';
        *{caller().'::name2freq'} = sub {
            my %midi=(c3=>48,e3=>52,f3=>53,a3=>57);
            die 'Unexpected test note' unless exists $midi{$_[0]};
            return 440 * 2**(($midi{$_[0]}-69)/12);
        };
    }
}
{
    # No sound device is ever opened; inspect the requested rate and PCM bytes.
    package Win32::Sound::WaveOut;
    sub new { bless {rate=>$_[1]},$_[0] }
    sub Status { $_[0]{done} || !$_[0]{written} }
    sub Load { $_[0]{pcm}=$_[1] }
    sub Write { $_[0]{written}=1 }
    sub Pause { $_[0]{done}=1 }
}
use Synth;
use Patch;
use Voice;
use ChordMemory qw(chord_frequencies);
sub fixture {
    return Patch->new(name=>'Fictional baked-chord fixture',chord=>1,
        length=>0.01,decay=>0.01,voices=>[Voice->new(volume_multiplier=>0.2)]);
}
my $root=440*2**((48-69)/12);
for my $rate (8000,44100) {
    my $patch=fixture();
    my $synth=Synth->new(Patches=>{fixture=>$patch},samplerate=>$rate);
    $synth->render_patch_as_middle_c($patch);
    cmp_ok(abs($patch->rendered_frequency-$root),'<',1e-9,"baked chord retains C3 reference at $rate Hz");
    my $reference=fixture();
    my @tones=map {$reference->render(440*2**(($_-69)/12),$rate,16)} (48,52,53,57);
    my $expected=Patch::mix_samples(\@tones);
    is_deeply($patch->rendered_sample,$expected,'C3/E3/F3/A3 tones and mix remain unchanged');
    is($patch->rendered_wave,Synth::sample2wav($expected),'PCM waveform unchanged by metadata correction');
    for my $ratio (1,2,0.5) {
        my $handles=$synth->play_patch($patch,'key',$root*$ratio);
        cmp_ok(abs($handles->[0]{rate}-$rate*$ratio),'<',1e-6,"root/octave ratio $ratio uses the correct device rate");
        is($handles->[0]{pcm},$patch->rendered_wave,'pitch change reuses exact baked waveform');
        $synth->stop_patch('key');
    }
    $synth->chord_memory(1);$synth->chord_type('Major');
    my $handles=$synth->play_patch($patch,'chord',$root);
    my $notes=chord_frequencies($root,1,'Major');
    is(scalar @$handles,scalar @$notes,'playback chord memory keeps its independent voices');
    for my $i (0..$#$notes) {
        cmp_ok(abs($handles->[$i]{rate}-$rate*$notes->[$i]/$root),'<',1e-6,'playback chord-memory interval remains correctly transposed');
    }
    $synth->stop_patch('chord');
    $patch->chord(0);
    $synth->render_patch_as_middle_c($patch);
    cmp_ok(abs($patch->rendered_frequency-$root),'<',1e-9,'ordinary single-note render still keeps its C3 reference');
    is_deeply($patch->rendered_sample,$reference->render($root,$rate,16),'ordinary render waveform is unchanged');
    $synth->render_patch($patch,[220,$root]);
    is($patch->rendered_frequency,220,'explicit multi-tone render keeps its first reference, not its last or lowest tone');
}
done_testing;
