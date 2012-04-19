#
# Image::Density::TIFF
#
#   Calculate the density of a TIFF image in a way that helps estimate scanned
#   image quality.
#
# Copyright (C) 2003-2012 Gregor N. Purdy, Sr. All rights reserved.
# This program is free software. It is subject to the same license as Perl.
#
# $Id$
#

=head1 NAME

Image::Density::TIFF

=head1 SYNOPSIS

  use Image::Density::TIFF;
  print "Density: %f\n", tiff_density("foo.tif"); # single-page
  print "Densities: ", join(", ", tiff_densities("bar.tif")), "\n"; # multi-page

=head1 DESCRIPTION

A trivial density calculation would count the number of black pixels and
divide by the total number of pixels. However, it would produce misleading
results in the case where the image contains one or more target areas with
scanned content and large blank areas in between (imagine a photocopy of a
driver's license in the middle of a page).

The metric implemented here estimates the density of data where there I<is>
data, and has a
reasonable correlation with goodness as judged by humans. That is, if you
let a human look at a set of images and judge quality, the density values for
those images as calculated here tend to correlate well with the human
judgement (densities that are too high or too low represent "bad" images).

This algorithm is intended for use on bitonal TIFF images, such as those from
scanning paper documents.

=head2 The calculation

We omit the margins because there is likely to be noise there, such as black
strips due to page skew. This does admit the possibility that we are skipping
over something important, but the margin skipping here worked well on the
test images.

Leading and trailing white on a row are omitted from counting, as are runs of
white at least as long as the margin width. This helps out when we have images
with large blank areas, but decent density within the areas filled in, which
is what we really care about.

=head1 AUTHOR

Gregor N. Purdy, Sr. <gnp@acm.org>

=head1 COPYRIGHT

Copyright (C) 2003-2012 Gregor N. Purdy, Sr. All rights reserved.

=head1 LICENSE

This program is free software. Its use is subject to the same license as Perl.

=cut

use strict;
use warnings 'all';

package Image::Density::TIFF;

our $VERSION = '0.3';

use Inline (
  C            => 'DATA',
  LIBS         => '-ltiff',
  AUTO_INCLUDE => '#include <stdio.h>',
  AUTO_INCLUDE => '#include <tiffio.h>'
);

BEGIN {
  use Exporter;
  use vars qw(@ISA @EXPORT);
  @ISA = qw(Exporter);
  @EXPORT = qw(&tiff_density &tiff_densities);
}

1;

__DATA__
__C__

#define MARGIN_FACTOR 20

#include <stdarg.h>

typedef void (*TIFFWarningHandler)(const char* module, const char* fmt, va_list ap);
#if 0
typedef void (*TIFFErrorHandler)(const char* module, const char* fmt, va_list ap);
#endif


#if 0
static void tiff_density_err(const char* module, const char* fmt, va_list ap)
{
  croak ... /* TODO??? */
}
#endif

double tiff_directory_density(TIFF * t, TIFFWarningHandler old_warn, TIFFErrorHandler old_err) {
  uint16             bps;     /* Bits per sample */
  uint16             spp;     /* Image depth (samples per pixel?) */
  uint32             w;       /* Image width */
  uint32             h;       /* Image height */
  tsize_t            s;       /* Size in bytes of one scanline */
  unsigned char *    b;       /* Scanline buffer */
  long               i;       /* Scanline index */
  long               j;       /* Byte index */
  long               k;       /* Bit index */
  long               black;
  long               white;
  double             density;
  uint32             w_margin; /* The margins are used to exclude part of the border */
  uint32             h_margin;

  if (t == NULL) {
    TIFFSetWarningHandler(old_warn);
    TIFFSetErrorHandler(old_err);
    croak("Could not open file for reading");
  }
	
  if (TIFFGetField(t, TIFFTAG_BITSPERSAMPLE, &bps) != 1) {
    TIFFSetWarningHandler(old_warn);
    TIFFSetErrorHandler(old_err);
    croak("Could not determine TIFF bits per sample file for reading");
  }

  if (bps != 1) {
    TIFFSetWarningHandler(old_warn);
    TIFFSetErrorHandler(old_err);
    croak("Cannot process TIFF files with more than one bit per sample!");
  }

  if (TIFFGetField(t, TIFFTAG_IMAGEDEPTH, &spp) != 1) {
    /* It is OK for this field to be missing. We'll assume 1. */
    spp = 1;
  }

  if (bps != 1) {
    TIFFSetWarningHandler(old_warn);
    TIFFSetErrorHandler(old_err);
    croak("Cannot process TIFF files with more than one sample per pixel!");
  }

  if (TIFFGetField(t, TIFFTAG_IMAGEWIDTH, &w) != 1) {
    TIFFSetWarningHandler(old_warn);
    TIFFSetErrorHandler(old_err);
    croak("Could not determine TIFF width!");
  }

  if (TIFFGetField(t, TIFFTAG_IMAGELENGTH, &h) != 1) {
    TIFFSetWarningHandler(old_warn);
    TIFFSetErrorHandler(old_err);
    croak("Could not determine TIFF height!");
  }
 
/*  fprintf(stderr, "Image Width  = %ld\n", w); */
/*  fprintf(stderr, "Image Height = %ld\n", h); */

  w_margin = w / MARGIN_FACTOR;
  h_margin = h / MARGIN_FACTOR;

  /*
  ** Prepare to read the Scanlines:
  */

  s = TIFFRasterScanlineSize(t);

  b = (char *)malloc(s);

/*  fprintf(stdout, "Raster Scanline Size = %ld\n", (long)s); */

  if (b == NULL) {
    TIFFSetWarningHandler(old_warn);
    TIFFSetErrorHandler(old_err);
    croak("Could not allocate memory for scanline reading!");
  }

  black = 0;
  white = 0;
     
  /*
  ** We omit the top and bottom margins because there is likely to be noise there,
  ** such as black strips due to page skew.
  **
  ** We have to read the first h_margin rows, rather than skip them, because the
  ** TIFF file's compression algorithm might not support random access.
  */

  for (i = 0; i < (h - (2 * h_margin)); i++) {
    long          row_black;
    long          row_white;
    unsigned char last_sample;
    long          run_length;

    if (TIFFReadScanline(t, b, i, 0) == -1) {
      TIFFSetWarningHandler(old_warn);
      TIFFSetErrorHandler(old_err);
      croak("Could not read scanline!");
    }

    if (i < h_margin) {
      continue;
    }
     
    /*
    ** We omit the left and right margins because there is likely to be noise there,
    ** such as black strips due to page skew.
    **
    ** The setup of last_sample and run_length simulates a leading white run long
    ** enough that any actual leading white, no matter how much, will be omitted.
    **/

    row_black   = 0;
    row_white   = 0;
    last_sample = 0;
    run_length  = w_margin;

    for (j = w_margin; j < (w - (2 * w_margin)); j++) {
      unsigned char byte_num = j / 8;
      unsigned char byte     = b[byte_num];
      unsigned char bit_num  = 7 - (j % 8);
      unsigned char sample   = (byte >> bit_num) & 0x01;

      /*
      ** We don't count row white until we see black. This omits leading and trailing
      ** white on the row, which helps out when we have images with large blank areas,
      ** but decent density within the areas filled in, which is what we really care
      ** about.
      **
      ** We also don't count row_white when it is greater than the margin, since that
      ** amounts to a "large" empty space, and we really want the density of *data*,
      ** where there *is* data.
      */

      if (sample == last_sample) {
        run_length++;
      }
      else {
        if (run_length < w_margin) {
          if (last_sample) {
            row_black += run_length;
          }
          else {
            row_white += run_length;
          }
        }

        last_sample = sample;
        run_length = 1;
      }

#if 0

      if (sample) {
        if (row_black && row_white < w_margin) {
          white += row_white;
        }

        row_black++;

        row_white = 0;
      }
      else {
        row_white++;
      }

#endif

    }

    if (run_length < w_margin) {
      if (last_sample) {
        row_black += run_length;
      }

      /* We don't add trailing white runs to the row's total */
    }
  
    white += row_white;
    black += row_black;
  }

  free(b);

  if (black + white > 0) {
    density = (double)black / (double)(black + white);
  }
  else {
    density = -1.0;
  }

  return density;
}

double tiff_density(char * file_name) {
  TIFF *             t;       /* TIFF */
  TIFFWarningHandler old_warn;
  TIFFErrorHandler   old_err;

  /*
  ** Open the TIFF file and find out some things about it.
  */

  old_warn = TIFFSetWarningHandler((TIFFWarningHandler)0);
  old_err  = TIFFSetErrorHandler((TIFFWarningHandler)0);

  t = TIFFOpen(file_name, "r");

  if (t == NULL) {
    TIFFSetWarningHandler(old_warn);
    TIFFSetErrorHandler(old_err);
    croak("Could not open file for reading");
  }

  double density = tiff_directory_density(t, old_warn, old_err);

  TIFFClose(t);

  TIFFSetWarningHandler(old_warn);
  TIFFSetErrorHandler(old_err);

  return density;
}

void tiff_densities(char * file_name) {
  TIFF *             t;       /* TIFF */
  TIFFWarningHandler old_warn;
  TIFFErrorHandler   old_err;

  /*
  ** Open the TIFF file and find out some things about it.
  */

  old_warn = TIFFSetWarningHandler((TIFFWarningHandler)0);
  old_err  = TIFFSetErrorHandler((TIFFWarningHandler)0);

  t = TIFFOpen(file_name, "r");

  if (t == NULL) {
    TIFFSetWarningHandler(old_warn);
    TIFFSetErrorHandler(old_err);
    croak("Could not open file for reading");
  }

  Inline_Stack_Vars;
  Inline_Stack_Reset;
  do {
  	double density = tiff_directory_density(t, old_warn, old_err);
    Inline_Stack_Push(sv_2mortal(newSVnv(density)));
  } while (TIFFReadDirectory(t));
  Inline_Stack_Done;

  TIFFClose(t);

  TIFFSetWarningHandler(old_warn);
  TIFFSetErrorHandler(old_err);

  return;
}


