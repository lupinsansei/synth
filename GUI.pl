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

# experimented to try and get export to json to work
#use JSON;
#use JSON::Any;
#use File::Slurp;
use JSON::Syck;		# I think only this one worked

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
			chord => 1,
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

my $table = $mw->Table(-rows => 10, -columns => 11, -fixedrows => 1);

my $dialog = $mw->Dialog(-text => 'Save File?', -bitmap => 'question', -title => 'Save File Dialog', -default_button => 'Yes', -buttons => [qw/Yes No Cancel/]);

my @voices = qw();

# we want to model a single patch in a patch panel and that has multiple voices
# we can change the patch later by selecting one from a list box

$table->pack;

my $selected_octave = 3;
build_keyboard($mw);

$mw->bind('<KeyPress>' => \&print_keysym);

sub print_keysym {

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
		play_selected_patch($note);
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

setSelectedPatchByName("bass");

MainLoop;

sub getSelectedPatch {
	return $synth->{Patches}->{ $lbox->get( $lbox->curselection->[0] ) };
}

sub setSelectedPatchByName
{
	my($name) = @_;
	
	my @elements = $lbox->get(0, 'end');
	for(my $i=0; $i<@elements; $i++ ) {
		if( $elements[$i] eq $name ) {
			$lbox->selectionSet($i);
		}
	}
	changePatch();
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

	$synth->render_patch_as_middle_c($selected_patch);

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
		#build_super_number_picker($table, 3, \$voice->{freq_multiplier}, sub{ OnPatchChange($patch) } )
		build_super_number_picker2($table, 3, 1, \$voice->{freq_multiplier}, sub{ OnPatchChange($patch) } )
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
	#print Dumper( $patch->{voices} );

	$mw->Busy;
	$mw->update;
	
	$synth->render_patch_as_middle_c($patch);

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

	my( $table, $note, $height, $background ) = @_;

	my $bt = $table->Button(
		-text		=> $note,
		-width		=> 3,
		-height		=> $height,
		-background => $background,
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

sub build_super_number_picker {
	
	my( $parent_table, $digits, $textvariable, $command ) = @_;
	
	my $table = $parent_table->Table(-rows => 1, -columns => $digits, -fixedrows => 1);
	$table->pack;
	
	my $increment = 1;
	
	# the first digit before the decimal place
	$table->put(0, 0,
		$table->Spinbox( -from => -1000, -to => 1000, -increment => 1, -width => 4, -textvariable => $textvariable, -command => $command ),		
	);
	
	# build the rest of the digits
	for(my $digit=1; $digit<$digits; $digit++) {
		
		$increment = $increment / 10;
		
		my $widget = undef;
		$widget = $table->Spinbox( -from => -1000, -to => 1000, -increment => $increment, -width => 1, -textvariable => $textvariable, -command => sub {
			
			
			&$command;
		
			
			# I think I need closures to do this 
			# my question! https://stackoverflow.com/questions/68141512/can-a-perl-tk-widget-command-access-itself#68141785
			# https://www.perlmonks.org/?node_id=274254
			# https://stackoverflow.com/questions/32834508/perl-tk-tcl-can-widget-callbacks-take-parameters
			

			# we can access the spinbox in here by making sure that the variable we assign it to is already declared first
			# e.g. print $widget->cget(-increment);
			# we can't use $digit anyway as it's stuck at 4, it's final value
			# maybe increment is enough, we should be able to work $digit back from this via some algorithm
			
			$widget->xview($digit+1);	# To only show the digit we want out of the whole number the variable is bound to. I don't know why this works! I thought we would need $self or $this or something here
		});	
		
		$widget->xview($digit+1);
	
		$table->put(0, $digit, $widget);
	}
	
	return $table;
}

sub build_super_number_picker2 {
	
	my( $parent_table, $digits, $decimal_point_position, $textvariable, $command ) = @_;
	
	my $widget_count = $digits+1; # +1 for the decimal point
	
	my $table = $parent_table->Table(
		-rows => 1, 
		-columns => $widget_count,
		-scrollbars => ''	# none
	);
	$table->pack;
	
	my $increment = 1;
	
	# # the first digit before the decimal place
	# $table->put(0, 0,
		# $table->Spinbox( -from => -1000, -to => 1000, -increment => 1, -width => 4, -textvariable => $textvariable, -command => $command ),		
	# );
	
	my @spinboxes = ();

	print "textvariable:";
	print $$textvariable;

	# build the rest of the digits
	for(my $digit=0; $digit<$widget_count; $digit++) {
		
		#$increment = $increment / 10;
		
		my $widget = undef;
		
		if( $digit == $decimal_point_position ) {
			$widget = ".";		
		} else {		
		
			my $this_spinbox_index = $digit;
			
			# let's set the value of this spinbox from $textvariable dividing by 10 each time?
			
			$widget = $table->Spinbox( -from => 0, -to => 9, -increment => $increment, -width => 1, -command => sub {

				my( $value, $action ) = @_;

				print "Spinbox command $value $action\n";

				$$textvariable = $value;	# this is the bit that updates the variable to have a new value

				print "textvariable:";
				print $$textvariable;	# this comes out as 2 when we print it, I think that's it's value
				print "\n";
				
				# next we want to patch $textvariable by reading out the values of all the other spinboxes around us
					# do we, or can we just work out what position we are in the decimal thing?

				# for now who cares about incrementing up or down!
				#if( $action eq "up" && $value == 10 ) {
				#	print "increment left\n";
				#}

				#if( $action eq "down" && $value == -1 ) {
				#	print "go down";
				#}				
				
				#print "this_spinbox_index = $this_spinbox_index ";
				#print @spinboxes;	# these are all the other spinboxes, next we need to work out which one we are, which index
								
				&$command;
			
				# I think I need closures to do this 
				# my question! https://stackoverflow.com/questions/68141512/can-a-perl-tk-widget-command-access-itself#68141785
				# https://www.perlmonks.org/?node_id=274254
				# https://stackoverflow.com/questions/32834508/perl-tk-tcl-can-widget-callbacks-take-parameters				
			});
			
			push(@spinboxes, $widget);
		}
	
		$table->put(0, $digit, $widget);
	}
	
	return $table;
}