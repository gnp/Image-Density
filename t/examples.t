print "1..3\n";

use Image::Density::TIFF;

my $tolerance = 0.000001;

my $original = tiff_density("t/original.tif");
print "not " unless abs($original - 0.218661) <= $tolerance;
print "ok 1\n";

my $noisy = tiff_density("t/noisy.tif");
print "not " unless abs($noisy - 0.085438) <= $tolerance;
print "ok 2\n";

my $diffuse = tiff_density("t/diffuse.tif");
print "not " unless abs($diffuse - 0.128822) <= $tolerance;
print "ok 3\n";

exit 0;
