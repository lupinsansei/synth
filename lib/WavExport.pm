package WavExport;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Temp qw(tempfile);

# The playback buffer is interleaved little-endian 16-bit stereo PCM, not a
# complete WAV file. Wrap those exact bytes; no second quantisation or resample.
sub wav_bytes {
    my ($class, $pcm, $rate) = @_;
    die "Invalid sample rate\n" unless defined($rate) && $rate =~ /\A[0-9]+\z/ && $rate > 0 && $rate <= int(0xffffffff / 4);
    die "Expected nonempty 16-bit stereo PCM\n" unless defined($pcm) && !ref($pcm) && length($pcm) && length($pcm) % 4 == 0 && !utf8::is_utf8($pcm);
    my $size = length($pcm);
    die "Sound exceeds the WAV size limit\n" if $size > 0xffffffff - 36;
    return pack('a4Va4a4VvvVVvva4V', 'RIFF', 36 + $size, 'WAVE', 'fmt ', 16,
        1, 2, $rate, $rate * 4, 4, 16, 'data', $size) . $pcm;
}

sub export_patch {
    my ($class, $path, $synth, $patch) = @_;
    die "Choose a WAV filename\n" unless defined($path) && length($path);
    die "WAV export supports 16-bit stereo only\n" unless $synth->bits == 16 && $synth->channels == 2;
    # Validate before rendering; export never starts playback or the sequencer.
    $class->wav_bytes(pack('vv', 0, 0), $synth->samplerate);
    $synth->render_patch_as_middle_c($patch);
    my $bytes = $class->wav_bytes($patch->rendered_wave, $synth->samplerate);
    my ($handle, $temp) = tempfile('.synth-wav-XXXXXX', DIR => dirname($path), UNLINK => 0);
    my $ok = eval {
        binmode($handle, ':raw') or die "Cannot prepare WAV: $!";
        print {$handle} $bytes or die "Cannot write WAV: $!";
        close($handle) or die "Cannot finish WAV: $!";
        rename($temp, $path) or die "Cannot replace WAV (original retained): $!";
        1;
    };
    unless ($ok) { my $error = $@; close($handle); unlink($temp); die $error; }
    return 1;
}
1;
