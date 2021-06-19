use strict;
use warnings;
use Win32::Sound;
use MIDI::Pitch qw(name2freq);
use Synth;
use Patch;
use Voice;
use Data::Dumper;
use Time::HiRes qw( time );

use feature qw( say );

use Win32::Console qw( STD_INPUT_HANDLE );

use constant {
   RIGHT_ALT_PRESSED  => 0x0001,
   LEFT_ALT_PRESSED   => 0x0002,
   RIGHT_CTRL_PRESSED => 0x0004,
   LEFT_CTRL_PRESSED  => 0x0008,
   SHIFT_PRESSED      => 0x0010,

   VK_UP => 0x26,
   
   Q_KEY				=> 81,
   W_KEY				=> 87,
   E_KEY				=> 69,
   R_KEY				=> 82,
   
   Y_KEY				=> 89,
   U_KEY				=> 85,
   I_KEY				=> 73,
   O_KEY				=> 79,
   
   Z_KEY				=> 90,
   S_KEY				=> 83,
   X_KEY				=> 88,
   D_KEY				=> 68,
   C_KEY				=> 67,   
   V_KEY				=> 86,
   G_KEY				=> 71,
   B_KEY				=> 66,
   H_KEY				=> 72,
   N_KEY				=> 78,
   J_KEY				=> 74,
   M_KEY				=> 77,
   COMMA_KEY			=> 188,
   L_KEY				=> 76,
   PERIOD_KEY			=> 190,
   SEMICOLON_KEY		=> 186,
   FORWARD_SLASH_KEY	=> 191
};

use constant SHIFTED_MASK =>
   RIGHT_ALT_PRESSED |
   LEFT_ALT_PRESSED |
   RIGHT_CTRL_PRESSED |
   LEFT_CTRL_PRESSED |
   SHIFT_PRESSED;

# http://search.cpan.org/dist/Music-Scales-0.07/lib/Music/Scales.pm
# http://search.cpan.org/~mlehmann/PDL-Audio-1.2/audio.pd
# http://search.cpan.org/dist/Audio-Analyzer-0.22/
# http://search.cpan.org/dist/Music-Note-0.01/lib/Music/Note.pm

# note if samples aren't the same length then a shorter one loaded into the audio buffer doesn't fully clear the longer one

my $synth = new Synth(
	Patches => {
		"snare" => new Patch( 
			name => "snare",
			length => 1,
			voices => [
				new Voice( wave => 'sine', freq_decay => 0.004, volume_decay => 0.000005 ),
				#new Voice( wave => 'noise', delay => 1000, tuned => 0, volume_decay => 0.0002 ),
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
				 new Voice( freq_multiplier => 2, freq_decay => 0.0004,
				 modulators => [
						new Voice( freq_multiplier => 4, freq_decay => 0.0002, volume_multiplier => 0.055, volume_decay => 0.000003 ),	
						new Voice( freq_multiplier => 8.1, freq_decay => 0.0003, volume_multiplier => 0.03, volume_decay => 0.0000001 ),
						new Voice( freq_multiplier => 16.1, freq_decay => 0.0003, volume_multiplier => 0.03, volume_decay => 0.0000001 ),
						#new Voice( freq_multiplier => 4.1, volume_multiplier => 0.40, volume_decay => 0.00005 ),
					 ]
				 )
			]
		),
		"amen" => new Patch(
			name => "amen",
			decay => 8,
			voices => [
				new Voice( wave => 'file', file => 'C:\development\synth\WAV\cw_amen19_172.wav', freq_decay => 0.04 )
			],
			#decay => 0.25
		),
	}
);

my $con_in = Win32::Console->new(STD_INPUT_HANDLE);

my $freq = 44100;

my $selected_patch;

my $octave = 2;

my $sample_length = 1;

