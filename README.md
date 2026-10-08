# lock-manager

[![abap2UI5-addons](https://img.shields.io/badge/abap2UI5--addons-library-1873b4)](https://github.com/abap2UI5-addons)
[![ABAP](https://img.shields.io/badge/ABAP-Standard%20%E2%89%A5%207.54-blue)](#installation)
[![abap2UI5](https://img.shields.io/badge/requires-abap2UI5-blue)](https://github.com/abap2UI5/abap2UI5)
[![License](https://img.shields.io/github/license/abap2UI5-addons/lock-manager)](LICENSE)
<br>
[![ABAP Standard](https://img.shields.io/github/actions/workflow/status/abap2UI5-addons/lock-manager/abap-standard.yaml?branch=main&label=ABAP%20Standard)](https://github.com/abap2UI5-addons/lock-manager/actions/workflows/abap-standard.yaml)
[![check-abap2UI5](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fabap2UI5-addons%2Flock-manager%2Fbadges%2Fcheck-abap2ui5.json)](https://github.com/abap2UI5-addons/lock-manager/actions/workflows/check-abap2ui5.yaml)
[![abap2UI5](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fabap2UI5-addons%2Flock-manager%2Fbadges%2Fabap2ui5.json)](https://github.com/abap2UI5-addons/lock-manager/actions/workflows/check-abap2ui5.yaml)

**Hold an SAP lock across the HTTP roundtrips of a stateless abap2UI5 app.**
A reusable, event-driven lock manager for [abap2UI5](https://github.com/abap2UI5/abap2UI5) apps — and any stateless ABAP web app.

Every stateless ABAP web call loses its SAP locks when the roundtrip ends. This addon decouples lock ownership from the web session: a **background handler** takes and holds the kernel locks on behalf of the web users, and a **persistent registry** records who actually holds what. On top of the classic exclusive lock it supports **shared** and **optimistic** locks, including the promotion of an optimistic lock to an exclusive one at save time.

> Part of [abap2UI5-addons](https://github.com/abap2UI5-addons) - addons and apps for [abap2UI5](https://github.com/abap2UI5/abap2UI5), installed with [abapGit](https://abapgit.org).

## Why

An abap2UI5 app gets a fresh session for every HTTP roundtrip, and an SAP
lock ends with the session that took it - so a lock taken when the user opens
an order for change is gone before the user sees the screen. A stateful
session would keep it, at the price of one reserved work process context per
user and locks that linger after a closed browser tab (see
[Concepts](#2-why-a-stateless-app-cannot-keep-a-lock)).

Good for:

- **ABAP developers of abap2UI5 apps that change business objects** - with a
  real SAP lock from a generated `ENQUEUE_*` module, which SAP GUI (VA02) and
  every other lock-aware program respect.
- **"Locked by X" with the real web user**, not the technical user that holds
  the kernel lock.
- **Optimistic locking** - open for change without blocking, first to save
  wins.

What it is not:

- **Not a replacement for durable locks.** Where your release and programming
  model offer them (RAP draft handling), they solve the problem at the kernel
  level; the lock manager is for where that is not an option.

## Installation

**Requirements**

- Standard ABAP 7.54 or higher
- [abap2UI5](https://github.com/abap2UI5/abap2UI5)
- a background user that may set the locks you request, and one background
  work process while any lock is held (see [Notes & limits](#notes--limits))

**Steps** - with [abapGit](https://abapgit.org):

1. [abap2UI5](https://github.com/abap2UI5/abap2UI5)
2. this repository (branch `main`) into a Z-package

**Start** - set up the background handler once:

1. **Create the event** in transaction **SM62** (tab *Background Events*, *New*): `LOCK_HANDLER` — and one `LOCK_HANDLER_<client>` per client if you use client-dependent jobs (e.g. `LOCK_HANDLER_100`, `LOCK_HANDLER_200`).
2. **Create a variant** for report `Z2UI5_RE_LOCK_BACKGROUND` in SE38 (e.g. `DEFAULT`):
   - `p_wait` — seconds between two looks at the queue (default and recommended: `2`)
   - `p_user` — the user the job step runs as; must match it, the report refuses to run otherwise
   - `p_time` — minutes after which a lock is released automatically (empty: never)
3. **Schedule the job** in **SM36**, e.g. `Z2UI5_LOCK_HANDLER`, with one step: user = the background user, program `Z2UI5_RE_LOCK_BACKGROUND`, variant `DEFAULT`. Start condition: **After event** `LOCK_HANDLER` with **Periodic job** checked — otherwise the job starts once and never again. For client-dependent jobs, create one job per client (e.g. `Z2UI5_LOCK_HANDLER_100` on event `LOCK_HANDLER_100`) and remove the job on the global event.
4. **Authorizations.** The background user must be allowed to set the locks you request.

Then run the sample app `?app_start=z2ui5_cl_lock_sample` (lock / promote /
unlock against `VBAK` / `ENQUEUE_EVVBAKE`, list SM12 and the registry) and
the SM12-style admin app `?app_start=z2ui5_cl_app_sm12`.

## Usage

### Calling the API

**Exclusive (pessimistic) lock:**

```abap
DATA(lt_params) = VALUE z2ui5_cl_lock_manager=>ty_params( (
  name  = 'VBELN'
  value = mv_vbeln
) ).

DATA(ls_result) = z2ui5_cl_lock_manager=>request(
  iv_process  = z2ui5_cl_lock_manager=>c_process_enqueue
  iv_function = 'ENQUEUE_EVVBAKE'
  iv_obj_type = 'VBAK'
  iv_obj_key  = mv_vbeln
  it_params   = lt_params
).

" ls_result-msg_type = 'Success' | 'Error'
" on a collision, ls_result-msg_desc = 'Locked by <USER>'
```

`type` in `ty_param` is optional — give it (`'VBAK-VBELN'`) to override the type the lock module declares.

**Release** — only object type and key are needed; the handler releases with the parameters the lock was taken with:

```abap
ls_result = z2ui5_cl_lock_manager=>request(
  iv_process  = z2ui5_cl_lock_manager=>c_process_dequeue
  iv_obj_type = 'VBAK'
  iv_obj_key  = mv_vbeln
).
```

**Optimistic lock** — open for change, then promote at save time:

```abap
" when the user opens the order for change
ls_result = z2ui5_cl_lock_manager=>request(
  iv_process  = z2ui5_cl_lock_manager=>c_process_enqueue
  iv_function = 'ENQUEUE_EVVBAKE'
  iv_mode     = z2ui5_cl_lock_manager=>c_mode_optimistic
  iv_obj_type = 'VBAK'
  iv_obj_key  = mv_vbeln
  it_params   = lt_params
).

" when the user saves - first to promote wins
ls_result = z2ui5_cl_lock_manager=>request(
  iv_process  = z2ui5_cl_lock_manager=>c_process_promote
  iv_obj_type = 'VBAK'
  iv_obj_key  = mv_vbeln
).
IF ls_result-msg_type = 'Error'.
  " 'Optimistic lock lost: Changed by <USER> first' - reload the data
ENDIF.
" then release and save as described in "Saving the data"
```

**Shared lock** — `iv_mode = z2ui5_cl_lock_manager=>c_mode_shared`: several users may hold it, nobody can lock the object exclusively meanwhile.

| Parameter | Default | Meaning |
| --- | --- | --- |
| `iv_process` | — | `E` enqueue, `D` dequeue, `R` promote |
| `iv_obj_type`, `iv_obj_key` | — | your identity for the object; the registry compares on these |
| `iv_function` | — | the `ENQUEUE_*` module (enqueue only); the `DEQUEUE_*` module is derived from it |
| `it_params` | — | key parameters of the lock module (enqueue only) |
| `iv_mode` | `E` | `E` exclusive, `S` shared, `O` optimistic |
| `iv_wait` | `abap_false` | pass `_WAIT = 'X'`: on a kernel collision, retry before giving up |
| `iv_timeout` | `10` | seconds to wait for the handler's answer |
| `iv_client_dependent` | `abap_false` | raise `LOCK_HANDLER_<client>` instead of `LOCK_HANDLER` |

### Reading lock state

```abap
" Kernel lock entries (SM12-style) - all owned by the background user
DATA(lt_sm12) = z2ui5_cl_lock_manager=>read_sm12_locks( ).

" Who holds what - the registry
DATA(lt_held) = z2ui5_cl_lock_manager=>read_lock_requests(
  iv_status   = z2ui5_cl_lock_manager=>c_status_active
  iv_obj_type = 'VBAK'
).
```

## What you get

- A **single API** (`z2ui5_cl_lock_manager=>request`) for any generated `ENQUEUE_*` lock module, with any number of key parameters
- **Three lock modes** — exclusive (`E`), shared (`S`) and optimistic (`O`) — plus **promotion** (`R`) of an optimistic lock to an exclusive one
- A persistent **registry** (`z2ui5_t_05` + `z2ui5_t_06`) of every request and every lock: object type, key, mode, owner, status and timestamp
- A **"locked by X" answer** that names the real web user, not the technical user holding the kernel lock — and the SAP GUI user when the object is locked outside the lock manager
- A **background handler** (`z2ui5_re_lock_background`) that owns the kernel locks, runs only while it is needed and never twice
- **Auto-release** after a configurable lifetime and **recovery** of all locks after a handler restart
- A ready-to-run **sample app** (`z2ui5_cl_lock_sample`) against `VBAK / ENQUEUE_EVVBAKE`
- An **SM12-style admin app** (`z2ui5_cl_app_sm12`) to browse and delete kernel lock entries

## Concepts

### 1. The SAP lock concept in brief

SAP does not rely on database locks to keep two users from changing the same business object. Database locks only live until the end of a database transaction, and a business transaction spans many of them. Instead, every application server talks to one central **enqueue server**, which keeps the **lock table** — the list you see in transaction **SM12**.

**Lock objects and lock modules.** A lock object (SE11, e.g. `EVVBAKE`) names one or more tables and the key fields that form the *lock argument*. Activating it generates two function modules, `ENQUEUE_EVVBAKE` and `DEQUEUE_EVVBAKE`. Their interface always follows the same pattern:

| Parameter | Meaning |
| --- | --- |
| key fields (`VBELN`, …) | the lock argument; an empty field locks generically (all values) |
| `MODE_<table>` | the lock mode per base table — `E`, `S`, `X` or `O` (and `R` to promote, see below) |
| `X_<field>` | lock the initial value of a field instead of treating it as generic |
| `_SCOPE` | who owns the lock: `1` the dialog session, `2` the update task (default), `3` both |
| `_WAIT` | on a collision, retry for a while before giving up |
| exception `FOREIGN_LOCK` | somebody else holds a colliding lock — `SY-MSGV1` names that user |
| exception `SYSTEM_FAILURE` | the enqueue server could not be reached or refused the request |

**Lock modes and collisions.** Whether a request is granted depends on the locks *other owners* already hold on the same argument:

| held by another owner → / requested ↓ | `S` shared | `O` optimistic | `E` exclusive | `X` exclusive, non-cumulative |
| --- | --- | --- | --- | --- |
| `S` shared | ✅ | ✅ | ❌ | ❌ |
| `O` optimistic | ✅ | ✅ | ❌ | ❌ |
| `E` exclusive | ❌ | ❌ | ❌ | ❌ |
| `X` exclusive, non-cumulative | ❌ | ❌ | ❌ | ❌ |

Shared locks are for reading ("nobody may change this while I look at it"), exclusive locks for changing. An optimistic lock collides like a shared lock; what makes it special is how it ends — see [section 5](#5-pessimistic-and-optimistic-locking).

**Lock owners and cumulation.** A lock does not belong to a user but to an *owner* — technically the session (dialog owner) or its update task (update owner). Locks of the *same* owner never collide with each other (except `X`); requesting the same lock again only increases a counter, and it takes the same number of dequeues to release it.

**When a lock ends.** A lock disappears when its owner calls the `DEQUEUE_*` module, when a lock passed to the update task (`_SCOPE = 2`) has been processed after `COMMIT WORK` — and in every case **when the session that owns it ends**.

### 2. Why a stateless app cannot keep a lock

That last rule is the whole problem. An abap2UI5 app — like any stateless ICF, OData or REST service — gets a fresh session for every HTTP roundtrip, and the session ends when the response is sent. A lock taken in roundtrip 1 is gone before the user even sees the screen that says "you are editing this sales order".

A stateful session would keep it, but at a high price: one reserved work process context per user, timeouts, and locks that linger after a user simply closes the browser tab. What is needed is a lock that outlives the request which took it, and whose owner is something other than the web session.

### 3. A proxy owner: the background handler

The lock manager makes a **long-running background job the owner of all kernel locks**:

```
 web session (stateless)                 registry                  background handler (one per client)
┌──────────────────────────┐        ┌──────────────┐        ┌──────────────────────────────────────────┐
│ request( ... )           │──(1)──▶│ z2ui5_t_05   │        │ loop every p_wait seconds:               │
│   write PENDING row      │        │ z2ui5_t_06   │◀──(3)──│   read PENDING rows, oldest first        │
│   start handler if none  │──(2)──▶│   event      │───────▶│   arbitrate against the registry         │
│   runs (SM64 event)      │        │ LOCK_HANDLER │        │   call ENQUEUE_* / DEQUEUE_*  (_SCOPE=1) │
│ wait_for_result( )       │◀──(4)──│ ACTIVE/ERROR │◀──(3)──│   write the answer, COMMIT WORK          │
└──────────────────────────┘        └──────────────┘        │ stop when nothing is pending or held     │
                                                            └──────────────────────────────────────────┘
```

1. The web request writes a `PENDING` row into `z2ui5_t_05` (key parameters into `z2ui5_t_06`) and commits it.
2. If no handler is running, it raises the event `LOCK_HANDLER` (or `LOCK_HANDLER_<client>`), which starts the job.
3. The handler works through the queue, calls the lock module **in its own session** and writes the answer back to the row.
4. The web request polls its row for up to `iv_timeout` seconds and returns `Success` or `Error`.

Because the kernel lock now lives in the handler's session, it survives the end of the HTTP roundtrip — and it stays a **real SAP lock**: a user in SAP GUI (VA02) or any other program that respects the lock object is kept out exactly as before.

Two details make this hold together:

- **`_SCOPE = 1`.** The handler commits after every request so the waiting web session sees the answer. With the default `_SCOPE = 2` that `COMMIT WORK` would hand the lock to the (empty) update task, which releases it immediately. With `_SCOPE = 1` the lock stays with the handler's session until it is dequeued.
- **Typed key fields.** Parameters travel through a database table as text. Before the call the handler converts each value into the type the lock module declares — taken from `ty_param-type` if you give one (`VBAK-VBELN`), otherwise read from the module's interface. A plain string where `VBAK-VBELN` is expected would make the call fail.

### 4. The registry: who really holds the lock

To the enqueue server, every lock now has the same owner: the handler. SM12 shows the background user for all of them, and the kernel's collision check no longer tells web user A from web user B — the handler would happily cumulate a second exclusive lock for B. So the decision *between web users* is made in the registry, and the kernel lock guards the object *against everything else*.

**Arbitration.** The handler is the only process that grants locks, and it handles one request at a time in arrival order. That makes the registry check and the kernel call a single atomic step without any database locking — first come, first served. The web request does a quick pre-check as well, but that only saves a roundtrip in the obvious case; the handler has the final word.

The registry applies the same collision matrix as the kernel, between different users:

| a user holds → / another user requests ↓ | `S` | `O` | `E` |
| --- | --- | --- | --- |
| `S` shared | ✅ | ✅ | ❌ |
| `O` optimistic | ✅ | ✅ | ❌ |
| `E` exclusive | ❌ | ❌ | ❌ |

**One kernel lock per object and mode.** When three users hold a shared lock on the same order, the kernel holds it once; the registry counts the holders. The kernel lock is taken for the first holder and released with the last one.

**Locked by whom.** A request that collides in the registry gets `Locked by <web user>`. A request that collides in the kernel — because a SAP GUI user or another program holds the object — gets the name the kernel reports in `SY-MSGV1`. Either way the answer names a person, never the technical background user.

**Statuses.** Every row in `z2ui5_t_05` goes through a small life cycle:

| Status | Meaning |
| --- | --- |
| `PENDING` | written by the web request, not yet handled |
| `ACTIVE` | an enqueue that was granted — this row *is* the lock |
| `DONE` | a dequeue or promotion that was carried out, or an enqueue the user already held |
| `ERROR` | rejected (collision, lock module failed, withdrawn after timeout) — `msg_text` says why |
| `RELEASED` | a lock that was released, by its user or by auto-release |
| `LOST` | an optimistic lock another user promoted first, or a lock that could not be recovered |

The registry keeps one lock per user, object and mode: asking again for a lock you hold is answered with success and does not stack up. A dequeue releases all locks the user holds on the object.

### 5. Pessimistic and optimistic locking

There are two ways to protect a change against a concurrent one.

**Pessimistic locking** assumes a conflict is likely and prevents it: lock the object *before* the user starts editing (`E`), and nobody else can even open it for change until the lock is released. It is simple and safe, but it blocks — a user who opens an order and goes to lunch keeps everybody else out.

**Optimistic locking** assumes a conflict is rare and detects it instead: many users may open the object for change at the same time; only at *save time* is it decided who wins, and the others learn that the data changed under them and must reload.

SAP builds optimistic locking into the lock concept itself, with lock mode **`O`**:

- An `O` lock is taken when a user opens an object in change mode. `O` locks of different owners do not collide, so any number of users can hold one on the same object. Against the rest of the world an `O` lock behaves like a shared lock: nobody gets an `E` lock while it exists.
- When a user saves, the `O` lock is **promoted** to an exclusive lock by requesting mode **`R`**. The promotion fails if someone else already holds a non-optimistic lock or promoted first.
- A successful promotion **deletes the `O` locks of all other owners**. Those users have lost the race: when they try to promote, they fail, and their application tells them to reload.

**The infinite transaction.** SAP's documentation illustrates this with a transaction that never leaves change mode. It keeps an `O` lock in the dialog (`_SCOPE = 1`) for as long as the user works, adds an update owner to it (`_SCOPE = 2`), and at every save converts only the update part into an `E` lock (mode `R`, `_SCOPE = 2`). `COMMIT WORK` passes the `E` lock to the update task, which releases it when the update is done — while the dialog's `O` lock simply stays, so the user continues editing without reloading. The `_WAIT` parameter lets the next promotion wait until the previous update has released its `E` lock.

**How the lock manager maps it.** All kernel locks belong to the handler, so the kernel cannot tell the optimistic holders apart; the registry does it instead, with exactly the kernel's rules:

1. `request( iv_process = 'E' iv_mode = 'O' … )` — the user opens the object. Other `O` and `S` holders are fine, an `E` holder is not.
2. `request( iv_process = 'R' … )` — the user saves. The handler checks that the user still holds an `O` lock and nobody holds `S` or `E`, then promotes the kernel lock with mode `R`. All other `O` holders on the object become `LOST` ("Changed by A first").
3. A user whose lock was lost gets `Optimistic lock lost: Changed by A first` on the promotion — the signal to reload.
4. `request( iv_process = 'D' … )` — the winner releases after saving.

The result is the familiar "first one to save wins" behaviour, enforced centrally, with a precise answer for the loser — and SAP GUI users are kept out for the whole time, because the kernel still holds a real lock.

**Optimistic checks on the data itself.** A lock only protects against other *lock-aware* programs. Keep a check on the data in your save path as well — compare a change timestamp, a version counter or an ETag read at display time with the current one. It is the last line of defence and costs one `SELECT`.

### 6. Saving the data

The handler holds the kernel lock, and your save runs in the web session. If the save calls a BAPI or function that locks the object itself, that inner `ENQUEUE_*` collides with the handler's lock (`FOREIGN_LOCK`, "locked by" the background user). The lock is a reservation, not a pass for the save. A save therefore follows this sequence, **in one roundtrip**:

1. **Promote** (optimistic mode) — decides that you are the one who may save; the other optimistic holders lose.
2. **Release** — `request( iv_process = 'D' … )`; the handler dequeues the kernel lock.
3. **Lock in your own session** — call `ENQUEUE_*` yourself (with `_WAIT = 'X'`), or let the BAPI do it.
4. **Check and save** — the optimistic data check from above, then the change, then `COMMIT WORK`.

Between steps 2 and 3 there is a short window in which another program could take the lock. If it does, step 3 fails with a proper "locked by" message and nothing has been written — exactly what a conflict should look like.

### 7. Lifecycle of the handler

The handler is a background job that is **started only when needed** and **stops when it has nothing left to do** — but it must keep running while it holds locks, because its locks die with it.

- **Start on demand.** `SM64` event `LOCK_HANDLER` starts it. A web request raises the event only if no handler is running; a running handler finds new requests on its next look at the queue, every `p_wait` seconds.
- **One instance per client.** The handler holds a guard — an exclusive `E_TABLE` lock on the registry table with the argument `<client>LOCK_HANDLER`. A second job started by the same event finds the guard taken and stops at once. The web request uses the same guard to find out whether a handler is running.
- **Stop when idle.** When no request is pending and no lock is held, the handler releases the guard, looks at the queue one last time and ends. A request committed before that last look is still handled; one committed after it finds the guard free and starts a new handler. No request falls between two handlers.
- **Client-dependent jobs.** The registry is client-dependent, so a handler only ever sees its own client's rows. With `iv_client_dependent = abap_true` the request raises `LOCK_HANDLER_<client>`, so that each client's job has an event of its own.

### 8. Housekeeping: auto-release and recovery

- **Auto-release.** With `p_time` set, the handler releases every lock older than `p_time` minutes (status `RELEASED`, "Auto-released after n minutes"). That bounds the damage of a user who never comes back — the stateless equivalent of a session timeout.
- **Withdrawal after timeout.** If the handler does not answer an enqueue within `iv_timeout` seconds, the web request withdraws it (`ERROR`, "Withdrawn…"). A lock granted after the requester gave up would be held by nobody who knows about it; if the handler grants it in that very moment anyway, it releases it again.
- **Recovery.** If the handler job ends abnormally (cancelled in SM37, short dump, system restart), its kernel locks are gone while the registry still lists them as `ACTIVE`. The next handler takes all of them again before it handles any new request. A lock that someone else grabbed in the meantime becomes `LOST`, with the name of the new holder.

Newer ABAP platform releases add **durable locks** to the SAP lock concept — locks whose lifetime is not bound to a session, which RAP builds on for draft handling. Where you can use them, they solve the problem of section 2 at the kernel level. The lock manager is for the releases and programming models where that is not an option.

## Repository layout

| Object | Purpose |
| --- | --- |
| `z2ui5_cl_lock_manager` | Public API: `request`, `run_handler`, `process_pending_requests`, `recover_locks`, `auto_release_locks`, `read_sm12_locks`, `read_lock_requests` |
| `z2ui5_t_05` | Registry: requests and locks (req_id, obj_type, obj_key, function, process, lock_mode, lock_wait, status, created_by, created_at, msg_text) |
| `z2ui5_t_06` | Key parameters per request (req_id, name, type, value) |
| `z2ui5_re_lock_background` | The background handler — a thin report around `run_handler` |
| `z2ui5_cl_lock_sample` | abap2UI5 sample app — lock (E/S/O) / promote / unlock / list SM12 / list registry |
| `z2ui5_cl_app_sm12` | abap2UI5 admin app — browse and delete kernel lock entries (SM12-style, with authorization checks) |

## Notes & limits

- **A running handler occupies one background work process** — for as long as any lock is held. Size the background work processes accordingly and use `p_time` to put an upper bound on forgotten locks.
- **`_WAIT` holds up the queue.** The handler works through requests one by one; a request with `iv_wait = abap_true` that meets a foreign kernel lock blocks the others until the enqueue server's wait time is over. Keep `iv_timeout` above that time when you use it.
- **Only generated lock modules.** The lock function must be an `ENQUEUE_*` module; the handler derives the `DEQUEUE_*` module from its name and reads its interface for types, `MODE_*`, `_SCOPE` and `_WAIT`.
- **One user, one holder.** The registry identifies holders by SAP user name. The same user in two browser tabs is one holder, just as two SAP GUI sessions of one user would not lock each other out of a shared lock.
- **SM12 shows the background user.** Use the registry (`read_lock_requests`, the sample app) to see who holds a lock; `SM12` shows the technical owner.
- **Keep the data check at save time.** The lock manager coordinates lock-aware programs. The optimistic check on the data (timestamp, version, ETag) at save time remains your responsibility — see [section 5](#5-pessimistic-and-optimistic-locking).

## Development

```sh
npm ci
npm run check   # abaplint (Standard ABAP 7.54) and the abap2UI5 linter - what CI runs
```

The gates and the linter baseline are described in
[CONTRIBUTING.md](CONTRIBUTING.md).

## Contributing

Issues and pull requests are welcome - see [CONTRIBUTING.md](CONTRIBUTING.md)
and [AGENTS.md](AGENTS.md). Security issues: [SECURITY.md](SECURITY.md).

## License

MIT - see [LICENSE](LICENSE).
