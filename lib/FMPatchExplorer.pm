package FMPatchExplorer;
use strict;
use warnings;
use Scalar::Util qw(refaddr looks_like_number);
use Storable qw(dclone);

my %families = (
    Bass => {ratios=>[1,1,2,2,3],index=>[0.25,1.6],attack=>[0.003,0.012],decay=>[0.25,0.7],brightness=>[0.04,0.18]},
    Pluck => {ratios=>[1,2,2,3,4],index=>[0.6,2.6],attack=>[0.002,0.008],decay=>[0.3,1.0],brightness=>[0.025,0.16]},
    Bell => {ratios=>[1.414213562,2.756,3.5],index=>[0.5,2.2],attack=>[0.003,0.02],decay=>[0.8,2.0],brightness=>[0.3,1.2]},
    'Soft keys' => {ratios=>[1,1,2],index=>[0.12,0.7],attack=>[0.01,0.04],decay=>[0.6,1.4],brightness=>[0.15,0.6]},
    Texture => {ratios=>[0.5,1.414213562,2.756,3,7],index=>[0.8,3.5],attack=>[0.03,0.12],decay=>[1.0,2.4],brightness=>[0.4,1.7]},
);
sub new { my ($class,%args)=@_; return bless {rng=>$args{rng}||sub{rand()},states=>{}},$class; }
sub families { return ['Bass','Pluck','Bell','Soft keys','Texture']; }
sub _random {
    my $self=shift; my $r=$self->{rng}->();
    die 'Invalid random source' unless defined $r && $r>=0 && $r<1;
    return $r;
}
sub _between { my ($self,$a,$b)=@_; return $a+($b-$a)*$self->_random; }
sub generate {
    my ($self,%args)=@_;
    my $family=$args{family}//'Pluck'; my $spec=$families{$family} or die 'Unknown sound family';
    my $wild=$args{wildness}//20;
    die 'Wildness must be 0..100' unless looks_like_number($wild) && $wild>=0 && $wild<=100;
    $wild/=100;
    my $root=$args{reference_frequency}//130.81278265;
    my $rate=$args{samplerate}//44100; my $bits=$args{bits}//16;
    die 'Unsupported render format' unless $root>0 && $rate>=8000 && $bits>=8 && $bits<=24;
    my $carrier=($family eq 'Bass' && $self->_random<0.35)?0.5:1;
    my $ratio=$spec->{ratios}[int($self->_random*@{$spec->{ratios}})];
    if($self->_random < $wild*0.35) {
        my @unusual=(1.414213562,2.756,5.01,7.03);
        $ratio=$unusual[int($self->_random*@unusual)];
    }
    $ratio *= $self->_between(0.995,1.005) if $wild>0 && $self->_random<$wild*0.4;
    my $modulator=$carrier*$ratio;
    my $index=$self->_between(@{$spec->{index}})*(0.8+0.8*$wild);
    # In this renderer a modulator emits PCM amplitude directly as Hz deviation.
    # Translate dimensionless FM index I into that amplitude: deviation = I * f_mod.
    # Leave conservative spectral headroom at the reference note (not an anti-alias filter).
    my $mod_hz=$root*$modulator;
    my $headroom=0.4*$rate-$root*$carrier-$mod_hz;
    die 'Reference note too high for this FM ratio' unless $headroom>0;
    my $deviation=$index*$mod_hz;
    $deviation=$headroom if $deviation>$headroom;
    my $amplitude=$deviation/(2**($bits-1));
    my $attack=$self->_between(@{$spec->{attack}});
    my $decay=$self->_between(@{$spec->{decay}});
    # Linked modulation envelope: brighter starts soften as the sound decays.
    my $brightness=$self->_between(@{$spec->{brightness}});
    $brightness=$decay*0.9 if $brightness>$decay*0.9;
    return {length=>$attack+$decay+0.03,attack=>$attack,decay=>$decay,chord=>0,
        voices=>[{wave=>'sine',tuned=>1,freq_multiplier=>$carrier,volume_multiplier=>$self->_between(0.3,0.42),
            freq_decay=>0,volume_decay=>0,delay=>0,
            modulators=>[{wave=>'sine',tuned=>1,freq_multiplier=>$modulator,volume_multiplier=>$amplitude,
                freq_decay=>0,volume_decay=>$amplitude/($rate*$brightness),delay=>0}]}]};
}
sub _voice_snapshot {
    my ($voice)=@_; my %data;
    for my $key(qw(wave file tuned freq_multiplier volume_multiplier freq_decay volume_decay delay)) {
        $data{$key}=$voice->{$key} if defined $voice->{$key};
    }
    $data{modulators}=[map{_voice_snapshot($_)}@{$voice->{modulators}}] if $voice->{modulators};
    return \%data;
}
sub snapshot {
    my ($self,$patch)=@_; my %data;
    for my $key(qw(length attack decay chord)) {$data{$key}=$patch->{$key} if defined $patch->{$key};}
    $data{voices}=[map{_voice_snapshot($_)}@{$patch->voices}];
    return \%data; # No rendered samples, Tk objects, names, or unrelated data.
}
sub _voice {
    my ($data)=@_; require Voice;
    my %args=%$data;
    $args{modulators}=[map{_voice($_)}@{$data->{modulators}}] if $data->{modulators};
    return Voice->new(%args);
}
sub _apply {
    my ($self,$patch,$data)=@_;
    my $voices=[map{_voice($_)}@{$data->{voices}}];
    $patch->voices($voices);
    for my $key(qw(length attack decay chord)) {$patch->$key($data->{$key}//0);}
    delete @{$patch}{qw(rendered_wave rendered_sample rendered_frequency)};
}
sub _state { my ($self,$patch)=@_; return $self->{states}{refaddr($patch)} ||= {history=>[]}; }
sub keep {
    my ($self,$patch)=@_; my $state=$self->_state($patch);
    die 'Sound change already in progress' if $state->{busy};
    $state->{anchor}=$self->snapshot($patch); return 1;
}
sub can_undo { my ($self,$patch)=@_; return scalar @{$self->_state($patch)->{history}}; }
sub _perform {
    my ($self,$patch,$data,$new_anchor,$preview,$undo)=@_;
    my $state=$self->_state($patch); die 'Sound change already in progress' if $state->{busy};
    local $state->{busy}=1;
    my $previous={data=>$self->snapshot($patch),anchor=>$state->{anchor}?dclone($state->{anchor}):undef};
    my %cache=map{exists $patch->{$_}?($_=>$patch->{$_}):()}qw(rendered_wave rendered_sample rendered_frequency);
    my $ok=eval{$self->_apply($patch,$data);$preview->($patch) if $preview;1};
    unless($ok) {
        my $error=$@; $self->_apply($patch,$previous->{data});
        @{$patch}{keys %cache}=values %cache;
        die $error;
    }
    if($undo) {pop @{$state->{history}};}
    else {push @{$state->{history}},$previous;shift @{$state->{history}} if @{$state->{history}}>32;}
    $state->{anchor}=$new_anchor?dclone($new_anchor):undef;
    return 1;
}
sub new_sound {
    my ($self,$patch,%args)=@_;my $data=$self->generate(%args);
    return $self->_perform($patch,$data,$data,$args{preview},0);
}
sub variation {
    my ($self,$patch,%args)=@_;my $state=$self->_state($patch);
    my $anchor=$state->{anchor}||$self->snapshot($patch); my $data=dclone($anchor);
    # Keep ratios, topology and pitch envelopes EXACTLY. Every variation starts
    # from the keeper, not from the last variation, so repeated clicks don't drift.
    my $envelope=$self->_between(0.85,1.15); my $brightness=$self->_between(0.85,1.15);
    $data->{attack}*= $envelope if $data->{attack};
    $data->{decay}*= $envelope if $data->{decay};
    $data->{length}*= $envelope if $data->{length};
    my $vary; $vary=sub{
        my ($voice,$modulator)=@_;
        $voice->{volume_multiplier}*= $brightness if $modulator && $voice->{volume_multiplier};
        $voice->{volume_decay}*= ($modulator?$brightness:1)/$envelope if $voice->{volume_decay};
        $voice->{delay}*= $envelope if $voice->{delay};
        $vary->($_,1) for @{$voice->{modulators}||[]};
    };
    $vary->($_,0) for @{$data->{voices}};
    return $self->_perform($patch,$data,$anchor,$args{preview},0);
}
sub undo {
    my ($self,$patch,%args)=@_;my $last=$self->_state($patch)->{history}[-1] or return 0;
    return $self->_perform($patch,$last->{data},$last->{anchor},$args{preview},1);
}
1;
