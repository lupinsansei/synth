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
    has 'chord_mode' => (is => 'rw', isa => 'Str', default => 'Together');
    has 'arpeggio_ms' => (is => 'rw', isa => 'Int', default => 120);

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

		my ($sample,$pcm);
		if( scalar @{$frequencies} == 1 ) {

			#print $frequencies->[0];

			$sample = $patch->render( $frequencies->[0], $self->samplerate, $self->bits, \$pcm );
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

        # Each component render overwrites the patch reference. The mixed
        # sample must transpose from its intended root, not the last chord tone.
        $patch->rendered_frequency($frequencies->[0]);

		$patch->rendered_sample( $sample );
		$patch->rendered_wave( defined($pcm) ? $pcm : sample2wav($sample) );

		my $end = time();
		printf("time: %.2f\n", $end - $start);
	}

    sub play_patch {
        my ($self, $patch, $vkcode, $frequency, $offset, $length) = @_;
        return if defined $vkcode && exists $self->Keys->{$vkcode}; # held-key repeat
        my $frequencies = chord_frequencies($frequency, $self->chord_memory, $self->chord_type);
        die 'Choose Together or Arpeggio' unless $self->chord_mode eq 'Together' || $self->chord_mode eq 'Arpeggio';
        die 'Arpeggio step must be 40..1000 ms' unless $self->arpeggio_ms =~ /\A[0-9]+\z/ && $self->arpeggio_ms >= 40 && $self->arpeggio_ms <= 1000;
        my (@handles, %reserved);
        my $ok = eval {
            for my $i (0..$#$frequencies) {
                my $delay = $self->chord_mode eq 'Arpeggio' ? $i * $self->arpeggio_ms : 0;
                push @handles, $self->_prepare_voice($patch, $frequencies->[$i], $offset, $length, $delay, \%reserved);
            }
            # Opening a device and loading a long buffer can be slow. Prepare
            # EVERY voice first, then submit asynchronous writes back-to-back.
            # Arpeggio offsets live in the buffers, not blocking sleeps/Tk timers.
            $_->Write() for @handles;
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

    sub _prepare_voice {
        my ($self, $patch, $frequency, $offset, $length, $delay_ms, $reserved) = @_;
        my $index = 0;
        $index++ while $reserved->{$index} || ($index < @{$self->Channels} && $self->Channels->[$index] && !$self->Channels->[$index]->Status());
        # Grow as necessary instead of wrapping over active chord notes.
        $self->ChannelIndex($index);
        my $rate = ($self->samplerate / $patch->rendered_frequency) * $frequency;
        my $pcm = defined($offset) || defined($length)
            ? sample2wav($patch->rendered_sample, $offset, $length) : $patch->{rendered_wave};
        # Account for EACH voice's playback rate, so a higher chord tone does
        # not shorten the intended time between arpeggio notes.
        my $silent_frames = int(int($rate) * $delay_ms / 1000 + 0.5);
        $pcm = ("\0" x ($silent_frames * 4)) . $pcm if $silent_frames;
        my $wave = $self->_loaded_wave($rate,$pcm,!defined($offset) && !defined($length) && !$silent_frames);
        $self->Channels->[$index] = $wave;
        $reserved->{$index} = 1;
        return $wave;
    }

    sub _loaded_wave {
        my ($self,$rate,$pcm,$reusable) = @_;
        my $format = join('/', int($rate), $self->bits, $self->channels);
        my $idle = $self->{idle_waves} ||= [];
        my $wave;
        for my $i (0 .. $#$idle) {
            next unless $idle->[$i]{synth_format} eq $format && $idle->[$i]{synth_pcm} eq $pcm;
            ($wave) = splice @$idle, $i, 1;
            last;
        }
        unless ($wave) {
            $wave = eval { Win32::Sound::WaveOut->new($rate, $self->bits, $self->channels) };
            if (!$wave) {
                die $@ unless @$idle;
                @$idle = ();
                $wave = Win32::Sound::WaveOut->new($rate, $self->bits, $self->channels);
            }
            $wave->Load($pcm);
            if ($wave->can('Reset') && $reusable) {
                $wave->{synth_format} = $format;
                $wave->{synth_pcm} = $pcm;
            }
        }
        return $wave;
    }

    sub _keep_idle_wave {
        my ($self,$wave) = @_;
        my $idle = $self->{idle_waves} ||= [];
        shift @$idle if @$idle >= 24;
        push @$idle, $wave;
    }

    sub prepare_notes {
        my ($self,$patch,@frequencies) = @_;
        return unless Win32::Sound::WaveOut->can('Reset');
        my %prepared;
        for my $frequency (@frequencies) {
            next unless defined $frequency;
            my $rate = $self->samplerate / $patch->rendered_frequency * $frequency;
            next if $prepared{int($rate)}++;
            my $wave = eval { $self->_loaded_wave($rate,$patch->{rendered_wave},1) };
            last unless $wave;
            $self->_keep_idle_wave($wave);
        }
    }

    sub stop_patch {
        my ($self, $vkcode) = @_;
        return unless defined $vkcode;
        my $handles = delete $self->Keys->{$vkcode};
        return unless $handles;
        # Preset/toggle changes affect the next note, not which held voices stop.
        $self->_release_voices($handles, 1);
    }

    # Include unkeyed auditions and arpeggio buffers still in their lead-in.
    sub stop_all {
        my ($self) = @_;
        delete $self->{idle_waves};
        my %seen;
        my @handles = grep { $_ && !$seen{refaddr($_)}++ } @{$self->Channels};
        $self->Keys({});
        $self->ChannelIndex(0);
        $self->_release_voices(\@handles);
    }

    sub _release_voices {
        my ($self, $handles, $reuse) = @_;
        my $error;
        for my $wave (@$handles) {
            unless (eval {
                if ($reuse && defined $wave->{synth_format}) {
                    $wave->Reset();
                    $self->_keep_idle_wave($wave);
                } else {
                    $wave->Pause();
                }
                1;
            }) {
                $error ||= $@;
                # Keep a failed handle reachable so another Panic can retry it.
                next;
            }
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

        my ($left_channel,$right_channel) = @$sample;
        my $end = $length ? $offset + $length : scalar @$left_channel;
        my $audio_end = $end;
        # Short notes often occupy only the start of a full render window.
        # Append the trailing stereo silence in one operation.
        --$audio_end while $audio_end > $offset
            && !$left_channel->[$audio_end-1] && !$right_channel->[$audio_end-1];
        my $pcm = '';
        for (my $i = $offset; $i < $audio_end; $i++) {
            # Saturate only at the final 16-bit PCM boundary. Keep raw sample
            # arrays and FM modulators untouched, including their extra headroom.
            my $left = $left_channel->[$i];
            my $right = $right_channel->[$i];
            $left = $left > 32767 ? 32767 : $left < -32768 ? -32768 : $left;
            $right = $right > 32767 ? 32767 : $right < -32768 ? -32768 : $right;
            $pcm .= pack('vv', $left, $right);
		}

        return $pcm . ("\0" x (4 * ($end - $audio_end)));
	}

return 1;
