use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use Test::More;
BEGIN {
 $INC{'MIDI/Pitch.pm'}=__FILE__;
 package MIDI::Pitch;
 sub import {
  my $caller=caller; no strict 'refs';
  *{$caller.'::name2freq'}=sub{my $note=shift;die 'Fixture pitch supports c3 only' unless $note eq 'c3';return 130.81278265};
  *{$caller.'::pitch2name'}=sub { my @n=('c','c#','d','d#','e','f','f#','g','g#','a','a#','b'); my $p=shift; return $n[$p%12].(int($p/12)-1) };
  *{$caller.'::name2pitch'}=sub { return 48 };
 }
 $INC{'Win32/Sound.pm'}=__FILE__;
 package Win32::Sound; sub import {}
 package Win32::Sound::WaveOut;
 our $writes=0;
 sub new {bless {},shift} sub Status {1} sub Load {} sub Write {$writes++} sub Pause {}
 $INC{'JSON/Syck.pm'}=__FILE__;
 package JSON::Syck;sub import {} sub DumpFile {die 'Unexpected fixture file write'}
}
use Tk;
my $captured;
my $constructor=MainWindow->can('new');
{
 no warnings qw(redefine once);
 local *MainWindow::new=sub {$captured=$constructor->(@_);return $captured};
 local *Tk::MainLoop=sub {
   my $window=$captured;
   ok($window, 'full synth GUI starts with real Tk and fake external audio');
   $window->update;
   my @widgets;
   my $walk;$walk=sub{for my $w($_[0]->children){push @widgets,$w;$walk->($w)}};$walk->($window);
   for my $text ('New sound','Like this','Variation','Undo') {
    my ($button)=grep{$_->isa('Tk::Button') && eval{($_->cget('-text') // '') eq $text}}@widgets;
    ok($button,"$text control integrated into full GUI");
    die "Missing $text" unless $button;
    ok($button->ismapped && $button->rooty >= $window->rooty && $button->rooty+$button->height <= $window->rooty+$window->height, "$text visible without resizing or a programmatic click");
    $button->invoke; $window->update;
   }
   cmp_ok($Win32::Sound::WaveOut::writes,'>=',3,'New, Variation and Undo each reach actual playback dispatch');

   $window->destroy;
 };
 do "$FindBin::Bin/../GUI.pl";
 die $@ if $@;
}

done_testing;
