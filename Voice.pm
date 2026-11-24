package Voice;

use Moose; # automatically turns on strict and warnings
use Storable qw(dclone);
use feature qw(switch);
use Data::Dumper;
use Audio::Wav;
use Scalar::Util qw(looks_like_number);
use POSIX qw(isfinite);
use Moose::Util::TypeConstraints;

subtype 'VoiceDelayMilliseconds', as 'Num',
    where { isfinite($_) && $_ >= 0 },
    message { 'Voice delay must be finite and non-negative (milliseconds)' };

use experimental qw( switch );

has 'wave'					=> ( is => 'rw', isa => 'Str', default => 'sine' );
has 'file'					=> ( is => 'rw', isa => 'Str', default => '' );
has 'tuned'					=> ( is => 'rw', isa => 'Bool', default => 0 );	# noise only

has 'volume_multiplier'		=> ( is => 'rw', isa => 'Num', default => 1 );
has 'freq_multiplier'		=> ( is => 'rw', isa => 'Num', default => 1 );

has 'volume_decay'		=> ( is => 'rw', isa => 'Num', default => 0 );
has 'freq_decay'		=> ( is => 'rw', isa => 'Num', default => 0 );

# delay in ms until the sounds starts - can be used to play 2 sounds at once in one patch with the mixing
has 'delay'				=> ( is => 'rw', isa => 'VoiceDelayMilliseconds', default => 0 );

has 'modulators'		=> ( is => 'rw', isa => 'ArrayRef[Voice]', required => 0 );

sub mutate {
	my $self = shift;

	$self->volume_multiplier( mutate_within_percent($self->volume_multiplier, 0.15, 0.05) );
	$self->freq_multiplier( mutate_within_percent($self->freq_multiplier, 0.10, 0.05) );

	if( defined $self->volume_decay && $self->volume_decay > 0 ) {
		$self->volume_decay( mutate_within_percent($self->volume_decay, 0.25, 0) );
	}

	if( defined $self->freq_decay && $self->freq_decay > 0 ) {
		$self->freq_decay( mutate_within_percent($self->freq_decay, 0.25, 0) );
	}

	if( defined $self->delay && $self->delay > 0 ) {
		$self->delay( mutate_within_percent($self->delay, 0.20, 0) );
	}

	if( $self->modulators && scalar @{$self->modulators} ) {
		foreach my $voice (@{$self->modulators}) {
			$voice->mutate();
		}
	}

	return;
}



# Delay the complete voice (including its modulation subtree) without extending
# the render window. Child delays are relative to the parent's audible onset.
sub render {
    my ($self, $samplerate, @args) = @_;
    # GUI bindings write the backing hash directly, bypassing Moose accessors.
    my $delay = $self->delay;
    die "Voice delay must be finite and non-negative (milliseconds)"
        unless defined($delay) && looks_like_number($delay) && isfinite($delay) && $delay >= 0;
    my $wave = $self->_render_undelayed($samplerate, @args);
    return $wave unless $delay;
    my $frames = scalar @{$wave->[0]};
    # Clamp before integer conversion/allocation, even for enormous delays.
    my $offset = ($samplerate * $delay) / 1000;
    $offset = $offset >= $frames ? $frames : int($offset + 0.5);
    return $wave unless $offset;
    for my $channel (@$wave) {
        splice @$channel, $frames - $offset, $offset;
        unshift @$channel, (0) x $offset;
    }
    return $wave;
}

sub _render_undelayed {
	my ($self, $samplerate, $bits, $length, $frequency, $left_volume, $right_volume) = @_;

	my $modulator_wave_ref = undef;

	# recursive part for modulating
	if( $self->modulators && scalar @{$self->modulators} ) {

		# could run this across lots of CPUs
		my @waves = ();
		foreach my $voice (@{$self->modulators}) {

			my $samples = $voice->render($samplerate, $bits, $length, $frequency, 1, 1);

			push( @waves, $samples );
		}

		$modulator_wave_ref = @waves == 1 ? $waves[0] : [Patch::mix_channel(\@waves, 0)];
	}


	given($self->wave) {

		when ("sine") {

			return make_sine( $samplerate, $bits, $length,
				$frequency * $self->freq_multiplier,
				$left_volume * $self->volume_multiplier,
				$right_volume * $self->volume_multiplier,
				$self->freq_decay,
				$modulator_wave_ref,
				$self->volume_decay
			);
		}

		when ("noise") {
			return make_noise( $samplerate, $bits, $length,
				$frequency * $self->freq_multiplier,
				$left_volume * $self->volume_multiplier,
				$right_volume * $self->volume_multiplier,
				$self->freq_decay,
				$self->volume_decay,
				$self->tuned
			);
		}

		when ("file") {

			return make_wav_file( $samplerate, $bits, $length,
				$frequency * $self->freq_multiplier,
				$left_volume * $self->volume_multiplier,
				$right_volume * $self->volume_multiplier,
				$self->freq_decay,
				$modulator_wave_ref,
				$self->volume_decay,
				$self->file
			);
		}
	}
}

