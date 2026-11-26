use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
BEGIN {
    $INC{'MIDI/Pitch.pm'}=__FILE__;
    package MIDI::Pitch;
    sub import { }
}
use Patch;
use Synth;
use PatchBank;
use FMPatchExplorer;
use File::Temp qw(tempdir);
use JSON::PP;
use Audio::Wav;

my $dir=tempdir(CLEANUP=>1);
my $path="$dir/fictional-stereo.wav";
my $writer=Audio::Wav->new->write($path,{bits_sample=>16,sample_rate=>8000,channels=>2});
$writer->write(1000,-2000) for 1..100;
$writer->finish;
my $rate=8000;
sub fixture {
    my ($kind)=@_;
    return Patch->new(length=>0.01,attack=>0.001,decay=>0.02,voices=>[
        Voice->new(wave=>$kind, file=>$kind eq 'file' ? $path : '',
            volume_multiplier=>0.6,volume_decay=>0.01,delay=>0.5,
            modulators=>[Voice->new(volume_multiplier=>0.03,delay=>0.125)])]);
}
sub silent { return !grep { $_ != 0 } @{$_[0]}; }
for my $perl_only (1, ($Synth::Native::AVAILABLE ? (0) : ())) {
    local $ENV{SYNTH_PERL_ONLY}=$perl_only;
    for my $kind (qw(sine noise file)) {
        my $p=fixture($kind);
        srand(310); my $centre=$p->render(220,$rate,16); my $rng=rand();
        for my $pan (-1,-0.5,0,0.5,1) {
            $p->voices->[0]->pan($pan);
            srand(310); my $pcm;
            my $wave=$p->render(220,$rate,16,\$pcm);
            is(rand(),$rng,"$kind pan=$pan Perl=$perl_only preserves RNG consumption");
            my @gain=($pan>0 ? 1-$pan : 1, $pan<0 ? 1+$pan : 1);
            for my $ch (0,1) {
                my @expected=map{$_*$gain[$ch]}@{$centre->[$ch]};
                is_deeply($wave->[$ch],\@expected,"$kind pan=$pan Perl=$perl_only balances channel $ch after FM/decay/delay/envelope");
            }
            if (!$perl_only && $kind ne 'file') {
                ok(defined($pcm),'compiled XS mixer supplies PCM');
                is($pcm,Synth::sample2wav($wave),'panned XS PCM matches reference packing');
            }
        }
        $p->voices->[0]->pan(0);
        if ($kind eq 'file') {
            cmp_ok(abs($centre->[0][8]),'>',0,'stereo WAV left is audible');
            is($centre->[1][8],-2*$centre->[0][8],'centred stereo WAV retains independent channels');
        }
        my $unchanged=$p->render(220,$rate,16);
        $p->voices->[0]->modulators->[0]->pan(1);
        srand(310); my $ignored=$p->render(220,$rate,16);
        if ($kind ne 'noise') {
            is_deeply($ignored,$unchanged,'modulator pan never changes carrier FM depth');
        }
    }
    my $p=fixture('sine');
    my $v=$p->voices->[0];$v->pan(-1);
    my $left=$p->render(220,$rate,16);
    $v->pan(1);$v->freq_multiplier(2);
    my $right=$p->render(220,$rate,16);
    $p->voices([Voice->new(%$v,pan=>-1,freq_multiplier=>1),$v]);
    my $mixed=$p->render(220,$rate,16);
    is_deeply($mixed->[0],[map{$_/2}@{$left->[0]}],'layered oscillators mix independently on left');
    is_deeply($mixed->[1],[map{$_/2}@{$right->[1]}],'layered oscillators mix independently on right');
}
SKIP: {
    skip 'XS not built (CI explicitly requires it after building)',5 unless $Synth::Native::AVAILABLE;
    local $ENV{SYNTH_PERL_ONLY}=0;
    my $p=fixture('sine');$p->voices->[0]->pan(0.5);
    push @{$p->voices},Voice->new(wave=>'noise',pan=>-1,volume_multiplier=>2);
    srand(911);my @reference;
    {local $ENV{SYNTH_PERL_ONLY}=1; @reference=map{$p->render($_,8000,16)}(220,330,440);}
    my $expected=Patch::mix_samples(\@reference);my $rng=rand();
    srand(911); my $pcm;my $actual=Synth::Native::render($p,[220,330,440],8000,16,\$pcm);
    ok(defined($actual) && defined($pcm),'stereo chord really uses XS');
    is(rand(),$rng,'stereo chord preserves RNG consumption');
    is_deeply($actual,$expected,'stereo chord mixes both independent channels exactly');
    is($pcm,Synth::sample2wav($expected),'stereo chord PCM agrees with Perl including clipping');
    isnt($actual->[0][8],$actual->[1][8],'chord does not collapse to mono');
}

my $p=fixture('sine');my $synth=Synth->new(Patches=>{fixture=>$p});
my $bank="$dir/fictional.synth.json";
$p->voices->[0]->pan(-0.5);
PatchBank->save_file($bank,$synth);
my $restored=PatchBank->read_file($bank)->{patches}{fixture};
is($restored->voices->[0]->pan,-0.5,'bank restores pan');
is_deeply($restored->render(220,8000,16),$p->render(220,8000,16),'bank restores identical stereo sound');
my $doc=PatchBank->capture($synth);
delete $doc->{patches}{fixture}{voices}[0]{pan};
open my $fh,'>',$bank or die $!;print {$fh} JSON::PP->new->encode($doc);close $fh;
is(PatchBank->read_file($bank)->{patches}{fixture}->voices->[0]->pan,0,'old bank without pan defaults to Centre');
for my $bad (-1.01,1.01,'NaN','Inf','not a number',undef) {
    ok(!eval{Voice->new(pan=>$bad);1},'invalid constructor pan rejected');
    $p->voices->[0]{pan}=$bad;
    ok(!eval{$p->render(220,8000,16);1},'invalid backing-hash edit rejected during rendering');
    ok(!eval{PatchBank->capture($synth);1},'invalid backing-hash edit rejected during save');
}
$p->voices->[0]->pan(-1);
my $explorer=FMPatchExplorer->new;
ok($explorer->set_pan($p,0,1),'pan edit recorded');
is($p->voices->[0]->pan,1,'pan changed');
$explorer->undo($p);
is($p->voices->[0]->pan,-1,'Undo restores pan edit');
$explorer->new_sound($p,family=>'Bell');$explorer->undo($p);
is($p->voices->[0]->pan,-1,'Undo after New sound restores previous pan');
$explorer->variation($p);is($p->voices->[0]->pan,-1,'Variation preserves pan');
my $before=$explorer->snapshot($p);my $depth=$explorer->can_undo($p);
eval{$explorer->set_pan($p,0,1,preview=>sub{die 'Fictional render failure'})};
like($@,qr/Fictional render failure/,'render failure reported');
is_deeply($explorer->snapshot($p),$before,'failed pan edit restores complete previous sound');
is($explorer->can_undo($p),$depth,'failed pan edit leaves Undo intact');
done_testing;
