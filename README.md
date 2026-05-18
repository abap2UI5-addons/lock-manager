# Locking Sales Orders in abap2UI5 — A Beginner's Guide

This guide explains **how to lock business objects in abap2UI5 apps**, step by step, starting from the simplest case and adding one layer at a time.

Every section points at a **complete, copy-paste-ready demo class** stored in this repository. To try a snippet:

1. Open the linked file.
2. Create a new ABAP class with the matching name (e.g. `z2ui5_test_lock_01`).
3. Paste the file contents as the class source.
4. Activate it.
5. Launch via the abap2UI5 launchpad URL with `?app=<class_name>`.

We use the **sales order header table `VBAK`** as the example throughout, because it ships with every SAP system and has a real, standard SAP enqueue object (`EVVBAK`).

## Repository layout

```
scenarios/
  z2ui5_test_lock_01.clas.abap   Scenario 1 — Naive editing (no locking)
  z2ui5_test_lock_02.clas.abap   Scenario 2 — Enqueue at save
  z2ui5_test_lock_03.clas.abap   Scenario 3 — Optimistic locking
  z2ui5_test_lock_04.clas.abap   Scenario 4 — Enqueue + Optimistic (recommended)
  z2ui5_test_lock_05.clas.abap   Scenario 5 — Stateful session
  z2ui5_test_lock_06.clas.abap   Scenario 6 — Soft lock (advisory)
  scenario_07_rap_draft.abap     Scenario 7 — RAP draft (BDEF + EML)

platform-lock-manager/
  z2ui5_test_lock_08.clas.abap   Scenario 8 — Platform lock manager demo
```

---

## 1. Why is locking on the web different?

In classic SAP GUI, you open transaction `VA02`, the system calls `ENQUEUE_EVVBAK`, and **the lock lives as long as your dialog session lives**. You can think for ten minutes — the lock is still there.

A web app is **stateless** by default. Every roundtrip (HTTP POST) is a fresh ABAP session. A lock set during one roundtrip is gone by the next one. abap2UI5 lets you opt into **stateful sessions**, but you have to think about *when* you want that.

That difference creates the entire field of "web locking strategies." We will go through them one by one.

### The two questions you must answer

| Axis | Question |
|---|---|
| **A — Edit phase** | What happens while the user is *thinking and typing*? |
| **B — Save phase** | What happens *the moment they hit save*? |

Every realistic app picks one strategy per axis. They compose.

---

## 2. Scenario 1 — Naive editing (no locking)

**Source:** [`scenarios/z2ui5_test_lock_01.clas.abap`](scenarios/z2ui5_test_lock_01.clas.abap)

The simplest possible starting point. The user can change a sales order and save. **There is no lock and no conflict check.** Last save wins, silently.

This is rarely what you want in production, but it is the right place to *start* — every later scenario layers a single concept on top of this one, so you can see exactly what each layer buys you.

**When to use this:**
- Personal sandboxes, throwaway demos, internal tools where only one user ever touches a record

**Key idea:** `client->_bind_edit( auart )` creates a two-way binding — what the user types lands back in `auart` before the SAVE event fires. There is no lock and no check. If two users edit the same order, the second save silently wipes the first one's changes. Every later scenario fixes a specific piece of this problem.

---

## 3. Scenario 2 — Edit + Enqueue at save

**Source:** [`scenarios/z2ui5_test_lock_02.clas.abap`](scenarios/z2ui5_test_lock_02.clas.abap)

Now the user can change the sales order type. We do **not** hold a lock while they think. At the moment they press *Save*, we lock, write, commit, and release in one short roundtrip.

**When to use this:**
- Quick edits with low chance of two users hitting the same record
- Default starting point for most stateless editing apps

**Key idea:** the lock only exists for milliseconds, during the save event. Two users editing the same order in parallel will both succeed if neither saves at the literal same instant — the last save wins. That is a problem we fix in the next scenario.

---

## 4. Scenario 3 — Optimistic locking (timestamp check)

**Source:** [`scenarios/z2ui5_test_lock_03.clas.abap`](scenarios/z2ui5_test_lock_03.clas.abap)

Now we add a *conflict check*. On read we remember the record's last-changed timestamp. On save, we re-read it and **reject** if it changed in the meantime. This is the same idea as HTTP ETag or OData's `@odata.etag`.

**When to use this:**
- Any time silent overwrites would be a problem
- Combine with Scenario 2 — it costs almost nothing and catches real bugs

**Key idea:** `token_aedat`/`token_aezet` travel with the app session. On save, we re-read the live values from the database and reject if they have shifted. No lock is held during the edit phase, so this scales to many concurrent users.

---

## 5. Scenario 4 — Combined (the recommended default)

