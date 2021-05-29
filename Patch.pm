package Patch;

	use Moose; # automatically turns on strict and warnings
	#use CHI::Memoize qw(:all);
	#use Storable qw(dclone);
	use Voice;
	use Data::Dumper;

	has 'name'		=> ( is => 'rw', isa => 'Str', required => 0 );

	has 'length'		=> ( is => 'rw', isa => 'Num', default => 0 );		# seconds - if any sample is longer than another one it seems to not be cleared from the audio buffer, maybe solved with a blank sample the size of the largest one?
																			# default to the length of the wav file if that's the voice type unless specified

	#has 'volume'		=> ( is => 'rw', isa => 'Num', default => 1 );		# 0..1

	has 'voices'		=> ( is => 'rw', isa => 'ArrayRef[Voice]', required => 1 );

	has 'attack'		=> ( is => 'rw', isa => 'Num', default => 0 );	# these are slower than volume_decay on voice
	has 'decay'			=> ( is => 'rw', isa => 'Num', default => 1 );		# these are slower than volume_decay on voice

	has 'rendered_frequency'		=> ( is => 'rw', isa => 'Num', required => 0 );	# the frequency it was rendered at, later used to change the pitch

	has 'rendered_sample'	=> ( is => 'rw' );	# what data type? Some kind of reference to raw binary?
	has 'rendered_wave'	=> ( is => 'rw', isa => 'Str' );

sub render {
	my ($self, $frequency, $samplerate, $bits) = @_;

	$self->rendered_frequency($frequency);

	if( @{$self->voices} > 1 ) {
		# could run this across lots of CPUs
		my @waves = ();
		foreach my $voice (@{$self->voices}) {
			my $wave = $voice->render( $samplerate, $bits, $self->length, $frequency, 1, 1 );
			$wave = envelope( $wave, $self->attack, $self->decay );
			push( @waves, $wave );
		}

		return mix_samples( \@waves );
	} else {

		# single voice
		my $wave = $self->voices->[0]->render( $samplerate, $bits, $self->length, $frequency, 1, 1 );
		$wave = envelope( $wave, $self->attack, $self->decay );
		return $wave;
	}
}

sub mix_samples {

	my $samples = shift;

	my @data_l;
	my @data_r;

	my $sample_count = scalar @$samples;
	my $scale = 1/$sample_count;

	for( my $j=0; $j<$sample_count; $j++ ) {

		my $sample = $samples->[$j];

		for( my $i=0; $i<scalar @{$sample->[0]}; $i++ ) {

			$data_l[$i] += $sample->[0]->[$i] * $scale;
			$data_r[$i] += $sample->[1]->[$i] * $scale;
		}
	}

	return [ \@data_l, \@data_r ];
}

# around 'profit' => sub {
	# my $orig = shift;
	# my $self = shift;

	# return $self->sell_price * $self->shares - ($self->buy_price * $self->shares) - ($self->transactionCost * 2);
# };

sub envelope {

	my( $sample, $attack, $decay ) = @_;

	my $attack_end = $attack * 44100;
	my $decay_end = $attack_end + $decay * 44100;
	my $decay_length = $decay_end-$attack_end;

	my $scale = 0;

	my $sample_length = scalar @{$sample->[0]};

	my @data_l = ();
	my @data_r = ();

	for( my $i=0; $i<$sample_length; $i++ ) {

		if( $i < $attack_end ) {

			# attack from 0% to 100%
			$scale = $i/$attack_end;

			$data_l[$i] = $sample->[0]->[$i] * $scale;
			$data_r[$i] = $sample->[1]->[$i] * $scale;

		} elsif( $i < $decay_end ) {

			# decay from 100% to 0%
			$scale = 1 - ($i-$attack_end)/$decay_length;

			$data_l[$i] = $sample->[0]->[$i] * $scale;
			$data_r[$i] = $sample->[1]->[$i] * $scale;

		} else {

			$data_l[$i] = 0;
			$data_r[$i] = 0;
		}
	}

	return [ \@data_l, \@data_r ];
}


# sub filter {

	# my( $sample, $delay, $gain ) = @_;

	# my $sample_length = scalar @{$sample->[0]};

	# my @data_l;
	# my @data_r;

	# for( my $i=0; $i<$sample_length; $i++ ) {

		# $data_l[$i] = ($sample->[0]->[$i] * (1-$gain)) + ($sample->[0]->[$i-$delay] * $gain);
		# $data_r[$i] = ($sample->[1]->[$i] * (1-$gain)) + ($sample->[1]->[$i-$delay] * $gain);
	# }

	# return [ \@data_l, \@data_r ];
# }

sub filter {

	my( $sample, $filters ) = @_;

	my $sample_length = scalar @{$sample->[0]};

	my @data_l;
	my @data_r;

	# apply each filter
	foreach my $filter (@$filters) {

		my( $delay, $gain ) = ( $filter->{delay}, $filter->{gain} );

		# sum with the results and amplify
		for( my $i=0; $i<$sample_length; $i++ ) {

			$data_l[$i] = $sample->[0]->[$i] * $gain + $sample->[0]->[$i-$delay] * $gain;
			$data_r[$i] = $sample->[1]->[$i] * $gain + $sample->[1]->[$i-$delay] * $gain;

			$data_l[$i] = ($data_l[$i] + $data_l[$i-1] * $filter->{feedback})/2;
			$data_r[$i] = ($data_r[$i] + $data_r[$i-1] * $filter->{feedback})/2;

			$delay += 0.0005;
		}
	}

	return [ \@data_l, \@data_r ];
}

return 1;
