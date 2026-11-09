package SuperSpinbox;
use strict;
use warnings;
use Tk;
use Tk::Trace;
use SuperSpinbox::Value;

# Small reusable control; the returned object's widget fits in Tk::Table or pack/grid.
sub new {
    my ($class, %args) = @_;
    die 'parent and scalar variable are required' unless $args{parent} && ref($args{variable}) eq 'SCALAR';
    my $self = bless { variable => $args{variable}, command => $args{command}, digits => [] }, $class;
    $self->{model} = SuperSpinbox::Value->new(%args, value => ${$args{variable}});
    my $frame = $self->{widget} = $args{parent}->Frame(-relief => 'groove', -borderwidth => 1);
    my $column = 0;
    $self->{sign} = $frame->Button(-text => '+', -width => 1, -command => sub { $self->_change(sub { $self->{model}->negate }) });
    $self->{sign}->grid(-row => 1, -column => $column++);
    for (my $place = $self->{model}{integers} - 1; $place >= -$self->{model}{places}; $place--) {
        if ($place == -1) { $frame->Label(-text => '.')->grid(-row => 1, -column => $column++); }
        my $exponent = $place;
        my $up = $frame->Button(-text => '+', -width => 1, -command => sub { $self->step($exponent, 1) });
        my $digit = $frame->Label(-text => '0', -width => 1, -font => 'TkFixedFont');
        my $down = $frame->Button(-text => '-', -width => 1, -command => sub { $self->step($exponent, -1) });
        $up->grid(-row => 0, -column => $column);
        $digit->grid(-row => 1, -column => $column);
        $down->grid(-row => 2, -column => $column++);
        push @{$self->{digits}}, $digit;
        $self->{up}{$exponent} = $up; $self->{down}{$exponent} = $down;
        for my $button ($up, $down) {
            $button->bind('<Up>' => sub { $self->step($exponent, 1); Tk->break });
            $button->bind('<Down>' => sub { $self->step($exponent, -1); Tk->break });
        }
    }
    my $entry = $self->{entry} = $frame->Entry(-width => $column + 2, -textvariable => \$self->{typed});
    $entry->grid(-row => 3, -column => 0, -columnspan => $column, -sticky => 'ew');
    $entry->bind('<Return>' => sub { $self->set($self->{typed}) });
    $entry->bind('<FocusOut>' => sub { $self->set($self->{typed}) });
    $entry->bind('<Escape>' => sub { $self->refresh });
    $frame->traceVariable($self->{variable}, 'w', sub {
        my $value = $_[1];
        $self->refresh($value) unless $self->{writing};
        return $value;
    });
    $frame->OnDestroy(sub { $self->{writing} = 1; $frame->traceVdelete($self->{variable}) });
    $self->refresh;
    return $self;
}
sub widget { return $_[0]{widget}; }
sub refresh {
    my ($self, $value) = @_;
    $value = ${$self->{variable}} unless defined $value;
    return 0 unless eval { $self->{model}->set($value); 1 };
    my $formatted = $self->{model}->formatted;
    $self->{sign}->configure(-text => substr($formatted, 0, 1));
    my @digits = substr($formatted, 1) =~ /(\d)/g;
    for my $i (0 .. $#digits) { $self->{digits}[$i]->configure(-text => $digits[$i]); }
    $self->{typed} = $self->{model}->value;
    $self->{entry}->configure(-background => 'white');
    return 1;
}
sub _change {
    my ($self, $operation) = @_;
    my $before = ${$self->{variable}};
    unless (eval { $self->{model}->set($before); $operation->(); 1 }) {
        $self->{entry}->configure(-background => '#ffdddd');
        return 0;
    }
    my $value = $self->{model}->value;
    { local $self->{writing} = 1; ${$self->{variable}} = $value; }
    $self->refresh($value);
    $self->{command}->($value) if $value != $before && $self->{command};
    return 1;
}
sub set { my ($self, $value) = @_; return $self->_change(sub { $self->{model}->set($value) }); }
sub step { my ($self, $place, $direction) = @_; return $self->_change(sub { $self->{model}->step($place, $direction) }); }
1;
