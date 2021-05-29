package Synth;

	use Moose; # automatically turns on strict and warnings
	
	use Time::HiRes qw( time );
	use Data::Dumper;

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

	# renders the patch by name - really we should pass in a patch object instead
	sub render_patch {

		my( $self, $patch_name, $frequencies ) = @_;

		print "rendering $patch_name...\n";

		my $start = time();

		my $sample;
		if( scalar @{$frequencies} == 1 ) {

			print $frequencies->[0];

			$sample = $self->Patches->{$patch_name}->render( $frequencies->[0], $self->samplerate, $self->bits );
		} else {

			# could run this across lots of CPUs
			my @samples = ();

			foreach my $frequency (@{$frequencies}) {

				print $frequency, "\t";

				$sample = $self->Patches->{$patch_name}->render( $frequency, $self->samplerate, $self->bits );
				push( @samples, $sample );
			}

			$sample = Patch::mix_samples( \@samples );
		}

		$self->Patches->{$patch_name}->rendered_sample( $sample );
		$self->Patches->{$patch_name}->rendered_wave( sample2wav( $sample ) );

		my $end = time();
		printf("time: %.2f\n", $end - $start);
	}

	sub play_patch {

		my( $self, $patch_name, $vkcode, $frequency, $offset, $length ) = @_;

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
		print "Channel: " . $self->ChannelIndex . " $patch_name ";

		my $samplerate = ($self->samplerate / $self->Patches->{$patch_name}->rendered_frequency) * $frequency;

		$self->Channels->[$self->ChannelIndex] = new Win32::Sound::WaveOut($samplerate, $self->bits, $self->channels);	# http://search.cpan.org/~acalpini/Win32-Sound/Sound.pm

		if( defined $offset || defined $length  ) {
			# we should cache this if offset and length stay the same
			$self->Channels->[$self->ChannelIndex]->Load( sample2wav( $self->Patches->{$patch_name}->rendered_sample, $offset, $length ) );
		} else {
			$self->Channels->[$self->ChannelIndex]->Load( $self->Patches->{$patch_name}->{rendered_wave} );
		}

		$self->Channels->[$self->ChannelIndex]->Write();
		if( defined $vkcode ) {
				$self->Keys->{$vkcode} = $self->ChannelIndex;
		}

		print "$patch_name ($frequency)\n";

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

		my $wav_data = "";

		if( $length ) {

			print " offset = $offset length = $length ";

			$length = $length + $offset;
		} else {
			$length = scalar @{$sample->[0]};

			print " length = $length ";
		}


		for( my $i = $offset; $i<$length; $i++ ) {
			$wav_data .= pack("vv", int($sample->[0]->[$i]), int($sample->[1]->[$i]) );
		}

		return $wav_data;
	}

return 1;
