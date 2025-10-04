package Voice;

use Moose; # automatically turns on strict and warnings
#use CHI::Memoize qw(:all);
use Storable qw(dclone);
use feature qw(switch);
use Data::Dumper;
use Audio::Wav;
#use Memoize;

use experimental qw( switch );

has 'wave'					=> ( is => 'rw', isa => 'Str', default => 'sine' );
has 'file'					=> ( is => 'rw', isa => 'Str', default => '' );
has 'tuned'					=> ( is => 'rw', isa => 'Bool', default => 0 );	# noise only

has 'volume_multiplier'		=> ( is => 'rw', isa => 'Num', default => 1 );
has 'freq_multiplier'		=> ( is => 'rw', isa => 'Num', default => 1 );

has 'volume_decay'		=> ( is => 'rw', isa => 'Num', default => 0 );
has 'freq_decay'		=> ( is => 'rw', isa => 'Num', default => 0 );

# delay in ms until the sounds starts - can be used to play 2 sounds at once in one patch with the mixing
has 'delay'				=> ( is => 'rw', isa => 'Num', default => 0 );

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



sub render {
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

		$modulator_wave_ref = Patch::mix_samples( \@waves );
	}

	# if( $self->delay ) {
				# # convert delay ms into samples
				# my $delay_samples = ($samplerate/$length) * ($self->delay * 1000);
				# print $delay_samples;

				# # put loads of empty samples at the beginning and remove that many from the end
				# # remember it's left and right samples

			# }

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
				$self->volume_decay,
				$modulator_wave_ref,
				$self->file
			);
		}
	}
}

#memoize( 'make_sine', driver => 'File', root_dir => 'c:\Cache', expires_in => '1h' );	this isn't any faster than normal, it's slightly slower
#memoize( 'make_sine', driver => 'RawMemory' );	# takes too long too!

sub make_sine {
	my( $samplerate, $bits, $length, $frequency, $left_volume, $right_volume, $freq_decay, $modulator_wave_ref, $volume_decay ) = @_;

	my $samples = $samplerate * $length;

	my $scale = (2**$bits)/2;

	my $carrier_counter = 0;
	
	my $frequency_divided_by_samplerate = $frequency/$samplerate;

	# fill the arrays with zeros to start
	my @data_l = (0) x $samples;
	my @data_r = (0) x $samples;	
	
	for( my $i=0; $i<$samples; $i++) {

		# Calculate the pitch, but only bother if volume greater than zero else you can't hear it
		my $v = sin($carrier_counter *6.28) * $scale;	# I tried to speed up sin with things like memoize and hash tables and lookups but it's not any faster

		$data_l[$i] = $v * $left_volume;
		$data_r[$i] = $v * $right_volume;		

		# modulate the carrier frequency with the current level of modulator_v
		if( $modulator_wave_ref ) {
			$carrier_counter += ($frequency + $modulator_wave_ref->[0]->[$i] )/$samplerate;		# hack: we are only using the left channel here
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

	my @data_l = ();
	my @data_r = ();

	my $samples = $samplerate * $length;

	my $scale = (2**$bits)/2;

	my $carrier_increment = $frequency/$samplerate;
	my $carrier_counter = 0;
	my $last_v = 0;

	for( my $i=0; $i <$samples; $i++) {

		my $step = $samplerate/$frequency;

		if( $left_volume > 0 || $right_volume > 0 ) {

			my $v;
			if( $tuned ) {
				unless( $i % $step == 0 ) {		# this makes the noise tuned, which sounds okay sometimes, like 80s computer
					$v = $last_v;
				} else {
					$v = int(rand($scale));
					$last_v = $v;
				}
			} else {
				$v = int(rand($scale));
			}

			$data_l[$i] = $v * $left_volume;
			$data_r[$i] = $v * $right_volume;
		} else {
			$data_l[$i] = 0;
			$data_r[$i] = 0;
		}

		$carrier_counter += $carrier_increment;

		# volume decay
		if( $left_volume > 0 && $volume_decay > 0) {
			$left_volume -= $volume_decay;
		}

		if( $right_volume > 0 && $volume_decay > 0 ) {
			$right_volume -= $volume_decay;
		}

		# frequency decay
		if( $frequency > 0 && $freq_decay > 0 ) {
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

	# default to the length of the wav file unless specified
	my $samples;
	if( $length == 0 ) {
		$samples = $read->length_samples();
	} else {
		$samples = $samplerate * $length;
	}

	#print "Sample length = $length\n";

	my @data_l = ();
	my @data_r = ();

	my $scale = (2**$bits)/2;

	my $carrier_counter = 0;
	my $modulator_increment = 0;
	my $modulator_counter = 0;



	for( my $i=0; $i <$samples; $i++) {

		my @channels = $read->read();

		if( ($left_volume > 0 || $right_volume > 0 ) && ( $read->position_samples() < $read->length_samples() ) ) {

			# Calculate the pitch, but only bother if volume greater than zero else you can't hear it
			#my $v = sin($carrier_counter*6.28) * $scale;

			$data_l[$i] = $channels[0] * $left_volume;
			$data_r[$i] = $channels[1] * $right_volume;

		} else {
			$data_l[$i] = 0;
			$data_r[$i] = 0;
		}

		# modulate the carrier frequency with the current level of modulator_v
		if( $modulator_wave_ref ) {
			$carrier_counter += ($frequency + $modulator_wave_ref->[0]->[$i] )/$samplerate;		# hack: we are only using the left channel here
		} else {
			$carrier_counter += $frequency/$samplerate;
		}

		# volume decay
		if( $volume_decay && $left_volume > 0) {
			$left_volume -= $volume_decay;
		}

		if( $volume_decay && $right_volume > 0 ) {
			$right_volume -= $volume_decay;
		}

		# frequency decay
		if( $freq_decay && $frequency > 0 ) {
			$frequency -= $freq_decay;

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
