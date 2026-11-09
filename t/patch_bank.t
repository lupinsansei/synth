use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Spec;
use JSON::PP;
BEGIN {
 $INC{'MIDI/Pitch.pm'}=__FILE__;
 package MIDI::Pitch;sub import {no strict 'refs';*{caller().'::name2freq'}=sub{130.81278265};}
}
use Synth;
use Patch;
use PatchBank;
my $dir=tempdir(CLEANUP=>1);
my $path="$dir/test.synth.json";
my $patch=Patch->new(name=>'Cloche café',length=>0.03,attack=>0.001,decay=>0.01,voices=>[
 Voice->new(freq_multiplier=>2,volume_multiplier=>0.2,volume_decay=>0.000001,delay=>0,
 modulators=>[Voice->new(freq_multiplier=>-0.5,volume_multiplier=>0.01,modulators=>[Voice->new(freq_multiplier=>3,volume_multiplier=>0.001)])])]);
my $synth=Synth->new(Patches=>{bell=>$patch},chord_memory=>1,chord_type=>'Minor 7th');
$patch->rendered_wave("PRIVATE RUNTIME CACHE\x00\xff");
$synth->Keys->{runtime}=[];
ok(PatchBank->save_file($path,$synth,selected_patch=>'bell'),'bank saved');
open my $fh,'<:raw',$path or die $!;local $/;my $bytes=<$fh>;close $fh;
unlike($bytes,qr/PRIVATE|rendered_|Channels|Keys/,'no binary buffers or playback state persisted');
my $loaded=PatchBank->read_file($path);
isa_ok($loaded->{patches}{bell},'Patch');
isa_ok($loaded->{patches}{bell}->voices->[0]->modulators->[0]->modulators->[0],'Voice');
is($loaded->{patches}{bell}->name,'Cloche café','UTF-8 name restored');
is($loaded->{selected_patch},'bell','selected patch retained');
is($loaded->{settings}{chord_type},'Minor 7th','chord preset retained');
is($loaded->{settings}{chord_memory},1,'playback chord toggle retained');
my $restored=Synth->new(Patches=>$loaded->{patches},%{$loaded->{settings}});
is_deeply(PatchBank->capture($restored),PatchBank->capture($synth),'all nested settings survive round trip');
is_deeply($patch->render(130.81278265,44100,16),$loaded->{patches}{bell}->render(130.81278265,44100,16),'restored FM patch renders the same waveform');
$patch->voices->[0]->freq_multiplier(4);
ok(PatchBank->save_file($path,$synth),'repeat save replaces existing bank');
is(PatchBank->read_file($path)->{patches}{bell}->voices->[0]->freq_multiplier,4,'replacement contains changed setting');
# Referenced assets are portable with the bank, not binary embedded data.
my $asset=File::Spec->catfile($dir,'tone.wav');
$synth->Patches->{sample}=Patch->new(name=>'Sample',voices=>[Voice->new(wave=>'file',file=>$asset)]);
PatchBank->save_file($path,$synth,selected_patch=>'bell');
my $assetbank=PatchBank->read_file($path);
is($assetbank->{patches}{sample}->voices->[0]->file,$asset,'relative WAV reference resolves against bank directory');
open $fh,'<:raw',$path or die $!;my $assetbytes=<$fh>;close $fh;
like($assetbytes,qr/"file"\s*:\s*"tone.wav"/,'sample reference stored relative to bank');
my $doc=PatchBank->capture($synth);
sub write_doc {open my $f,'>:raw',"$dir/invalid.json" or die $!;print {$f} JSON::PP->new->utf8->encode($_[0]);close $f;}
for my $case (
 ['fractional sample rate',sub{$_[0]{synth}{samplerate}=44100.5}],
 ['unknown version',sub{$_[0]{version}=9}],
 ['unknown field',sub{$_[0]{command}='never execute'}],
 ['missing selection',sub{$_[0]{selected_patch}='absent'}],
 ['invalid waveform',sub{$_[0]{patches}{bell}{voices}[0]{wave}='execute'}],
 ['unbounded duration',sub{$_[0]{patches}{bell}{length}=9999}],
 ['nonfinite setting',sub{$_[0]{patches}{bell}{voices}[0]{freq_multiplier}='NaN'}],
 ['invalid chord',sub{$_[0]{synth}{chord_type}='unknown'}],
 ['excessive nesting',sub{my $v=$_[0]{patches}{bell}{voices}[0];for(1..12){$v->{modulators}=[{wave=>'sine'}];$v=$v->{modulators}[0];}}]
) {
 my $copy=JSON::PP->new->decode(JSON::PP->new->encode($doc));$case->[1]->($copy);write_doc($copy);
 ok(!eval{PatchBank->read_file("$dir/invalid.json");1},"reject $case->[0]");
}
open $fh,'>:raw',"$dir/invalid.json" or die $!;print {$fh} '{truncated';close $fh;
ok(!eval{PatchBank->read_file("$dir/invalid.json");1},'truncated JSON rejected');
# A failed replacement must not remove the destination or leave partial temp files.
mkdir "$dir/destination" or die $!;
ok(!eval{PatchBank->save_file("$dir/destination",$synth);1},'failed replace reported');
ok(-d "$dir/destination",'existing destination retained');
is(scalar(glob("$dir/.synth-bank-*")),undef,'temporary save cleaned after failure');
# Old object dumps are whitelisted, never deserialised into arbitrary objects.
my $legacy={Patches=>$doc->{patches},samplerate=>44100,Channels=>['ignored'],arbitrary=>'ignored'};
$legacy->{Patches}{bell}{rendered_wave}='discard me';
write_doc($legacy);
my $old=PatchBank->read_file("$dir/invalid.json");
isa_ok($old->{patches}{bell},'Patch','legacy settings reconstructed');
ok(!exists $old->{patches}{bell}{rendered_wave},'legacy binary cache dropped');
SKIP: {
 skip 'Optional JSON::Syck legacy reader unavailable',1 unless eval{require JSON::Syck;1};
 my $import=PatchBank->read_file("$dir/invalid.json",legacy=>1);
 is(scalar keys %{$import->{patches}},2,'explicit old-parser import works');
}
done_testing;
