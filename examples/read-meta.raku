#!/usr/bin/env raku

my constant $root = $?FILE.IO.cleanup.parent.parent;
use lib $root.child('lib');

use Image::PNG::Portable;

sub MAIN(Str:D $file-path) {
    my $img = Image::PNG::Portable.new(:width(0), :height(0));
    
    $img.read($file-path)
        or die "Failed to read PNG file: $file-path";

    my %meta = $img.text-metadata;

    say "Text metadata discovered: {%meta.elems} pairs.";

    for %meta.kv -> $k, $v {
        say "$k: $v";
    }
}
