package Sine;

use Moose;
use CHI::Memoize qw(:all);
	
with 'Voice';
	
sub render {
	my ($self, $samplerate, $bits, $length, $frequency, $left_volume, $right_volume) = @_;
		
	return make_sine_wave( $samplerate, $bits, $length, 
		$frequency * $self->frequency_multiplier, 
		$left_volume * $self->volume_multiplier_left, 
		$right_volume * $self->volume_multiplier_right
	);
}

memoize( 'make_sine_wave', driver => 'File', root_dir => 'c:\Cache', expires_in => '1h' );

sub make_sine_wave {
	my( $samplerate, $bits, $length, $frequency, $left_volume, $right_volume ) = @_;

	my $counter = 0;
	
	my @data_l = (); 
	my @data_r = ();
	
	my $samples = $samplerate * $length;
		
	my $step_size = $frequency/$samplerate;		# would change this in a loop for FM
	
	my $scale = (2**$bits)/2;
	
	for( my $i=0; $i <$samples; $i++) {
		my $v = sin($counter*6.28) * $scale;
						
		$data_l[$i] = $v * $left_volume;
		$data_r[$i] = $v * $right_volume;
		
		$counter += $step_size;	# would use this in a wave table
	}
			
	return [ \@data_l, \@data_r ];
}
  
return 1;