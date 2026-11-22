package VoiceSample;
use strict;
use warnings;
use Audio::Wav;
use File::Spec;

sub validate {
    my ($class, $path, $synth) = @_;
    die "Choose a readable WAV file\n" unless defined($path) && length($path) && -f $path && -r $path;
    my $wav = Audio::Wav->new;
    $wav->set_error_handler(sub { my %error = @_; die "Cannot read WAV: $error{message}\n"; });
    my $read = $wav->read($path) or die "Cannot read WAV\n";
    my $details = $read->details;
    # The existing file renderer reads raw frames, without rate/format conversion.
    die "Choose standard uncompressed 16-bit stereo PCM WAV audio\n"
        unless $details->{bits_sample} == 16 && $details->{channels} == 2 && !$details->{'wave-ex'};
    die "Choose a WAV at " . $synth->samplerate . " Hz; sample-rate conversion is not supported\n"
        unless $details->{sample_rate} == $synth->samplerate;
    die "WAV contains no audio frames\n" unless $read->length_samples > 0;
    return File::Spec->rel2abs($path);
}

sub apply {
    my ($class, %args) = @_;
    my ($voice, $patch, $wave) = @args{qw(voice patch wave)};
    die "Unknown waveform\n" unless defined($wave) && $wave =~ /\A(?:sine|noise|file)\z/;
    my $path = $wave eq 'file' ? $class->validate($args{path}, $args{synth}) : undef;
    my %previous = map { exists $voice->{$_} ? ($_ => $voice->{$_}) : () } qw(wave file);
    my @cache_keys = qw(rendered_sample rendered_wave rendered_frequency);
    my %cache = map { exists $patch->{$_} ? ($_ => $patch->{$_}) : () } @cache_keys;
    my $ok = eval {
        $args{before}->() if $args{before};
        $voice->wave($wave);
        $voice->file($path) if defined $path;
        $args{render}->();
        1;
    };
    unless ($ok) {
        my $error = $@;
        delete @{$voice}{qw(wave file)};
        @{$voice}{keys %previous} = values %previous;
        delete @{$patch}{@cache_keys};
        @{$patch}{keys %cache} = values %cache;
        die $error;
    }
    return 1;
}
1;
