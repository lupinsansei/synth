use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Tk;
use SuperSpinbox;
my $window = MainWindow->new(-title => 'Super Spinbox — per-digit controls');
$window->Label(-text => 'Change any digit. Carry and borrow work across the decimal point.')->pack;
for my $example (['Frequency multiplier', 12.3456, 4], ['Volume decay', 0.000005, 8]) {
    my ($name, $value, $places) = @$example;
    $window->Label(-text => $name)->pack;
    my $control = SuperSpinbox->new(parent => $window, variable => \$value,
        integers => 4, places => $places, min => -1000, max => 1000,
        command => sub { print "$name = $_[0]\n" });
    $control->widget->pack(-padx => 10, -pady => 10);
}
MainLoop;
