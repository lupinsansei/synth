# Silent explorer demo: generates the real waveform but does not access audio hardware.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use Tk;
use Patch;
use Voice;
use FMPatchExplorer::Tk;
my $window=MainWindow->new(-title=>'Musical FM explorer (silent demo)');
my $patch=Patch->new(name=>'Demo',length=>0.5,voices=>[Voice->new]);
my $ui=FMPatchExplorer::Tk->new(parent=>$window,patch=>sub{$patch},preview=>sub {
 my $wave=$patch->render(130.81278265,44100,16);
 printf "Generated %d samples, carrier ratio %.4f\n",scalar(@{$wave->[0]}),$patch->voices->[0]->freq_multiplier;
});
$ui->widget->pack(-padx=>10,-pady=>10);
MainLoop;
