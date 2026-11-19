use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use MiniSequencer::Tk;
{
    package VirtualFrame;
    sub after {
        my ($self,$ms,$callback)=@_;
        die 'Timer delay must be a positive integer' unless $ms>=1 && $ms==int($ms);
        my $id=++$self->{serial};
        $self->{timers}{$id}=[$self->{clock}{now}+$ms/1000,$callback];
        return $id;
    }
    sub afterCancel { delete $_[0]{timers}{$_[1]} }
    sub fire {
        my ($self,$late)=@_; $late//=0;
        my @ids=keys %{$self->{timers}};
        die 'Expected exactly one pending timer' unless @ids==1;
        my $timer=delete $self->{timers}{$ids[0]};
        $self->{clock}{now}=$timer->[0]+$late;
        $timer->[1]->();
    }
    package ClockSequencer;
    our @ISA=('MiniSequencer::Tk');
    sub refresh { $_[0]{test_clock}{now}+=$_[0]{test_clock}{refresh_cost} }
}
# Model/Tk scheduling only. Fake widgets and callbacks never access sound hardware.
no warnings 'redefine';
local *Tk::Exists=sub { $_[0]{alive} };
sub harness {
    my (%args)=@_;
    my $clock={now=>0,refresh_cost=>$args{refresh_cost}//0.02};
    my $frame=bless {clock=>$clock,timers=>{},serial=>0,alive=>1},'VirtualFrame';
    my @onsets;
    my $seq=bless {model=>MiniSequencer->new(rng=>sub{0.9}),widget=>$frame,
        clock=>sub{$clock->{now}},test_clock=>$clock,octave=>3,
        tempo=>$args{tempo}//120,token=>0,running=>0,
        play=>sub{push @onsets,$clock->{now};$clock->{now}+=$args{play_cost}//0},
        stop=>sub{}},'ClockSequencer';
    return ($seq,$frame,$clock,\@onsets);
}
for my $tempo (40,120,137,240) {
    my ($seq,$frame,$clock,$onsets)=harness(tempo=>$tempo,play_cost=>0.005);
    $seq->start;
    $frame->fire for 1..64;
    my $period=60/($tempo*4);
    my $worst=0;
    for my $i (0..$#$onsets) {
        my $error=abs($onsets->[$i]-$onsets->[0]-$i*$period);
        $worst=$error if $error>$worst;
    }
    cmp_ok($worst,'<',0.00101,"$tempo BPM stays within one Tk millisecond over four bars including callback overhead");
    cmp_ok(abs($onsets->[16]-$onsets->[0]-16*$period),'<',0.00101,'one bar has the selected duration');
    $seq->stop;
    is(scalar keys %{$frame->{timers}},0,'stop cancels the only timer');
    ok(!exists $seq->{next_step_at},'stop clears the old deadline');
}
my ($seq,$frame,$clock,$onsets)=harness();
$seq->start;
$seq->{tempo}=240;
$frame->fire;
cmp_ok(abs($onsets->[1]-$onsets->[0]-0.125),'<',0.00101,'tempo change does not move the already pending step');
$frame->fire;
cmp_ok(abs($onsets->[2]-$onsets->[1]-0.0625),'<',0.00101,'new tempo applies to the following interval');
my $count=@$onsets;
$frame->fire(3); # A delayed event loop must not start a string of immediate notes.
is(scalar @$onsets,$count+1,'long stall plays one step, not a catch-up burst');
my ($timer)=values %{$frame->{timers}};
cmp_ok($timer->[0]-$clock->{now},'>=',0.0625-1e-9,'long stall schedules a full new interval after the current callback');
$frame->fire;
cmp_ok($onsets->[-1]-$onsets->[-2],'>=',0.0625,'recovery does not bunch notes');
my ($old)=values %{$frame->{timers}};
my $stale=$old->[1];
$seq->stop;
$clock->{now}+=100;
$seq->start;
is($seq->{current},0,'restart begins at step one');
my $restarted=@$onsets;
$stale->();
is(scalar @$onsets,$restarted,'cancelled callback cannot play after restart');
is(scalar keys %{$frame->{timers}},1,'cancelled callback cannot create a second timer');
$frame->fire;
cmp_ok(abs($onsets->[-1]-$onsets->[-2]-0.0625),'<',0.00101,'restart uses a fresh timing origin');
$seq->{tempo}='bad';
$frame->fire;
ok(!$seq->{running} && !keys %{$frame->{timers}},'invalid tempo stops cleanly without a pending timer');
like($seq->{status},qr/40 to 240/,'invalid live tempo is explained');

my ($slow,$slow_frame,$slow_clock,$slow_onsets)=harness(refresh_cost=>0.3);
$slow->start;
$slow_frame->fire for 1..3;
is(scalar @$slow_onsets,4,'callbacks longer than a step still schedule one note per timer');
for my $i (1..$#$slow_onsets) {
    cmp_ok($slow_onsets->[$i]-$slow_onsets->[$i-1],'>=',0.425-1e-9,'over-budget work rebases rather than spinning zero-delay callbacks');
}
my ($broken,$broken_frame)=harness();
$broken->{play}=sub{die 'Simulated playback error'};
$broken->start;
ok(!$broken->{running} && !keys %{$broken_frame->{timers}},'playback exception stops transport without scheduling more work');
like($broken->{status},qr/Simulated playback error/,'playback error remains visible');
done_testing;
