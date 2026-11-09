use strict;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/lib";
use SuperSpinbox;
use MiniSequencer::Tk;
use FMPatchExplorer::Tk;
use PatchBank::Tk;
use ChordMemory qw(chord_names);
use warnings;
use Data::Dumper;

use Tk;
use Tk::Table;
use Tk::Dialog;
use Tk::Spinbox;
use Tk::Checkbutton;

use Synth;
use Patch;
use Voice;
use MIDI::Pitch qw(name2freq pitch2name name2pitch);
use Win32::Sound;

use feature qw(switch);
no warnings 'experimental';

my $synth = new Synth(
	Patches => {
		"snare" => new Patch(
			name => "snare",
			length => 1,
			voices => [
				new Voice( wave => 'sine', freq_decay => 0.004, volume_decay => 0.000005 ),
				new Voice( wave => 'noise', delay => 1000, tuned => 0, volume_decay => 0.0002 ),
			],
			#decay => 0.15
		),
		"hihat" => new Patch(
			name => "hihat",
			length => 1,
			voices => [
				new Voice( wave => 'noise', tuned => 0, volume_decay => 0.00025 )
			],
			#decay => 0.25
		),
		'bass' => new Patch(
			name => "bass",
			length => 1,
			chord => 0,
			voices => [
				 new Voice( freq_multiplier => 2.00, freq_decay => 0.0004, volume_decay => 0.0001,
				 modulators => [
						new Voice( freq_multiplier => 6, freq_decay => 0.0002, volume_multiplier => 0.055, volume_decay => 0.000006 ),
						new Voice( freq_multiplier => 12, freq_decay => 0.0002, volume_multiplier => 0.03, volume_decay => 0.0000001 ),
						#new Voice( freq_multiplier => 4.1, volume_multiplier => 0.40, volume_decay => 0.00005 ),
					 ]
				 )
			]
		),
		"amen" => new Patch(
			name => "amen",
			decay => 4,
			voices => [
				new Voice( wave => 'file', file => 'C:\development\synth\WAV\cw_amen02_165.wav', freq_decay => 0.04 )
			],
			#decay => 0.25
		),
	}
);

my $mw = MainWindow->new;
#my $c = $mw->Canvas(-width => 300, -height => 200); # set width https://www.perlmonks.org/?node_id=624997
#$c->pack;

$mw->Label(-text => 'Synth Gui')->pack;

# Playback-only harmony: never calls OnPatchChange or regenerates a sample.
my $harmony = $mw->Frame->pack(-fill => 'x');
my $chord_toggle = $harmony->Checkbutton(-text => 'Chord memory', -variable => \$synth->{chord_memory})->pack(-side => 'left');
my $chord_selector = $harmony->Optionmenu(-variable => \$synth->{chord_type}, -options => chord_names())->pack(-side => 'left');


# $mw->Button(
#     -text    => 'Quit',
#     -command => sub { exit },
# )->pack;

$mw->Label(-text => 'Patches')->pack(-side => 'left', -anchor => 'ne', -padx => 8);

my $lbox = $mw->Listbox()->pack(-side => 'left', -anchor => 'ne', -padx => 8);
$lbox->insert('end', keys %{$synth->{Patches}} );
$lbox->bind('<<ListboxSelect>>' => \&changePatch );


# $table = $parent->Table(-rows => number,
#                         -columns => number,
#                         -scrollbars => anchor,
#                         -fixedrows => number,
#                         -fixedcolumns => number,
#                         -takefocus => boolean);
#
# $widget = $table->Button(...);
#
# $old = $table->put($row,$col,$widget);
# $old = $table->put($row,$col,"Text");  # simple Label
# $widget = $table->get($row,$col);
#
# $cols = $table->totalColumns;
# $rows = $table->totalRows;
#
# $table->see($widget);
# $table->see($row,$col);
#
# ($row,$col) = $table->Posn($widget);

my $table = $mw->Table(-rows => 10, -columns => 11, -fixedrows => 1, -scrollbars => 'se');

my $dialog = $mw->Dialog(-text => 'Save File?', -bitmap => 'question', -title => 'Save File Dialog', -default_button => 'Yes', -buttons => [qw/Yes No Cancel/]);

my @voices = qw();

# we want to model a single patch in a patch panel and that has multiple voices
# we can change the patch later by selecting one from a list box



# Add waveform visualization canvas
my $waveform_canvas = $mw->Canvas(-width => 600, -height => 150, -bg => 'black', -relief => 'sunken', -bd => 2)->pack(-side => 'top', -padx => 10, -pady => 5);

