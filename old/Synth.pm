package Synth;

	use Moose; # automatically turns on strict and warnings

	has 'samplerate'	=> ( is => 'rw', isa => 'Int', default => 44100 );
	has 'bits'			=> ( is => 'rw', isa => 'Int', default => 8 );
	has 'channels'		=> ( is => 'rw', isa => 'Int', default => 2 );
	
	has 'frequency'		=> ( is => 'rw', isa => 'Num', required => 1 );
	has 'length'		=> ( is => 'rw', isa => 'Num', required => 1 );		# seconds
	has 'volume'		=> ( is => 'rw', isa => 'Num', default => 1 );		# 0..1
	#has 'pan'			=> ( is => 'rw', isa => 'Num', default => 1 );		# -1..1
	
sub render {
	my ($self) = @_;
	 
	my $data = ""; 
	my $counter = 0;
	my $increment = $self->frequency/$self->samplerate;

	# Generate samples
	for my $i (1..($self->samplerate * $self->length) ) {

		# Calculate the pitch
		# (range 0..255 for 8 bits)
		my $v = sin($counter*2*3.14) * 127 + 128;

		if( $self->volume < 1 ) {
			$v = $v * $self->volume;
		}
		
		my $v_left = $v;
		my $v_right = $v;
		
		$data .= pack("CC", $v_left, $v_right);	# "pack" it twice for left and right

		$counter += $increment;
	}
	 
	return $data;
}
  
# around 'profit' => sub {
	# my $orig = shift;
	# my $self = shift;
		  
	# return $self->sell_price * $self->shares - ($self->buy_price * $self->shares) - ($self->transactionCost * 2);
# };
  
return 1;