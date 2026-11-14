package WavExport::Tk;
use strict;
use warnings;
use WavExport;
sub new {
    my ($class, %args) = @_;
    die 'parent and capture callback required' unless $args{parent} && $args{capture};
    return bless \%args, $class;
}
sub export {
    my $self = shift;
    my $path = $self->{choose_save} ? $self->{choose_save}->() : $self->{parent}->getSaveFile(
        -title => 'Export reference-note sound (not sequencer or playback chords)',
        -defaultextension => '.wav', -initialfile => 'sound.wav',
        -filetypes => [['WAV audio', '.wav'], ['All files', '*']]);
    return 0 unless defined($path) && length($path);
    my $ok = eval {
        my ($synth, $patch) = $self->{capture}->();
        WavExport->export_patch($path, $synth, $patch);
        1;
    };
    unless ($ok) {
        my $message = 'WAV export failed; any previous file was kept. ' . $@;
        if ($self->{error}) { $self->{error}->($message); }
        else { $self->{parent}->messageBox(-title=>'WAV export', -message=>$message, -type=>'OK', -icon=>'error'); }
        return 0;
    }
    return 1;
}
1;
