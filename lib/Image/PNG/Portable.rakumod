unit class Image::PNG::Portable;

use String::CRC32;
use Compress::Zlib;

has Int $.width;
has Int $.height;
has Bool $.alpha = True;

has Int $!channels;
has Int $!line-bytes;
has Int $!data-bytes;
has Buf $!data;
has Str %.text-metadata;

# magic string for PNGs
my $magic = Blob.new: 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A;

method set(
    Int $x where * < $!width,
    Int $y where * < $!height,
    Int $r, Int $g, Int $b, Int $a = 255
) {
    self!init-if-needed;
    my $buffer = $!data;
    my $index = $!line-bytes * $y + $!channels * $x + 1;

    $buffer[$index++] = $r;
    $buffer[$index++] = $g;
    $buffer[$index  ] = $b;
    $buffer[++$index] = $a if $!alpha;

    True
}

method set-all(Int:D $r, Int:D $g, Int:D $b, Int:D $a = 255) {
    self!init-if-needed;
    my $buffer = $!data;
    my $index = 0;
    my $alpha = $!alpha;

    for ^$!height {
        # every line offset by 1 again for filter byte
        $index++;
        for ^$!width {
            $buffer[$index++] = $r;
            $buffer[$index++] = $g;
            $buffer[$index++] = $b;
            $buffer[$index++] = $a if $alpha;
        }
    }

    True
}

method get(
    Int:D $x where * < $!width,
    Int:D $y where * < $!height
) {
    my $buffer = $!data;
    my $index = $!line-bytes * $y + $!channels * $x + 1;

    my $r = $buffer[$index++];
    my $g = $buffer[$index++];
    my $b = $buffer[$index++];
    my $a = $!alpha ?? $buffer[$index++] !! 255;

    $r, $g, $b, $a
}

method write(Str:D $file) {
    fail "width and/or height not specified" unless $!width && $!height;
    my $fh = $file.IO.open(:w, :bin);

    $fh.write: $magic;

    write-chunk $fh, 'IHDR', @(bytes($!width, 4).Slip, bytes($!height, 4).Slip,
        8, ($!alpha ?? 6 !! 2), 0, 0, 0); # w, h, bits/channel, color, compress, filter, interlace

    write-chunk $fh, 'IDAT', compress $!data;

    for %!text-metadata.kv -> $key, $value {
        my @data = flat $key.encode('latin-1').list, 0, $value.encode('latin-1').list;
        write-chunk $fh, 'tEXt', @data;
    }

    write-chunk $fh, 'IEND';

    $fh.close;

    True
}

multi method set-text-meta(Str:D $key, Str:D $value) {
    fail "Invalid tEXt keyword (must be 1–79 Latin-1 chars)"
        if !$key || $key.contains(/<:!Script<Latin>>/) || $key.chars > 79;
    %!text-metadata{$key} = $value;
}

multi method set-text-meta(%pairs) {
    for %pairs.kv -> $k, $v {
        self.set-text-meta($k, $v.Str) with $v;
    }
}

sub write-chunk (IO::Handle:D $fh, Str:D $type, @data = ()) {
    $fh.write: bytes @data.elems, 4;

    my @type := $type.encode;
    my @td := @data ~~ Blob ??
        @type ~ @data !!
        Blob[uint8].new: @type.list, @data.list;
    $fh.write: @td;

    $fh.write: bytes String::CRC32::crc32 @td;

    True
}

method read(Str:D $file) {
    my $blob = self!slurp-blob($file);
    fail "Not a PNG file" unless $blob[0..7] eqv $magic.list;

    my %chunks = self!parse-chunks($blob.subbuf(8));

    fail "Missing or malformed IHDR chunk" unless %chunks<IHDR>:exists && %chunks<IHDR>.elems == 1;
    my %ihdr = self!parse-ihdr(%chunks<IHDR>[0]);

    self!init-from-ihdr(%ihdr);

    my $idat = self!collect-idat(%chunks<IDAT>);
    self!decode-scanlines($idat);

    if %chunks<tEXt>:exists {
        for %chunks<tEXt>.List -> $chunk {
            my $null = $chunk.list.first(* == 0, :k);
            next unless $null.defined;
            my $key = $chunk.subbuf(0, $null).decode('latin-1');
            my $val = $chunk.subbuf($null + 1).decode('latin-1');
            self.set-text-meta($key, $val);
        }
    }

    True
}

method !slurp-blob($file) {
    $file.IO.open(:r, :bin).slurp(:bin)
}

sub uint32-be(Blob $b) {
    ($b[0] +< 24) + ($b[1] +< 16) + ($b[2] +< 8) + $b[3]
}

