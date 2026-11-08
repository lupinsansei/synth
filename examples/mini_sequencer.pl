# Silent UI demo: prints the notes instead of accessing audio hardware.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Tk;
use MiniSequencer::Tk;
use ChordMemory qw(chord_names chord_frequencies);
my $window=MainWindow->new(-title=>'Mini sequencer (silent demo)');
my ($enabled,$chord)=(0,'Major 7th');
$window->Checkbutton(-text=>'Chord memory',-variable=>\$enabled)->pack;
$window->Optionmenu(-variable=>\$chord,-options=>chord_names())->pack;
my $seq=MiniSequencer::Tk->new(parent=>$window,
    play=>sub { print join(' ',map{sprintf('%.2fHz',$_)}@{chord_frequencies($_[0],$enabled,$chord)}),"\n"; },
    stop=>sub {});
$seq->widget->pack;
MainLoop;
