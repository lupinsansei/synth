package Sampler;

	use Moose; # automatically turns on strict and warnings	
	use Time::HiRes qw( time );
	use Data::Dumper;
	use MIDI::Pitch qw(name2freq);
	use Audio::Wav;
	use File::Slurp;

	has 'samplerate'	=> ( is => 'rw', isa => 'Int', default => 44100 );
	has 'bits'			=> ( is => 'rw', isa => 'Int', default => 16 );	# about 16 bit http://www.perlmonks.org/bare/?node_id=476642
	has 'channels'		=> ( is => 'rw', isa => 'Int', default => 2 );
	
	has 'directory'		=> ( is => 'rw', isa => 'Str', required => 1 );
	
	has 'polyphony'		=> ( is => 'rw', isa => 'Int', default => 32 );
	
	has 'selected_sample_index'		=> ( is => 'rw', isa => 'Int', default => 0 );
	
	# the patches (sound definition)
	has 'Samples'	=> ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
	has 'Waves'	=> ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
	
	# the sound channels the waves play through (also contains the rendered wave which can be played again)
	has 'Channels'	=> ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );

	has 'ChannelIndex'		=> ( is => 'rw', isa => 'Int', default => 0 );
	
	has 'Keys'				=> ( is => 'rw', isa => 'HashRef', default => sub { {} } );
	
	sub load {
		my( $self ) = @_;

		opendir(DH, $self->directory) or die "Directory Open Error!";

		my @filelist = grep {!-d $self->directory."/$_"} readdir(DH);

		my $i = 0;
		my $filename;
		foreach $filename(@filelist){
		
			eval{

				next unless $filename =~ /\.wav$/i;
				
				print "Sample $i) ".$filename . "...";
				
				$filename = $self->directory."/$filename";
				
				my $sample = $self->load_wav_file($filename);
				
				$self->Samples->[$i] = $sample;
				$self->Waves->[$i] = sample2wav( $sample );
				
				printf( "%d samples ", length $self->Waves->[$i] );
				
				$i++;
				
				print "[Ok]\n";
			};
			warn $@ if $@;		
		}
		
		print "\nready\n";
	}
	
	sub select_sample {
		my( $self, $vkcode, $frequency, $sample_index ) = @_;
		
		$self->selected_sample_index($sample_index);
		
		$self->play_patch($vkcode, $frequency );
	}
	
	sub play_patch {

		my( $self, $vkcode, $frequency, $offset, $length ) = @_;
		
		if( defined $self->Keys->{$vkcode} ) {
		
			# sample already triggered from this key - don't retrigger it
			return;
		}
		
		# get channel to use if this channel is in use
		if( $self->Channels->[$self->ChannelIndex] && !$self->Channels->[$self->ChannelIndex]->Status() ) {
					
			# polyphonic - use  next channel
			$self->ChannelIndex($self->ChannelIndex + 1 );
			if( $self->ChannelIndex > $self->polyphony ) {
				$self->ChannelIndex(0);
			}			
		}
			
		my $samplerate = ($self->samplerate / name2freq('c3') ) * $frequency;
		
		$self->Channels->[$self->ChannelIndex] = new Win32::Sound::WaveOut($samplerate, $self->bits, $self->channels);
		
		#if( defined $offset || defined $length  ) {
			# we should cache this if offset and length stay the same
		#	$self->Channels->[$self->ChannelIndex]->Load( sample2wav( $self->Patches->{$patch}->rendered_sample, $offset, $length ) );				
		#} else {

			$self->Channels->[$self->ChannelIndex]->Load( $self->Waves->[$self->selected_sample_index] );
		#}		
				
		$self->Channels->[$self->ChannelIndex]->Write();
		$self->Keys->{$vkcode} = $self->ChannelIndex;	
	}
	
	sub stop_patch {
		my( $self,$vkcode ) = @_;
		
		if( defined $self->Keys->{$vkcode} ) {
		
			#print "stopping patch $vkcode on channel ".$self->Keys->{$vkcode}."\n";
		
			#$self->Channels->[$self->Keys->{$vkcode}]->Pause();	
			$self->Channels->[$self->Keys->{$vkcode}]->Pause();	# pause isn't clicky whereas reset is
			#$self->Channels->[$self->Keys->{$vkcode}]->Reset();	# clicky but Status() doesn't work above otherwise 
			delete $self->Keys->{$vkcode};			
		}
		
	}
	
	sub sample2wav {

		# turn our raw sample format (left and right array of values) into a Wave file (string) suitable for playing
	
		my( $sample, $offset, $length ) = @_;

		$offset = 0 unless $offset;
		
		# "pack" it twice for left and right
		
		my $wav_data = "";
		
		if( $length ) {
		
			print " offset = $offset length = $length ";
		
			$length = $length + $offset;
		} else {
			$length = scalar @{$sample->[0]};
			
			#print " length = $length ";
		}
		
		
		for( my $i = $offset; $i<$length; $i++ ) {
		
			my $left_value = $sample->[0]->[$i] ? $sample->[0]->[$i] : 0;
			my $right_value = $sample->[1]->[$i] ?  $sample->[1]->[$i] : 0;
		
			$wav_data .= pack("vv", int($left_value), int($right_value) );
		}
		
		return $wav_data;
	}
	
	sub load_wav_file {

		my( $self, $file ) = @_;

		# open the wav file and get the samples	into our format of 2 arrays of left and right	
		my $wav = new Audio::Wav;
		my $read = $wav->read($file);

		my $samples = $read->length_samples();

		my @data_l = ();
		my @data_r = ();
		
		my $found_start = 0;
		my $start_threshold = 0;	# autotrim? does it work?
		my $max_value = 0;
		
		my $channels = -1;
					
		for( my $i=0; $i <$samples; $i++) {
		
			my @channels = $read->read();
			
			if( $channels == -1 ) {
				$channels = scalar @channels;
				print " channels=$channels ";
			}
			
			my $left_value = 0;
			my $right_value = 0;
			if( $channels == 1 ) {
				#mono
				$left_value = $channels[0];
				$right_value = $channels[0];
				
			} else {
				#stereo
				$left_value = $channels[0];
				$right_value = $channels[1];
				
			}

			# stereo
			if( !$found_start && ($left_value > $start_threshold || $right_value > $start_threshold) ) {
				$found_start = 1;
			}
				
			if( $found_start ) {
				$data_l[$i] = $left_value;
				$data_r[$i] = $right_value;
			}
			
			if( $left_value > $max_value ) {
				$max_value = $left_value;
			}
			
			if( $right_value > $max_value ) {
				$max_value = $right_value;
			}
		}
		
		if( $max_value < 128 ) {
			# 8 bit sample
			print " 8bit ";
			
			for( my $i=0; $i<scalar @data_l; $i++ ) {
				if( defined $data_l[$i] ) {
					$data_l[$i]*= 256;
				}
			}
			
			for( my $i=0; $i<scalar @data_r; $i++ ) {
				if( defined $data_r[$i] ) {
					$data_r[$i]*= 256;
				}
			}
			
		}
			
		return [ \@data_l, \@data_r ];
	}
		
 
return 1;