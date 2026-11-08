package Synth;

    use FindBin;
    use lib "$FindBin::Bin/lib";
    use ChordMemory qw(chord_frequencies);
    use Scalar::Util qw(refaddr);

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

    has 'chord_memory' => (is => 'rw', isa => 'Bool', default => 0);
    has 'chord_type' => (is => 'rw', isa => 'Str', default => 'Major 7th');

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

			#print $frequencies->[0];

			$sample = $patch->render( $frequencies->[0], $self->samplerate, $self->bits );
		} else {

			# could run this across lots of CPUs
			my @samples = ();

			foreach my $frequency (@{$frequencies}) {

				#print $frequency, "\t";

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
        my ($self, $patch, $vkcode, $frequency, $offset, $length) = @_;
        return if defined $vkcode && exists $self->Keys->{$vkcode}; # held-key repeat
        my $frequencies = chord_frequencies($frequency, $self->chord_memory, $self->chord_type);
        my @handles;
        my $ok = eval {
            for my $note (@$frequencies) {
                push @handles, $self->_play_single($patch, $note, $offset, $length);
            }
            1;
        };
        unless ($ok) {
            my $error = $@;
            eval { $self->_release_voices(\@handles) };
            die $error;
        }
        # Remember the actual handles, not slot numbers: a completed slot may be
        # reused by another key before this key is released.
        $self->Keys->{$vkcode} = \@handles if defined $vkcode;
        return \@handles;
    }

    sub _play_single {
        my ($self, $patch, $frequency, $offset, $length) = @_;
        my $index = 0;
        $index++ while $index < @{$self->Channels} && $self->Channels->[$index] && !$self->Channels->[$index]->Status();
        # Grow as necessary instead of wrapping over active chord notes.
        $self->ChannelIndex($index);
        my $rate = ($self->samplerate / $patch->rendered_frequency) * $frequency;
        my $wave = Win32::Sound::WaveOut->new($rate, $self->bits, $self->channels);
        if (defined $offset || defined $length) {
            $wave->Load(sample2wav($patch->rendered_sample, $offset, $length));
        } else {
            $wave->Load($patch->{rendered_wave});
        }
        $wave->Write();
        $self->Channels->[$index] = $wave;
        return $wave;
    }

    sub stop_patch {
        my ($self, $vkcode) = @_;
        return unless defined $vkcode;
        my $handles = delete $self->Keys->{$vkcode};
        return unless $handles;
        # Preset/toggle changes affect the next note, not which held voices stop.
        $self->_release_voices($handles);
    }

    sub _release_voices {
        my ($self, $handles) = @_;
        my $error;
        for my $wave (@$handles) {
            eval { $wave->Pause(); 1 } or $error ||= $@;
            # Paused WaveOut handles need not report Status=finished. Free their
            # slots explicitly, but never remove a different note that reused one.
            for my $i (0 .. $#{$self->Channels}) {
                my $current = $self->Channels->[$i];
                $self->Channels->[$i] = undef if $current && refaddr($current) == refaddr($wave);
            }
        }
        die $error if $error;
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
