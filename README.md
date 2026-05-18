# Locking Sales Orders in abap2UI5 — A Beginner's Guide

This guide explains **how to lock business objects in abap2UI5 apps**, step by step, starting from the simplest case and adding one layer at a time.

Every section ships with a **complete, copy-paste-ready demo class**. To try a snippet:

1. Create a new ABAP class with the given name (e.g. `z2ui5_test_lock_01`).
2. Paste the code as the class source.
3. Activate it.
4. Launch via the abap2UI5 launchpad URL with `?app=<class_name>`.

We use the **sales order header table `VBAK`** as the example throughout, because it ships with every SAP system and has a real, standard SAP enqueue object (`EVVBAK`).

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

The simplest possible starting point. The user can change a sales order and save. **There is no lock and no conflict check.** Last save wins, silently.

This is rarely what you want in production, but it is the right place to *start* — every later scenario layers a single concept on top of this one, so you can see exactly what each layer buys you.

**When to use this:**
- Personal sandboxes, throwaway demos, internal tools where only one user ever touches a record

```abap
CLASS z2ui5_test_lock_01 DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    DATA vbeln    TYPE vbak-vbeln VALUE `0000004711`.
    DATA auart    TYPE vbak-auart.
    DATA ernam    TYPE vbak-ernam.
    DATA erdat    TYPE vbak-erdat.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_init.
    METHODS on_event_save.
    METHODS view_display.
    METHODS data_read.
  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_test_lock_01 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.
    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( `SAVE` ).
      on_event_save( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_init.

    data_read( ).
    view_display( ).

  ENDMETHOD.


  METHOD data_read.

    SELECT SINGLE auart, ernam, erdat
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @auart, @ernam, @erdat ).

  ENDMETHOD.


  METHOD on_event_save.

    UPDATE vbak SET auart = @auart WHERE vbeln = @vbeln.
    COMMIT WORK.

    client->message_toast_display( `Saved.` ).

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_xml_view=>factory( ).
    view->shell(
        )->page(
            title          = `Edit Sales Order — No Locking`
            shownavbutton  = client->check_app_prev_stack( )
            navbuttonpress = client->_event_nav_app_leave( )
            )->simple_form(
                title    = `Header`
                editable = abap_true
                )->content( `form`
                )->label( `Sales Order`
                )->input(
                    value   = vbeln
                    enabled = abap_false
                )->label( `Type`
                )->input( client->_bind_edit( auart )
                )->label( `Created by`
                )->input(
                    value   = ernam
                    enabled = abap_false
                )->label( `Created on`
                )->input(
                    value   = CONV string( erdat )
                    enabled = abap_false
                )->button(
                    text  = `Save`
                    press = client->_event( `SAVE` ) ).
    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
```

**Key idea:** `client->_bind_edit( auart )` creates a two-way binding — what the user types lands back in `auart` before the SAVE event fires. There is no lock and no check. If two users edit the same order, the second save silently wipes the first one's changes. Every later scenario fixes a specific piece of this problem.

---

## 3. Scenario 2 — Edit + Enqueue at save

Now the user can change the sales order type. We do **not** hold a lock while they think. At the moment they press *Save*, we lock, write, commit, and release in one short roundtrip.

**When to use this:**
- Quick edits with low chance of two users hitting the same record
- Default starting point for most stateless editing apps

