Review complete. Six files read; findings below are from static inspection only, no runs.

## P1 — correctness

1. **Weak-import symbols are fatal instead of binding NULL.** `src/ios/ios_bind.c:384-405` discards `imm` on `BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM`, so `BIND_SYMBOL_FLAGS_WEAK_IMPORT` (0x1) is lost, and `src/ios/ios_bind.c:333-339` then errors with "cannot resolve" for any symbol the synthetic libSystem lacks. Any app using availability-guarded APIs (`if (&fn)` idiom, very common in 32-bit iOS builds) fails to load. Fix: add `bool weak_import` to `ios_bind_state_t`, set it from `imm & 0x1`, and in `ios_bind_once` on `!found && weak_import` write 0 to the slot and return 0.

2. **Initializer order is reverse-BFS, not dependency order.** `src/ios/ios_dylib.c:271-276` runs images `count-1 .. 1`, then 0. Images are appended in BFS order by `ios_load_inner`, so if the executable lists `[B, A]` and A depends on B, A is index 3 and B is index 2, so A's constructors run before B's. Fix: DFS post-order over `dep_image_idx` with a visited bitmap, root at image 0.

3. **CRT0 exits via raw `SYS_exit`, bypassing atexit and stdio flush.** `src/ios/ios_commpage_stack.c:174-177` does `mov r12,#1; svc #0x80` when `main` returns. `__cxa_atexit` destructors and any guest-side buffering are skipped. Fix: call the synthetic `exit` stub (`svc #0x81` with its stub id) with r0 = main's return. Verify first how `a32_ios_handle_stub_svc` implements `exit`; if it already drains atexit this drops to P2.

## P2 — correctness and robustness

4. **`ios_apply_prot` over-protects by a page when vmaddr is unaligned.** `src/ios/ios_dylib.c:369-370` computes `end = page_up(vmaddr + vmsize)` but `vmsize` is already `seg_end - seg_start` (rounded from `page_down(vmaddr)`). Every other consumer uses `start + vmsize` (`ios_dylib.c:256`, `ios_bind.c:58`, `ios_dylib.c:393`). Fix: `end = start + vmsize`.

5. **Export trie edges longer than 255 bytes mis-match.** `src/ios/ios_export.c:125-130` truncates the edge into `edge[256]` and returns the truncated length, then `ios_export.c:218-222` compares and advances `rem` by that truncated length. Long C++ mangled template names produce long edges. Fix: compare `b + start` against `rem` with the true length and drop the copy.

6. **Dedupe is by path string only.** `src/ios/ios_dylib.c:116-120`. The same dylib reached via `@rpath/Foo` and `@executable_path/Frameworks/Foo` loads twice: two copies of globals, two initializer runs. Fix: also compare `(st_dev, st_ino)` after `fstat`, and compare `install_name` once parsed.

7. **Dylibs with a nonzero preferred base above the bump are rejected.** `src/ios/ios_macho.c:556-561` fails with "dylib base collision" if `*dylib_bump < min_va`. Slide should be computed mod 2^32; the later `slid` math at `ios_macho.c:594-595` would then also need to be done in `uint32_t` before range-checking.

8. **No cross-image overlap check before `MAP_FIXED`.** `src/ios/ios_macho.c:617` maps anonymously over whatever is there; `prev_end` is per image only. A non-PIE executable linked at or above `0x10000000` is silently clobbered by the first dylib. Fix: call `a32_vm_range_overlaps(map_start, seg_end)` and fail. Also, the branch at `ios_macho.c:608-615` is dead: `prev_end` is page-aligned so `page_down(prev_end) == prev_end`, and the "same page shared" path is unreachable; either delete it or implement it. Note the loop also assumes segments are sorted by vmaddr.

9. **Classic (pre-`LC_DYLD_INFO`) binding gaps.** `src/ios/ios_bind.c:45-46` defines `INDIRECT_SYMBOL_LOCAL/ABS` as `0xFFFFFFFF/0xFFFFFFFE`; the real values are `0x80000000` and `0x40000000`, possibly OR'd. It only works by accident via the `>= nsyms` check at `ios_bind.c:602`. External relocations (`extreloff/nextrel`) are never applied, so data-resident pointers to external symbols stay unbound. `ios_run_local_relocs` at `ios_bind.c:240` ignores `MH_SPLIT_SEGS` (r_address relative to first writable segment). Three `goto out` paths (`ios_bind.c:581`, `:612`, `:631`) return -1 with no diagnostic, so the loader dies silently.

10. **Synthetic fallback inside `a32_ios_resolve_in` masks two-level namespace errors.** `src/ios/ios_export.c:343` returns a synthetic libSystem symbol with `found=true` for *any* image. A bind whose ordinal points at a real user dylib that lacks the symbol silently binds to libSystem instead of failing. Move the fallback to `ios_bind_once`, only when the target is image 1 or the flat-lookup path.

