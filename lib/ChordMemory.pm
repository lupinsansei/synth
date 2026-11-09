package ChordMemory;
use strict;
use warnings;
use Exporter 'import';
use Scalar::Util qw(looks_like_number);
use POSIX qw(isfinite);
our @EXPORT_OK = qw(chord_names chord_intervals chord_frequencies);
my @names = ('Major', 'Minor', 'Major 7th', 'Minor 7th', 'Dominant 7th', 'Sus2', 'Sus4', 'Octave');
my %chords = (
    'Major' => [0,4,7], 'Minor' => [0,3,7], 'Major 7th' => [0,4,7,11],
    'Minor 7th' => [0,3,7,10], 'Dominant 7th' => [0,4,7,10],
    'Sus2' => [0,2,7], 'Sus4' => [0,5,7], 'Octave' => [0,12],
);
sub chord_names { return [@names]; }
sub chord_intervals {
    my ($name) = @_;
    die 'Unknown chord type' unless defined $name && exists $chords{$name};
    return [@{$chords{$name}}];
}
sub chord_frequencies {
    my ($root, $enabled, $name) = @_;
    die 'Invalid root frequency' unless defined $root && looks_like_number($root) && isfinite($root) && $root > 0;
    my $intervals = $enabled ? chord_intervals($name) : [0];
    my @frequencies = map { $root * 2 ** ($_ / 12) } @$intervals;
    die 'Chord frequency out of range' if grep { !isfinite($_) } @frequencies;
    return \@frequencies;
}
1;