```abap
CLASS z2ui5_test_lock_02 DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    DATA vbeln TYPE vbak-vbeln VALUE `0000004711`.
    DATA auart TYPE vbak-auart.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_init.
    METHODS on_event_save.
    METHODS view_display.
    METHODS data_read.
  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_test_lock_02 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.
    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( `SAVE` ).
      on_event_save( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_init.

    data_read( ).
    view_display( ).

  ENDMETHOD.


  METHOD data_read.

    SELECT SINGLE auart
      FROM vbak
      WHERE vbeln = @vbeln
      INTO @auart.

  ENDMETHOD.


  METHOD on_event_save.

    CALL FUNCTION 'ENQUEUE_EVVBAK'
      EXPORTING
        mode_vbak      = `E`
        mandt          = sy-mandt
        vbeln          = vbeln
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.

    IF sy-subrc <> 0.
      client->message_box_display( |Cannot lock { vbeln } — already locked by another user| ).
      RETURN.
    ENDIF.

    UPDATE vbak SET auart = @auart WHERE vbeln = @vbeln.
    COMMIT WORK.

    CALL FUNCTION 'DEQUEUE_EVVBAK'
      EXPORTING
        mode_vbak = `E`
        mandt     = sy-mandt
        vbeln     = vbeln.

    client->message_toast_display( `Saved.` ).

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_xml_view=>factory( ).
    view->shell(
        )->page(
            title          = `Edit Sales Order — Enqueue at Save`
            shownavbutton  = client->check_app_prev_stack( )
            navbuttonpress = client->_event_nav_app_leave( )
            )->simple_form(
                title    = `Header`
                editable = abap_true
                )->content( `form`
                )->label( `Sales Order`
                )->input(
                    value   = vbeln
                    enabled = abap_false
                )->label( `Type`
                )->input( client->_bind_edit( auart )
                )->button(
                    text  = `Save`
                    press = client->_event( `SAVE` ) ).
    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
```

**Key idea:** the lock only exists for milliseconds, during the save event. Two users editing the same order in parallel will both succeed if neither saves at the literal same instant — the last save wins. That is a problem we fix in the next scenario.

---

## 4. Scenario 3 — Optimistic locking (timestamp check)

Now we add a *conflict check*. On read we remember the record's last-changed timestamp. On save, we re-read it and **reject** if it changed in the meantime. This is the same idea as HTTP ETag or OData's `@odata.etag`.

**When to use this:**
- Any time silent overwrites would be a problem
- Combine with Scenario 2 — it costs almost nothing and catches real bugs

```abap
CLASS z2ui5_test_lock_03 DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    DATA vbeln TYPE vbak-vbeln VALUE `0000004711`.
    DATA auart TYPE vbak-auart.

    DATA token_aedat TYPE vbak-aedat.
    DATA token_aezet TYPE vbak-aezet.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_init.
    METHODS on_event_save.
    METHODS view_display.
    METHODS data_read.
  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_test_lock_03 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.
    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( `SAVE` ).
      on_event_save( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_init.

    data_read( ).
    view_display( ).

  ENDMETHOD.


  METHOD data_read.

    SELECT SINGLE auart, aedat, aezet
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @auart, @token_aedat, @token_aezet ).

  ENDMETHOD.


  METHOD on_event_save.

    DATA current_aedat TYPE vbak-aedat.
    DATA current_aezet TYPE vbak-aezet.

    SELECT SINGLE aedat, aezet
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @current_aedat, @current_aezet ).

    IF current_aedat <> token_aedat OR current_aezet <> token_aezet.
      client->message_box_display(
        |Sales order { vbeln } has been changed by another user since you opened it. Please refresh.| ).
      RETURN.
    ENDIF.

    UPDATE vbak
      SET auart = @auart,
          aedat = @sy-datum,
          aezet = @sy-uzeit
      WHERE vbeln = @vbeln.
    COMMIT WORK.

    data_read( ).
    client->view_model_update( ).
    client->message_toast_display( `Saved.` ).

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_xml_view=>factory( ).
    view->shell(
        )->page(
            title          = `Edit Sales Order — Optimistic Locking`
            shownavbutton  = client->check_app_prev_stack( )
            navbuttonpress = client->_event_nav_app_leave( )
            )->simple_form(
                title    = `Header`
                editable = abap_true
                )->content( `form`
                )->label( `Sales Order`
                )->input(
                    value   = vbeln
                    enabled = abap_false
                )->label( `Type`
                )->input( client->_bind_edit( auart )
                )->button(
                    text  = `Save`
                    press = client->_event( `SAVE` ) ).
    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
```

**Key idea:** `token_aedat`/`token_aezet` travel with the app session. On save, we re-read the live values from the database and reject if they have shifted. No lock is held during the edit phase, so this scales to many concurrent users.

---

## 5. Scenario 4 — Combined (the recommended default)

Enqueue at save **and** the optimistic check. This is the safest stateless pattern and the one most production apps should default to.

**Why both:**
- The enqueue serializes concurrent writers so two saves cannot interleave.
- The timestamp check catches anyone who slipped in via another path (SE16, batch job, classic SAP GUI) between your read and your write.

