package MiniSequencer::Tk;
use strict;
use warnings;
use Tk;
use Tk::Spinbox;
use MiniSequencer;
sub new {
    my ($class,%args)=@_;
    die 'parent, play and stop callbacks required' unless $args{parent} && ref($args{play}) eq 'CODE' && ref($args{stop}) eq 'CODE';
    my $self=bless {model=>MiniSequencer->new(rng=>$args{rng}),play=>$args{play},stop=>$args{stop},root=>$args{root}||sub{48},tempo=>120,token=>0,running=>0,status=>'Stopped'},$class;
    my $frame=$self->{widget}=$args{parent}->Frame(-relief=>'groove',-borderwidth=>2);
    $frame->Label(-text=>'Mini sequencer — find a pattern by ear')->pack;
    my $transport=$frame->Frame->pack;
    $self->{randomise}=$transport->Button(-text=>'Randomise & Play',-command=>sub{$self->randomise})->pack(-side=>'left');
    $self->{play_button}=$transport->Button(-text=>'Play',-command=>sub{$self->start})->pack(-side=>'left');
    $self->{stop_button}=$transport->Button(-text=>'Stop',-command=>sub{$self->stop})->pack(-side=>'left');
    $transport->Label(-text=>'BPM')->pack(-side=>'left');
    $self->{tempo_entry}=$transport->Spinbox(-from=>40,-to=>240,-width=>4,-textvariable=>\$self->{tempo})->pack(-side=>'left');
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
sub widget { return $_[0]{widget}; }
sub refresh {
    my $self=shift;
    for my $i (0..15) {
        $self->{buttons}[$i]->configure(-text=>($i+1).' '.$self->{model}->label($i,$self->{root}->()),
            -relief=>($self->{running} && defined $self->{current} && $self->{current}==$i ? 'sunken':'raised'));
    }
}
sub stop {
    my $self=shift;
    $self->{running}=0; $self->{token}++;
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
    $self->_tick($self->{token});
}
sub randomise { my $self=shift; $self->{model}->randomise; $self->start; }
sub _tick {
    my ($self,$token)=@_;
    return unless $self->{running} && $self->{token}==$token;
    my $ok=eval {
        $self->{stop}->();
        my $frequency=$self->{model}->frequency($self->{current},$self->{root}->());
        $self->{play}->($frequency) if defined $frequency;
        $self->{status}='Playing step '.($self->{current}+1).' / 16';
        $self->refresh;
        # Sixteenth-note timing; changes to BPM take effect on the next tick.
        die 'Choose a tempo from 40 to 240 BPM' unless $self->{tempo}=~/^\d+$/ && $self->{tempo}>=40 && $self->{tempo}<=240;
        my $delay=int(60000/($self->{tempo}*4));
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
