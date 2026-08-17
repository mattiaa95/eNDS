#import "Core/MelonDSCoreBridge.h"

// Vendored minizip (zlib license, ported from iGBA's Libs/minizip) — read-only
// ZIP extraction for .zip ROM imports. See Model/NDSZipExtractor.swift.
#import "Vendor/minizip/unzip.h"

// Flat-C shim around the vendored LZMA SDK (public domain, Vendor/lzma/) —
// read-only .7z extraction for ROM imports. See Model/NDS7zExtractor.swift.
#import "Model/Sz7zShim.h"

// zlib's gzip file API (already linked via -lz for minizip) — single-file
// .gz decompression for ROM imports. See Model/NDSGzExtractor.swift.
#include <zlib.h>