```abap
CLASS z2ui5_test_lock_04 DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    DATA vbeln TYPE vbak-vbeln VALUE `0000004711`.
    DATA auart TYPE vbak-auart.

    DATA token_aedat TYPE vbak-aedat.
    DATA token_aezet TYPE vbak-aezet.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_init.
    METHODS on_event_save.
    METHODS view_display.
    METHODS data_read.
  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_test_lock_04 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.
    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( `SAVE` ).
      on_event_save( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_init.

    data_read( ).
    view_display( ).

  ENDMETHOD.


  METHOD data_read.

    SELECT SINGLE auart, aedat, aezet
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @auart, @token_aedat, @token_aezet ).

  ENDMETHOD.


  METHOD on_event_save.

    CALL FUNCTION 'ENQUEUE_EVVBAK'
      EXPORTING
        mode_vbak      = `E`
        mandt          = sy-mandt
        vbeln          = vbeln
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.

    IF sy-subrc <> 0.
      client->message_box_display( |Sales order { vbeln } is currently being saved by another user. Try again.| ).
      RETURN.
    ENDIF.

    DATA current_aedat TYPE vbak-aedat.
    DATA current_aezet TYPE vbak-aezet.

    SELECT SINGLE aedat, aezet
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @current_aedat, @current_aezet ).

    IF current_aedat <> token_aedat OR current_aezet <> token_aezet.

      CALL FUNCTION 'DEQUEUE_EVVBAK'
        EXPORTING
          mode_vbak = `E`
          mandt     = sy-mandt
          vbeln     = vbeln.

      client->message_box_display(
        |Sales order { vbeln } has been changed by another user since you opened it. Please refresh.| ).
      RETURN.

    ENDIF.

    UPDATE vbak
      SET auart = @auart,
          aedat = @sy-datum,
          aezet = @sy-uzeit
      WHERE vbeln = @vbeln.
    COMMIT WORK.

    CALL FUNCTION 'DEQUEUE_EVVBAK'
      EXPORTING
        mode_vbak = `E`
        mandt     = sy-mandt
        vbeln     = vbeln.

    data_read( ).
    client->view_model_update( ).
    client->message_toast_display( `Saved.` ).

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_xml_view=>factory( ).
    view->shell(
        )->page(
            title          = `Edit Sales Order — Enqueue + Optimistic`
            shownavbutton  = client->check_app_prev_stack( )
            navbuttonpress = client->_event_nav_app_leave( )
            )->simple_form(
                title    = `Header`
                editable = abap_true
                )->content( `form`
                )->label( `Sales Order`
                )->input(
                    value   = vbeln
                    enabled = abap_false
                )->label( `Type`
                )->input( client->_bind_edit( auart )
                )->button(
                    text  = `Save`
                    press = client->_event( `SAVE` ) ).
    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
```

**Key idea:** belt-and-suspenders. The enqueue prevents two parallel saves of *this* app from colliding. The timestamp check catches everything else.

---

## 6. Scenario 5 — Stateful session with a persistent enqueue

Sometimes you want classic SAP GUI behaviour: the moment the user opens the screen, the lock is held until they save or leave. With `client->set_session_stateful( )`, abap2UI5 keeps the session alive between roundtrips so a real `ENQUEUE_EVVBAK` survives.

**When to use this:**
- Internal back-office apps with few concurrent users
- You want users to *immediately* see "locked by X" when opening

**Cost:** each active user pins a work process. Do **not** use this for high-traffic apps.

