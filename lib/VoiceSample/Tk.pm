package VoiceSample::Tk;
use strict;
use warnings;
use Tk;
use File::Basename qw(basename dirname);
use VoiceSample;

sub new {
    my ($class, %args) = @_;
    die 'parent, voice, patch, synth and render required' unless $args{parent} && $args{voice} && $args{patch} && $args{synth} && $args{render};
    my $self = bless \%args, $class;
    my $frame = $self->{widget} = $args{parent}->Frame;
    $self->{wave} = $args{voice}->wave;
    $self->{menu} = $frame->Optionmenu(-variable=>\$self->{wave}, -options=>[qw(sine noise file)],
        -command=>sub { $self->change_wave })->pack(-fill=>'x');
    $self->{file_frame} = $frame->Frame;
    $self->{choose_button} = $self->{file_frame}->Button(-text=>'Choose WAV...', -command=>sub { $self->choose })->pack(-fill=>'x');
    $self->{file_frame}->Label(-textvariable=>\$self->{filename}, -width=>18, -anchor=>'w')->pack(-fill=>'x');
    $self->refresh;
    return $self;
}
sub widget { return $_[0]{widget}; }
sub refresh {
    my $self = shift;
    $self->{wave} = $self->{voice}->wave;
    my $name = length($self->{voice}->file) ? basename($self->{voice}->file) : 'No WAV chosen';
    $self->{filename} = length($name) > 18 ? substr($name,0,6).'...'.substr($name,-9) : $name;
    if ($self->{wave} eq 'file') { $self->{file_frame}->pack(-fill=>'x'); }
    else { $self->{file_frame}->packForget; }
}
sub _path {
    my $self = shift;
    return $self->{choose_open}->() if $self->{choose_open};
    my %initial;
    my $old = $self->{voice}->file;
    %initial = (-initialdir=>dirname($old), -initialfile=>basename($old)) if length($old) && -d dirname($old);
    return $self->{parent}->getOpenFile(-title=>'Choose WAV sample',
        -filetypes=>[['WAV audio','.wav'],['All files','*']], %initial);
}
sub _apply {
    my ($self, $wave, $path) = @_;
    my $synth = ref($self->{synth}) eq 'CODE' ? $self->{synth}->() : $self->{synth};
    return VoiceSample->apply(voice=>$self->{voice}, patch=>$self->{patch}, synth=>$synth,
        wave=>$wave, path=>$path, before=>$self->{before}, render=>$self->{render});
}
sub _run {
    my ($self, $operation) = @_;
    return 0 if $self->{busy};
    local $self->{busy} = 1;
    my $result;
    my $ok = eval { $result = $operation->(); 1; };
    my $error = $@;
    $self->refresh;
    unless ($ok) {
        eval { $self->{recover}->() } if $self->{recover};
        my $message = 'Sample change failed; the previous sound was kept. '.$error;
        if ($self->{error}) { $self->{error}->($message); }
        else { $self->{parent}->messageBox(-title=>'WAV sample', -message=>$message, -type=>'OK', -icon=>'error'); }
        return 0;
    }
    return $result;
}
sub choose {
    my $self = shift;
    return $self->_run(sub {
        my $path = $self->_path;
        return 0 unless defined($path) && length($path);
        return $self->_apply('file',$path);
    });
}
sub change_wave {
    my $self = shift;
    my $wave = $self->{wave};
    return $self->_run(sub {
        my $path = $self->{voice}->file;
        if ($wave eq 'file' && (!length($path) || !-f $path)) {
            $path = $self->_path;
            return 0 unless defined($path) && length($path);
        }
        return $self->_apply($wave,$path);
    });
}
1;