sub make_sine {
	my( $samplerate, $bits, $length, $frequency, $left_volume, $right_volume, $freq_decay, $modulator_wave_ref, $volume_decay ) = @_;

	my $samples = int($samplerate * $length);

	my $scale = (2**$bits)/2;

	my $carrier_counter = 0;
	
	my $frequency_divided_by_samplerate = $frequency/$samplerate;
	my $modulation = $modulator_wave_ref && $modulator_wave_ref->[0];

	# fill the arrays with zeros to start
	my @data_l = (0) x $samples;
	my @data_r = (0) x $samples;	
	
	for my $i (0 .. $samples-1) {

		# Calculate the pitch, but only bother if volume greater than zero else you can't hear it
		my $v = sin($carrier_counter *6.28) * $scale;

		$data_l[$i] = $v * $left_volume;
		$data_r[$i] = $v * $right_volume;		

		# modulate the carrier frequency with the current level of modulator_v
		if( $modulation ) {
			$carrier_counter += ($frequency + $modulation->[$i])/$samplerate;
		} else {
			$carrier_counter += $frequency_divided_by_samplerate;
		}

		# volume decay
		if( $left_volume > 0 ) {
			$left_volume -= $volume_decay;
			$right_volume -= $volume_decay;
		} else {
			last;
		}

		# one day we should make this stereo for now lets treat the $volume_decay as mono

		#if( $right_volume > 0 ) {
		#	$right_volume -= $volume_decay;
		#}
		
		#if( $left_volume <= 0 || $right_volume <= 0 ) {
		#	last;
		#}

		# frequency decay
		if( $frequency > 0 ) {
			$frequency -= $freq_decay;
		} else {
			last;
		}
	}

	return [ \@data_l, \@data_r ];
}

sub make_noise {
	my( $samplerate, $bits, $length, $frequency, $left_volume, $right_volume, $freq_decay, $volume_decay, $tuned ) = @_;

	my $samples = int($samplerate * $length);
	my @data_l = (0) x $samples;
	my @data_r = (0) x $samples;

	my $scale = (2**$bits)/2;
	# Remove the unipolar DC component without doubling the random range:
	# 16-bit noise stays within -16384..16383 before gain/envelopes. This
	# preserves the old noise's AC energy rather than adding a 6 dB boost.
	my $noise_midpoint = $scale/2;

	my $last_v = 0;

	for my $i (0 .. $samples-1) {
		last if $left_volume <= 0 && $right_volume <= 0;
		my $v;
		if( $tuned ) {
			# Buffers are already zero-filled: stop before dividing or drawing
			# once initial pitch or frequency decay reaches nonpositive pitch.
			last if $frequency <= 0;
			my $step = $samplerate/$frequency;
			if ($i % $step == 0) {
				$last_v = int(rand($scale)) - $noise_midpoint;
			}
			$v = $last_v;
		} else {
			$v = int(rand($scale)) - $noise_midpoint;
		}

		$data_l[$i] = $v * $left_volume;
		$data_r[$i] = $v * $right_volume;

		# volume decay
		if( $left_volume > 0 && $volume_decay > 0) {
			$left_volume -= $volume_decay;
		}

		if( $right_volume > 0 && $volume_decay > 0 ) {
			$right_volume -= $volume_decay;
		}

		# frequency decay
		if( $tuned && $frequency > 0 && $freq_decay > 0 ) {
			$frequency -= $freq_decay;
		}
	}

	return [ \@data_l, \@data_r ];
}

sub make_wav_file {

	my( $samplerate, $bits, $length, $frequency, $left_volume, $right_volume, $freq_decay, $modulator_wave_ref, $volume_decay, $file ) = @_;

	# open the wav file and get the samples
	my $wav = new Audio::Wav;
	my $read = $wav->read($file);

    my $file_frames = $read->length_samples;
    my $frames = $length == 0 ? $file_frames : int($samplerate * $length);
    my @data_l = (0) x $frames;
    my @data_r = (0) x $frames;
    # Preserve the existing silent last frame when rendering through EOF.
    my $end = $frames < $file_frames ? $frames : $file_frames - 1;
    my $format = $read->details;
    my $stereo_pcm = $format->{bits_sample} == 16 && $format->{channels} == 2
        && $format->{block_align} == 4 && !$format->{'wave-ex'};

    for (my $start = 0; $start < $end; $start += 4096) {
        last if $left_volume <= 0 && $right_volume <= 0;
        my $count = $end - $start;
        $count = 4096 if $count > 4096;
        my @pcm;
        if ($stereo_pcm) {
            my $bytes = $read->read_raw_samples($count);
            die "Short PCM read from $file" unless defined $bytes && length($bytes) == 4 * $count;
            @pcm = unpack('s<*',$bytes);
        }
        for my $i (0 .. $count-1) {
            last if $left_volume <= 0 && $right_volume <= 0;
            my ($left,$right) = $stereo_pcm ? @pcm[2*$i, 2*$i+1] : $read->read();
            $data_l[$start+$i] = $left * $left_volume;
            $data_r[$start+$i] = $right * $right_volume;
            $left_volume -= $volume_decay if $volume_decay && $left_volume > 0;
            $right_volume -= $volume_decay if $volume_decay && $right_volume > 0;
        }
    }

	return [ \@data_l, \@data_r ];
}

sub mutate_within_percent {
	my ($value, $percent, $minimum) = @_;

	return $value unless defined $value;
	return $value if $value == 0;

	my $delta = (rand() * 2 * $percent) - $percent;
	my $mutated = $value * (1 + $delta);

	if( defined $minimum ) {
		$mutated = $minimum if $mutated < $minimum;
	} elsif( $mutated < 0 ) {
		$mutated = 0;
	}

	return $mutated;
}

return 1;