```abap
CLASS z2ui5_test_lock_05 DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    DATA vbeln TYPE vbak-vbeln VALUE `0000004711`.
    DATA auart TYPE vbak-auart.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_init.
    METHODS on_event_save.
    METHODS on_event_cancel.
    METHODS lock_acquire.
    METHODS lock_release.
    METHODS view_display.
    METHODS data_read.
  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_test_lock_05 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.
    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( `SAVE` ).
      on_event_save( ).
    ELSEIF client->check_on_event( `CANCEL` ).
      on_event_cancel( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_init.

    lock_acquire( ).

  ENDMETHOD.


  METHOD lock_acquire.

    CALL FUNCTION 'ENQUEUE_EVVBAK'
      EXPORTING
        mode_vbak      = `E`
        mandt          = sy-mandt
        vbeln          = vbeln
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.

    IF sy-subrc <> 0.

      client->set_session_stateful( abap_false ).
      client->message_box_display( |Sales order { vbeln } is locked by another user.| ).
      RETURN.

    ENDIF.

    client->set_session_stateful( ).
    data_read( ).
    view_display( ).

  ENDMETHOD.


  METHOD lock_release.

    CALL FUNCTION 'DEQUEUE_EVVBAK'
      EXPORTING
        mode_vbak = `E`
        mandt     = sy-mandt
        vbeln     = vbeln.

    client->set_session_stateful( abap_false ).

  ENDMETHOD.


  METHOD data_read.

    SELECT SINGLE auart
      FROM vbak
      WHERE vbeln = @vbeln
      INTO @auart.

  ENDMETHOD.


  METHOD on_event_save.

    UPDATE vbak
      SET auart = @auart,
          aedat = @sy-datum,
          aezet = @sy-uzeit
      WHERE vbeln = @vbeln.
    COMMIT WORK.

    lock_release( ).
    client->message_toast_display( `Saved.` ).
    client->nav_app_leave( ).

  ENDMETHOD.


  METHOD on_event_cancel.

    lock_release( ).
    client->nav_app_leave( ).

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_xml_view=>factory( ).
    view->shell(
        )->page(
            title          = `Edit Sales Order — Stateful Lock`
            shownavbutton  = client->check_app_prev_stack( )
            navbuttonpress = client->_event( `CANCEL` )
            )->simple_form(
                title    = `Header`
                editable = abap_true
                )->content( `form`
                )->label( `Sales Order`
                )->input(
                    value   = vbeln
                    enabled = abap_false
                )->label( `Type`
                )->input( client->_bind_edit( auart )
                )->button(
                    text  = `Save`
                    press = client->_event( `SAVE` )
                )->button(
                    text  = `Cancel`
                    press = client->_event( `CANCEL` ) ).
    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
```

**Key idea:** while the app is open, an SM12 entry for `EVVBAK` / `0000004711` is visible. The user can navigate, type, wait — the lock stays. If they close the browser without pressing *Cancel*, the lock will eventually expire when the session times out.

**Compare with `z2ui5_cl_demo_app_350`** in this repo for a similar pattern using `ENQUEUE_E_TABLE`.

---

## 7. Scenario 6 — Soft lock (advisory only)

A soft lock is a row in a **custom Z table** marking *"user X is editing sales order Y."* It is **not** enforced by the SAP kernel — only your app code respects it. Use it for **UX feedback** ("locked by Alice since 09:32"), always layered on top of a real save-time guard.

### 7.1 Create the Z table

Create a small table in SE11 called `ZS_SO_LOCK`:

| Field      | Type        | Description           |
|------------|-------------|-----------------------|
| MANDT      | MANDT       | Client (key)          |
| VBELN      | VBELN_VA    | Sales order (key)     |
| USERNAME   | SYUNAME     | Editing user          |
| LOCKED_AT  | TIMESTAMPL  | When the lock started |

Maintain delivery class `A`, two-level enhancement category irrelevant for our purpose. Activate.

### 7.2 The app

