use strict;
use warnings;
use Config;
use Cwd qw(abs_path);
use FindBin;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use ExtUtils::ParseXS;
use ExtUtils::CBuilder;

# Install only for this interpreter's ABI, without changing the Perl installation.
my $root = abs_path("$FindBin::Bin/..");
my $dest = "$root/lib/native/$Config{archname}-$Config{version}/auto/Synth/Native";
make_path($dest);
my $tmp = tempdir('build-XXXXXX', DIR=>$dest, CLEANUP=>1);
my $c = "$tmp/Native.c";
my $library = "$tmp/Native.$Config{dlext}";
ExtUtils::ParseXS::process_file(filename=>"$root/native/Native.xs",output=>$c);
sub run { system { $_[0] } @_ ; die "Build failed: @_\n" if $? }
my $cc = $Config{cc};
my $cross = 0;
if ($^O eq 'MSWin32' && $Config{ptrsize} == 4 && $cc =~ /gcc(?:\.exe)?$/i) {
    open my $target,'-|',$cc,'-dumpmachine' or die "Cannot run $cc: $!";
    $cross = (<$target> // '') =~ /^x86_64/;
    close $target or die "Cannot identify GCC target";
}
if ($cross) {
    # ActivePerl 2400 ships 32-bit Perl with a 64-bit-default MinGW. Its
    # compiler can emit x86 objects, but its bundled CRT import libs are x64.
    my $core = "$Config{archlib}/CORE";
    my $def = "$tmp/crt.def";
    open my $out,'>',$def or die $!;
    print {$out} "LIBRARY msvcrt.dll\nEXPORTS\nsin\nmemset\nmemcpy\nmemmove\n";
    close $out or die $!;
    open my $tools,'-|',$cc,'-print-prog-name=dlltool' or die $!;
    my $dlltool = <$tools>;
    close $tools or die "Cannot locate dlltool";
    chomp $dlltool;
    run($dlltool,'-m','i386','-d',$def,'-l',"$tmp/crt.a",'--as-flags=--32');
    run($cc,'-m32','-O2','-std=gnu99','-msse2','-mfpmath=sse','-mms-bitfields',
        '-DPERL_IMPLICIT_CONTEXT','-DPERL_IMPLICIT_SYS','-DPERL_NO_GET_CONTEXT',
        "-I$core",'-c',$c,'-o',"$tmp/Native.o");
    run($cc,'-m32','-nostdlib','-shared','-Wl,--entry,0',"$tmp/Native.o",
        "$core/$Config{libperl}","$tmp/crt.a",'-o',$library);
} else {
    my $builder=ExtUtils::CBuilder->new(quiet=>1);
    my $o=$builder->compile(source=>$c);
    $builder->link(objects=>$o,module_name=>'Synth::Native',lib_file=>$library);
}
my $installed = "$dest/Native.$Config{dlext}";
rename $library,$installed or die "Cannot install $installed (close any running synth first): $!";
print "Built $installed\n";