**Source:** [`scenarios/z2ui5_test_lock_04.clas.abap`](scenarios/z2ui5_test_lock_04.clas.abap)

Enqueue at save **and** the optimistic check. This is the safest stateless pattern and the one most production apps should default to.

**Why both:**
- The enqueue serializes concurrent writers so two saves cannot interleave.
- The timestamp check catches anyone who slipped in via another path (SE16, batch job, classic SAP GUI) between your read and your write.

**Key idea:** belt-and-suspenders. The enqueue prevents two parallel saves of *this* app from colliding. The timestamp check catches everything else.

---

## 6. Scenario 5 — Stateful session with a persistent enqueue

**Source:** [`scenarios/z2ui5_test_lock_05.clas.abap`](scenarios/z2ui5_test_lock_05.clas.abap)

Sometimes you want classic SAP GUI behaviour: the moment the user opens the screen, the lock is held until they save or leave. With `client->set_session_stateful( )`, abap2UI5 keeps the session alive between roundtrips so a real `ENQUEUE_EVVBAK` survives.

**When to use this:**
- Internal back-office apps with few concurrent users
- You want users to *immediately* see "locked by X" when opening

**Cost:** each active user pins a work process. Do **not** use this for high-traffic apps.

**Key idea:** while the app is open, an SM12 entry for `EVVBAK` / `0000004711` is visible. The user can navigate, type, wait — the lock stays. If they close the browser without pressing *Cancel*, the lock will eventually expire when the session times out.

**Compare with `z2ui5_cl_demo_app_350`** in the abap2UI5 demos repo for a similar pattern using `ENQUEUE_E_TABLE`.

---

## 7. Scenario 6 — Soft lock (advisory only)

**Source:** [`scenarios/z2ui5_test_lock_06.clas.abap`](scenarios/z2ui5_test_lock_06.clas.abap)

A soft lock is a row in a **custom Z table** marking *"user X is editing sales order Y."* It is **not** enforced by the SAP kernel — only your app code respects it. Use it for **UX feedback** ("locked by Alice since 09:32"), always layered on top of a real save-time guard.

### 7.1 Create the Z table

Create a small table in SE11 called `ZS_SO_LOCK`:

| Field      | Type        | Description           |
|------------|-------------|-----------------------|
| MANDT      | MANDT       | Client (key)          |
| VBELN      | VBELN_VA    | Sales order (key)     |
| USERNAME   | SYUNAME     | Editing user          |
| LOCKED_AT  | TIMESTAMPL  | When the lock started |

Delivery class `A`. Activate.

### 7.2 The app

See [`scenarios/z2ui5_test_lock_06.clas.abap`](scenarios/z2ui5_test_lock_06.clas.abap).

**Key idea:** the soft lock decides *who can edit in the UI*. The enqueue + timestamp check decides *whether the save is allowed*. They serve different jobs.

**Gotcha:** if a user closes the browser without pressing *Release & Exit*, the row stays in `ZS_SO_LOCK` forever. In production you would add a small background job that deletes rows older than, say, 30 minutes.

---

## 8. Scenario 7 — RAP draft (the modern alternative)

**Source:** [`scenarios/scenario_07_rap_draft.abap`](scenarios/scenario_07_rap_draft.abap)

If you are on **S/4HANA** or **BTP ABAP Environment (Steampunk)**, the canonical pattern is no longer "hold a lock during edit." Instead you create a **draft instance** of the sales order in a framework-managed shadow table. The active record is untouched until the user explicitly activates.

This sidesteps the whole lock-during-think-time problem.

The linked file contains both the RAP **behaviour definition** (BDEF) and an example abap2UI5 **EML** call from an event handler.

**Key idea:** the framework handles ETag checks, draft persistence, and the activation enqueue **for you**. abap2UI5 just calls the BO methods. For non-trivial editing apps on a modern stack, this is usually the cleanest choice.