```abap
CLASS z2ui5_test_lock_06 DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    DATA vbeln       TYPE vbak-vbeln VALUE `0000004711`.
    DATA auart       TYPE vbak-auart.
    DATA locked_by   TYPE string.
    DATA token_aedat TYPE vbak-aedat.
    DATA token_aezet TYPE vbak-aezet.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_init.
    METHODS on_event_save.
    METHODS on_event_release.
    METHODS soft_lock_acquire
      RETURNING
        VALUE(ok) TYPE abap_bool.
    METHODS soft_lock_release.
    METHODS view_display.
    METHODS data_read.
  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_test_lock_06 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.
    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( `SAVE` ).
      on_event_save( ).
    ELSEIF client->check_on_event( `RELEASE` ).
      on_event_release( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_init.

    IF soft_lock_acquire( ) = abap_false.

      data_read( ).
      view_display( ).
      RETURN.

    ENDIF.

    data_read( ).
    view_display( ).

  ENDMETHOD.


  METHOD soft_lock_acquire.

    DATA s_existing TYPE zs_so_lock.

    SELECT SINGLE *
      FROM zs_so_lock
      WHERE vbeln = @vbeln
      INTO @s_existing.

    IF sy-subrc = 0 AND s_existing-username <> sy-uname.

      locked_by = |Locked by { s_existing-username } since { s_existing-locked_at TIMESTAMP = USER }|.
      ok        = abap_false.
      RETURN.

    ENDIF.

    DATA s_new TYPE zs_so_lock.
    s_new-vbeln    = vbeln.
    s_new-username = sy-uname.
    GET TIME STAMP FIELD s_new-locked_at.

    MODIFY zs_so_lock FROM @s_new.
    COMMIT WORK.

    locked_by = ``.
    ok       = abap_true.

  ENDMETHOD.


  METHOD soft_lock_release.

    DELETE FROM zs_so_lock
      WHERE vbeln    = @vbeln
        AND username = @sy-uname.
    COMMIT WORK.

  ENDMETHOD.


  METHOD data_read.

    SELECT SINGLE auart, aedat, aezet
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @auart, @token_aedat, @token_aezet ).

  ENDMETHOD.


  METHOD on_event_save.

    CALL FUNCTION 'ENQUEUE_EVVBAK'
      EXPORTING
        mode_vbak      = `E`
        mandt          = sy-mandt
        vbeln          = vbeln
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.

    IF sy-subrc <> 0.
      client->message_box_display( `Could not acquire enqueue` ).
      RETURN.
    ENDIF.

    DATA current_aedat TYPE vbak-aedat.
    DATA current_aezet TYPE vbak-aezet.

    SELECT SINGLE aedat, aezet
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @current_aedat, @current_aezet ).

    IF current_aedat <> token_aedat OR current_aezet <> token_aezet.

      CALL FUNCTION 'DEQUEUE_EVVBAK'
        EXPORTING
          mode_vbak = `E`
          mandt     = sy-mandt
          vbeln     = vbeln.

      client->message_box_display( `Record changed by another user. Please refresh.` ).
      RETURN.

    ENDIF.

    UPDATE vbak
      SET auart = @auart,
          aedat = @sy-datum,
          aezet = @sy-uzeit
      WHERE vbeln = @vbeln.
    COMMIT WORK.

    CALL FUNCTION 'DEQUEUE_EVVBAK'
      EXPORTING
        mode_vbak = `E`
        mandt     = sy-mandt
        vbeln     = vbeln.

    soft_lock_release( ).
    client->message_toast_display( `Saved.` ).
    client->nav_app_leave( ).

  ENDMETHOD.


  METHOD on_event_release.

    soft_lock_release( ).
    client->nav_app_leave( ).

  ENDMETHOD.


  METHOD view_display.

    DATA(editable) = COND abap_bool( WHEN locked_by IS INITIAL THEN abap_true ELSE abap_false ).

    DATA(view) = z2ui5_cl_xml_view=>factory( ).
    view->shell(
        )->page(
            title          = `Edit Sales Order — Soft Lock + Save Guard`
            shownavbutton  = client->check_app_prev_stack( )
            navbuttonpress = client->_event_nav_app_leave( )
            )->simple_form(
                title    = `Header`
                editable = editable
                )->content( `form`
                )->label( `Sales Order`
                )->input(
                    value   = vbeln
                    enabled = abap_false
                )->label( `Type`
                )->input( client->_bind_edit( auart )
                )->label( `Status`
                )->input(
                    value   = locked_by
                    enabled = abap_false
                )->button(
                    text    = `Save`
                    press   = client->_event( `SAVE` )
                    enabled = editable
                )->button(
                    text  = `Release & Exit`
                    press = client->_event( `RELEASE` ) ).
    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
```

**Key idea:** the soft lock decides *who can edit in the UI*. The enqueue + timestamp check decides *whether the save is allowed*. They serve different jobs.

**Gotcha:** if a user closes the browser without pressing *Release & Exit*, the row stays in `ZS_SO_LOCK` forever. In production you would add a small background job that deletes rows older than, say, 30 minutes.

---

