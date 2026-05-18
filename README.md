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
