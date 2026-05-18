# Platform lock manager

A small, reusable wrapper around the standard SAP `ENQUEUE_*` / `DEQUEUE_*`
function modules. Apps no longer call the kernel enqueue directly — they
call **one** function module, `Z_REQUEST_LOCKING`, and pass in:

- A **header** describing the business object (`obj_type`, `obj_key`) and
  which kernel function module to delegate to (`function`), plus whether
  this is a lock or unlock request (`process` = `'E'` / `'D'`).
- A **parameters table** that is passed through to the kernel function
  module — one row per parameter (`name`, `type`, `value`).

While delegating, the wrapper keeps a persistent **registry table** of
all currently held locks (object type + key + owner + timestamp) so any
app on the platform can answer "who is editing this object right now?"
with a single SELECT — even after the original session has ended.

If a lock cannot be acquired, the function module returns the current
owner in `msg_description`, so the caller can show a friendly
"Locked by Alice since 09:32" message without doing the lookup itself.

## What you need to install

### 1. DDIC table `ZTLOCK_REGISTRY` (SE11)

Delivery class `A`, data browser/table view maintenance allowed.

| Field      | Key | Data element / Type | Description                |
|------------|-----|---------------------|----------------------------|
| MANDT      | X   | MANDT               | Client                     |
| OBJ_TYPE   | X   | CHAR30              | Business object type       |
| OBJ_KEY    | X   | CHAR70              | Business object key        |
| USERNAME   |     | SYUNAME             | Lock holder                |
| FUNCTION   |     | CHAR30              | SAP enqueue FM used        |
| LOCKED_AT  |     | TIMESTAMPL          | When the lock was acquired |

### 2. DDIC structure `ZS_LOCK_HEADER`

| Field    | Data element / Type | Description                            |
|----------|---------------------|----------------------------------------|
| OBJ_TYPE | CHAR30              | Business object type                   |
| OBJ_KEY  | CHAR70              | Business object key                    |
| FUNCTION | CHAR30              | Kernel enqueue/dequeue FM to call      |
| PROCESS  | CHAR1               | `'E'` for Enqueue, `'D'` for Dequeue   |

### 3. DDIC structure `ZS_LOCK_PARAM`

| Field | Data element / Type | Description                                       |
|-------|---------------------|---------------------------------------------------|
| NAME  | CHAR30              | Parameter name in the kernel FM (e.g. `VBELN`)    |
| TYPE  | CHAR40              | Parameter type (e.g. `VBAK-VBELN`, `CHAR1`)       |
| VALUE | CHAR250             | Parameter value as string                         |

### 4. Function group `Z_LOCK_MANAGER` containing the FM `Z_REQUEST_LOCKING`

Source code: [`z_request_locking.fugr.abap`](z_request_locking.fugr.abap).

## Function module interface

```text
FUNCTION Z_REQUEST_LOCKING

  IMPORTING
    VALUE(WA_HEADER)        TYPE  ZS_LOCK_HEADER
    VALUE(CLIENT_DEPENDENT) TYPE  CHAR1 DEFAULT 'X'
    VALUE(TTL_SECONDS)      TYPE  I     DEFAULT 1800

  EXPORTING
    VALUE(MSG_CODE)         TYPE  STRING
    VALUE(MSG_TYPE)         TYPE  CHAR1
    VALUE(MSG_TITLE)        TYPE  STRING
    VALUE(MSG_DESCRIPTION)  TYPE  STRING

  TABLES
    IT_PARAMETERS           STRUCTURE ZS_LOCK_PARAM
```

`MSG_TYPE` follows the SAP convention: `'S'` success, `'E'` error.

On `MSG_TYPE = 'E'` the caller should treat the request as failed and
display `MSG_DESCRIPTION` to the user. On a foreign lock,
`MSG_DESCRIPTION` contains the current owner and the lock time.

`TTL_SECONDS` controls how long a registry entry is considered valid.
After it elapses, the next lock request from any user overwrites the
old row — that is how the manager recovers from browser crashes that
left a stale lock behind. Default is 1800 seconds (30 minutes).

## How locks survive a session

The kernel SAP enqueue (`ENQUEUE_*`) is bound to the session that
acquired it. In a stateless abap2UI5 app, that session ends with the
HTTP roundtrip — so the kernel lock is gone right after the call
returns. That is unavoidable without `set_session_stateful( )`.

What carries the lock across sessions is the **registry table**
`ZTLOCK_REGISTRY`. A row inserted on a successful `ENQUEUE_*` is a
normal database record and survives session termination, work-process
recycling, even an app server restart. The function module reads the
registry **before** it touches the kernel, so a still-registered lock
from a long-finished session keeps blocking new attempts — exactly the
"who is editing this?" behaviour callers want. Cleanup is handled by
the `TTL_SECONDS` expiry; no background job required.

To keep the platform manager's kernel enqueues isolated from any
other enqueues the caller is holding, the kernel FM is invoked via
`DESTINATION 'NONE'`, so it runs in its own RFC session and shows up
under its own lock owner in SM12.

## How a consumer uses it

To lock sales order `0000004711` via `ENQUEUE_EVVBAK`:

```abap
DATA wa_header     TYPE zs_lock_header.
DATA it_parameters TYPE STANDARD TABLE OF zs_lock_param.

wa_header-obj_type = 'VBAK'.
wa_header-obj_key  = '0000004711'.
wa_header-function = 'ENQUEUE_EVVBAK'.
wa_header-process  = 'E'.

APPEND VALUE #( name = 'MODE_VBAK' type = 'CHAR1'      value = 'E' )           TO it_parameters.
APPEND VALUE #( name = 'MANDT'     type = 'MANDT'      value = sy-mandt )      TO it_parameters.
APPEND VALUE #( name = 'VBELN'     type = 'VBAK-VBELN' value = '0000004711' )  TO it_parameters.

CALL FUNCTION 'Z_REQUEST_LOCKING'
  EXPORTING
    wa_header        = wa_header
    client_dependent = 'X'
  IMPORTING
    msg_type         = DATA(msg_type)
    msg_description  = DATA(msg_description)
  TABLES
    it_parameters    = it_parameters.
```

To unlock, flip `function` to `DEQUEUE_EVVBAK` and `process` to `'D'`;
the parameters table stays the same.

For a complete consumer example see
[`../scenarios/z2ui5_test_lock_08.clas.abap`](../scenarios/z2ui5_test_lock_08.clas.abap).
