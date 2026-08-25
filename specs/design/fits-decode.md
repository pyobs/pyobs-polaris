# FITS decode (`fits::FitsImage`, first real Conan dependency)

Status: implemented, closed.

**Scope**: the second slice of TODO.md's "`ICamera` follow-up" - decode
only. `fits::FitsImage` (new `src/fits/`) turns a complete in-memory FITS
file (the exact bytes `comm::VfsClient::fetchFile()` produces) into
`width()`/`height()`/row-major `double` pixels/header cards. No QML
surface, no `CameraView.qml` wiring, no display widget - this project's
own `CoordinateTransform.h` precedent (plain, independently-testable
pure functions/classes, QML adapter added later only once something
actually needs one) applies here too: nothing consumes decoded pixels
yet, so there's no QML API worth guessing at before the display widget
(TODO.md's next bullet) shapes what it actually needs.

**`cfitsio` is this project's first real Conan dependency** (previously
just `[generators]`/`[layout]`, zero `[requires]` - see Phase 0's own
note anticipating exactly this). Unlike `qxmpp`/`QtKeychain`,
`find_package(cfitsio REQUIRED)` + `cfitsio::cfitsio` needed no
FetchContent workaround - cfitsio has no Qt dependency of its own to
conflict with system Qt6, so ConanCenter's ordinary binary/source
resolution just works.

**API surface used** (cfitsio's "long name" macros, confirmed against
the actual vendored `fitsio.h`/`longnam.h` rather than assumed from
memory - the short `ff...` names are what's declared in `fitsio.h`
itself, `longnam.h` is a header of plain `#define` aliases mapping the
friendly names onto them):
- `fits_open_memfile`/`fits_close_file` - reads directly from the
  in-memory `QByteArray` (`buffptr` points straight at
  `data.constData()`, no copy), `READONLY` mode so `mem_realloc` is
  passed `nullptr` and simply never invoked (that callback only exists
  for growing a buffer being written to).
- `fits_get_num_hdus`/`fits_movabs_hdu`/`fits_get_img_param` - walks HDUs
  looking for the first `IMAGE_HDU` with `NAXIS == 2` and real
  dimensions, skipping a dataless primary HDU (`NAXIS == 0`) if present.
  Not something this project's own `DummyCamera` fixture actually
  produces (confirmed live - see below: it writes the image straight
  into the primary HDU, `EXTNAME='SCI'` is just a header card on it, not
  a real extension), but a real, well-known FITS convention worth
  handling defensively rather than assuming every future producer looks
  like `DummyCamera`.
- `fits_read_img(..., TDOUBLE, ...)` - reads pixel data as `double`
  regardless of the file's actual on-disk `BITPIX` (int8/16/32/64 or
  float32/64), with cfitsio applying any `BZERO`/`BSCALE` unsigned
  rescaling itself. A future stretch/display widget wants one uniform
  pixel type to work with, not eight separate on-disk-type branches.
- `fits_get_hdrspace`/`fits_read_keyn` - header cards in file order
  (not semantically meaningful the way `codec::WireDict`'s wire order
  is - kept anyway since it's simply what a raw card list naturally is).

**Testing** (`tests/fits/tst_fitsimage.cpp`): the "happy path" fixture
(a minimal 2x2 `BITPIX=16` image, values including a negative one to
exercise two's-complement decoding) is hand-built byte-for-byte, not
generated via cfitsio's own writer - deliberately independent of the
code under test, so a decode bug can't be masked by a matching encode
bug. The "dataless primary HDU + image extension" fallback case, by
contrast, *is* built via cfitsio's write API
(`fits_create_memfile`/`fits_create_img`/`fits_write_img`) - hand-rolling
a second HDU's exact byte layout (`XTENSION` card, `PCOUNT`/`GCOUNT`,
block alignment) by hand would itself be exactly the kind of
error-prone detail worth leaving to a library, and this only exercises
cfitsio's *write* path while `FitsImage::decode()` only ever calls its
*read* path, so the two stay meaningfully independent.

**Live verification**, extending the VFS transport harness from
`specs/design/vfs-transport.md` rather than starting over: `grab_data()` via the same
throwaway `XmppComm` proxy script (`/cache/pyobs-20260710-0002-e00.fits.gz`,
a fresh file, not the one reused from the VFS transport pass) →
`VfsEndpointsModel::resolveVfsPath()` → `VfsClient::fetchFile()` → piped
straight into `FitsImage::decode()`, all in one hand-compiled headless
harness (same manual-`moc` technique as before, now also linking
`FitsImage.cpp` against the vendored cfitsio static lib + `libz` - note
for next time: cfitsio's static lib needs `-lz` explicitly on the final
link line, or `libQt6Network.so`'s own `-lz` link ends up earlier on the
command line than cfitsio's undefined `inflateEnd` reference and GNU ld
refuses to resolve it backwards). Decoded **512×512, BITPIX 16, DATAMIN
5.0/DATAMAX 14.0, IMAGETYP 'object', EXTNAME 'SCI', 65 header cards** -
every one of these independently cross-checked against `astropy`'s own
read of the same bytes (via the already-available `pyobs-core/.venv`)
and matching exactly, including the header card count. The actual
decoded pixel min/max (**5, 14**) matched the file's own `DATAMIN`/
`DATAMAX` header claims exactly too - proof the pixel *data*, not just
the header parsing, decoded correctly.

