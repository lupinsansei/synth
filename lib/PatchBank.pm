package PatchBank;
use strict;
use warnings;
use JSON::PP;
use File::Spec;
use File::Basename qw(dirname);
use File::Temp qw(tempfile);
use Scalar::Util qw(looks_like_number);
use POSIX qw(isfinite);
use ChordMemory qw(chord_intervals);
use FMPatchExplorer;
my $FORMAT='perl-synth-patch-bank';
my $MAX_BYTES=8*1024*1024;
sub _number {
 my($v,$min,$max,$label)=@_;
 die "Invalid $label" unless defined $v && !ref($v) && looks_like_number($v) && isfinite($v) && $v>=$min && $v<=$max;
 return 0+$v;
}
sub _boolean {
 my($v,$label)=@_;
 die "Invalid $label" if !defined $v || (ref($v) && !JSON::PP::is_bool($v)) || ($v ne '0' && $v ne '1');
 return $v?1:0;
}
sub _keys {
 my($data,$allowed,$label)=@_;die "Expected $label object" unless ref($data) eq 'HASH';
 my %ok=map{$_=>1}@$allowed;die "Unknown $label field" if grep{!$ok{$_}}keys %$data;
}
sub _text {
 my($v,$label)=@_;die "Invalid $label" unless defined $v && !ref($v) && length($v) && length($v)<=1024 && $v !~ /[\x00-\x1f]/;
 return $v;
}
sub _voice {
 my($v,$depth,$count)=@_;die 'Patch has too many/deeply nested voices' if $depth>8 || ++$$count>256;
 _keys($v,[qw(wave file tuned freq_multiplier volume_multiplier freq_decay volume_decay delay modulators)],'voice');
 my %out;my $wave=$v->{wave}//'sine';die 'Unsupported waveform' unless $wave =~ /\A(?:sine|noise|file)\z/;$out{wave}=$wave;
 for my $key(qw(freq_multiplier volume_multiplier freq_decay volume_decay delay)) {
  $out{$key}=_number($v->{$key},-1000,1000,$key) if exists $v->{$key};
 }
 $out{tuned}=_boolean($v->{tuned},'tuned') if exists $v->{tuned};
 if(defined $v->{file} && $v->{file} ne '') {$out{file}=_text($v->{file},'sample path');}
 die 'File voice needs a sample path' if $wave eq 'file' && !length($out{file}//'');
 if(exists $v->{modulators}) {
  die 'Modulators must be an array' unless ref($v->{modulators}) eq 'ARRAY';
  $out{modulators}=[map{_voice($_,$depth+1,$count)}@{$v->{modulators}}];
 }
 return \%out;
}
sub _validate {
 my($data)=@_;
 _keys($data,[qw(format version selected_patch synth patches)],'bank');
 die 'Not a synth patch bank' unless ($data->{format}//'') eq $FORMAT;
 die 'Unsupported patch bank version' unless defined $data->{version} && !ref($data->{version}) && $data->{version} eq '1';
 my $patches=$data->{patches};die 'Expected 1..128 patches' unless ref($patches) eq 'HASH' && keys(%$patches)>=1 && keys(%$patches)<=128;
 my %out;my $count=0;
 for my $name(sort keys %$patches) {
  _text($name,'patch name');my $p=$patches->{$name};_keys($p,[qw(name length attack decay chord voices)],'patch');
  my %p=(name=>_text($p->{name}//$name,'patch name'));
  for my $key(qw(length attack decay)) {$p{$key}=_number($p->{$key},0,60,$key) if exists $p->{$key};}
  $p{chord}=_boolean($p->{chord},'baked chord') if exists $p->{chord};
  die 'Patch needs 1..32 voices' unless ref($p->{voices}) eq 'ARRAY' && @{$p->{voices}} && @{$p->{voices}}<=32;
  $p{voices}=[map{_voice($_,0,\$count)}@{$p->{voices}}];$out{$name}=\%p;
 }
 my $settings=$data->{synth}//{};_keys($settings,[qw(samplerate bits channels chord_memory chord_type chord_mode arpeggio_ms)],'synth settings');
 my %settings=(samplerate=>44100,bits=>16,channels=>2,chord_memory=>0,chord_type=>'Major 7th',chord_mode=>'Together',arpeggio_ms=>120);
 $settings{samplerate}=_number($settings->{samplerate},8000,192000,'sample rate') if exists $settings->{samplerate};
 die 'Sample rate must be an integer' unless int($settings{samplerate})==$settings{samplerate};
 # Existing sample2wav packs stereo 16-bit PCM. Reject unsupported formats rather than silently misplaying them.
 die 'Only stereo 16-bit banks are supported' if (exists $settings->{bits} && $settings->{bits}!=16) || (exists $settings->{channels} && $settings->{channels}!=2);
 $settings{chord_memory}=_boolean($settings->{chord_memory},'chord memory') if exists $settings->{chord_memory};
 if(exists $settings->{chord_type}) {chord_intervals($settings->{chord_type});$settings{chord_type}=$settings->{chord_type};}
 if(exists $settings->{chord_mode}) {die 'Invalid chord playback mode' unless !ref($settings->{chord_mode}) && ($settings->{chord_mode} eq 'Together' || $settings->{chord_mode} eq 'Arpeggio');$settings{chord_mode}=$settings->{chord_mode};}
 if(exists $settings->{arpeggio_ms}) {$settings{arpeggio_ms}=_number($settings->{arpeggio_ms},40,1000,'arpeggio step');die 'Arpeggio step must be an integer' unless int($settings{arpeggio_ms})==$settings{arpeggio_ms};}
 my $selected=$data->{selected_patch}//(sort keys %out)[0];
 die 'Selected patch is missing' unless !ref($selected) && exists $out{$selected};
 return {format=>$FORMAT,version=>1,selected_patch=>$selected,synth=>\%settings,patches=>\%out};
}
sub capture {
 my($class,$synth,%args)=@_;my %patches;my $snapshot=FMPatchExplorer->new;
 for my $name(keys %{$synth->Patches}) {
  my $patch=$synth->Patches->{$name};$patches{$name}={%{$snapshot->snapshot($patch)},name=>$patch->name//$name};
 }
 return _validate({format=>$FORMAT,version=>1,selected_patch=>$args{selected_patch}//(sort keys %patches)[0],patches=>\%patches,
   synth=>{map{$_=>$synth->$_}qw(samplerate bits channels chord_memory chord_type chord_mode arpeggio_ms)}});
}
sub _paths {
 my($doc,$callback)=@_;my $walk;$walk=sub{my $v=shift;$v->{file}=$callback->($v->{file}) if defined $v->{file} && length $v->{file};$walk->($_) for @{$v->{modulators}||[]};};
 for my $p(values %{$doc->{patches}}) {$walk->($_) for @{$p->{voices}};}
}
sub save_file {
 my($class,$path,$synth,%args)=@_;die 'Choose a bank filename' unless defined $path && length $path;
 my $doc=$class->capture($synth,%args);my $dir=File::Spec->rel2abs(dirname($path));
 _paths($doc,sub {
  my $file=shift;
  # File::Spec on Windows handles drive paths; foreign absolute references are preserved for a clear missing-file error.
  return $file if $^O ne 'MSWin32' && $file =~ /^[A-Za-z]:[\\\/]/;
  my $abs=File::Spec->rel2abs($file);my $relative=File::Spec->abs2rel($abs,$dir);$relative =~ s{\\}{/}g;return $relative;
 });
 my $encoded=JSON::PP->new->utf8->canonical->pretty->encode($doc);
 die 'Patch bank is too large' if length($encoded)>$MAX_BYTES;
 my($handle,$temp)=tempfile('.synth-bank-XXXXXX',DIR=>$dir,UNLINK=>0);
 my $ok=eval {
  binmode($handle,':raw') or die "Cannot prepare patch bank: $!";
  print {$handle} $encoded or die "Cannot write patch bank: $!";
  close($handle) or die "Cannot finish patch bank: $!";
  rename($temp,$path) or die "Cannot replace patch bank (original retained): $!";
  1;
 };
 unless($ok) {my $error=$@;close($handle);unlink($temp);die $error;}
 return 1;
}
sub _legacy {
 my($old)=@_;die 'Not an old synth object dump' unless ref($old) eq 'HASH' && ref($old->{Patches}) eq 'HASH';
 die 'Expected 1..128 legacy patches' unless keys(%{$old->{Patches}}) && keys(%{$old->{Patches}})<=128;
 my %patches; my $count=0;
 for my $name(keys %{$old->{Patches}}) {
  my $p=$old->{Patches}{$name};die 'Invalid legacy patch' unless ref($p) eq 'HASH';
  my $copy={map{exists $p->{$_}?($_=>$p->{$_}):()}qw(name length attack decay chord voices)};
  my $walk;$walk=sub{
   my($v,$depth)=@_;die 'Legacy voices too deeply nested or numerous' if $depth>8 || ++$count>256;die 'Invalid legacy voice' unless ref($v) eq 'HASH';
   my $out={map{defined $v->{$_}?($_=>$v->{$_}):()}qw(wave file tuned freq_multiplier volume_multiplier freq_decay volume_decay delay)};
   if ($v->{modulators}) {die 'Invalid legacy modulators' unless ref($v->{modulators}) eq 'ARRAY';$out->{modulators}=[map{$walk->($_,$depth+1)}@{$v->{modulators}}];}return $out;
  };
  die 'Invalid legacy voices' unless ref($copy->{voices}) eq 'ARRAY';$copy->{voices}=[map{$walk->($_,0)}@{$copy->{voices}}];$patches{$name}=$copy;
 }
 return {format=>$FORMAT,version=>1,patches=>\%patches,synth=>{map{exists $old->{$_}?($_=>$old->{$_}):()}qw(samplerate bits channels chord_memory chord_type chord_mode arpeggio_ms)}};
}
sub read_file {
 my($class,$path,%args)=@_;
 open my $fh,'<:raw',$path or die "Cannot open patch bank: $!";
 my $bytes='';my $size=read($fh,$bytes,$MAX_BYTES+1);close $fh;
 die 'Cannot read patch bank' unless defined $size;die 'Patch bank is too large' if $size>$MAX_BYTES;
 my $data;my $imported_legacy=0;
 if($args{legacy}) {
  # Explicit opt-in only. This is the old JSON parser, NOT YAML/eval/Storable thaw.
  require JSON::Syck;$data=JSON::Syck::Load($bytes);$data=_legacy($data);$imported_legacy=1;
 } else {
  $data=eval{JSON::PP->new->utf8->max_depth(64)->decode($bytes)};
  die 'Not valid UTF-8 JSON. Old whole-object dumps may need Import legacy JSON; the current bank was not changed.' if $@;
  if(ref($data) eq 'HASH' && exists $data->{Patches} && !exists $data->{format}) {$data=_legacy($data);$imported_legacy=1;}
 }
 my $doc=_validate($data);my $dir=File::Spec->rel2abs(dirname($path));
 _paths($doc,sub{my $file=shift;return $file if $file =~ /^[A-Za-z]:[\\\/]/;return File::Spec->rel2abs($file,$dir)});
 require Patch;
 my %objects;
 for my $name(keys %{$doc->{patches}}) {
  my %p=%{$doc->{patches}{$name}};$p{voices}=[map{FMPatchExplorer::_voice($_)}@{$p{voices}}];
  $objects{$name}=Patch->new(%p);
 }
 return {patches=>\%objects,settings=>$doc->{synth},selected_patch=>$doc->{selected_patch},imported_legacy=>$imported_legacy};
}
1;
