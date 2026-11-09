package SuperSpinbox::Value;
use strict;
use warnings;
use Math::BigFloat;

sub new {
    my ($class, %args) = @_;
    my $self = bless { places => $args{places} // 4, integers => $args{integers} // 4 }, $class;
    die 'Invalid digit layout' unless $self->{places} =~ /^\d+$/ && $self->{integers} =~ /^\d+$/
        && $self->{places} <= 8 && $self->{integers} >= 1 && $self->{integers} + $self->{places} <= 14;
    $self->{scale} = 10 ** $self->{places};
    my $maximum = 10 ** $self->{integers} * $self->{scale} - 1;
    $self->{min} = defined $args{min} ? $self->_units($args{min}) : -$maximum;
    $self->{max} = defined $args{max} ? $self->_units($args{max}) : $maximum;
    die 'Bounds do not fit digit layout' if $self->{min} < -$maximum || $self->{max} > $maximum || $self->{min} > $self->{max};
    $self->set($args{value} // 0);
    return $self;
}
sub _units {
    my ($self, $value) = @_;
    die 'Enter a finite number' unless defined $value && !ref($value)
        && $value =~ /^\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*$/;
    my $number = Math::BigFloat->new($value)->bmul($self->{scale})->bfround(0);
    die 'Number is too large' if $number->copy->babs->bcmp('99999999999999') > 0;
    return 0 + $number->bstr;
}
sub set {
    my ($self, $value) = @_;
    my $units = $self->_units($value); # validate before changing state
    $self->{units} = $units < $self->{min} ? $self->{min} : $units > $self->{max} ? $self->{max} : $units;
    return $self->value;
}
sub step {
    my ($self, $place, $direction) = @_;
    die 'Invalid digit place' unless defined $place && $place =~ /^-?\d+$/ && $place >= -$self->{places} && $place < $self->{integers};
    die 'Direction must be +1 or -1' unless defined $direction && ($direction == 1 || $direction == -1);
    my $units = $self->{units} + $direction * 10 ** ($place + $self->{places});
    $self->{units} = $units < $self->{min} ? $self->{min} : $units > $self->{max} ? $self->{max} : $units;
    return $self->value;
}
sub negate { my $self = shift; return $self->set(-$self->value); }
sub value { my $self = shift; return $self->{units} / $self->{scale}; }
sub formatted {
    my $self = shift;
    my $abs = abs($self->{units});
    my $whole = sprintf('%0*d', $self->{integers}, int($abs / $self->{scale}));
    my $fraction = $self->{places} ? '.' . sprintf('%0*d', $self->{places}, $abs % $self->{scale}) : '';
    return ($self->{units} < 0 ? '-' : '+') . $whole . $fraction;
}
1;