my $selected_octave = 3;
my $sequencer = MiniSequencer::Tk->new(parent => $mw,
    root => sub { ($selected_octave + 1) * 12 },
    play => sub { $synth->play_patch(getSelectedPatch(), 'mini-sequencer', $_[0]); },
    stop => sub { $synth->stop_patch('mini-sequencer'); });
$sequencer->widget->pack(-fill => 'x', -pady => 6);
my $explorer = FMPatchExplorer::Tk->new(parent => $mw,
    patch => sub { getSelectedPatch() },
    before => sub { $sequencer->stop },
    context => sub { {samplerate=>$synth->samplerate, bits=>$synth->bits} },
    preview => sub {
        my $patch = shift;
        changePatch();
        $synth->play_patch($patch, undef, name2freq('c' . $selected_octave));
    },
    recover => sub { $mw->Unbusy; changePatch('no-render'); });
$explorer->widget->pack(-fill => 'x', -pady => 6);


build_keyboard($mw);
# Reserve space for transport/explorer first; scroll the larger voice table.
$table->pack(-fill => 'both', -expand => 1);

$mw->bind('<KeyPress>' => \&print_keysym);
$mw->bind('<KeyRelease>' => sub { my $widget = shift; $synth->stop_patch($widget->XEvent->K); });

sub print_keysym {

    # Typing a value is editing, not a request to play the keyboard.
    my $focus = $mw->focus;
    return if $focus && ($focus->isa('Tk::Entry') || $focus->isa('Tk::Spinbox'));

	# based on https://www.perlmonks.org/?node_id=144722

   my $widget = shift;

   my $e = $widget->XEvent;
   my ($keysym_text, $keysym_decimal) = ($e->K, $e->N);

   print "keysym=$keysym_text, numberic=$keysym_decimal\n";

	# change selected octave if 1-5 is pressed
	if( $keysym_text =~ /^([0-5])$/ ) {
		$selected_octave = $1;
		# force into number https://stackoverflow.com/questions/288900/how-can-i-convert-a-string-to-a-number-in-perl

		print "Octave changed to $selected_octave\n";			
	}
	
	my $note = "";

	given($keysym_text) {

		$note = "c$selected_octave" when ("z");
		$note = "c#$selected_octave" when ("s");
	 	$note = "d$selected_octave" when ("x");
		$note = "d#$selected_octave" when ("d");
		$note = "e$selected_octave" when ("c");
		$note = "f$selected_octave" when ("v");
		$note = "f#$selected_octave" when ("g");
		$note = "g$selected_octave" when ("b");
		$note = "g#$selected_octave" when ("h");
		$note = "a$selected_octave" when ("n");
		$note = "a#$selected_octave" when ("j");
		$note = "b$selected_octave" when ("m");
		$note = "c".($selected_octave+1) when ("comma");
		$note = "d".($selected_octave+1) when ("period");
	}

	if( $note ) {
		print "Note = $note\n";
		$synth->play_patch(getSelectedPatch(), $keysym_text, name2freq($note));
	}
}

# Settings-only bank files: no device handles, rendered buffers or GUI objects.
my $banks = PatchBank::Tk->new(parent => $mw,
    capture => sub { return ($synth, $lbox->get($lbox->curselection->[0])); },
    apply => sub {
        my $bank = shift;
        my $candidate = Synth->new(Patches => $bank->{patches}, %{$bank->{settings}});
        # Validate/render before touching the active synth. Missing WAVs or render
        # errors leave the old bank and its controls available.
        $candidate->render_patch_as_middle_c($candidate->Patches->{$bank->{selected_patch}});
        $sequencer->stop;
        $synth->stop_patch($_) for keys %{$synth->Keys};
        my $previous = $synth;
        my $previous_name = $lbox->get($lbox->curselection->[0]);
        my $ok = eval {
            $synth = $candidate;
            $lbox->delete(0, 'end'); $lbox->insert('end', sort keys %{$synth->Patches});
            $chord_toggle->configure(-variable => \$synth->{chord_memory});
            $chord_selector->configure(-variable => \$synth->{chord_type});
            setSelectedPatchByName($bank->{selected_patch}, 1);
            1;
        };
        unless ($ok) {
            my $error = $@; $synth = $previous;
            $lbox->delete(0, 'end'); $lbox->insert('end', sort keys %{$synth->Patches});
            $chord_toggle->configure(-variable => \$synth->{chord_memory});
            $chord_selector->configure(-variable => \$synth->{chord_type});
            $mw->Unbusy; setSelectedPatchByName($previous_name, 1);
            die $error;
        }
        # Undo/keeper state from another bank must not leak into the loaded one.
        $explorer->{manager} = FMPatchExplorer->new;
        $explorer->{buttons}{undo}->configure(-state=>'disabled');
        $explorer->{status} = 'Patch bank loaded. Like this can set a new variation starting point.';
    });
