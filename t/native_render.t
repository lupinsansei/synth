use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use Test::More;
BEGIN {
    $INC{'MIDI/Pitch.pm'}=__FILE__;
    package MIDI::Pitch;
    sub import { }
}
use Patch;
use Synth;

plan skip_all => 'Build the optional renderer with perl native/build.pl' unless $Synth::Native::AVAILABLE;
local $ENV{SYNTH_PERL_ONLY}=0;
my $root=440*2**(-21/12);
my $bass=Voice->new(freq_multiplier=>2,freq_decay=>0.0004,volume_decay=>0.0001,
    modulators=>[Voice->new(freq_multiplier=>6,volume_multiplier=>0.055,volume_decay=>0.000006,freq_decay=>0.0002),
                 Voice->new(freq_multiplier=>12,volume_multiplier=>0.03,volume_decay=>0.0000001,freq_decay=>0.0002)]);
for my $case (
    ['bass',44100,1,0,1,[$bass]],
    ['hi-hat',44100,1,0,1,[Voice->new(wave=>'noise',volume_decay=>0.00025)]],
    ['snare',44100,1,0,1,[Voice->new(freq_decay=>0.004,volume_decay=>0.000005),
        Voice->new(wave=>'noise',delay=>1000,volume_decay=>0.0002)]],
    ['tuned noise and nested noise FM',16000,0.08,0.001,0.1,[
        Voice->new(wave=>'noise',tuned=>1,delay=>2.5,freq_decay=>0.03,modulators=>[Voice->new(wave=>'noise')]),
        Voice->new(modulators=>[Voice->new(wave=>'noise',volume_multiplier=>0.05,delay=>4)])]],
    ['nested FM and stereo mix',22050,0.08,0.007,0.03,[
        Voice->new(delay=>3.9,modulators=>[Voice->new(delay=>1.75,modulators=>[$bass])]),
        Voice->new(freq_multiplier=>0.5,volume_multiplier=>2.25)]],
    ['decay crossing zero and delay beyond window',8000,0.1,0.3,0,[
        Voice->new(volume_multiplier=>0.5,volume_decay=>0.15,freq_decay=>100),
        Voice->new(delay=>2000)]],
    ['tuned noise zero multiplier',8000,0.01,0,1,[Voice->new(wave=>'noise',tuned=>1,freq_multiplier=>0)]],
    ['tuned noise negative multiplier',8000,0.01,0,1,[Voice->new(wave=>'noise',tuned=>1,freq_multiplier=>-1)]],
    ['tuned noise exact zero decay',8000,0.01,0,1,[Voice->new(wave=>'noise',tuned=>1,freq_multiplier=>0.125,freq_decay=>$root*0.125)]],
    ['tuned noise decay crossing zero with delay',8000,0.01,0,1,[Voice->new(wave=>'noise',tuned=>1,freq_decay=>100,delay=>0.5)]],
    ['stopped tuned noise preserves following random voice',8000,0.01,0,1,[
        Voice->new(wave=>'noise',tuned=>1,freq_decay=>100),Voice->new(wave=>'noise')]],
    ['untuned noise zero multiplier',8000,0.01,0,1,[Voice->new(wave=>'noise',freq_multiplier=>0)]],
    ['untuned noise negative multiplier',8000,0.01,0,1,[Voice->new(wave=>'noise',freq_multiplier=>-1)]],
    ['clipping',48000,0.1,0,1,[Voice->new(volume_multiplier=>4)]],
    ['hard right with decay and delayed FM',8000,0.02,0.001,0.02,[
        Voice->new(pan=>1,volume_decay=>0.01,delay=>1,modulators=>[Voice->new(pan=>1,volume_multiplier=>0.03)])]],
    ['split stereo with clipping and noise',16000,0.02,0.001,0.02,[
        Voice->new(pan=>-1,volume_multiplier=>5),Voice->new(pan=>0.5,wave=>'noise',delay=>1)]],
    ['empty render',44100,0,0,0,[Voice->new]],
) {
    my ($name,$rate,$length,$attack,$decay,$voices)=@$case;
    my $patch=Patch->new(name=>$name,length=>$length,attack=>$attack,decay=>$decay,voices=>$voices);
    my $reference;
    srand(77);
    { local $ENV{SYNTH_PERL_ONLY}=1; $reference=$patch->render($root,$rate,16) }
    my $next_random=rand();
    srand(77);
    my $pcm;
    my $actual=$patch->render($root,$rate,16,\$pcm);
    is(rand(),$next_random,"$name consumes the same random draws");
    is(length($pcm),4*@{$reference->[0]},"$name used XS and returned stereo PCM");
    ok(defined($pcm) && $pcm eq Synth::sample2wav($reference),"$name matches Perl playback bytes");
    for my $ch (0,1) {
        is(scalar @{$actual->[$ch]},scalar @{$reference->[$ch]},"$name channel $ch length");
        my $max=0;
        for my $i (0..$#{$reference->[$ch]}) {
            my $d=abs($actual->[$ch][$i]-$reference->[$ch][$i]);
            $max=$d if $d>$max;
        }
        cmp_ok($max,'<',0.000001,"$name channel $ch raw samples");
    }
}
my $wav_patch=Patch->new(length=>0.05,voices=>[Voice->new(modulators=>[Voice->new(wave=>'file')])]);
ok(!defined(Synth::Native::render($wav_patch,$root,44100,16)), 'nested file selects the Perl path');
my $invalid=Voice->new;
$invalid->{delay}=-1;
my $patch=Patch->new(length=>0.01,voices=>[$invalid]);
eval { $patch->render($root,44100,16) };
like($@,qr/delay must be finite and non-negative/,'invalid delay retains the Perl diagnostic');
done_testing;
