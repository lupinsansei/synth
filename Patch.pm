package Patch;

	use Moose; # automatically turns on strict and warnings
	#use Storable qw(dclone);	
	use Voice;
	use File::Basename ();
	use File::Spec ();
	use lib File::Spec->catdir(File::Basename::dirname(__FILE__), 'lib');
	use Synth::Native ();
	use Data::Dumper;	

	has 'name'					=> ( is => 'rw', isa => 'Str', required => 0 );

	has 'length'				=> ( is => 'rw', isa => 'Num', default => 0 );		# seconds - if any sample is longer than another one it seems to not be cleared from the audio buffer, maybe solved with a blank sample the size of the largest one?
																			# default to the length of the wav file if that's the voice type unless specified

	#has 'volume'				=> ( is => 'rw', isa => 'Num', default => 1 );		# 0..1

	has 'voices'				=> ( is => 'rw', isa => 'ArrayRef[Voice]', required => 1 );

	has 'attack'				=> ( is => 'rw', isa => 'Num', default => 0 );	# these are slower than volume_decay on voice
	has 'decay'					=> ( is => 'rw', isa => 'Num', default => 1 );	# these are slower than volume_decay on voice

	has 'rendered_frequency'	=> ( is => 'rw', isa => 'Num', required => 0 );	# the frequency it was rendered at, later used to change the pitch

	has 'rendered_sample'		=> ( is => 'rw' );	# what data type? Some kind of reference to raw binary?
	has 'rendered_wave'			=> ( is => 'rw', isa => 'Str' );

	has 'chord' 				=> ( is => 'rw', isa => 'Bool', default => 0 );
	has 'baked_chord_type' => (is => 'rw', isa => 'Str', default => 'Fmaj7/C');

sub mutate {

	my $self = shift;

	if( defined $self->length && $self->length > 0 ) {
		$self->length( mutate_within_percent($self->length, 0.10, 0.05) );
	}

	if( defined $self->attack && $self->attack > 0 ) {
		$self->attack( mutate_within_percent($self->attack, 0.25, 0) );
	}

	if( defined $self->decay && $self->decay > 0 ) {
		$self->decay( mutate_within_percent($self->decay, 0.25, 0.05) );
	}

	foreach my $voice (@{$self->voices}) {
		$voice->mutate();
	}

	return;
}


sub render {
	my ($self, $frequency, $samplerate, $bits, $pcm) = @_;

	$self->rendered_frequency($frequency);
    my $native = Synth::Native::render($self,$frequency,$samplerate,$bits,$pcm);
    return $native if defined $native;

	if( @{$self->voices} > 1 ) {
		# could run this across lots of CPUs
		my @waves = ();
		foreach my $voice (@{$self->voices}) {
			my $wave = $voice->render( $samplerate, $bits, $self->length, $frequency, 1, 1 );
			$wave = envelope( $wave, $self->attack, $self->decay, $samplerate );
			push( @waves, $wave );
		}

		return mix_samples( \@waves );
	} else {

		# single voice
		my $wave = $self->voices->[0]->render( $samplerate, $bits, $self->length, $frequency, 1, 1 );
		$wave = envelope( $wave, $self->attack, $self->decay, $samplerate );
		return $wave;
	}
}

# Mix one channel at a time. FM carriers read only the left channel.
sub mix_channel {
    my ($waves,$channel) = @_;
    return [] unless @$waves;
    my @mixed = @{$waves->[0][$channel]};
    for my $voice (1 .. $#$waves) {
        my $input = $waves->[$voice][$channel];
        for my $i (0 .. $#$input) {
            $mixed[$i] += $input->[$i];
        }
    }
    my $count = @$waves;
    $_ /= $count for @mixed;
    return \@mixed;
}

sub mix_samples {
    my ($waves) = @_;
    return [mix_channel($waves,0), mix_channel($waves,1)];
}

# around 'profit' => sub {
	# my $orig = shift;
	# my $self = shift;

	# return $self->sell_price * $self->shares - ($self->buy_price * $self->shares) - ($self->transactionCost * 2);
# };

sub envelope {

	my( $sample, $attack, $decay, $samplerate ) = @_;
	# Preserve legacy direct callers; render() always supplies its actual rate.
	$samplerate //= 44100;

	my $attack_end = $attack * $samplerate;
	my $decay_end = $attack_end + $decay * $samplerate;
	my $decay_length = $decay_end-$attack_end;

    my ($left,$right) = @$sample;
    my @data_l = (0) x @$left;
    my @data_r = (0) x @$left;
    for my $i (0 .. $#$left) {
        last if $i >= $attack_end && $i >= $decay_end;
        my $scale = $i < $attack_end ? $i/$attack_end : 1 - ($i-$attack_end)/$decay_length;
        $data_l[$i] = $left->[$i] * $scale;
        $data_r[$i] = $right->[$i] * $scale;
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
