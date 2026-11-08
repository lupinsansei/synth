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
}
use Tk;
use File::Temp qw(tempdir);
use PatchBank::Tk;
use PatchBank;
my $dir=tempdir(CLEANUP=>1);
my $bank_path="$dir/round-trip.synth.json";
my ($banks,@errors,$open_path);
$open_path=$bank_path;
my $bank_constructor=PatchBank::Tk->can('new');
my $captured;
my $constructor=MainWindow->can('new');
{
 no warnings qw(redefine once);
 local *PatchBank::Tk::new=sub {my($class,%args)=@_;$banks=$bank_constructor->($class,%args,choose_save=>sub{$bank_path},choose_open=>sub{$open_path},error=>sub{push @errors,$_[0]});return $banks};
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

   ok($banks->save,'full GUI Save writes settings bank');
   my($original_synth,$original_selection)=$banks->{capture}->();
   my $original=PatchBank->capture($original_synth,selected_patch=>$original_selection);
   $original_synth->Patches->{$original_selection}->voices->[0]->freq_multiplier(9);
   ok($banks->open,'full GUI Open restores bank and selected patch');
   my($restored,$selection)=$banks->{capture}->();
   isnt($restored,$original_synth,'load replaces synth with freshly reconstructed objects');
   is_deeply(PatchBank->capture($restored,selected_patch=>$selection),$original,'GUI bank round trip preserves settings');
   ok(!$restored->Keys || !keys %{$restored->Keys},'loading does not start playback');
   my($chord_button)=grep{$_->isa('Tk::Checkbutton') && eval{($_->cget('-text')//'') eq 'Chord memory'}}@widgets;
   ok($chord_button,'playback chord toggle found');
   if($chord_button) {
    my $before=$restored->chord_memory;$chord_button->invoke;
    is($restored->chord_memory,!$before?1:0,'chord control rebinds to loaded synth');
   }
   # A missing selected sample must fail before changing the active bank.
   my $bad=Synth->new(Patches=>{missing=>Patch->new(name=>'Missing sample',voices=>[Voice->new(wave=>'file',file=>"$dir/missing.wav")])});
   $open_path="$dir/missing.synth.json";PatchBank->save_file($open_path,$bad);
   ok(!$banks->open,'selected missing WAV rejects GUI load');
   my($unchanged)=$banks->{capture}->();
   is($unchanged,$restored,'failed render leaves original synth active');
   is($banks->current_file,$bank_path,'failed load preserves previous save filename');
   is(scalar @errors,1,'failed load reported exactly once without dialog');
   $window->update;
   $window->destroy;
 };
 do "$FindBin::Bin/../GUI.pl";
 die $@ if $@;
}

done_testing;
