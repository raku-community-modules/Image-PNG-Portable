[![Actions Status](https://github.com/raku-community-modules/Image-PNG-Portable/actions/workflows/linux.yml/badge.svg)](https://github.com/raku-community-modules/Image-PNG-Portable/actions) [![Actions Status](https://github.com/raku-community-modules/Image-PNG-Portable/actions/workflows/macos.yml/badge.svg)](https://github.com/raku-community-modules/Image-PNG-Portable/actions) [![Actions Status](https://github.com/raku-community-modules/Image-PNG-Portable/actions/workflows/windows.yml/badge.svg)](https://github.com/raku-community-modules/Image-PNG-Portable/actions)

NAME
====

Image::PNG::Portable - portable PNG output for Raku

SYNOPSIS
========

```raku
use Image::PNG::Portable;
my $o = Image::PNG::Portable.new: :width(16), :height(16);
$o.set: 8,8, 255,255,255;
$o.set-text-meta('Author', 'Apogee');
$o.write: 'image.png';

my $o2 = Image::PNG::Portable.new;
$o2.read: 'image.png';
$o2.get: 0, 0; # Pixel color value at x,y of 0,0 => (0, 0, 0, 255)
$o2.get-text-meta('Author');
```

STATUS
------

This module is currently useful for reading & outputting 8-bit-per-channel truecolor images with tExt metadata. Writing precompression filters, palettes, grayscale, non-8-bit channels, and ancillary features like gamma correction, and color profiles are all NYI.

DESCRIPTION
===========

This is an almost-pure Raku PNG module.

USAGE
=====

The following types are used internally and in this documentation. They are here for brevity, not exported in the public API.

```raku
subset UInt8 of Int where 0 <= * <= 255; # unsigned 8-bit
subset PInt  of Int where * > 0;         # positive
```

METHODS
=======

.new(PInt :$width!, PInt :$height!, Bool $alpha = True)
-------------------------------------------------------

Creates a new `Image::PNG::Portable` object, initialized to black. If the alpha channel is enabled, it is initialized to transparent.

.set(UInt $x, UInt $y, UInt8 $red, UInt8 $green, UInt8 $blue, UInt8 $alpha = 255)
---------------------------------------------------------------------------------

Sets the color of a pixel in the image.

.set-all(UInt8 $red, UInt8 $green, UInt8 $blue, UInt8 $alpha = 255)
-------------------------------------------------------------------

Sets the color of all pixels in the image.

.get(UInt $x, UInt $y)
----------------------

Gets the color of a pixel in the image as an array of channel values.

.write($file)
-------------

Writes the contents of the image to the specified file.

.read($file)
------------

Reads the PNG file to the Image object.

.get($x, $y)
------------

Get the color information at pixel $x,$y (zero-indexed).

.set-text-meta($key, $value)
----------------------------

Set tExt metadata for $key to $value.

.set-text-meta(%pairs)
----------------------

Set tExt metadata from %pairs.

.text-meta-keys()
-----------------

Get all tExt metadata keys.

.get-text-meta($key)
--------------------

Get tExt metadata for given key $key.

.clear-text-metadata()
----------------------

Clear tExt metadata.

.text-metadata()
----------------

Get the tExt metadata as a Hash.

AUTHORs
=======

  * raydiak
  * Matt Doughty

COPYRIGHT AND LICENSE
=====================

Copyright 2015 - 2021 raydiak

Copyright 2025 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

