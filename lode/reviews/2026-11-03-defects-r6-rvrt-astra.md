Found **five findings** at HEAD `8b57344`. Used seven read-only shell invocations; no Markdown, builds, tests, Docker, or QEMU. Novelty was checked against available remediation commit messages and code diffs; exclusion from every historical finding cannot be guaranteed without the prior reports.

1. **rvrt-R6-1 — BUG — HIGH**  
   **Location:** `src/dbt_emit_m.c:110–120`, `:64–76`, `:139–151`  
   Division overwrites its divisor before checking for zero when `mdst == mr2`. The register mapping in `src/dbt_emit_fp.h:418–445` permits this when `rd == rs2`, and for distinct guest registers sharing a cache slot. For example, `div a1,a0,a1` with `a0=1, a1=2` produces quotient zero, then compares that overwritten divisor against zero and replaces the correct result with −1. This affects signed/unsigned division in RV32, RV64, and RV64 word forms.  
   **Fix:** Compare the original divisor before emitting division, preserving those flags through `CSEL`, or retain the divisor in a scratch register. Cover destination/divisor aliases and zero quotients.

2. **rvrt-R6-2 — BUG — HIGH**  
   **Location:** `src/linux/message.c:493–513`  
   `load_message()` accepts RV32’s 28-byte `msghdr`, but `update_header()` always writes RV64 offsets: flags at `+48`, eight-byte control length at `+40`, and name length at `+8`. RV32 requires four-byte fields at `+24`, `+20`, and `+4`. Successful receives therefore overwrite adjacent guest memory or return `EFAULT` after consuming data. A non-null name also causes the guest’s iovec pointer at `+8` to be read and overwritten as a length.  
   **Fix:** Select output offsets and widths with `rv_space_is32()`. Add adjacent-memory canaries and a header ending at a page boundary.

3. **rvrt-R6-3 — DEFECT — MEDIUM**  
   **Location:** `src/linux/message.c:230–244`, `:440–487`  
   Ancillary-data decoding and encoding always use a 16-byte header, eight-byte `cmsg_len`, and eight-byte alignment. RV32 requires a 12-byte header, four-byte length, and four-byte alignment. A valid RV32 single-fd `SCM_RIGHTS` message is rejected because `le64(control)` incorporates `cmsg_level` into the length. Receiving into the normal 16-byte RV32 buffer yields zero descriptor capacity and truncation; larger buffers receive malformed headers.  
   **Fix:** Implement guest-width-aware control-header offsets, length codecs, alignment, and payload capacity for both directions.

4. **rvrt-R6-4 — DRY — LOW**  
   **Location:** `src/loader/stack.c:103–118`, `:190–205`  
   RV32 and RV64 stack builders duplicate the complete `/dev/urandom` open/read/retry/close sequence and its failure handling. Changes to entropy acquisition must be maintained twice within the same file.  
   **Fix:** Extract one file-local helper that fills the 16-byte auxiliary-vector random payload, preserving short-read, `EINTR`, and close-error handling. Keep it entirely within `rvrt`.

5. **rvrt-R6-5 — YAGNI — LOW**  
   **Location:** `src/linux/message.c:42`, `:109–120`  
   `guest_message_t.input_flags` is populated for both ABIs but never read. Actual syscall flags come from `arguments[2]`; receive output flags are computed separately. The field misleadingly suggests that input `msg_flags` participates in processing.  
   **Fix:** Remove the field and both initializer assignments.

These are static findings, not runtime-verified reproductions. No files were changed.