$mw->configure(-menu => my $menubar = $mw->Menu);
my $file = $menubar->cascade(-label => '~File');
$file->command(-label=>'Open...', -command=>sub{$banks->open});
$file->command(-label=>'Save', -command=>sub{$banks->save});
$file->command(-label=>'Save As...', -command=>sub{$banks->save_as});
$file->separator;
$file->command(-label=>'Import legacy JSON...', -command=>sub{$banks->open(legacy=>1)});
$mw->bind('<Control-o>' => sub{$banks->open; Tk->break});
$mw->bind('<Control-s>' => sub{$banks->save; Tk->break});

CenterWindow($mw, 1200, 650);

setSelectedPatchByName("bass");

MainLoop;

sub getSelectedPatch {
	return $synth->{Patches}->{ $lbox->get( $lbox->curselection->[0] ) };
}

sub setSelectedPatchByName
{
	my($name, $skip_render) = @_;
	
	my @elements = $lbox->get(0, 'end');
	for(my $i=0; $i<@elements; $i++ ) {
		if( $elements[$i] eq $name ) {
			$lbox->selectionSet($i);
		}
	}
	changePatch($skip_render ? 'no-render' : ());
}

sub changePatch {
    my $skip_render = defined $_[0] && !ref($_[0]) && $_[0] eq 'no-render';

	# called when we change the patch in the listbox on the side

	my $selected_patch = getSelectedPatch();

	# clear the voice table
	$table->clear();

	my $row_index = 0;

	# patch widgets

	# chord
	$table->put($row_index, 0,
		"Baked chord (legacy)"
	);

	$table->put($row_index, 1,
		$table->Checkbutton(-variable => \$selected_patch->{chord}, -command => sub{ OnPatchChange($selected_patch) } )
	);


	$row_index++;

	# foreach voice in patch
	
	for(my $i=0; $i<@{$selected_patch->voices}; $i++) {

		my $voice = $selected_patch->voices->[$i];

		#print Dumper( $voice );

		# rebuild it
		AddTableHeader($table, $row_index++, ["Wave", "Tuned", "f X", "v X", "f Decay", "v Decay", "Delay"]);
		AddVoicePanel($table, $row_index++, $selected_patch, $voice);
	}

	# render the sound
	#print "changePatch\n";
	$mw->Busy;
	$mw->update;	

	$synth->render_patch_as_middle_c($selected_patch) unless $skip_render;
	
	# Update waveform visualization
	draw_waveform($waveform_canvas, $selected_patch->rendered_sample);

	$mw->Unbusy;
	$mw->update;
}

sub AddVoicePanel {
	my $table = shift;
	my $row_index = shift;
	my $patch = shift;
	my $voice = shift;
	my $indent = shift;

	$indent = 0 unless defined($indent);

	my $col = 0;

	$col += $indent;

	# create new voice data structure, with their defaults
	# $voices->[$row_index-1] = {
	#   wave => 'sine',
	#   f_decay => 0,
	#   v_decay => 0,
	#   tuned => 0,
	#   f_multiplier => 0,
	#   v_multiplier => 0,
	#   modulators => []
	# };

	#print "AddVoicePanel($row_index)\n";

	#$table->put($row_index,$col++,"$row_index");  # simple Label

	# wave menu
	$table->put($row_index,$col++,
		$table->Optionmenu(-variable => \$voice->{wave}, -options => GetVoiceList(), -command => sub { OnPatchChange($patch) } )->pack()
	);

	# Tuned	
	$table->put($row_index, $col++,
		$table->Checkbutton(-variable => \$voice->{tuned}, -command => sub{ OnPatchChange($patch) } )
	);

	# f multiplier
	$table->put($row_index, $col++,
		build_super_number_picker($table, 4, \$voice->{freq_multiplier}, sub{ OnPatchChange($patch) } )
	);

	# v multiplier
	$table->put($row_index, $col++,
		build_super_number_picker($table, 4, \$voice->{volume_multiplier}, sub{ OnPatchChange($patch) } )
	);

	# f Decay
	$table->put($row_index, $col++,
		build_super_number_picker($table, 6, \$voice->{freq_decay}, sub{ OnPatchChange($patch) } )
	);

	# v Decay
	$table->put($row_index, $col++,
		build_super_number_picker($table, 8, \$voice->{volume_decay}, sub{ OnPatchChange($patch) } )
	);

	# delay
	$table->put($row_index, $col++,
		build_super_number_picker($table, 3, \$voice->{delay}, sub{ OnPatchChange($patch) } )
	);

	# modulators
	if( $voice->modulators ) {
		$indent++;

		for(my $i=0; $i<@{$voice->modulators}; $i++) {

			print "modulator $i\n";

			my $modulator = $voice->modulators->[$i];

			AddTableHeader($table, ++$row_index, ["Wave", "Tuned", "f X", "v X", "f Decay", "v Decay", "Delay"], $indent);
			AddVoicePanel($table, ++$row_index, $patch, $modulator, $indent);
		}
	}

  # add row button
  # $table->put($row_index,$col++,$table->Button(
  #     -text    => '>',
  #     -command => sub { AddVoicePanel($row_index+1, $voices, $table, ++$indent) },
  # ));
	#
  # # add modulators row button
  # $table->put($row_index,$col++,$table->Button(
  #     -text    => '+',
  #     -command => sub { AddVoicePanel($row_index+1, $voices, $table) },
  # ));

}

