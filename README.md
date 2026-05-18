
## 9. Scenario 8 — Platform lock manager

**Source (consumer):** [`scenarios/z2ui5_test_lock_08.clas.abap`](scenarios/z2ui5_test_lock_08.clas.abap)
**Source (implementation):** [`platform-lock-manager/`](platform-lock-manager/) — see the README in that folder for the DDIC setup and the function-module interface.

If your installation ships with a **platform lock manager** — a reusable wrapper around `ENQUEUE_*` / `DEQUEUE_*` plus a persistence table — prefer it over rolling your own enqueue + soft-lock combo by hand. This repo ships one such wrapper as a working example. It gives you:

- A **single API** (one function module, `Z_REQUEST_LOCKING`) for any kernel enqueue object
- A persistent **`ZTLOCK_REGISTRY` table** carrying every active lock with object type, key, owner and timestamp
- A **uniform "locked by X since Y" lookup** — the FM itself returns the owner in `msg_description` on a foreign lock
- **Lock-by-key** for arbitrary business object types, not just standard SAP enqueue objects

The call shape is always the same:

```abap
wa_header-obj_type = 'VBAK'.
wa_header-obj_key  = vbeln.
wa_header-function = 'ENQUEUE_EVVBAK'.   " or DEQUEUE_EVVBAK
wa_header-process  = 'E'.                " or 'D'

" pass the kernel FM's parameters as rows
APPEND VALUE #( name = 'VBELN' type = 'VBAK-VBELN' value = vbeln ) TO it_parameters.
...

CALL FUNCTION 'Z_REQUEST_LOCKING'
  EXPORTING wa_header = wa_header
            client_dependent = 'X'
  IMPORTING msg_type = msg_type
            msg_description = msg_description
  TABLES    it_parameters = it_parameters.
```

To unlock the same object you flip `function` to `DEQUEUE_EVVBAK` and `process` to `'D'` — same parameters table.

**When to use this:**
- Your platform already provides one — using it makes your app consistent with every other app on that platform (single overview of who locks what, single admin tool to clear stuck locks)
- You want soft-lock semantics (Scenario 6) without writing the Z table, the lookup, and the cleanup logic yourself

**Key idea:** the wrapper hides the persistence table and the lookup behind a single FM. Your app just asks "can I have a lock on `VBAK / 0000004711`?" and gets back a clear yes/no plus, on a foreign lock, the owner and timestamp ready to display. You still pair it with the optimistic timestamp check at save time, because the registry is advisory at the UX layer — the database-level guard at save is still your responsibility.

**Persistence across sessions:** the kernel `ENQUEUE_*` is bound to the calling session and dies with the HTTP roundtrip — that is true of every stateless ABAP web call. What carries the lock across sessions is the `ZTLOCK_REGISTRY` row, which is a normal DB record and survives session termination. The wrapper reads the registry **before** it touches the kernel, so a still-registered lock from a long-finished session keeps blocking new attempts. A `TTL_SECONDS` parameter (default 30 minutes) lets expired entries get overwritten automatically, so a browser crash does not leave a permanent block. The kernel call itself goes through `DESTINATION 'NONE'` to keep the manager's enqueues isolated from anything else the caller may be holding.

---
