package SuperSpinbox;
use strict;
use warnings;
use Tk;
use Tk::Spinbox;
use Tk::Trace;
use SuperSpinbox::Value;

sub new {
    my ($class, %args) = @_;
    die 'parent and scalar variable are required' unless $args{parent} && ref($args{variable}) eq 'SCALAR';
    my $self = bless { variable => $args{variable}, command => $args{command} }, $class;
    my $model = $self->{model} = SuperSpinbox::Value->new(%args, value => ${$args{variable}});
    my $frame = $self->{widget} = $args{parent}->Frame(
        -relief => 'groove', -borderwidth => 2, -padx => 3, -pady => 1,
    );
    my $font = [$frame->fontActual('TkFixedFont', '-family'), 10];
    my $column = 0;
    if ($model->{min} < 0) {
        $self->{sign} = $frame->Spinbox(-width => 1, -values => ['+', '-'], -wrap => 1,
            -font => $font, -state => 'readonly', -command => sub { $self->set(-$model->value) });
        $self->{sign}->grid(-row => 0, -column => $column++);
    }
    for (my $place = $model->{integers}-1; $place >= -$model->{places}; $place--) {
        $frame->Label(-text => '.', -font => $font, -padx => 0)->grid(-row => 0, -column => $column++) if $place == -1;
        my $exponent = $place;
        # The extra endpoints distinguish 9->10 from 0->-1 before refreshing all digits.
        my $spin = $frame->Spinbox(-width => 1, -from => -1, -to => 10, -increment => 1,
            -font => $font, -borderwidth => 1, -justify => 'center', -state => 'readonly',
            -command => sub {
                my $digit = $self->{digits}{$exponent}->get;
                $self->step($exponent, $digit > $self->{shown}{$exponent} ? 1 : -1);
            });
        $self->{digits}{$place} = $spin;
        $spin->grid(-row => 0, -column => $column++);
        # Typing or pasting edits the entire number without adding a second row.
        $spin->bind('<KeyPress>' => sub {
            my $key = $spin->XEvent->A;
            return unless defined($key) && $key =~ /\A[0-9.+-]\z/;
            $self->_edit($key);
            Tk->break;
        });
        $spin->bind('<F2>' => sub { $self->_edit; Tk->break });
        $spin->bind('<Control-v>' => sub { $self->_edit; $self->{entry}->eventGenerate('<<Paste>>'); Tk->break });
        $spin->bind('<Double-Button-1>' => sub {
            return unless $spin->identify($spin->XEvent->x,$spin->XEvent->y) eq 'entry';
            $self->_edit; Tk->break;
        });
        for my $key (qw(BackSpace Delete)) {
            $spin->bind("<$key>" => sub { $self->_edit(''); Tk->break });
        }
    }
    my $entry = $self->{entry} = $frame->Entry(-textvariable => \$self->{typed}, -width => $column, -font => $font);
    $self->{columns} = $column;
    $self->{background} = $entry->cget('-background');
    $entry->bind('<Return>' => sub { $self->_finish(1); Tk->break });
    $entry->bind('<FocusOut>' => sub { $self->_finish(1) });
    $entry->bind('<Escape>' => sub { $self->_finish(0); Tk->break });
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
sub _edit {
    my ($self,$replacement) = @_;
    my $entry = $self->{entry};
    $self->{editing} = 1;
    $entry->grid(-row => 0, -column => 0, -columnspan => $self->{columns}, -sticky => 'nsew');
    $entry->raise;
    $entry->focus;
    if (defined $replacement) {
        $self->{typed} = $replacement;
        $entry->icursor('end');
    } else {
        $entry->selectionRange(0,'end');
    }
}
sub _finish {
    my ($self,$commit) = @_;
    return unless $self->{editing};
    return if $commit && !$self->set($self->{typed});
    delete $self->{editing};
    $self->refresh unless $commit;
    my $entry = $self->{entry};
    my $focus = $entry->focusCurrent;
    $entry->toplevel->focus if $focus && $focus == $entry;
    $entry->gridForget;
}
sub refresh {
    my ($self, $value) = @_;
    $value = ${$self->{variable}} unless defined $value;
    return 0 unless eval { $self->{model}->set($value); 1 };
    my $formatted = $self->{model}->formatted;
    $self->{sign}->set(substr($formatted,0,1)) if $self->{sign};
    my @digits = substr($formatted,1) =~ /(\d)/g;
    my $place = $self->{model}{integers}-1;
    for my $digit (@digits) {
        $self->{shown}{$place} = $digit;
        $self->{digits}{$place--}->set($digit);
    }
    $self->{typed} = $self->{model}->value;
    $self->{entry}->configure(-background => $self->{background});
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
