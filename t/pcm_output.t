use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use Storable qw(dclone);
BEGIN {
    $INC{'MIDI/Pitch.pm'} = __FILE__;
    package MIDI::Pitch;
    sub import { no strict 'refs'; *{caller().'::name2freq'} = sub { 130.81278265 }; }
}
use Synth;
use Patch;
use Voice;

# Inspect real final-conversion bytes without opening an audio device.
my $sample = [
    [40000, -40000, 32768, -32769, 65536, -65536, 1e12, -1e12],
    [-40000, 40000, -32769, 32768, -65536, 65536, -1e12, 1e12],
];
my $original = dclone($sample);
my $pcm = Synth::sample2wav($sample);
is_deeply([unpack('s<*', $pcm)], [
    32767,-32768, -32768,32767, 32767,-32768, -32768,32767,
    32767,-32768, -32768,32767, 32767,-32768, -32768,32767,
], 'overloaded stereo peaks saturate rather than wrap or invert');
is_deeply($sample, $original, 'conversion never clips the source sample arrays in place');
is(length($pcm), 8 * 4, 'clipping preserves stereo frame count');

my $normal = [[-32768,-32767,-1,0,1,32766,32767,-1.75,1.75],
              [32767,32766,1,0,-1,-32767,-32768,1.75,-1.75]];
my $legacy = join '', map { pack('vv', $normal->[0][$_], $normal->[1][$_]) } 0..$#{$normal->[0]};
is(Synth::sample2wav($normal), $legacy, 'boundaries, silence, normal levels and fractional truncation stay byte-identical');
is_deeply([unpack('s<*', Synth::sample2wav($sample, 1, 2))],
    [-32768,32767,32767,-32768], 'offset and length clip the requested stereo frames only');
is(Synth::sample2wav([[],[]]), '', 'empty output remains empty');

# The full renderer keeps high-amplitude FM data in its floating-point domain.
my $mod = Voice->new(wave=>'sine', volume_multiplier=>4, freq_multiplier=>2);
my $patch = Patch->new(name=>'Fictional overload fixture', length=>0.01,
    attack=>0, decay=>0.01, voices=>[Voice->new(wave=>'sine', volume_multiplier=>4, modulators=>[$mod])]);
my $synth = Synth->new(Patches=>{fixture=>$patch});
my $raw = $patch->render(130.81278265,44100,16);
my $raw_snapshot = dclone($raw);
my $mod_before = $mod->render(44100,16,0.01,130.81278265,1,1);
cmp_ok(scalar(grep { abs($_)>32768 } @{$mod_before->[0]}), '>', 0,
    'fixture actually exercises above-PCM-range FM modulation');
$synth->render_patch($patch, [130.81278265]);
is_deeply($patch->rendered_sample, $raw_snapshot, 'rendered sample retains raw FM output before final conversion');
is_deeply($mod->render(44100,16,0.01,130.81278265,1,1), $mod_before,
    'final conversion leaves internal modulator output unchanged');
my @out = unpack('s<*', $patch->rendered_wave);
my @raw_interleaved = map { ($raw->[0][$_], $raw->[1][$_]) } 0..$#{$raw->[0]};
my ($overloads,$mismatches) = (0,0);
for my $i (0..$#out) {
    my $v = $raw_interleaved[$i];
    if ($v>32767) { $overloads++; $mismatches++ if $out[$i]!=32767; }
    elsif ($v< -32768) { $overloads++; $mismatches++ if $out[$i]!= -32768; }
    else { $mismatches++ if $out[$i]!=int($v); }
}
cmp_ok($overloads,'>',0,'full renderer exercises clipping, not merely quiet audio');
is($mismatches,0,'rendered playback buffer clips every overloaded peak and preserves other samples');
done_testing;