## 8. Scenario 7 — RAP draft (the modern alternative)

If you are on **S/4HANA** or **BTP ABAP Environment (Steampunk)**, the canonical pattern is no longer "hold a lock during edit." Instead you create a **draft instance** of the sales order in a framework-managed shadow table. The active record is untouched until the user explicitly activates.

This sidesteps the whole lock-during-think-time problem.

### 8.1 What it looks like in RAP

```abap
managed implementation in class zbp_i_so unique;
strict ( 2 );

define behavior for ZI_SalesOrder alias SalesOrder
persistent table zsalesorder
draft table zsalesorder_d
lock master
authorization master ( instance )
etag master last_changed_at
with draft
{
  field ( readonly ) Vbeln;
  field ( mandatory ) Auart;

  create;
  update;
  delete;

  draft action Edit;
  draft action Activate;
  draft determine action Prepare;
}
```

### 8.2 Calling a draft-enabled BO from abap2UI5

abap2UI5 can call the RAP entity manipulation language (`EML`) directly from an event handler:

```abap
METHOD on_event_save.

  MODIFY ENTITIES OF zi_salesorder
    ENTITY SalesOrder
    UPDATE FIELDS ( Auart )
      WITH VALUE #( ( Vbeln = vbeln
                      Auart = auart
                      %control-Auart = if_abap_behv=>mk-on ) )
    FAILED   DATA(failed)
    REPORTED DATA(reported).

  IF failed IS NOT INITIAL.
    client->message_box_display( `Update failed` ).
    RETURN.
  ENDIF.

  COMMIT ENTITIES.

  client->message_toast_display( `Saved.` ).

ENDMETHOD.
```

**Key idea:** the framework handles ETag checks, draft persistence, and the activation enqueue **for you**. abap2UI5 just calls the BO methods. For non-trivial editing apps on a modern stack, this is usually the cleanest choice.