11. **Stub-and-resolver exports bind to the stub.** `src/ios/ios_export.c:329-333` picks `arg0` (stub) and ignores `arg1` (resolver). The stub reads a lazy pointer in its own image that our eager bind resolves to the same stub, giving an infinite loop at first call. Rare outside libSystem, but should at least fail loudly or bind the resolver and call it once at init.

12. **Host filesystem fallback.** `src/ios/ios_dylib.c:127` opens `cand` on the host when the sysroot misses. A guest binary can direct the loader to arbitrary host paths. Gate it behind an explicit opt-in.

13. **Silent initializer cap.** `src/ios/ios_dylib.c:283,336` stops collecting at 64 with no error. Large C++ binaries exceed this. Fail loudly or raise the cap.

14. **Caller-owned `exec_fd` is closed.** `src/ios/ios_dylib.c:455` stores the passed-in fd in `images[0].fd`, and `ios_dylib.c:621-626` closes it. If `main.c` keeps using `AT_EXECFD`, that is a double close. Verify in `main.c`.

15. **Non-PIE executable can be slid without relocations.** `src/ios/ios_macho.c:548-549` applies `slide = 0x4000 - min_va` to a non-PIE `MH_EXECUTE` with `min_va < 0x1000`. Non-PIE executables carry no rebase info, so this corrupts absolute addresses. Refuse instead.

## PERF — candidate hypotheses, unmeasured

- **PERF-1: every symbol lookup re-reads and re-parses the whole export trie or symtab+strtab.** `src/ios/ios_export.c:244-251` and `:305-311` do `malloc` + `pread` of the full tables per call, inside per-slot loops in `ios_bind.c`. Bind cost is O(slots × table bytes) of I/O. Cache the blobs per image for the duration of `a32_ios_bind_all` and free after.
- **PERF-2: hot libc leaves go through `svc #0x81`.** `src/ios/ios_commpage_stack.c:197-203`. Every `memcpy`, `strlen`, `memcmp` call is a full guest-to-host context switch with d0-d31 save/restore. There are about 6 KiB free at `0xFFFF2800..0xFFFF4000` for guest-native Thumb-2 implementations of the top leaf routines. Instrument with a per-stub-id counter under `--stats` before doing this.
- **PERF-2: segment payload is copied twice** through an 8 KiB stack buffer (`src/ios/ios_macho.c:308-320`). Mach-O segments are page-aligned, so a file-backed `MAP_PRIVATE|MAP_FIXED` would be zero-copy and demand-paged, if the `hl` backend allows file mappings into the window.

## POLISH — ABI and observability

- **CommPage:** `src/ios/ios_commpage_stack.c:93` writes version 13, which is the x86 value; `_COMM_PAGE_THIS_VERSION` for arm is 3. `_COMM_PAGE_CPU_CAPABILITIES` (0x020) is left zero. Offsets 0x058, 0x085, 0x087 are written without named constants; cross-check against `osfmk/arm/cpu_capabilities.h` and name them.
- **TSD:** `ios_commpage_stack.c:221` sets slot 1 to the integer 1. Darwin slot 1 is the errno pointer (should be `0xFFFF5500`) and slot 3 is `mach_thread_self`.
- **apple[] vector:** constant `stack_guard` and `malloc_entropy`; missing `main_stack=`, `executable_file=`, `ptr_munge=`. `pfz=` points at an RO data page.
- **Stack:** no guard page below `IOS_STACK_BASE`; `RLIMIT_STACK` ignored; `a32_vm_record_region` return ignored at `ios_commpage_stack.c:336`; argv/envp silently truncated at 511.
- **Environment:** host `envp` is passed verbatim into the Darwin guest.
- **Slice choice:** `ios_macho.c:156-159` prefers armv7s over armv7. armv7 is the safer default unless the DBT's `sdiv/udiv` and VFPv4 paths are specifically validated.
- **Unhandled Mach-O features:** `LC_ROUTINES`, `__mod_term_func`, thread-local variable sections (`S_THREAD_LOCAL_*`), `DYLD_LIBRARY_PATH` / fallback paths, `@rpath` from the full load chain rather than only `images[cur]` and `images[0]` (`ios_dylib.c:206`).
- **Observability:** honor `DYLD_PRINT_LIBRARIES` / `DYLD_PRINT_BINDINGS` style tracing; today the only output is terse stderr on fatal paths.

Items 1, 2, 4, 5, and 9's constants are mechanical fixes. Item 3 and 14 need a quick look at the stub handler and `main.c` to confirm severity.