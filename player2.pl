use strict;
use warnings;
use Win32::Sound;
use MIDI::Pitch qw(name2freq);
use Sampler;
use Data::Dumper;
use Time::HiRes qw( time );
use feature qw( say switch );
no warnings "experimental";

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
   T_KEY				=> 84,   
   Y_KEY				=> 89,
   U_KEY				=> 85,
   I_KEY				=> 73,
   O_KEY				=> 79,
   P_KEY				=> 80,
   
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

my $sampler = new Sampler(
	directory => 'C:\development\synth\wav'
);
$sampler->load();

my $con_in = Win32::Console->new(STD_INPUT_HANDLE);

my $freq = 44100;

my $octave = 3;

for (;;) {
	my @event = $con_in->Input();

	my $event_type = shift(@event);
	next if !defined($event_type) || $event_type != 1;  # 1: Keyboard

	my ($key_down, $repeat_count, $vkcode, $vscode, $char, $ctrl_key_state) = @event;
	
	#print "vkcode = $vkcode\n";

	if( !$key_down ) {		
		$sampler->stop_patch($vkcode);
		next;
	}
	
	# octave selectors
	if( $vkcode == 49 ) {
		$octave = 1;			
		#print "Octave: 1\r";
	}
	if( $vkcode == 50 ) {
		$octave = 2;			
		#print "Octave: 2\r";
	}
	if( $vkcode == 51 ) {
		$octave = 3;			
		#print "Octave: 3\r";
	}
	if( $vkcode == 52 ) {
		$octave = 4;			
		#print "Octave: 4\r";
	}	
	
	my $sample = undef;
	my $frequency = 0;
	
	given($vkcode) {
	
		# sample chopper	
	
		# my $chunk = 18_750;
		# # we need to be able to specify the chunks of the sample here by getting he length of it
		
		# if( $vkcode == Y_KEY ) {
			# $sampler->play_patch($vkcode, name2freq('c3'), 0, $chunk);
		# }
		# if( $vkcode == U_KEY ) {
			# $sampler->play_patch($vkcode, name2freq('c3'), $chunk, $chunk);
		# }
		# if( $vkcode == I_KEY ) {
			# $sampler->play_patch($vkcode, name2freq('c3'), $chunk * 2, $chunk);
		# }
		# if( $vkcode == O_KEY ) {
			# $sampler->play_patch($vkcode, name2freq('c3'), $chunk * 3, $chunk);
		# }	
	
		# sample selector
		when(Q_KEY) { $sample = 0; }
		when(W_KEY) { $sample = 1; }
		when(E_KEY) { $sample = 2; }
		when(R_KEY) { $sample = 3; }
		when(T_KEY) { $sample = 4; }
		when(Y_KEY) { $sample = 5; }
		when(U_KEY) { $sample = 6; }
		when(I_KEY) { $sample = 7; }
		when(O_KEY) { $sample = 8; }
		when(P_KEY) { $sample = 9; }
	
		# musical keyboard for current select sample (last played one)
		when(Z_KEY) { $frequency = name2freq('c'.$octave); }
		when(S_KEY) { $frequency = name2freq('c#'.$octave); }
		when(X_KEY) { $frequency = name2freq('d'.$octave); }
		when(D_KEY) { $frequency = name2freq('d#'.$octave); }
		when(C_KEY) { $frequency = name2freq('e'.$octave); }
		when(V_KEY) { $frequency = name2freq('f'.$octave); }
		when(G_KEY) { $frequency = name2freq('f#'.$octave); }
		when(B_KEY) { $frequency = name2freq('g'.$octave); }
		when(H_KEY) { $frequency = name2freq('g#'.$octave); }
		when(N_KEY) { $frequency = name2freq('a'.$octave); }
		when(J_KEY) { $frequency = name2freq('a#'.$octave); }
		when(M_KEY) { $frequency = name2freq('b'.$octave); }
		
		when(COMMA_KEY) { $frequency = name2freq('c'.($octave+1)); }
		when(L_KEY) { $frequency = name2freq('c#'.($octave+1)); }
		when(PERIOD_KEY) { $frequency = name2freq('d'.($octave+1)); }
		when(SEMICOLON_KEY) { $frequency = name2freq('d#'.($octave+1)); }
		when(FORWARD_SLASH_KEY) { $frequency = name2freq('e'.($octave+1)); }
	}
	
	if( $frequency ) {
		$sampler->play_patch($vkcode, $frequency);
		
	}
	
	if( defined $sample ) {
		$sampler->select_sample($vkcode, name2freq('c'.$octave), $sample);	
	}
}