#include "Sz7zShim.h"

#include <stdlib.h>
#include <string.h>

#include "7z.h"
#include "7zAlloc.h"
#include "7zCrc.h"
#include "7zFile.h"

/// Everything the vendored SDK needs kept alive for the lifetime of an open
/// archive: the file + buffered-look-ahead input streams `SzArEx_Open`
/// parses the header through, the parsed header itself (`db`), the
/// allocator vtables the SDK calls back into, and the solid-block
/// extraction cache (`blockIndex`/`outBuffer`/`outBufferSize`) that
/// `SzArEx_Extract` reuses across entries -- see the "Extracting cache"
/// comment on `SzArEx_Extract` in `7z.h`.
struct Sz7zArchive {
    CFileInStream archiveStream;
    CLookToRead2 lookStream;
    CSzArEx db;
    ISzAlloc allocImp;
    ISzAlloc allocTempImp;
    UInt32 blockIndex;
    Byte *outBuffer;
    size_t outBufferSize;
};

/// Read-ahead buffer size for the archive's input stream. Matches
/// `Util/7z/7zMain.c`'s `kInputBufSize`.
static const size_t kSz7zInputBufSize = (size_t)1 << 18;

Sz7zArchive *Sz7zArchive_Open(const char *path)
{
    if (!path) {
        return NULL;
    }

    Sz7zArchive *archive = (Sz7zArchive *)calloc(1, sizeof(Sz7zArchive));
    if (!archive) {
        return NULL;
    }

    archive->allocImp.Alloc = SzAlloc;
    archive->allocImp.Free = SzFree;
    archive->allocTempImp.Alloc = SzAllocTemp;
    archive->allocTempImp.Free = SzFreeTemp;
    archive->blockIndex = (UInt32)-1; /* any value is fine before the first Extract call */

    if (InFile_Open(&archive->archiveStream.file, path) != 0) {
        free(archive);
        return NULL;
    }

    FileInStream_CreateVTable(&archive->archiveStream);
    archive->archiveStream.wres = 0;

    LookToRead2_CreateVTable(&archive->lookStream, False);
    archive->lookStream.buf = (Byte *)ISzAlloc_Alloc(&archive->allocImp, kSz7zInputBufSize);
    if (!archive->lookStream.buf) {
        File_Close(&archive->archiveStream.file);
        free(archive);
        return NULL;
    }
    archive->lookStream.bufSize = kSz7zInputBufSize;
    archive->lookStream.realStream = &archive->archiveStream.vt;
    LookToRead2_INIT(&archive->lookStream)

    CrcGenerateTable();
    SzArEx_Init(&archive->db);

    const SRes res = SzArEx_Open(&archive->db, &archive->lookStream.vt, &archive->allocImp, &archive->allocTempImp);
    if (res != SZ_OK) {
        /* db was zero-initialized by SzArEx_Init, so Free is safe even on a failed Open. */
        SzArEx_Free(&archive->db, &archive->allocImp);
        ISzAlloc_Free(&archive->allocImp, archive->lookStream.buf);
        File_Close(&archive->archiveStream.file);
        free(archive);
        return NULL;
    }

    return archive;
}

void Sz7zArchive_Close(Sz7zArchive *archive)
{
    if (!archive) {
        return;
    }
    if (archive->outBuffer) {
        ISzAlloc_Free(&archive->allocImp, archive->outBuffer);
    }
    SzArEx_Free(&archive->db, &archive->allocImp);
    if (archive->lookStream.buf) {
        ISzAlloc_Free(&archive->allocImp, archive->lookStream.buf);
    }
    File_Close(&archive->archiveStream.file);
    free(archive);
}

uint32_t Sz7zArchive_GetNumFiles(const Sz7zArchive *archive)
{
    return archive ? (uint32_t)archive->db.NumFiles : 0;
}

int Sz7zArchive_IsDir(const Sz7zArchive *archive, uint32_t index)
{
    if (!archive || index >= archive->db.NumFiles) {
        return 0;
    }
    return SzArEx_IsDir(&archive->db, index) ? 1 : 0;
}

uint64_t Sz7zArchive_GetFileSize(const Sz7zArchive *archive, uint32_t index)
{
    if (!archive || index >= archive->db.NumFiles) {
        return 0;
    }
    return (uint64_t)SzArEx_GetFileSize(&archive->db, index);
}

int Sz7zArchive_CopyFileNameUTF16(const Sz7zArchive *archive, uint32_t index, uint16_t **outUTF16, size_t *outCount)
{
    if (!outUTF16 || !outCount) {
        return 0;
    }
    *outUTF16 = NULL;
    *outCount = 0;
    if (!archive || index >= archive->db.NumFiles) {
        return 0;
    }

    /* dest == NULL: SzArEx_GetFileNameUtf16 returns the required length,
       in 16-bit units, including the NUL terminator. See 7z.h. */
    const size_t length = SzArEx_GetFileNameUtf16(&archive->db, index, NULL);
    if (length == 0) {
        return 0;
    }

    UInt16 *buffer = (UInt16 *)malloc(length * sizeof(UInt16));
    if (!buffer) {
        return 0;
    }
    SzArEx_GetFileNameUtf16(&archive->db, index, buffer);

    *outUTF16 = (uint16_t *)buffer;
    *outCount = length - 1;
    return 1;
}

int Sz7zArchive_ExtractToBuffer(Sz7zArchive *archive, uint32_t index, uint8_t **outData, size_t *outSize)
{
    if (!outData || !outSize) {
        return 0;
    }
    *outData = NULL;
    *outSize = 0;
    if (!archive || index >= archive->db.NumFiles || SzArEx_IsDir(&archive->db, index)) {
        return 0;
    }

    size_t offset = 0;
    size_t outSizeProcessed = 0;
    const SRes res = SzArEx_Extract(
        &archive->db, &archive->lookStream.vt, index,
        &archive->blockIndex, &archive->outBuffer, &archive->outBufferSize,
        &offset, &outSizeProcessed,
        &archive->allocImp, &archive->allocTempImp);
    if (res != SZ_OK) {
        return 0;
    }

    if (outSizeProcessed == 0) {
        /* Legitimate zero-byte entry: hand back a valid non-NULL pointer
           (malloc(0)'s return value is implementation-defined) with size 0. */
        *outData = (uint8_t *)malloc(1);
        if (!*outData) {
            return 0;
        }
        *outSize = 0;
        return 1;
    }

    uint8_t *copy = (uint8_t *)malloc(outSizeProcessed);
    if (!copy) {
        return 0;
    }
    memcpy(copy, archive->outBuffer + offset, outSizeProcessed);

    *outData = copy;
    *outSize = outSizeProcessed;
    return 1;
}

void Sz7zArchive_FreeMemory(void *buffer)
{
    free(buffer);
}
