package Synth;

	use Moose; # automatically turns on strict and warnings
	
	use Time::HiRes qw( time );
	use Data::Dumper;
	use MIDI::Pitch qw(name2freq pitch2name name2pitch);

	has 'samplerate'	=> ( is => 'rw', isa => 'Int', default => 44100 );
	has 'bits'			=> ( is => 'rw', isa => 'Int', default => 16 );	# about 16 bit http://www.perlmonks.org/bare/?node_id=476642
	has 'channels'		=> ( is => 'rw', isa => 'Int', default => 2 );

	has 'polyphony'		=> ( is => 'rw', isa => 'Int', default => 32 );

	# the patches (sound definition)
	has 'Patches'	=> ( is => 'rw', isa => 'HashRef[Patch]', required => 1 );

	# the sound channels the waves play through (also contains the rendered wave which can be played again)
	has 'Channels'	=> ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );

	has 'ChannelIndex'		=> ( is => 'rw', isa => 'Int', default => 0 );

	has 'Keys'				=> ( is => 'rw', isa => 'HashRef', default => sub { {} } );

	sub render_patch_as_middle_c {
		my( $self, $patch ) = @_;
		
		my $frequencies;
		
		if( $patch->{chord} ) {
			#$frequencies = [name2freq('f3'), name2freq('a3'), name2freq('c4'), name2freq('e4')]; # FACE FMAJ7
			$frequencies = [name2freq('c3'), name2freq('e3'), name2freq('f3'), name2freq('a3')]; # FACE FMAJ7 but the way I discovered it on the piano
		} else {					
			$frequencies = [name2freq('c3')];
		}
		
		$self->render_patch($patch, $frequencies);		
	}

	sub render_patch {

		my( $self, $patch, $frequencies ) = @_;	
		
		print "rendering $patch->{name}...\n";

		my $start = time();

		my $sample;
		if( scalar @{$frequencies} == 1 ) {

			print $frequencies->[0];

			$sample = $patch->render( $frequencies->[0], $self->samplerate, $self->bits );
		} else {

			# could run this across lots of CPUs
			my @samples = ();

			foreach my $frequency (@{$frequencies}) {

				print $frequency, "\t";

				$sample = $patch->render( $frequency, $self->samplerate, $self->bits );
				push( @samples, $sample );
			}

			$sample = Patch::mix_samples( \@samples );
		}

		$patch->rendered_sample( $sample );
		$patch->rendered_wave( sample2wav( $sample ) );

		my $end = time();
		printf("time: %.2f\n", $end - $start);
	}

	sub play_patch {

		my( $self, $patch, $vkcode, $frequency, $offset, $length ) = @_;

		if( defined $vkcode && defined $self->Keys->{$vkcode} ) {

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
			# monophonic - stop sound on this channel (also Reset() works here), don't know what's best though
			#$self->Channels->[$self->ChannelIndex]->Pause();

		}
		print "Channel: " . $self->ChannelIndex . " $patch->{name} ";

		my $samplerate = ($self->samplerate / $patch->rendered_frequency) * $frequency;

		$self->Channels->[$self->ChannelIndex] = new Win32::Sound::WaveOut($samplerate, $self->bits, $self->channels);	# http://search.cpan.org/~acalpini/Win32-Sound/Sound.pm

		if( defined $offset || defined $length  ) {
			# we should cache this if offset and length stay the same
			$self->Channels->[$self->ChannelIndex]->Load( sample2wav( $patch->rendered_sample, $offset, $length ) );
		} else {
			$self->Channels->[$self->ChannelIndex]->Load( $patch->{rendered_wave} );
		}

		$self->Channels->[$self->ChannelIndex]->Write();
		if( defined $vkcode ) {
				$self->Keys->{$vkcode} = $self->ChannelIndex;
		}

		print "$patch->{name} ($frequency)\n";

		# reset sound to begining so it is ready to play again, we can also just pause it $WAV->Pause() if $WAV or Unload()
		#$self->Channels->[$channel_number]->Pause();

		#$channel->Reset();	# if we don't reset the sound we have to wait to the end before it can be played again

		# change frequency in real time here to play different pitches
		#$self->Channels->[$channel_number]->CloseDevice();	# have to close or the pitch can't be changed
		#$channel->OpenDevice();
		#1 until $WAV->Status();  			# wait for completion

		#$freq -= 100;
	}

	sub stop_patch {
		my( $self,$vkcode ) = @_;

		if( defined $self->Keys->{$vkcode} ) {

			print "stopping patch $vkcode on channel ".$self->Keys->{$vkcode}."\n";

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

		if( $length ) {

			#print " offset = $offset length = $length ";

			$length = $length + $offset;
		} else {
			$length = scalar @{$sample->[0]};

			#print " length = $length ";
		}

		# I tried packing a whole array here once but got clicks
		my @wav_data = ();

		for( my $i = $offset; $i<$length; $i++ ) {
			push( @wav_data, pack("vv", $sample->[0]->[$i], $sample->[1]->[$i] ) );
		}

		return join('', @wav_data);
	}

return 1;
