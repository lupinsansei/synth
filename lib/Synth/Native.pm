package Synth::Native;
use strict;
use warnings;
use Config;
use File::Basename qw(dirname);
use File::Spec;
use Scalar::Util qw(looks_like_number);
use POSIX qw(isfinite);

our $VERSION = '0.01';
our $AVAILABLE = do {
    local @INC = (File::Spec->catdir(dirname(__FILE__), '..', 'native',
        "$Config{archname}-$Config{version}"), @INC);
    eval { require XSLoader; XSLoader::load(__PACKAGE__, $VERSION); 1 };
};

sub _eligible {
    my ($v) = @_;
    return 0 unless ref($v) eq 'Voice';
    return 0 unless $v->wave eq 'sine' || ($v->wave eq 'noise' && __PACKAGE__->can('_noise'));
    # Let the Perl renderer report invalid GUI edits using its existing diagnostics.
    my $delay = $v->delay;
    return 0 unless defined($delay) && looks_like_number($delay) && isfinite($delay) && $delay >= 0;
    for my $child (@{$v->modulators || []}) { return 0 unless _eligible($child) }
    return 1;
}

sub _voice {
    my ($v,$frames,$root,$rate,$scale) = @_;
    my @mods = map { _voice($_,$frames,$root,$rate,$scale) } @{$v->modulators || []};
    my $delay = $rate*$v->delay/1000;
    my $offset = $delay >= $frames ? $frames : int($delay+0.5);
    if ($v->wave eq 'noise') {
        return _noise($frames,$root*$v->freq_multiplier,$rate,$scale,$v->volume_multiplier,
            $v->volume_decay,$v->freq_decay,$offset,$v->tuned);
    }
    return _oscillator(\@mods,$frames,$root*$v->freq_multiplier,$rate,$scale,
        $v->volume_multiplier,$v->volume_decay,$v->freq_decay,
        $offset);
}

sub render {
    my ($patch,$root,$rate,$bits,$pcm) = @_;
    return unless $AVAILABLE && !$ENV{SYNTH_PERL_ONLY} && ref($patch) eq 'Patch'
        && $bits == 16 && $rate > 0 && @{$patch->voices};
    my $frames = int($rate*$patch->length);
    return unless $frames >= 0 && $frames <= 0x07ffffff;
    for my $voice (@{$patch->voices}) { return unless _eligible($voice) }
    my $chord = ref($root) eq 'ARRAY';
    return if $chord && !__PACKAGE__->can('_finish_chord');
    my ($samples,$bytes,@tones);
    for my $frequency ($chord ? @$root : ($root)) {
        my @voices = map { _voice($_,$frames,$frequency,$rate,32768) } @{$patch->voices};
        my @envelope = ($patch->attack*$rate,$patch->decay*$rate);
        if ($chord) {
            push @tones, _finish(\@voices,$frames,@envelope,0,1);
        } else {
            ($samples,$bytes) = _finish(\@voices,$frames,@envelope,defined $pcm);
        }
    }
    ($samples,$bytes) = _finish_chord(\@tones,$frames) if $chord;
    $$pcm = $bytes if defined $pcm;
    return $samples;
}
1;
