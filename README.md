# Platform Lock Manager

A reusable, event-driven lock manager for [abap2UI5](https://github.com/abap2UI5/abap2UI5) apps (and any stateless ABAP web app) that need to hold a lock across HTTP roundtrips.

The kernel `ENQUEUE_*` is bound to the calling session and dies with the HTTP roundtrip — that is true of every stateless ABAP web call. This addon decouples lock ownership from the web session by funneling every lock request through a **background user** that holds the kernel enqueue, and keeps a **persistent registry** of who locked what.

## What you get

- A **single API** (`z2ui5_cl_lock_manager=>request`) for any kernel enqueue object
- A persistent registry (`z2ui5_t_05` + `z2ui5_t_06`) carrying every active lock with object type, key, owner and timestamp
- A **uniform "locked by X" lookup** — `request` itself returns the owner in `msg_desc` on a foreign lock
- **Lock-by-key** for arbitrary business object types, not just standard SAP enqueue objects
- A **background report** that owns the kernel enqueue so the lock survives session end
- **Auto-release** based on a configurable TTL
- A ready-to-run **sample app** (`z2ui5_cl_lock_sample`) showing the full flow against `VBAK / ENQUEUE_EVVBAKE`

## Architecture

```
┌─────────────────┐       ┌──────────────┐       ┌──────────────────┐
│  abap2UI5 app   │──(1)─▶│  z2ui5_t_05  │       │  Background job  │
│                 │       │   PENDING    │       │ (system user)    │
│ request(...)    │──(2)─▶│ BP_EVENT_RAISE ────▶ │ process_pending  │
│                 │       │  LOCK_HANDLER│       │   ENQUEUE_*      │
│ wait_for_result │◀─(3)──│   DONE       │◀──────│   update row     │
└─────────────────┘       └──────────────┘       └──────────────────┘
```

1. The web request writes a `PENDING` row into `z2ui5_t_05` (parameters into `z2ui5_t_06`) and raises the SM64 event `LOCK_HANDLER` (or `LOCK_HANDLER_<mandt>` for client-dependent jobs).
2. SAP starts the background report, which loops over all pending rows and calls the requested `ENQUEUE_*` / `DEQUEUE_*` function module under its own user — so the kernel lock lives in the background work process, not in the web session.
3. The web request polls the row for up to 10 seconds and returns `Success` / `Error` / `Timeout`.

Because the kernel enqueue is held by the background user, the lock survives the HTTP roundtrip. The registry row in `z2ui5_t_05` is what makes the lock visible to other web sessions, even after the original work process has been recycled.

## Repository layout

| Object | Purpose |
| --- | --- |
| `z2ui5_cl_lock_manager` | Public API: `request`, `process_pending_requests`, `auto_release_locks`, `read_sm12_locks`, `read_lock_requests` |
| `z2ui5_t_05` | Lock requests (req_id, obj_type, obj_key, function, process, status, created_by, created_at, msg_text) |
| `z2ui5_t_06` | Lock request parameters (req_id, name, type, value) |
| `z2ui5_re_lock_background` | Background report — processes pending rows and auto-releases expired ones |
| `z2ui5_cl_lock_sample` | abap2UI5 sample app — lock / unlock / list SM12 / list registry |

## Setup

1. **Pull the repo** with abapGit into a Z-package.
2. **Create an SM64 event** named `LOCK_HANDLER` (and one `LOCK_HANDLER_<mandt>` per client if you want client-dependent jobs).
3. **Schedule the background job** `Z2UI5_RE_LOCK_BACKGROUND` in SM36 to start on the `LOCK_HANDLER` event:
   - `p_user` — the user the job runs as (must match `sy-uname` of the step)
   - `p_wait` — seconds between checks (default `2`)
   - `p_time` — minutes after which a held lock is auto-released (leave empty to disable)
4. Make sure the background user has enqueue authorization for the objects you want to lock.

## Calling the API

```abap
DATA(lt_params) = VALUE z2ui5_cl_lock_manager=>ty_params( (
  name  = 'VBELN'
  type  = 'VBAK-VBELN'
  value = mv_vbeln
) ).

DATA(ls_result) = z2ui5_cl_lock_manager=>request(
  iv_function = 'ENQUEUE_EVVBAKE'
  iv_process  = z2ui5_cl_lock_manager=>c_process_enqueue
  iv_obj_type = 'VBAK'
  iv_obj_key  = mv_vbeln
  it_params   = lt_params
).

" ls_result-msg_type = 'Success' | 'Error'
" ls_result-msg_desc on a foreign lock: 'Locked by: <USER>'
```

To release, flip the function and process:

```abap
ls_result = z2ui5_cl_lock_manager=>request(
  iv_function = 'DEQUEUE_EVVBAKE'
  iv_process  = z2ui5_cl_lock_manager=>c_process_dequeue
  iv_obj_type = 'VBAK'
  iv_obj_key  = mv_vbeln
  it_params   = lt_params
).
```

Set `iv_client_dependent = abap_true` if you want the request routed to a per-client `LOCK_HANDLER_<mandt>` event instead of the global `LOCK_HANDLER` event.

## Reading lock state

```abap
" Active kernel enqueues (SM12-style view)
DATA(lt_sm12) = z2ui5_cl_lock_manager=>read_sm12_locks( ).

" Registry rows
DATA(lt_reg)  = z2ui5_cl_lock_manager=>read_lock_requests(
  iv_status   = z2ui5_cl_lock_manager=>c_status_done
  iv_obj_type = 'VBAK'
).
```

## Sample app

`z2ui5_cl_lock_sample` is a ready-to-run abap2UI5 app that locks/unlocks a `VBAK` document and displays both the SM12 entries and the registry rows side by side. Wire it into your abap2UI5 launchpad to verify the round-trip end to end.

## Notes & limits

- `request` polls the registry row for up to **10 seconds**. If the background job is delayed beyond that you get `msg_type = 'Error'` / `msg_desc = 'Timeout'`. The row is still picked up later — call `read_lock_requests` to see the final status.
- The check for an existing lock looks at `status = DONE AND process = ENQUEUE` in `z2ui5_t_05`. Make sure your release path actually flips the row (or rely on `auto_release_locks`), otherwise stale entries will keep blocking new requests.
- `auto_release_locks` is invoked from the background report whenever `p_time` is set, so the cleanup cadence equals the event cadence. Schedule a periodic kick if you need a hard upper bound independent of incoming requests.
- The manager is advisory at the UX layer. Keep your save-time optimistic check (timestamp / ETag) in place — the database-level guard at save remains your responsibility.
