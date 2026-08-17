#ifndef Sz7zShim_h
#define Sz7zShim_h

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Thin, flat-C wrapper around the vendored LZMA SDK (`../Vendor/lzma/`) so
/// `NDS7zExtractor.swift` can drive `.7z` extraction without dealing with
/// the SDK's `ISzAlloc`/`ILookInStream` vtable structs directly from Swift.
/// Mirrors the call sequence in the SDK's own `Util/7z/7zMain.c` reference
/// CLI (`SzArEx_Open` -> per-entry `SzArEx_GetFileNameUtf16`/`SzArEx_Extract`
/// -> `SzArEx_Free`), just packaged as an opaque handle + a handful of
/// functions instead of one big `main()`.
///
/// Every function here is defensive about bad input (NULL archive,
/// out-of-range index, malformed/unsupported `.7z` data, allocation
/// failure): they return NULL/0/false rather than crashing, so a corrupt or
/// hostile `.7z` can only ever fail an import, never take the app down.
typedef struct Sz7zArchive Sz7zArchive;

/// Opens and parses the `.7z` archive at `path` (a POSIX path). Returns
/// NULL if the file can't be opened, isn't a `.7z` archive, or uses
/// something this SDK subset can't decode (e.g. a header-encrypted
/// archive -- see `Sz7zArchive_ExtractToBuffer` for the more common
/// per-entry-encrypted case).
Sz7zArchive *Sz7zArchive_Open(const char *path);

/// Closes the archive and frees every resource `Sz7zArchive_Open`
/// allocated. No-op if `archive` is NULL.
void Sz7zArchive_Close(Sz7zArchive *archive);

/// Number of entries (files + directories) in the archive.
uint32_t Sz7zArchive_GetNumFiles(const Sz7zArchive *archive);

/// Non-zero if entry `index` is a directory. 0 (and thus "not a directory")
/// for an out-of-range index, same as every other accessor below.
int Sz7zArchive_IsDir(const Sz7zArchive *archive, uint32_t index);

/// Uncompressed size, in bytes, of entry `index`.
uint64_t Sz7zArchive_GetFileSize(const Sz7zArchive *archive, uint32_t index);

/// Writes entry `index`'s name as malloc'd, NUL-terminated UTF-16LE code
/// units into `*outUTF16`, and their count -- excluding the terminator --
/// into `*outCount`. The caller takes ownership and must release it with
/// `Sz7zArchive_FreeMemory`. Returns 0 on failure (bad index/OOM), in which
/// case `*outUTF16`/`*outCount` are left as NULL/0.
int Sz7zArchive_CopyFileNameUTF16(const Sz7zArchive *archive, uint32_t index, uint16_t **outUTF16, size_t *outCount);

/// Decompresses entry `index` in full into a freshly malloc'd buffer
/// written to `*outData` (size `*outSize`). The caller takes ownership and
/// must release it with `Sz7zArchive_FreeMemory`. Returns 0 on failure --
/// bad index, a directory entry, an unsupported coder (AES-256 encryption
/// isn't linked into this SDK subset, so an encrypted entry fails exactly
/// like any other unsupported codec would), a CRC mismatch, or OOM -- in
/// which case `*outData`/`*outSize` are left as NULL/0.
int Sz7zArchive_ExtractToBuffer(Sz7zArchive *archive, uint32_t index, uint8_t **outData, size_t *outSize);

/// Frees a buffer returned by `Sz7zArchive_CopyFileNameUTF16` or
/// `Sz7zArchive_ExtractToBuffer`. NULL-safe.
void Sz7zArchive_FreeMemory(void *buffer);

#ifdef __cplusplus
}
#endif

#endif /* Sz7zShim_h */
