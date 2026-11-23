package MiniSequencer::Tk;
use strict;
use warnings;
use Tk;
use Tk::Spinbox;
use MiniSequencer;
use Time::HiRes ();
use POSIX qw(ceil);

sub _default_clock {
    my $id = eval { Time::HiRes::CLOCK_MONOTONIC() };
    if (defined $id && defined eval { Time::HiRes::clock_gettime($id) }) {
        return sub { Time::HiRes::clock_gettime($id) };
    }
    if ($^O eq 'MSWin32') {
        require Win32;
        my $previous = Win32::GetTickCount();
        my $elapsed = 0;
        return sub {
            my $now = Win32::GetTickCount();
            # The Windows millisecond counter wraps every 2^32 ticks.
            $elapsed += ($now - $previous) % 4294967296;
            $previous = $now;
            return $elapsed / 1000;
        };
    }
    return \&Time::HiRes::time;
}

sub new {
    my ($class,%args)=@_;
    die 'parent, play and stop callbacks required' unless $args{parent} && ref($args{play}) eq 'CODE' && ref($args{stop}) eq 'CODE';
    my $self=bless {model=>MiniSequencer->new(rng=>$args{rng}),clock=>$args{clock}//_default_clock(),play=>$args{play},stop=>$args{stop},octave=>$args{octave}//3,tempo=>120,token=>0,running=>0,status=>'Stopped'},$class;
    die 'clock must be a callback' unless ref($self->{clock}) eq 'CODE';
    die 'Octave must be 0..7' unless $self->{octave} =~ /\A[0-7]\z/;
    my $frame=$self->{widget}=$args{parent}->Frame(-relief=>'groove',-borderwidth=>2);
    $frame->Label(-text=>'Mini sequencer — find a pattern by ear')->pack;
    my $transport=$frame->Frame->pack;
    $self->{randomise}=$transport->Button(-text=>'Randomise & Play',-command=>sub{$self->randomise})->pack(-side=>'left');
    $self->{play_button}=$transport->Button(-text=>'Play',-command=>sub{$self->start})->pack(-side=>'left');
    $self->{stop_button}=$transport->Button(-text=>'Stop',-command=>sub{$self->stop})->pack(-side=>'left');
    $transport->Label(-text=>'BPM')->pack(-side=>'left');
    $self->{tempo_entry}=$transport->Spinbox(-from=>40,-to=>240,-width=>4,-textvariable=>\$self->{tempo})->pack(-side=>'left');
    $transport->Label(-text=>'Octave')->pack(-side=>'left');
    $self->{octave_down}=$transport->Button(-text=>'Octave -',-command=>sub{$self->shift_octave(-1)})->pack(-side=>'left');
    $transport->Label(-textvariable=>\$self->{octave})->pack(-side=>'left');
    $self->{octave_up}=$transport->Button(-text=>'Octave +',-command=>sub{$self->shift_octave(1)})->pack(-side=>'left');
    my $scale=$self->{model}->scale;
    $transport->Optionmenu(-variable=>\$scale,-options=>MiniSequencer->scales,-command=>sub{$self->{model}->scale($scale)})->pack(-side=>'left');
    my $steps=$frame->Frame->pack;
    for my $i (0..15) {
        my $index=$i;
        my $button=$steps->Button(-width=>5,-command=>sub{$self->{model}->toggle($index);$self->refresh});
        $button->grid(-row=>int($i/8),-column=>$i%8);
        push @{$self->{buttons}},$button;
    }
    $frame->Label(-textvariable=>\$self->{status})->pack;
    $frame->OnDestroy(sub{$self->{destroying}=1; $self->stop});
    $self->refresh; return $self;
}
sub _root { return ($_[0]{octave}+1)*12; }
sub shift_octave {
    my ($self,$direction)=@_;
    my $next=$self->{octave}+$direction;
    return if $next<0 || $next>7;
    $self->{octave}=$next;
    # Keep the pattern and transport; the next step uses the new register.
    $self->refresh;
}
sub widget { return $_[0]{widget}; }
sub refresh {
    my $self=shift;
    $self->{octave_down}->configure(-state=>$self->{octave}==0?'disabled':'normal');
    $self->{octave_up}->configure(-state=>$self->{octave}==7?'disabled':'normal');
    for my $i (0..15) {
        $self->{buttons}[$i]->configure(-text=>($i+1).' '.$self->{model}->label($i,$self->_root),
            -relief=>($self->{running} && defined $self->{current} && $self->{current}==$i ? 'sunken':'raised'));
    }
}
sub stop {
    my $self=shift;
    $self->{running}=0; $self->{token}++;
    delete $self->{next_step_at};
    if(my $timer=delete $self->{timer}) { eval{$self->{widget}->afterCancel($timer)}; }
    $self->{stop}->(); $self->{status}='Stopped';
    if(!$self->{destroying} && Tk::Exists($self->{widget})) {$self->refresh;}
}
sub start {
    my $self=shift;
    $self->stop;
    unless($self->{tempo}=~/^\d+$/ && $self->{tempo}>=40 && $self->{tempo}<=240) {
        $self->{status}='Choose a tempo from 40 to 240 BPM'; return;
    }
    $self->{running}=1; $self->{current}=0;
    $self->{next_step_at}=$self->{clock}->();
    $self->_tick($self->{token});
}
sub randomise { my $self=shift; $self->{model}->randomise; $self->start; }
sub _tick {
    my ($self,$token)=@_;
    return unless $self->{running} && $self->{token}==$token;
    my $ok=eval {
        $self->{stop}->();
        my $frequency=$self->{model}->frequency($self->{current},$self->_root);
        $self->{play}->($frequency) if defined $frequency;
        $self->{status}='Playing step '.($self->{current}+1).' / 16';
        $self->refresh;
        # Sixteenth-note timing; changes to BPM take effect on the next tick.
        die 'Choose a tempo from 40 to 240 BPM' unless $self->{tempo}=~/^\d+$/ && $self->{tempo}>=40 && $self->{tempo}<=240;
        return unless $self->{running} && $self->{token}==$token;
        my $period=60/($self->{tempo}*4);
        my $now=$self->{clock}->();
        my $next=$self->{next_step_at}+$period;
        # Keep fractional deadlines: callback work and Tk's millisecond rounding
        # must not accumulate into a slower tempo. After a missed deadline,
        # rebase rather than firing catch-up notes back-to-back.
        $next=$now+$period if $next<=$now;
        $self->{next_step_at}=$next;
        my $delay=ceil(($next-$now)*1000);
        $self->{timer}=$self->{widget}->after($delay,sub {
            return unless $self->{running} && $self->{token}==$token;
            $self->{current}=($self->{current}+1)%16;
            $self->_tick($token);
        });
        1;
    };
    unless($ok) { my $error=$@; $self->stop; $self->{status}='Playback stopped: '.$error; }
}
1;
