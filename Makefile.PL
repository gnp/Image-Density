use ExtUtils::MakeMaker;

WriteMakefile(
  NAME          => 'Image::Density',
  VERSION_FROM  => 'lib/Image/Density/TIFF.pm',
  AUTHOR        => 'Gregor N. Purdy, Sr. <gnp@acm.org>',
  PREREQ_PM     => { 'Inline::C' => 0.44 }
);
