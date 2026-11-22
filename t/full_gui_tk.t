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
 sub new {bless {},shift}
 sub Status {!$_[0]{writes} || $_[0]{paused}}
 sub Load {}
 sub Write {$writes++;$_[0]{writes}++}
 sub Pause {die 'Simulated pause error' if $_[0]{fail_pause};$_[0]{paused}++}
}
use Tk;
use SuperSpinbox;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use PatchBank::Tk;
use PatchBank;
use WavExport::Tk;
use VoiceSample::Tk;
use MiniSequencer::Tk;
my $dir=tempdir(CLEANUP=>1);
my $bank_path="$dir/round-trip.synth.json";
my $sample_choice="$dir/fictional-gui.wav";
my $sample_writer=Audio::Wav->new->write($sample_choice,{bits_sample=>16,sample_rate=>44100,channels=>2});
$sample_writer->write(1000,-1000) for 1..32;$sample_writer->finish;
my (@sample_controls,@sample_errors);
my $sample_constructor=VoiceSample::Tk->can('new');

my ($banks,@errors,$open_path);
$open_path=$bank_path;
my $bank_constructor=PatchBank::Tk->can('new');
my $captured;
my $exporter;
my $export_constructor=WavExport::Tk->can('new');
my @delay_controls;
my $sequencer;
my $sequencer_constructor=MiniSequencer::Tk->can('new');
my $spinbox_constructor=SuperSpinbox->can('new');
my $constructor=MainWindow->can('new');
{
 no warnings qw(redefine once);
 local *PatchBank::Tk::new=sub {my($class,%args)=@_;$banks=$bank_constructor->($class,%args,choose_save=>sub{$bank_path},choose_open=>sub{$open_path},error=>sub{push @errors,$_[0]});return $banks};
 local *WavExport::Tk::new=sub {my($class,%args)=@_;$exporter=$export_constructor->($class,%args,choose_save=>sub{"$dir/gui.wav"},error=>sub{push @errors,$_[0]});return $exporter};
 local *SuperSpinbox::new=sub {
   my($class,%args)=@_;
   my $control=$spinbox_constructor->($class,%args);
   push @delay_controls,$control if $args{places}==3 && $args{min}==0;
   return $control;
 };
 local *MiniSequencer::Tk::new=sub { $sequencer=$sequencer_constructor->(@_); return $sequencer };
 local *VoiceSample::Tk::new=sub {
   my($class,%args)=@_;
   my $control=$sample_constructor->($class,%args,choose_open=>sub{$sample_choice},error=>sub{push @sample_errors,$_[0]});
   push @sample_controls,$control;return $control;
 };
 local *MainWindow::new=sub {$captured=$constructor->(@_);return $captured};
 local *Tk::MainLoop=sub {
   my $window=$captured;
   ok($window, 'full synth GUI starts with real Tk and fake external audio');
   $window->update;
   ok(@delay_controls,'voice Delay widgets use non-negative bounds');
   if (@delay_controls) {
     my $control=$delay_controls[0];
     ok($control->set(-1),'real Delay widget handles negative entry at its lower bound');
     is(${$control->{variable}},0,'real Delay widget clamps negative input to zero');
   }
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

   my ($panic_button)=grep{$_->isa('Tk::Button') && eval{($_->cget('-text')//'') eq 'Panic / All notes off'}}@widgets;
   ok($panic_button && $panic_button->ismapped,'Panic button visible in full GUI');
   my ($active,$selected)=$banks->{capture}->();
   $active->chord_memory(1); $active->chord_mode('Arpeggio');
   my $held=$active->play_patch($active->Patches->{$selected},'z',440);
   my $audition=$active->play_patch($active->Patches->{$selected},undef,440);
   $sequencer->start;
   my $token=$sequencer->{token};
   my $steps=$sequencer->{model}->steps;
   $panic_button->invoke;
   ok(!$sequencer->{running} && !exists $sequencer->{timer},'Panic stops sequencer and cancels timer');
   is_deeply($active->Keys,{},'GUI Panic clears held keys');
   is_deeply([map{$_->{paused}}(@$held,@$audition)],[(1)x8],'real GUI button pauses keyed and one-shot arpeggio handles');
   is(scalar(grep{defined $_}@{$active->Channels}),0,'GUI Panic includes unkeyed auditions');
   is_deeply($sequencer->{model}->steps,$steps,'Panic preserves sequencer pattern');
   my $writes=$Win32::Sound::WaveOut::writes;
   $sequencer->_tick($token);
   my $wait=0;$window->after(160,sub{$wait=1});$window->DoOneEvent(0) until $wait;
   is($Win32::Sound::WaveOut::writes,$writes,'stale callbacks and real timer cannot restart playback after Panic');
   $sequencer->start;
   cmp_ok($Win32::Sound::WaveOut::writes,'>',$writes,'explicit Play works after Panic');
   $panic_button->invoke;
   $sequencer->start;
   my ($failing)=grep{defined $_}@{$active->Channels};
   $failing->{fail_pause}=1;
   my $extra=$active->play_patch($active->Patches->{$selected},undef,440);
   my @panic_errors;
   {
     no warnings 'redefine';
     local *Tk::messageBox=sub {my($widget,%args)=@_;push @panic_errors,$args{-message};return 'OK'};
     $panic_button->invoke;
   }
   ok(!$sequencer->{running} && !exists $sequencer->{timer},'sequencer remains stopped even if its release fails');
   is_deeply([map{$_->{paused}}@$extra],[(1)x4],'sequencer release error does not skip audition cleanup');
   is(scalar @panic_errors,1,'Panic reports device error once after cleanup');
   like($panic_errors[0],qr/Simulated pause error/,'Panic dialog contains device error');
   $failing->{fail_pause}=0;
   $panic_button->invoke;
   is(scalar(grep{defined $_}@{$active->Channels}),0,'GUI Panic retries failed device');
   $active->chord_memory(0); $active->chord_mode('Together');

   my ($sample_control)=grep{Tk::Exists($_->widget) && $_->{patch}==$active->Patches->{$selected} && $_->{voice}==$active->Patches->{$selected}->voices->[0]}reverse @sample_controls;
   ok($sample_control,'sample chooser connected to current full-GUI voice');
   my $before_sample_writes=$Win32::Sound::WaveOut::writes;
   ok($sample_control->choose,'full GUI chooser renders chosen fictional WAV');
   is($active->Patches->{$selected}->voices->[0]->file,$sample_choice,'full GUI updates selected voice path');
   is($Win32::Sound::WaveOut::writes,$before_sample_writes,'choosing a sample does not audition automatically');
   my $chosen_pcm=$active->Patches->{$selected}->rendered_wave;
   {
     local *Synth::render_patch_as_middle_c=sub {$_[1]->rendered_wave('partial render');die "GUI render failure\n"};
     ok(!$sample_control->choose,'full GUI catches sample render error');
   }
   is($active->Patches->{$selected}->rendered_wave,$chosen_pcm,'full GUI sample error keeps previous waveform');
   is(scalar @sample_errors,1,'full GUI reports sample error once');
   ok($sample_control->choose,'full GUI remains usable after sample render error');

   ok($banks->save,'full GUI Save writes settings bank');
   my($original_synth,$original_selection)=$banks->{capture}->();
   my $original=PatchBank->capture($original_synth,selected_patch=>$original_selection);
   $original_synth->Patches->{$original_selection}->voices->[0]->freq_multiplier(9);
   ok($banks->open,'full GUI Open restores bank and selected patch');
   my($restored,$selection)=$banks->{capture}->();
   isnt($restored,$original_synth,'load replaces synth with freshly reconstructed objects');
   my $round_trip=PatchBank->capture($restored,selected_patch=>$selection);
   # Bank paths are intentionally relative on disk. Compare referenced files,
   # not the spelling of an absolute path containing parent-directory segments.
   my $canonical_voice;$canonical_voice=sub {
     my $voice=shift;
     $voice->{file}=abs_path($voice->{file}) || $voice->{file} if $voice->{file};
     $canonical_voice->($_) for @{$voice->{modulators} || []};
   };
   for my $doc ($original,$round_trip) {
     for my $patch (values %{$doc->{patches}}) { $canonical_voice->($_) for @{$patch->{voices}}; }
   }
   is_deeply($round_trip,$original,'GUI bank round trip preserves settings and sample references');
   ok(-f $restored->Patches->{amen}->voices->[0]->file,'portable bundled sample remains accessible after bank load');
   ok(!$restored->Keys || !keys %{$restored->Keys},'loading does not start playback');
   $restored->play_patch($restored->Patches->{$selection},undef,440);
   $panic_button->invoke;
   is(scalar(grep{defined $_}@{$restored->Channels}),0,'Panic targets current synth after loading bank');
   my($chord_button)=grep{$_->isa('Tk::Checkbutton') && eval{($_->cget('-text')//'') eq 'Chord memory'}}@widgets;
   ok($chord_button,'playback chord toggle found');
   if($chord_button) {
    my $before=$restored->chord_memory;$chord_button->invoke;
    is($restored->chord_memory,!$before?1:0,'chord control rebinds to loaded synth');
   }
   my ($mode_control)=grep{$_->isa('Tk::Optionmenu') && eval{($_->cget('-text')//'') eq 'Together'}}@widgets;
   ok($mode_control,'chord playback selector integrated');
   $mode_control->cget('-menu')->invoke('Arpeggio');
   is($restored->chord_mode,'Arpeggio','mode selector rebinds after bank load');
   my ($arp_step)=grep{$_->isa('Tk::Spinbox') && eval{$_->cget('-to')==1000}}@widgets;
   $arp_step->delete(0,'end');$arp_step->insert(0,'180');
   is($restored->arpeggio_ms,180,'arpeggio timing control rebinds after load');
   for my $label ('Octave -','Octave +') {
    my ($control)=grep{$_->isa('Tk::Button') && eval{($_->cget('-text')//'') eq $label}}@widgets;
    ok($control && $control->ismapped,"$label visible in full GUI");
   }
   my $writes_before=$Win32::Sound::WaveOut::writes;
   my $menubar=$window->cget('-menu');
   my ($file_index)=grep { $menubar->type($_) eq 'cascade' } 0..$menubar->index('end');
   my $filemenu=$menubar->entrycget($file_index,'-menu');
   my ($export_index)=grep { eval { $filemenu->entrycget($_,'-label') eq 'Export sound as WAV...' } } 0..$filemenu->index('end');
   ok(defined $export_index,'File menu offers WAV export');
   ok($filemenu->invoke($export_index),'full GUI menu exports selected sound after bank load');
   open my $wav,'<:raw',"$dir/gui.wav" or die $!;
   local $/;my $wav_bytes=<$wav>;close $wav;
   is(substr($wav_bytes,0,4),'RIFF','GUI export has WAV header');
   is(substr($wav_bytes,44),$restored->Patches->{$selection}->rendered_wave,'export uses loaded selected patch, not old bank');
   is($Win32::Sound::WaveOut::writes,$writes_before,'GUI export never starts playback');
   is($banks->current_file,$bank_path,'WAV export does not change patch-bank Save target');
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
