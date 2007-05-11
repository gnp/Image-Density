print "1..4\n";

use Image::Density::TIFF;

my $tolerance = 0.000001;

my $original = tiff_density("t/original.tif");
print "1 (original): ", $original, "\n";
print "not " unless abs($original - 0.218661) <= $tolerance;
print "ok 1\n";

my $diffuse = tiff_density("t/diffuse.tif");
print "2 (diffuse): ", $diffuse, "\n";
print "not " unless abs($diffuse - 0.128822) <= $tolerance;
print "ok 2\n";

my $noisy = tiff_density("t/noisy.tif");
print "3 (noisy): ", $noisy, "\n";
print "not " unless abs($noisy - 0.085438) <= $tolerance;
print "ok 3\n";

my @multi = tiff_densities("t/multi.tif");
print "4 (multi): ", join(", ", @multi), "\n";
print "not " unless (scalar(@multi) == 3)
  && (abs($multi[0] - 0.218661) <= $tolerance)
  && (abs($multi[1] - 0.128822) <= $tolerance)
  && (abs($multi[2] - 0.085438) <= $tolerance);
print "ok 4\n";

exit 0;
