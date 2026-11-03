---
layout: home

hero:
  name: "Lock Manager"
  text: "Hold a real SAP lock across the roundtrips of a stateless app."
  image:
    src: /favicon.png
    alt: abap2UI5
  actions:
    - theme: brand
      text: Get started
      link: /guide
    - theme: alt
      text: GitHub
      link: https://github.com/abap2UI5-addons/lock-manager
    - theme: alt
      text: All addons
      link: https://abap2ui5-addons.github.io/

features:
  - title: "Single API z2ui5_cl_lock_manager=&gt;request for any generated ENQUEUE_* lock module"
  - title: "Three lock modes (exclusive, shared, optimistic) plus promotion to exclusive"
  - title: "Persistent registry of every request and lock in tables z2ui5_t_05 and z2ui5_t_06"
  - title: "Locked-by answer names the real web user, not the technical background user"
  - title: "Background handler that owns the kernel locks and runs only while needed"
  - title: "Auto-release after a configurable lifetime and recovery after a handler restart"
  - title: "Sample app z2ui5_cl_lock_sample and SM12-style admin app z2ui5_cl_lock_app_sm12"
---

## What it does

Every stateless ABAP web call loses its SAP locks when the roundtrip ends. This addon decouples lock ownership from the web session: a background handler takes and holds the kernel locks on behalf of the web users, and a persistent registry records who actually holds what. On top of the classic exclusive lock it supports shared and optimistic locks, including the promotion of an optimistic lock to an exclusive one at save time. It is for abap2UI5 apps that change business objects where durable locks or RAP draft handling are not an option.

## Requirements

- Standard ABAP 7.50 or higher; NetWeaver 7.02 - 7.40 with the downported branch 702
- abap2UI5
- ABAP Cloud: no (Standard ABAP only)
- A background user that may set the requested locks and one background work process while any lock is held

## Installation

With [abapGit](https://abapgit.org), from [the repository](https://github.com/abap2UI5-addons/lock-manager):

- Install with abapGit: abap2UI5, then this repository (branch main) into a Z-package
- Create the background event LOCK_HANDLER in SM62 (and LOCK_HANDLER_&lt;client&gt; per client for client-dependent jobs)
- Create a variant for report Z2UI5_RE_LOCK_BACKGROUND in SE38 with p_wait, p_user and p_time
- Schedule a periodic job in SM36 for the report, started after event LOCK_HANDLER, running as the background user
- Give the background user the authorizations to set the requested locks
- Try ?app_start=z2ui5_cl_lock_sample and ?app_start=z2ui5_cl_lock_app_sm12

The [Guide](/guide) has every step.

## A first app

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

## Links

- [The repository](https://github.com/abap2UI5-addons/lock-manager) - issues and pull requests welcome