for (;;) {
	my @event = $con_in->Input();

	my $event_type = shift(@event);
	next if !defined($event_type) || $event_type != 1;  # 1: Keyboard

	my ($key_down, $repeat_count, $vkcode, $vscode, $char, $ctrl_key_state) = @event;

	#print "key press vkcode = $vkcode\n";

	# if ($vkcode == 90 && ($ctrl_key_state & SHIFTED_MASK) == 0) {
		# if ($key_down) {
			# say "$vkcode down" for 1..$repeat_count;
		# } else {
			# say "$vkcode released";
		# }
	# }

	if( !$key_down ) {		
		$synth->stop_patch($vkcode);
		next;
	}
	
	if( $vkcode == Q_KEY ) {
		
		$selected_patch = $synth->{Patches}->{ "snare" };
		$synth->render_patch($selected_patch, [name2freq('f3')]);		
		
		$sample_length = scalar @{$selected_patch->{rendered_sample}->[0]};	
		print "sample length = $sample_length\n";
	}
	
	if( $vkcode == W_KEY ) {
		
		$selected_patch = $synth->{Patches}->{ "hihat" };
		$synth->render_patch($selected_patch, [name2freq('g3')]);
		
		$sample_length = scalar @{$selected_patch->{rendered_sample}->[0]};	
		print "sample length = $sample_length\n";
	}
	
	if( $vkcode == E_KEY ) {
		
		$selected_patch = $synth->{Patches}->{ "bass" };
		$synth->render_patch_as_middle_c($selected_patch);
		
		$sample_length = scalar @{$selected_patch->{rendered_sample}->[0]};	
		print "sample length = $sample_length\n";
	}
	
	if( $vkcode == R_KEY ) {

		$selected_patch = $synth->{Patches}->{ "amen" };		
		$synth->render_patch_as_middle_c($selected_patch);
		
		$sample_length = scalar @{$selected_patch->{rendered_sample}->[0]};	
		print "sample length = $sample_length\n";
	}

	if( $vkcode == 49 ) {
		$octave = 1;			
		print "Octave: 1\n";
	}
	if( $vkcode == 50 ) {
		$octave = 2;			
		print "Octave: 2\n";
	}
	if( $vkcode == 51 ) {
		$octave = 3;			
		print "Octave: 3\n";
	}
	if( $vkcode == 52 ) {
		$octave = 4;			
		print "Octave: 4\n";
	}	

	# sample chopper
	
	my $divider = 16;
	my $chop_length = $sample_length/$divider;
	
	if( $vkcode == Y_KEY ) {
		$synth->play_patch($selected_patch, $vkcode, name2freq('c3'), 0, $chop_length);
	}
	if( $vkcode == U_KEY ) {
		$synth->play_patch($selected_patch, $vkcode, name2freq('c3'), $chop_length, $chop_length);
	}
	if( $vkcode == I_KEY ) {
		$synth->play_patch($selected_patch, $vkcode, name2freq('c3'), $chop_length * 2, $chop_length);
	}
	if( $vkcode == O_KEY ) {
		$synth->play_patch($selected_patch, $vkcode, name2freq('c3'), $chop_length * 3, $chop_length);
	}
	
	
	# musical keyboard
	next unless $selected_patch;

	$synth->play_patch($selected_patch, $vkcode, name2freq('c'.$octave)) if $vkcode == Z_KEY;	
		$synth->play_patch($selected_patch, $vkcode, name2freq('c#'.$octave)) if $vkcode == S_KEY;
	$synth->play_patch($selected_patch, $vkcode, name2freq('d'.$octave)) if $vkcode == X_KEY;
		$synth->play_patch($selected_patch, $vkcode, name2freq('d#'.$octave)) if $vkcode == D_KEY;
	$synth->play_patch($selected_patch, $vkcode, name2freq('e'.$octave)) if $vkcode == C_KEY;
	
	$synth->play_patch($selected_patch, $vkcode, name2freq('f'.$octave)) if $vkcode == V_KEY;
		$synth->play_patch($selected_patch, $vkcode, name2freq('f#'.$octave)) if $vkcode == G_KEY;
	$synth->play_patch($selected_patch, $vkcode, name2freq('g'.$octave)) if $vkcode == B_KEY;	
		$synth->play_patch($selected_patch, $vkcode, name2freq('g#'.$octave)) if $vkcode == H_KEY;
	$synth->play_patch($selected_patch, $vkcode, name2freq('a'.$octave)) if $vkcode == N_KEY;
		$synth->play_patch($selected_patch, $vkcode, name2freq('a#'.$octave)) if $vkcode == J_KEY;
	$synth->play_patch($selected_patch, $vkcode, name2freq('b'.$octave)) if $vkcode == M_KEY;

	$synth->play_patch($selected_patch, $vkcode, name2freq('c'.($octave+1))) if $vkcode == COMMA_KEY;
		$synth->play_patch($selected_patch, $vkcode, name2freq('c#'.($octave+1))) if $vkcode == L_KEY;
	$synth->play_patch($selected_patch, $vkcode, name2freq('d'.($octave+1))) if $vkcode == PERIOD_KEY;
		$synth->play_patch($selected_patch, $vkcode, name2freq('d#'.($octave+1))) if $vkcode == SEMICOLON_KEY;
	$synth->play_patch($selected_patch, name2freq('e'.($octave+1))) if $vkcode == FORWARD_SLASH_KEY;
	
}

# my $sample1 = Patch::mix_samples(
	# Patch::filter( $snare_drum->render( name2freq('d2') ), 2 )
	# #$synth1->render( name2freq('c5') ),
	# #$synth1->render( name2freq('g4') )
# );


#my $sample1 = Patch::filter( $snare_drum->render( name2freq('d2') ), [
#	{ delay => 1, gain => 0.5, feedback => 0 },
#] );
#$sample1 = $snare_drum->render( 22_000 );

#$sample1 = $snare_drum->render( name2freq('d3') );

#$WAV->Save("sinus.wav");			# write to disk
#$WAV->Unload();          			# drop it

#my $in = Win32::Console->new(STD_INPUT_HANDLE);	# https://stackoverflow.com/questions/10172253/how-to-read-in-special-keys-with-win32console
#$in->Mode(ENABLE_PROCESSED_INPUT);

# for(;;) {	

	# my $result = $in->InputChar(1);
	# print "<$result>";
# }

# for (;;) {	
	# print "x";
	# my $result = $in->InputChar(1);
	# print "<$result>";


# }

#print "<$result>";


# my $con_in = Win32::Console->new(STD_INPUT_HANDLE);
# $con_in->Mode(ENABLE_PROCESSED_INPUT);
# for (;;) {
   # my @event = $con_in->Input();
   
   # print "x";

   # my $event_type = shift(@event);
   # next if !defined($event_type) || $event_type != 1;  # 1: Keyboard

   # my ($key_down, $repeat_count, $vkcode, $vscode, $char, $ctrl_key_state) = @event;
   
   # print $vkcode;
   
   # if ($vkcode == VK_UP && ($ctrl_key_state & SHIFTED_MASK) == 0) {
      # if ($key_down) {
         # print "<Up> pressed/held down" for 1..$repeat_count;
      # } else {
         # print "<Up> released";
      # }
   # }
# }