method !parse-chunks(Blob $data) {
    my $pos = 0;
    my %chunks;
    while $pos < $data.bytes {
        my $len = uint32-be($data.subbuf($pos, 4));
        my $type = $data.subbuf($pos+4, 4).decode('latin-1');
        my $chunk = $data.subbuf($pos+8, $len);
        %chunks{$type} //= [];
        %chunks{$type}.push($chunk);
        $pos += 8 + $len + 4;
    }
    %chunks
}

method !parse-ihdr(Blob:D $ihdr) {
    my %meta = (
        width    => uint32-be($ihdr.subbuf(0,4)),
        height   => uint32-be($ihdr.subbuf(4,4)),
        bitdepth => $ihdr[8],
        coltype  => $ihdr[9],
        alpha    => $ihdr[9] == 6 ?? True !! False,
    );

    fail "Bit depth must be 8" unless %meta<bitdepth> == 8;
    fail "Color type must be 2 or 6" unless %meta<coltype> == 2|6;

    %meta
}

method !init-from-ihdr(%ihdr) {
    $!width  = %ihdr<width>;
    $!height = %ihdr<height>;
    $!alpha  = %ihdr<alpha>;
    self!recompute-buffers;
}

method !init-if-needed {
    return if $!line-bytes;
    self!recompute-buffers;
}

method !recompute-buffers {
    $!channels = $!alpha ?? 4 !! 3;
    $!line-bytes = $!width * $!channels + 1;
    $!data-bytes = $!line-bytes * $!height;
    $!data = buf8.new;
    $!data[$!data-bytes - 1] = 0;
}

method !collect-idat(@idat-chunks) {
    Blob.new: flat @idat-chunks».list
}

method !decode-scanlines(Blob $idat) {
    my $raw = uncompress $idat;
    fail "Corrupt PNG: wrong length" unless $raw.bytes == $!data-bytes;

    my $prev = buf8.new($!line-bytes - 1);
    for ^$!height -> $y {
        my $offset = $y * $!line-bytes;
        my $filter = $raw[$offset];
        my $row    = $raw.subbuf($offset+1, $!line-bytes-1).list;
        my @unfiltered = self!apply-filter($filter, $row, $prev, $!channels);
        $!data[$offset] = $filter;
        $!data[$offset+1 ..^ $offset + $!line-bytes] = @unfiltered;
        $prev = buf8.new(|@unfiltered);
    }
}

method !apply-filter($filter, @row, $prev, $channels) {
    my @cur = @row;
    given $filter {
        when 0 { }
        when 1 { # SUB
            for ^@row.elems -> $i {
                @cur[$i] += @cur[$i-$channels] if $i >= $channels;
                @cur[$i] %= 256;
            }
        }
        when 2 { # UP
            for ^@row.elems -> $i {
                @cur[$i] += $prev[$i] // 0;
                @cur[$i] %= 256;
            }
        }
        when 3 { # AVERAGE
            for ^@row.elems -> $i {
                my $a = $i >= $channels ?? @cur[$i-$channels] !! 0;
                my $b = $prev[$i] // 0;
                @cur[$i] += (($a + $b) div 2);
                @cur[$i] %= 256;
            }
        }
        when 4 { # PAETH
            for ^@row.elems -> $i {
                my $a = $i >= $channels ?? @cur[$i-$channels] !! 0;
                my $b = $prev[$i] // 0;
                my $c = $i >= $channels ?? $prev[$i-$channels] !! 0;
                @cur[$i] += self!paeth($a,$b,$c);
                @cur[$i] %= 256;
            }
        }
        default {
            fail "Unsupported or invalid PNG filter $filter";
        }
    }
    @cur
}

method !paeth($a,$b,$c) {
    my $p = $a + $b - $c;
    my $pa = abs($p-$a);
    my $pb = abs($p-$b);
    my $pc = abs($p-$c);

    $pa <= $pb && $pa <= $pc ?? $a
        !! $pb <= $pc        ?? $b
        !!                      $c;
}

method text-meta-keys {
    %!text-metadata.keys.sort
}

method get-text-meta(Str:D $key) {
    %!text-metadata{$key} // Nil
}

method clear-text-metadata {
    %!text-metadata := Hash[Str, Str]({});
}

sub bytes (Int:D $n is copy, Int:D $count = 0) {
    my @return;

    my $exp = 1;
    $exp++ while 256 ** $exp <= $n;

    if $count {
        my $diff = $exp - $count;
        die 'Overflow' if $diff > 0;
        @return.append(0 xx -$diff) if $diff < 0;
    }

    while $exp {
        my $scale = 256 ** --$exp;
        my $value = $n div $scale;
        @return.push: $value;
        $n -= $value * $scale;
    }

    Blob[uint8].new: @return;
}

# vim: expandtab shiftwidth=4