For a full draft workflow (Edit → multiple round-trips on the draft → Activate), see the official [SAP RAP documentation](https://help.sap.com/docs/abap-cloud/abap-rap/draft).

---

## 9. Scenario 8 — Platform lock manager

**Source:** [`platform-lock-manager/z2ui5_test_lock_08.clas.abap`](platform-lock-manager/z2ui5_test_lock_08.clas.abap)

If your installation ships with a **platform lock manager** — a reusable class that wraps `ENQUEUE_*` / `DEQUEUE_*` and a persistence table behind a single API — you should usually prefer it over rolling your own enqueue + soft-lock combo by hand. The platform manager typically gives you:

- A **single API** for both transient (`ENQUEUE_*`) and persistent (Z-table-backed) locks
- Automatic **heartbeat / expiry**, so a crashed browser does not leave a permanent lock
- A **uniform "locked by X since Y" lookup** that any app on the platform can consume
- Built-in **lock-by-key** for arbitrary business object types, not just standard SAP enqueue objects

Method names vary across platforms — common shapes are `lock( )` / `unlock( )` / `check( )` / `get_info( )` on a class like `cl_platform_lock_manager` (often invoked via singleton, e.g. `cl_platform_lock_manager=>get_instance( )`). The linked file uses generic placeholders; swap in whatever your platform actually exposes.

**When to use this:**
- Your platform already provides one — using it makes your app consistent with every other app on that platform (single SM12-equivalent overview, single admin tool to clear stuck locks)
- You want soft-lock semantics (Scenario 6) without writing the Z table, the cleanup job, and the heartbeat logic yourself

**Key idea:** the platform lock manager hides the persistence table, the heartbeat, and the expiry policy behind a single API. Your app just asks "can I have a lock on `SALES_ORDER` / `0000004711`?" and gets a clear yes/no with an owner and timestamp. You still pair it with `ENQUEUE_EVVBAK` + the optimistic check at save time, because the platform lock is advisory at the UX layer — the database-level guard at save is still your responsibility.

**Heartbeat note:** the `lock_heartbeat( )` call in the fallthrough branch of `main` keeps the lock alive on every roundtrip. If the browser dies, the heartbeat stops and the lock auto-expires after `ttl_seconds`.

---

## 10. Side-by-side comparison

| Scenario | SM12 entry during edit | Pins WP | Survives browser close | Conflict detection | Complexity |
|---|---|---|---|---|---|
| 1 Naive editing | — | — | — | — | trivial |
| 2 Enqueue at save | only at save | no | — | at save (race possible) | low |
| 3 Optimistic | — | no | — | at save (reliable) | low |
| 4 **Enqueue + Optimistic** | only at save | no | — | at save (reliable) | low |
| 5 Stateful session | yes, full duration | **yes** | dies on timeout | at open | medium |
| 6 Soft lock + save guard | only at save | no | row lingers | UX at open + data at save | medium |
| 7 RAP draft | only at activate | no | **draft persists** | framework handles it | medium (BO modelling) |
| 8 **Platform lock manager** | only at save | no | auto-expires via heartbeat | UX at open + data at save | low (if platform ships one) |

---

## 11. Choosing a strategy

Use this flow:

```
Does the app edit data at all?
├── No → render as read-only (every input with enabled = abap_false)
└── Yes
    ├── On modern S/4 / Steampunk and editing a non-trivial business object?
    │   └── Scenario 7 (RAP draft)
    ├── Does your platform ship a lock manager class?
    │   └── Scenario 8 (Platform lock manager)
    ├── Need "locked by X" feedback at open?
    │   ├── Few users, GUI-like feel → Scenario 5
    │   └── Many users → Scenario 6
    └── Default high-scale stateless editing
        └── Scenario 4 (Enqueue + Optimistic)
```

---

## 12. Common gotchas

- **Don't hold an enqueue across roundtrips without `set_session_stateful( )`.** It will be silently released the moment the HTTP response is sent.
- **Always release the enqueue on every code path** — both success and error. A leaked enqueue blocks future users until session timeout.
- **Soft locks need cleanup.** Without a reaper job or `onbeforeunload` release, you will accumulate stale "edited by" rows.
- **Optimistic timestamps require a field that always updates.** If anyone writes to `VBAK` bypassing `AEDAT/AEZET`, your check will miss real conflicts. Prefer a real timestamp column (`UPDATE_TMSTMP`) when available.
- **Statefulness is contagious.** Once `set_session_stateful( )` is on, every roundtrip costs a work process slot until you turn it off again. Always pair it with an explicit `set_session_stateful( abap_false )` on exit.
- **Always include the optimistic check.** It is the only mechanism that catches conflicts originating *outside* your app (SE16, batch, RFC, another transaction).

---

## 13. Summary

| If you need... | Use |
|---|---|
| Personal sandbox or demo where conflicts are impossible | Scenario 1 |
| Quick edits, low contention, no fanciness | Scenario 2 |
| Stateless edits with reliable conflict detection | Scenario 3 |
| Stateless edits, production-grade default | **Scenario 4** |
| GUI-like "lock on open" for internal apps | Scenario 5 |
| UX feedback "locked by Alice" via your own Z table | Scenario 6 |
| Modern S/4 / cloud, non-trivial edits, resumable drafts | **Scenario 7** |
| Platform already ships a lock manager — use the standard | **Scenario 8** |

There is no single "best" lock strategy — only the one that fits your scenario. Start with **Scenario 4** as the safe stateless default; if your platform ships a lock manager, prefer **Scenario 8** for consistency with the rest of the platform; reach for the others when the requirements push you there.
