use Win32::Sound;
 
# Create the object
my $WAV = new Win32::Sound::WaveOut(44100, 8, 2);
 
my $data = "";
my $counter = 0;

my $carrier_freq = 440;
my $modulator_freq = 1;
my $modulator2_freq = 2;

use Time::HiRes qw( time );
my $start = time();

my @data_l = ();
my @data_r = ();

# Generate 44100 samples ( = 1 second)
for my $i (1..(44100*5)) {

    # Calculate the pitches
    # (range 0..255 for 8 bits) 
	my $modulator_v	= sin($modulator_counter*2*3.14) * 127 + 128;
	my $modulator2_v	= sin($modulator2_counter*2*3.14) * 127 + 128;
    my $carrier_v	= sin($carrier_counter*2*3.14) * 127 + 128;
 
	$data_l[$i] = $carrier_v;
	$data_r[$i] = $carrier_v;	
	
	$carrier_increment = ($carrier_freq + $modulator_v + $modulator2_v)/44100;		# modulate the carrier frequency with the current level of modulator_v
    $carrier_counter += $carrier_increment;
	
	$modulator_increment = ($modulator_freq)/44100;	
	$modulator_counter += $modulator_increment;
	
	# sweep the modulator freq
	$modulator_freq = $modulator_freq - ($modulator_freq/44100) * 2.6;
	if( $modulator_freq < 0 ) {
		$modulator_freq = 0;
	}
	
	$modulator2_increment = $modulator2_freq/44100;	
	$modulator2_counter += $modulator2_increment;
	
	# sweep the modulator freq
	#$modulator2_freq = $modulator2_freq + ($modulator2_freq/44100);
}

print "$carrier_freq\n";
print "$modulator_freq\n";

# "pack" it twice for left and right
for( $i = 0; $i<scalar @data_l-1; $i++ ) {
	$data .= pack("CC", $data_l[$i], $data_r[$i]);
}

my $end = time();
printf("Run time: %.2f\n", $end - $start);
 
$WAV->Load($data);       # get it

$WAV->Write();           # hear it
1 until $WAV->Status();  # wait for completion
$WAV->Save("sinus.wav"); # write to disk
$WAV->Unload();          # drop it