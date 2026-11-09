package FMPatchExplorer::Tk;
use strict;
use warnings;
use Tk;
use FMPatchExplorer;
sub new {
    my ($class,%args)=@_;
    die 'parent, patch and preview required' unless $args{parent} && $args{patch} && $args{preview};
    my $self=bless {manager=>$args{manager}||FMPatchExplorer->new,patch=>$args{patch},preview=>$args{preview},
        recover=>$args{recover},before=>$args{before},context=>$args{context},family=>'Pluck',wildness=>20,
        status=>'Choose a family, then New sound. Like this sets the starting point for variations.'},$class;
    my $frame=$self->{widget}=$args{parent}->Frame(-relief=>'groove',-borderwidth=>2);
    $frame->Label(-text=>'Musical FM explorer')->pack;
    my $options=$frame->Frame->pack;
    $options->Optionmenu(-variable=>\$self->{family},-options=>FMPatchExplorer->families)->pack(-side=>'left');
    $options->Scale(-label=>'Wildness',-from=>0,-to=>100,-orient=>'horizontal',-length=>140,-variable=>\$self->{wildness})->pack(-side=>'left');
    for my $item (['New sound','new_sound'],['Like this','keep'],['Variation','variation'],['Undo','undo']) {
        my ($label,$action)=@$item;
        $self->{buttons}{$action}=$options->Button(-text=>$label,-command=>sub{$self->run($action)})->pack(-side=>'left');
    }
    $self->{buttons}{undo}->configure(-state=>'disabled');
    $frame->Label(-textvariable=>\$self->{status},-wraplength=>850)->pack;
    return $self;
}
sub widget { return $_[0]{widget}; }
sub run {
    my ($self,$action)=@_;return if $self->{busy};local $self->{busy}=1;
    $_->configure(-state=>'disabled') for values %{$self->{buttons}};
    my $patch;
    my $ok=eval {
        $patch=$self->{patch}->();die 'Choose a patch first' unless $patch;
        $self->{before}->() if $self->{before} && $action ne 'keep';
        my %context=$self->{context}?%{$self->{context}->()}:();
        if($action eq 'new_sound') {
            $self->{manager}->new_sound($patch,%context,family=>$self->{family},wildness=>$self->{wildness},preview=>$self->{preview});
            $self->{status}=$self->{family}.' sound generated. Like this, or try another.';
        } elsif($action eq 'keep') {
            $self->{manager}->keep($patch);$self->{status}='Variation starting point set. The patch is not saved to disk.';
        } elsif($action eq 'variation') {
            $self->{manager}->variation($patch,preview=>$self->{preview});$self->{status}='Gentle variation: ratios and structure preserved.';
        } elsif($action eq 'undo') {
            my $changed=$self->{manager}->undo($patch,preview=>$self->{preview});$self->{status}=$changed?'Previous sound restored.':'Nothing to undo for this patch.';
        } else {die 'Unknown explorer action';}
        1;
    };
    unless($ok) {
        my $error=$@;
        eval{$self->{recover}->()} if $self->{recover};
        $self->{status}='Sound unchanged: '.$error;
    }
    $_->configure(-state=>'normal') for values %{$self->{buttons}};
    $self->{buttons}{undo}->configure(-state=>'disabled') unless $patch && $self->{manager}->can_undo($patch);
    return $ok?1:0;
}
1;
