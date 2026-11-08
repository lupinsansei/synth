package PatchBank::Tk;
use strict;
use warnings;
use Tk;
use PatchBank;
sub new {my($class,%args)=@_;die 'parent, capture and apply callbacks required' unless $args{parent} && $args{capture} && $args{apply};return bless \%args,$class;}
sub current_file {return $_[0]{path};}
sub _error {
 my($self,$message)=@_;
 if($self->{error}) {$self->{error}->($message);}
 else {$self->{parent}->messageBox(-title=>'Patch bank',-message=>$message,-type=>'OK',-icon=>'error');}
}
sub save_as {
 my $self=shift;
 my $path=$self->{choose_save}?$self->{choose_save}->():$self->{parent}->getSaveFile(-title=>'Save patch bank',-defaultextension=>'.synth.json',-initialfile=>'patch-bank.synth.json',-filetypes=>[['Synth JSON bank',['.synth.json','.json']],['All files','*']]);
 return 0 unless defined $path && length $path;
 return $self->_save($path);
}
sub save {my $self=shift;return $self->{path}?$self->_save($self->{path}):$self->save_as;}
sub _save {
 my($self,$path)=@_;
 my $ok=eval{my($synth,$selected)=$self->{capture}->();PatchBank->save_file($path,$synth,selected_patch=>$selected);1};
 unless($ok) {$self->_error('Save failed; your previous file was kept. '.$@);return 0;}
 $self->{path}=$path;return 1;
}
sub open {
 my($self,%args)=@_;
 my $path=$self->{choose_open}?$self->{choose_open}->():$self->{parent}->getOpenFile(-title=>$args{legacy}?'Import old JSON dump':'Open patch bank',-filetypes=>[['Synth JSON bank',['.synth.json','.json']],['All files','*']]);
 return 0 unless defined $path && length $path;
 my $imported_legacy;
 my $ok=eval{my $bank=PatchBank->read_file($path,legacy=>$args{legacy});$imported_legacy=$bank->{imported_legacy};$self->{apply}->($bank);1};
 unless($ok) {$self->_error('Load failed; the current bank was kept. '.$@);return 0;}
 # Imported old files must be saved under a NEW name, not overwritten automatically.
 $self->{path}=$imported_legacy?undef:$path;return 1;
}
1;
