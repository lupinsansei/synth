use strict;
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
#use JSON;
#use JSON::Any;
#use File::Slurp;

use JSON::Syck;

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
			length => 2,
			chord => 1,
			voices => [
				 new Voice( freq_multiplier => 2, freq_decay => 0.0004, volume_decay => 0.0001,
				 modulators => [
						new Voice( freq_multiplier => 4, freq_decay => 0.0002, volume_multiplier => 0.055, volume_decay => 0.000003 ),
						new Voice( freq_multiplier => 8, freq_decay => 0.0002, volume_multiplier => 0.03, volume_decay => 0.0000001 ),
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

# $mw->Button(
#     -text    => 'Quit',
#     -command => sub { exit },
# )->pack;

$mw->Label(-text => 'Patches')->pack(-side => 'left', -anchor => 'ne', -padx => 8);

my $lbox = $mw->Listbox()->pack(-side => 'left', -anchor => 'ne', -padx => 8);
$lbox->insert('end', keys $synth->{Patches} );
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

my $table = $mw->Table(-rows => 10, -columns => 11, -fixedrows => 1);

my $dialog = $mw->Dialog(-text => 'Save File?', -bitmap => 'question', -title => 'Save File Dialog', -default_button => 'Yes', -buttons => [qw/Yes No Cancel/]);

my @voices = qw();

# we want to model a single patch in a patch panel and that has multiple voices
# we can change the patch later by selecting one from a list box

$table->pack;

my $selected_octave = 2;
build_keyboard($mw);

$mw->bind('<KeyPress>' => \&print_keysym);

sub print_keysym {

	# based on https://www.perlmonks.org/?node_id=144722

   my $widget = shift;

   my $e = $widget->XEvent;
   my ($keysym_text, $keysym_decimal) = ($e->K, $e->N);

   print "keysym=$keysym_text, numberic=$keysym_decimal\n";

	 if( $keysym_text =~ /^[0-5]$/ ) {
		 	$selected_octave = $keysym_text;
	 }

	 given($keysym_text) {

		 play_selected_patch("c$selected_octave") when ("z");
		 play_selected_patch("c#$selected_octave") when ("s");
	 	 play_selected_patch("d$selected_octave") when ("x");
		 play_selected_patch("d#$selected_octave") when ("d");
		 play_selected_patch("e$selected_octave") when ("c");
		 play_selected_patch("f$selected_octave") when ("v");
		 play_selected_patch("f#$selected_octave") when ("g");
		 play_selected_patch("g$selected_octave") when ("b");
		 play_selected_patch("g#$selected_octave") when ("h");
		 play_selected_patch("a$selected_octave") when ("n");
		 play_selected_patch("a#$selected_octave") when ("j");
		 play_selected_patch("b$selected_octave") when ("m");

		 play_selected_patch("c".($selected_octave+1)) when ("comma");
		 play_selected_patch("d".($selected_octave+1)) when ("period");
	}
}

# menu - https://docstore.mik.ua/orelly/perl3/tk/ch12_02.htm
$mw->configure(-menu => my $menubar = $mw->Menu);
my $file = $menubar->cascade(-label => '~File'); 
#my $edit = $menubar->cascade(-label => '~Edit'); 
#my $help = $menubar->cascade(-label => '~Help');

# my $new = $file->cascade(
#     -label       => 'New',
#     -accelerator => 'Ctrl-n',
#     -underline   => 0,
# );
# $file->separator;
# $file->command(
#     -label       => 'Open',
#     -accelerator => 'Ctrl-o',
#     -underline   => 0,
# );
# $file->separator;
$file->command(
    -label       => 'Save',
    -accelerator => 'Ctrl-s',
    -underline   => 0,
	-command => sub {
		# save file to json

		# https://stackoverflow.com/a/3408107/74585
		JSON::Syck::DumpFile("patches.json", $synth);
	}
);
# $file->command(
#     -label       => 'Save As ...',
#     -accelerator => 'Ctrl-a',
#     -underline   => 1,
# );
# $file->separator;
# $file->command(
#     -label       => "Close",
#     -accelerator => 'Ctrl-w',
#     -underline   => 0,
#     -command     => \&exit,
# );
# $file->separator;
# $file->command(
#     -label       => "Quit",
#     -accelerator => 'Ctrl-q',
#     -underline   => 0,
#     -command     => \&exit,
# );

CenterWindow($mw, 800, 400);
MainLoop;

sub getSelectedPatch {
	return $synth->{Patches}->{ $lbox->get( $lbox->curselection->[0] ) };
}

sub changePatch {

	# called when we change the patch in the listbox on the side

	my $selected_patch = getSelectedPatch();

	# clear the voice table
	$table->clear();

	my $row_index = 0;

	# patch widgets

	# chord
	$table->put($row_index, 0,
		"Chord"
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

	if( $selected_patch->{chord} ) {
		$synth->render_patch($selected_patch, [name2freq('f3'), name2freq('a3'), name2freq('c4'), name2freq('e4')]);
	} else {		
		$synth->render_patch($selected_patch, [name2freq('c3')]);
	}

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
	print $voice->{tuned};
	$table->put($row_index, $col++,
		$table->Checkbutton(-variable => \$voice->{tuned}, -command => sub{ OnPatchChange($patch) } )
	);

	# f multiplier
	$table->put($row_index, $col++,
		$table->Spinbox(-from => -1000, -to => 1000, -increment => 0.1, -width => 9, -textvariable => \$voice->{freq_multiplier}, -command => sub{ OnPatchChange($patch) } )
	);

	# v multiplier
	$table->put($row_index, $col++,
		$table->Spinbox(-from => -1000, -to => 1000, -increment => 0.1, -width => 9, -textvariable => \$voice->{volume_multiplier}, -command => sub{ OnPatchChange($patch) } )
	);

	# f Decay
	$table->put($row_index, $col++,
		$table->Spinbox(-from => -1000, -to => 1000, -increment => 0.001, -width => 9, -textvariable => \$voice->{freq_decay}, -command => sub{ OnPatchChange($patch) } )
	);

	# v Decay
	$table->put($row_index, $col++,
		$table->Spinbox(-from => -1000, -to => 1000, -increment => 0.00001, -width => 9, -textvariable => \$voice->{volume_decay}, -command => sub{ OnPatchChange($patch) } )
	);

	# delay
	$table->put($row_index, $col++,
		$table->Spinbox(-from => -1000, -to => 1000, -increment => 0.01, -width => 9, -textvariable => \$voice->{delay}, -command => sub{ OnPatchChange($patch) } )
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
	print Dumper( $patch->{name} );

	#print "OnPatchChange\n";

	$mw->Busy;
	$mw->update;

	print "chord = " . $patch->{chord};

	if( $patch->{chord} ) {
		$synth->render_patch($patch, [name2freq('f3'), name2freq('a3'), name2freq('c4'), name2freq('e4')]);
	} else {		
		$synth->render_patch($patch, [name2freq('c3')]);
	}

	$mw->Unbusy;
	$mw->update;

	$synth->play_patch($patch, undef, name2freq('c' . $selected_octave));
	#$dialog->Show();
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

	my $keys = 12;
	my $start_pitch = name2pitch('c' . $selected_octave);

	my $table = $mw->Table(-rows => 2, -columns => $keys, -fixedrows => 1);

	for( my $pitch=$start_pitch; $pitch<$start_pitch+$keys; $pitch++ ) {
		my $name = pitch2name($pitch);

		my $bt;
		if( $name =~ /#/ ) {
			$bt = build_key($table, $name, 3, "black");	# black key
			$table->put(0,$pitch-$start_pitch,$bt);
		} else {
			$bt = build_key($table, $name, 4, "white");	# white key
			$table->put(1,$pitch-$start_pitch,$bt);
		}
	}

	$table->pack;
}

sub build_key {

	my( $table, $name, $height, $background ) = @_;

	my $bt = $table->Button(
		-text			=> $name,
		-width		=> 3,
		-height		=> $height,
		-background => $background,
		-command => sub {
			play_selected_patch($name);			# name is kind of like a closure?
		}
	);

	# triggered when the button is pressed
	#$bt->bind('<Button-1>'        => sub {
	#	print "yo\n";
	#});

	return $bt;
}

sub play_selected_patch {

	my($name) = @_;
	
	$synth->play_patch(getSelectedPatch(), undef, name2freq($name));	# name is kind of like a closure
}
