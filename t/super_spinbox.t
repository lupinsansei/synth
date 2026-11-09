use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use SuperSpinbox::Value;
my $value = SuperSpinbox::Value->new(value => '12.3456', integers => 4, places => 4, min => -1000, max => 1000);
is($value->formatted, '+0012.3456', 'initial scalar populates all digits');
is($value->step(1,1), 22.3456, 'tens digit changes tens without replacing the whole number');
is($value->step(-3,-1), 22.3446, 'thousandths independently decrease');
$value->set('9.9999'); is($value->step(-4,1),10,'carry across the decimal');
is($value->step(-4,-1),9.9999,'borrow across decimal');
$value->set(0); is($value->step(-4,-1),-0.0001,'cross zero into negative');
is($value->step(-4,1),0,'return to exact zero');
$value->set(1000); is($value->step(0,1),1000,'upper bound clamps without wrapping');
$value->set(-1000); is($value->step(0,-1),-1000,'lower bound clamps');
$value->set(0); $value->step(-1,1) for 1..1000;
is($value->formatted,'+0100.0000','repeated decimal steps have no float drift');
$value->set('1e-3'); is($value->formatted,'+0000.0010','numeric exponent input');
for my $bad ('', 'abc', 'NaN', 'Inf', '1e999', '1.2.3') {
    my $before=$value->value;
    ok(!eval { $value->set($bad); 1 }, "reject $bad"); is($value->value,$before,'invalid input preserves previous value');
}
my $decay=SuperSpinbox::Value->new(value=>'0.000005', places=>8);
is($decay->formatted,'+0000.00000500','tiny decay preserved');
is($decay->step(-8,1),0.00000501,'smallest decay digit independently adjustable');
done_testing;