sub GetVoiceList {
  return [qw(sine noise file)];
}

sub OnPatchChange {

	# this is called when a voice parameter has changed and we need to re-render the patch

	my($patch) = @_;

	#print Dumper( $synth );	# this works and dumps out the whole set of patches
	#print Dumper( $patch->{voices} );

	$mw->Busy;
	$mw->update;
	
	$synth->render_patch_as_middle_c($patch);
	
	# Update waveform visualization
	draw_waveform($waveform_canvas, $patch->rendered_sample);

	$mw->Unbusy;
	$mw->update;

	# Removed automatic playback - user can play manually with keyboard
	#$synth->play_patch($patch, undef, name2freq('c' . $selected_octave));
}

sub AddTableHeader {

	my($table, $row_index, $label_list_ref, $indent) = @_;

	$indent = 0 unless defined($indent);

  for( my $i=0; $i<@$label_list_ref; $i++) {
    $table->put( $row_index, $i + $indent, $label_list_ref->[$i] );
  }
}

sub CenterWindow
{
	# https://www.perlmonks.org/?node_id=356942

    my($window, $width, $height) = @_;
    $window->idletasks;
    $width  = $window->reqwidth  unless $width;
    $height = $window->reqheight unless $height;
    my $x = int(($window->screenwidth  / 2) - ($width  / 2));
    my $y = int(($window->screenheight / 2) - ($height / 2));
    #$window->geometry("+" . $x . "+" .$y);
    $window->geometry($width . "x" . $height . "+" . $x . "+" .$y);
}

# on Spinbox we had this option that would send values through -command => sub{ show_set($index, @_)
#sub show_set{
#  my( $index, $value, $direction ) = @_;
#   print "$index, $value, $direction\n";
#}