For a full draft workflow (Edit → multiple round-trips on the draft → Activate), see the official [SAP RAP documentation](https://help.sap.com/docs/abap-cloud/abap-rap/draft).

---

## 9. Scenario 8 — Platform lock manager

If your installation ships with a **platform lock manager** — a reusable class that wraps `ENQUEUE_*` / `DEQUEUE_*` and a persistence table behind a single API — you should usually prefer it over rolling your own enqueue + soft-lock combo by hand. The platform manager typically gives you:

- A **single API** for both transient (`ENQUEUE_*`) and persistent (Z-table-backed) locks
- Automatic **heartbeat / expiry**, so a crashed browser does not leave a permanent lock
- A **uniform "locked by X since Y" lookup** that any app on the platform can consume
- Built-in **lock-by-key** for arbitrary business object types, not just standard SAP enqueue objects

Method names vary across platforms — common shapes are `lock( )` / `unlock( )` / `check( )` / `get_info( )` on a class like `cl_platform_lock_manager` (often invoked via singleton, e.g. `cl_platform_lock_manager=>get_instance( )`). The example below uses generic placeholders; swap in whatever your platform actually exposes.

**When to use this:**
- Your platform already provides one — using it makes your app consistent with every other app on that platform (single SM12-equivalent overview, single admin tool to clear stuck locks)
- You want soft-lock semantics (Scenario 6) without writing the Z table, the cleanup job, and the heartbeat logic yourself

```abap
CLASS z2ui5_test_lock_08 DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    DATA vbeln       TYPE vbak-vbeln VALUE `0000004711`.
    DATA auart       TYPE vbak-auart.
    DATA lock_status TYPE string.
    DATA editable    TYPE abap_bool.

    DATA token_aedat TYPE vbak-aedat.
    DATA token_aezet TYPE vbak-aezet.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    CONSTANTS c_object_type TYPE string VALUE `SALES_ORDER`.

    METHODS on_init.
    METHODS on_event_save.
    METHODS on_event_release.
    METHODS lock_acquire.
    METHODS lock_release.
    METHODS lock_heartbeat.
    METHODS view_display.
    METHODS data_read.
  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_test_lock_08 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.

    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( `SAVE` ).
      on_event_save( ).
    ELSEIF client->check_on_event( `RELEASE` ).
      on_event_release( ).
    ELSE.
      lock_heartbeat( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_init.

    lock_acquire( ).
    data_read( ).
    view_display( ).

  ENDMETHOD.


  METHOD lock_acquire.

    DATA(lock_mgr) = cl_platform_lock_manager=>get_instance( ).

    DATA lock_owner TYPE string.
    DATA locked_at  TYPE timestampl.

    lock_mgr->check(
      EXPORTING
        object_type = c_object_type
        object_key  = CONV string( vbeln )
      IMPORTING
        owner       = lock_owner
        locked_at   = locked_at ).

    IF lock_owner IS NOT INITIAL AND lock_owner <> sy-uname.

      editable    = abap_false.
      lock_status = |Locked by { lock_owner } since { locked_at TIMESTAMP = USER }|.
      RETURN.

    ENDIF.

    TRY.

        lock_mgr->lock(
          object_type = c_object_type
          object_key  = CONV string( vbeln )
          ttl_seconds = 1800 ).

        editable    = abap_true.
        lock_status = `Editing`.

      CATCH cx_platform_lock_failed.

        editable    = abap_false.
        lock_status = `Could not acquire lock`.

    ENDTRY.

  ENDMETHOD.


  METHOD lock_heartbeat.

    IF editable = abap_false.
      RETURN.
    ENDIF.

    cl_platform_lock_manager=>get_instance( )->refresh(
      object_type = c_object_type
      object_key  = CONV string( vbeln ) ).

  ENDMETHOD.


  METHOD lock_release.

    cl_platform_lock_manager=>get_instance( )->unlock(
      object_type = c_object_type
      object_key  = CONV string( vbeln ) ).

  ENDMETHOD.


  METHOD data_read.

    SELECT SINGLE auart, aedat, aezet
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @auart, @token_aedat, @token_aezet ).

  ENDMETHOD.


  METHOD on_event_save.

    IF editable = abap_false.
      client->message_box_display( lock_status ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'ENQUEUE_EVVBAK'
      EXPORTING
        mode_vbak      = `E`
        mandt          = sy-mandt
        vbeln          = vbeln
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.

    IF sy-subrc <> 0.
      client->message_box_display( `Could not acquire enqueue` ).
      RETURN.
    ENDIF.

    DATA current_aedat TYPE vbak-aedat.
    DATA current_aezet TYPE vbak-aezet.

    SELECT SINGLE aedat, aezet
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @current_aedat, @current_aezet ).

    IF current_aedat <> token_aedat OR current_aezet <> token_aezet.

      CALL FUNCTION 'DEQUEUE_EVVBAK'
        EXPORTING
          mode_vbak = `E`
          mandt     = sy-mandt
          vbeln     = vbeln.

      client->message_box_display( `Record changed by another user. Please refresh.` ).
      RETURN.

    ENDIF.

    UPDATE vbak
      SET auart = @auart,
          aedat = @sy-datum,
          aezet = @sy-uzeit
      WHERE vbeln = @vbeln.
    COMMIT WORK.

    CALL FUNCTION 'DEQUEUE_EVVBAK'
      EXPORTING
        mode_vbak = `E`
        mandt     = sy-mandt
        vbeln     = vbeln.

    lock_release( ).
    client->message_toast_display( `Saved.` ).
    client->nav_app_leave( ).

  ENDMETHOD.


  METHOD on_event_release.

    lock_release( ).
    client->nav_app_leave( ).

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_xml_view=>factory( ).
    view->shell(
        )->page(
            title          = `Edit Sales Order — Platform Lock Manager`
            shownavbutton  = client->check_app_prev_stack( )
            navbuttonpress = client->_event_nav_app_leave( )
            )->simple_form(
                title    = `Header`
                editable = editable
                )->content( `form`
                )->label( `Sales Order`
                )->input(
                    value   = vbeln
                    enabled = abap_false
                )->label( `Type`
                )->input( client->_bind_edit( auart )
                )->label( `Lock status`
                )->input(
                    value   = lock_status
                    enabled = abap_false
                )->button(
                    text    = `Save`
                    press   = client->_event( `SAVE` )
                    enabled = editable
                )->button(
                    text  = `Release & Exit`
                    press = client->_event( `RELEASE` ) ).
    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
```

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
