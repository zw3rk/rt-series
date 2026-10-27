- **RESOLVED — Multiple mappings:** `src/vm/vm_file.c:95` keys entries by inode and mapping GVA, preserving earlier mappings. The mutation loop visits every matching entry and applies shrink handling (`:224`, `:239`).
- **RESOLVED — COW preservation:** `src/rt32/vm_mmap.c:229` uses the state-preserving helper, which republishes each page’s existing state (`:247`) through the accessor added at `src/vm/vm32.c:208`.

**Final verdict: PASS** for the two requested items in `26f4923`.

Reviewed only the commit’s touched lines. No files modified; no builds, tests, or Docker run.