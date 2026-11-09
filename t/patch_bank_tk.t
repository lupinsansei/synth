use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
BEGIN {$INC{'MIDI/Pitch.pm'}=__FILE__;package MIDI::Pitch;sub import {}}
use Synth;
use Patch;
use PatchBank::Tk;
my $mw=MainWindow->new;
my $dir=tempdir(CLEANUP=>1);
my($save_path,$open_path,@errors,$fail_apply);
my $synth=Synth->new(Patches=>{test=>Patch->new(name=>'Fixture',length=>0.01,voices=>[Voice->new])});
my $banks=PatchBank::Tk->new(parent=>$mw,capture=>sub{($synth,'test')},
 apply=>sub{die 'Fixture apply failure' if $fail_apply;my $b=shift;$synth=Synth->new(Patches=>$b->{patches},%{$b->{settings}})},
 choose_save=>sub{$save_path},choose_open=>sub{$open_path},error=>sub{push @errors,$_[0]});
ok(!$banks->save,'cancelled Save As makes no change');
ok(!defined $banks->current_file,'cancel keeps no current filename');
$save_path="$dir/a.synth.json";
ok($banks->save,'Save first prompts and writes');
is($banks->current_file,$save_path,'successful Save sets filename');
$synth->Patches->{test}->voices->[0]->freq_multiplier(3);
$save_path=undef;
ok($banks->save,'subsequent Save does not prompt');
$open_path=$banks->current_file;
$synth->Patches->{test}->voices->[0]->freq_multiplier(7);
ok($banks->open,'Open loads stored setting');
is($synth->Patches->{test}->voices->[0]->freq_multiplier,3,'stored rather than current setting loaded');
$fail_apply=1;
ok(!$banks->open,'apply failure reported');
like($errors[-1],qr/Fixture apply failure/,'useful apply error');
$fail_apply=0;$open_path=undef;
ok(!$banks->open,'cancelled Open harmless');
is($banks->current_file,"$dir/a.synth.json",'cancel retains last filename');
$save_path="$dir/nonexistent/b.synth.json";
ok(!$banks->save_as,'Save As failure reported');
is($banks->current_file,"$dir/a.synth.json",'Save As failure retains last filename');
SKIP: {
 skip 'Optional legacy parser unavailable',3 unless eval{require JSON::Syck;1};
 my $legacy={Patches=>{test=>{name=>'Old fixture',length=>0.01,voices=>[{wave=>'sine'}]}}};
 $open_path="$dir/old.json";open my $fh,'>:raw',$open_path or die $!;print {$fh} JSON::PP->new->encode($legacy);close $fh;
 ok($banks->open(legacy=>1),'explicit legacy import loads');
 ok(!defined $banks->current_file,'legacy import forces Save As to preserve original');
 is($synth->Patches->{test}->name,'Old fixture','legacy data applied');
}
$mw->destroy;
done_testing;
