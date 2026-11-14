Review complete. All seven files were read in full and checked against the six ledger items plus the general hunt list.

## Residual defects

**1. D13 residual: export-trie edges longer than 255 bytes still truncate** (`src/ios/ios_export.c:125-130`, used at `:209-222`). `ios_trie_str` clamps `len` to `dstsz - 1` and then reports that clamped value through `out_len`. For a 300-byte edge the walk compares only 255 bytes and advances `rem` by 255, so the remaining 45 edge bytes are matched against the child's edges. Any symbol whose unique suffix exceeds 255 bytes (long C++ template manglings) fails to resolve or resolves through the wrong child, and a non-weak bind then aborts the load. The re-export `import_name` is truncated the same way. Fix: have `ios_trie_str` return the in-buffer start offset and the full length, and compare with `memcmp(b + estart, rem, elen)` without copying; enlarge `import_name` to 512 to match `st.sym`.

**2. D12 residual: `__mod_init_func` order is reverse-load order, not DFS post-order** (`src/ios/ios_dylib.c:419-424`). The order array is `count-1 .. 1, 0`. Images are discovered breadth-first in `ios_load_inner:781-805`, so for an executable depending on B then C, where C depends on B, the loader yields `[exe, libSystem, B, C]` and runs C's initializers before B's. dyld runs B first. `dep_image_idx` is already populated before `ios_collect_inits` runs. Fix: recursive post-order DFS from image 0 over `dep_image_idx` with a visited bitmap, appending each image after its deps.

**3. D12 residual: `ios_apply_prot` end rounding overshoots for unaligned `vmaddr`** (`src/ios/ios_dylib.c:534-535`). `segs[k].vmsize` is already the page-aligned span from `page_down(vmaddr)` (`ios_macho.c:716`). Computing `page_up(vmaddr + vmsize)` with an unaligned `vmaddr` therefore extends one page past the mapped region. Example: `slid = 0x1800`, original `vmsize = 0x1000` maps `[0x1000, 0x3000)` but seals `[0x1000, 0x4000)`. Every other consumer uses `start + vmsize`. Fix: `end = start + img->segs[k].vmsize`.

**4. LC_UNIXTHREAD entry uses the unslid `pc`** (`src/ios/ios_dylib.c:849` and `:744`). `ios_macho.c:742-743` validates `tstate[15] + slide`, but `ios_dylib.c` passes the raw `tstate[15]` to `ios_thread_entry`. Any slid LC_UNIXTHREAD image (PIE with `min_va == 0`, or a dylinker with `min_va == 0` which gets `A32_IOS_DYLD_BASE`) starts at the wrong address. Fix: pass `slid_pc` at line 849 and `parsed[1].tstate[15] + images[1].slide` at line 744.

**5. `EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE` exports get `mh_va` added** (`src/ios/ios_export.c:376-380`). Both branches compute `mh_va + arg0`. For kind `0x02` the trie value is absolute and dyld returns it unslid. Fix: `if ((hit.flags & 0x3u) == 0x2u) addr = (uint32_t)hit.arg0;`.

**6. Classic images never process external relocations** (`src/ios/ios_bind.c:526-701`, `a32_ios_bind_all:782-789`). Only `S_LAZY_SYMBOL_PTRS` and `S_NON_LAZY_SYMBOL_PTRS` are bound; `dysymtab.extreloff`/`nextrel` are never read. A classic image with a `__DATA` pointer to an imported symbol keeps the on-disk addend (usually 0). Fix: iterate `extreloff` entries, resolve `syms[r_symbolnum]` by name, write `sym_addr + *slot`.

## VERIFIED

- **D5**: `IOS_INDIRECT_LOCAL`/`ABS` are `0x80000000`/`0x40000000` (`ios_bind.c:45-46`); weak imports via `BIND_SYMBOL_FLAGS_WEAK_IMPORT`, `BIND_SPECIAL_DYLIB_WEAK_LOOKUP`, and weak-missing deps all write `0` (`ios_bind.c:323-341, 375-380`). Classic `INDIRECT_SYMBOL_LOCAL` sliding matches dyld's `doBindIndirectSymbolPointers`.
- **D12 (remaining parts)**: `(st_dev, st_ino)` plus path/install_name dedup (`ios_dylib.c:147-185`); same-image page-granular overlap check (`ios_macho.c:668-681`).
- **D13 (ordinal fallback)**: re-export ordinals route through `dep_image_idx` with synthetic fallback (`ios_export.c:361-375`).
- **D14 (loader side)**: CRT0 Thumb-2 encodings all check out; `main` returns into the exit stub via `blx r12` (`ios_commpage_stack.c:183-186`); buffer bounds (9 and 20 halfwords) are exact.
- **P5**: export, symtab, and strtab blobs are cached per image and freed after `a32_ios_bind_all` and again in `a32_ios_load` (`ios_export.c:233-292`, `ios_dylib.c:806-810, 890`).
- **P6 (producer)**: `text_start`/`text_end`/`load_bias` populated and `LC_FUNCTION_STARTS` decoded exactly as ld64 encodes it, including the Thumb bit and zero-delta terminator (`ios_dylib.c:575-652`).

Not counted, unverifiable within the allowed file scope: the commpage writes version `13` at `0x01E` and page-shift bytes at `0x085`/`0x087`, which match no XNU ARM layout I know (ARM uses version `3` and page shifts at `0x024`/`0x025`), but this only matters for real-libSystem dyld handoff.

**6 RESIDUAL DEFECTS**
