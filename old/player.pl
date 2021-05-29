use Win32::Sound;
use MIDI::Pitch qw(name2freq);
use Synth;

# http://search.cpan.org/dist/Music-Scales-0.07/lib/Music/Scales.pm
# http://search.cpan.org/~mlehmann/PDL-Audio-1.2/audio.pd
# http://search.cpan.org/dist/Audio-Analyzer-0.22/
# http://search.cpan.org/dist/Music-Note-0.01/lib/Music/Note.pm

my $synth1 = new Synth( frequency => name2freq('a4'), length => 0.5);
#my $synth2 = new Synth( frequency => name2freq('a4'), length => 0.5);
    
my $WAV = new Win32::Sound::WaveOut(44100, 8, 2);	# http://search.cpan.org/~acalpini/Win32-Sound/Sound.pm

$WAV->Load($synth1->render());      # get it
$WAV->Write();           			# hear it
1 until $WAV->Status();  			# wait for completion
$WAV->Save("sinus.wav");			# write to disk
$WAV->Unload();          			# drop it