sub build_keyboard {

	my( $mw ) = @_;

	my $keys = 13; # include the next octave's C so UI matches keyboard shortcuts
	my $start_pitch = name2pitch('c' . $selected_octave);

	my @notes = map { pitch2name($start_pitch + $_) } 0 .. ($keys - 1);

	my $white_key_width = 50;
	my $white_key_height = 140;
	my $black_key_width = 30;
	my $black_key_height = 80;

	my $white_key_count = scalar grep { $_ !~ /#/ } @notes;
	my $keyboard_width = $white_key_count * $white_key_width;

	my $keyboard = $mw->Frame(-width => $keyboard_width, -height => $white_key_height)
		->pack(-side => 'top', -padx => 10, -pady => 10);
	$keyboard->packPropagate(0);

	my $white_index = 0;
	my $index = 0;
	while( $index < @notes ) {

		my $white_note = $notes[$index];

		my $key_frame = $keyboard->Frame(-width => $white_key_width, -height => $white_key_height)->pack(-side => 'left', -padx => 0, -pady => 0);
		$key_frame->packPropagate(0);

		my $white_button = build_key($key_frame, $white_note, 4, "white");
		$white_button->pack(-side => 'bottom', -fill => 'both', -expand => 1);

		if( $index + 1 < @notes && $notes[$index + 1] =~ /#/ ) {
			my $black_note = $notes[$index + 1];
			my $black_button = build_key($keyboard, $black_note, 3, "black");

			my $center_x = ($white_index + 1) * $white_key_width;
			my $left_x = int($center_x - ($black_key_width / 2));

			$black_button->place(-x => $left_x, -y => 0, -width => $black_key_width, -height => $black_key_height, -bordermode => 'outside');
			$black_button->raise;
			$index++;
		}

		$white_index++;
		$index++;
	}
}

sub build_key {

	my( $table, $note, $height, $background ) = @_;

	my $bt = $table->Button(
		-text		=> $note,
		-width		=> ($background eq 'black' ? 2 : 3),
		-height		=> $height,
		-background => $background,
		-foreground => ($background eq 'black' ? 'white' : 'black'),
		-command => sub {
			play_selected_patch($note);			# note is kind of like a closure?
		}
	);

	# triggered when the button is pressed
	#$bt->bind('<Button-1>'        => sub {
	#	print "yo\n";
	#});

	return $bt;
}

sub play_selected_patch {

	my($note) = @_;
	
	print "play_selected_patch $note\n";

	$synth->play_patch(getSelectedPatch(), undef, name2freq($note));	# note is kind of like a closure
}

sub draw_waveform {
	my($canvas, $sample) = @_;
	
	return unless $sample && @{$sample->[0]} > 0;
	
	# Clear the canvas
	$canvas->delete('all');
	
	my $canvas_width = $canvas->cget(-width);
	my $canvas_height = $canvas->cget(-height);
	my $center_y = $canvas_height / 2;
	
	# Find the last non-zero sample to trim silence
	my $sample_count = @{$sample->[0]};
	my $last_nonzero = $sample_count - 1;
	
	for my $i (reverse 0..$sample_count-1) {
		if (abs($sample->[0]->[$i]) > 100) { # threshold for "silence"
			$last_nonzero = $i;
			last;
		}
	}
	
	# Use only the non-silent portion
	my $active_sample_count = $last_nonzero + 1;
	my $display_samples = $canvas_width;
	my $step = int($active_sample_count / $display_samples) || 1;
	
	# Draw background gradient effect
	for my $y (0..$canvas_height) {
		my $intensity = int(20 * (1 - abs($y - $center_y) / $center_y));
		my $color = sprintf("#%02x%02x%02x", 0, $intensity, 0);
		$canvas->createLine(0, $y, $canvas_width, $y, -fill => $color, -width => 1);
	}
	
	# Draw grid lines
	$canvas->createLine(0, $center_y, $canvas_width, $center_y, -fill => '#006600', -width => 2);
	for my $i (1..4) {
		my $y = ($canvas_height / 4) * $i;
		$canvas->createLine(0, $y, $canvas_width, $y, -fill => '#003300', -width => 1);
	}
	
	# Add vertical grid lines
	for my $i (1..9) {
		my $x = ($canvas_width / 10) * $i;
		$canvas->createLine($x, 0, $x, $canvas_height, -fill => '#002200', -width => 1);
	}
	
	# Find the maximum amplitude for scaling
	my $max_amplitude = 0;
	for my $i (0..$active_sample_count-1) {
		my $amplitude = abs($sample->[0]->[$i]);
		$max_amplitude = $amplitude if $amplitude > $max_amplitude;
	}
	
	return if $max_amplitude == 0;
	
	# Draw the waveform
	my @points = ();
	for my $x (0..$display_samples-1) {
		my $sample_index = $x * $step;
		last if $sample_index >= $active_sample_count;
		
		my $amplitude = $sample->[0]->[$sample_index];
		my $normalized = $amplitude / $max_amplitude;
		my $y = $center_y - ($normalized * ($canvas_height / 2 - 10));
		
		push @points, $x, $y;
	}
	
	# Draw the main waveform line with glow effect
	if (@points >= 4) {
		# Draw glow layers
		for my $width (6, 4, 2) {
			my $alpha = int(255 / (8 - $width));
			my $color = sprintf("#00%02x00", $alpha);
			$canvas->createLine(@points, -fill => $color, -width => $width, -smooth => 1);
		}
		
		# Draw the main bright line
		$canvas->createLine(@points, -fill => '#00ff00', -width => 1, -smooth => 1);
	}
}

sub build_super_number_picker {
    my ($parent, $places, $variable, $command) = @_;
    my $control = SuperSpinbox->new(parent => $parent, variable => $variable,
        integers => 4, places => $places, min => -1000, max => 1000, command => $command);
    return $control->widget;
}
