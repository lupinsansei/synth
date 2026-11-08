package MiniSequencer;
use strict;
use warnings;
my %scales = ('Minor pentatonic' => [0,3,5,7,10], 'Minor' => [0,2,3,5,7,8,10], 'Major' => [0,2,4,5,7,9,11]);
sub new {
    my ($class,%args)=@_;
    my $self=bless {rng=>$args{rng}||sub{rand()},scale=>'Minor pentatonic',steps=>[]},$class;
    $self->randomise; return $self;
}
sub scales { return ['Minor pentatonic','Minor','Major']; }
sub scale {
    my ($self,$name)=@_;
    if(defined $name) { die 'Unknown scale' unless exists $scales{$name}; $self->{scale}=$name; }
    return $self->{scale};
}
sub _pick {
    my ($self,$length)=@_;
    my $random=$self->{rng}->();
    die 'Random source must return 0..1 (exclusive)' unless defined $random && $random >= 0 && $random < 1;
    return int($random*$length);
}
sub _note {
    my $self=shift; my $scale=$scales{$self->{scale}};
    return $scale->[$self->_pick(scalar @$scale)] + 12*$self->_pick(2);
}
sub randomise {
    my $self=shift;
    my @steps;
    for my $i (0..15) { push @steps, $i==0 || $self->_pick(5)>0 ? $self->_note : undef; }
    # Keep a usable phrase even if the random generator chooses many rests.
    for my $i (4,8,12) { $steps[$i]=$self->_note unless defined $steps[$i]; }
    $self->{steps}=\@steps;
    return $self->steps;
}
sub steps { return [@{$_[0]{steps}}]; }
sub toggle {
    my ($self,$index)=@_;
    die 'Step out of range' unless defined $index && $index =~ /^\d+$/ && $index<16;
    $self->{steps}[$index]=defined $self->{steps}[$index] ? undef : $self->_note;
}
sub midi {
    my ($self,$index,$root)=@_; $root=48 unless defined $root;
    die 'Step out of range' unless defined $index && $index =~ /^\d+$/ && $index<16;
    die 'Root out of range' unless $root =~ /^\d+$/ && $root<=103;
    return defined $self->{steps}[$index] ? $root+$self->{steps}[$index] : undef;
}
sub frequency { my ($self,$index,$root)=@_; my $note=$self->midi($index,$root); return defined $note ? 440*2**(($note-69)/12) : undef; }
sub label {
    my ($self,$index,$root)=@_; my $note=$self->midi($index,$root);
    return '--' unless defined $note;
    my @names=('C','C#','D','D#','E','F','F#','G','G#','A','A#','B');
    return $names[$note%12].(int($note/12)-1);
}
1;
