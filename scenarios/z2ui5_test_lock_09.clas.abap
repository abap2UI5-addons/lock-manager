* Scenario 9 — Consume a standard SAP draft-enabled BO via EML
*
* You are on S/4HANA or BTP ABAP Environment. The sales order is
* already exposed by SAP as a draft-enabled BO (I_SalesOrderTP). You
* do NOT build your own BO and you do NOT create a draft table — SAP
* ships both.
*
* The flow the user sees:
*   on_init               -> Edit       (create or resume the draft)
*   "Save Draft" pressed  -> UPDATE     (writes the draft only)
*   "Save Draft" again    -> UPDATE     (still draft, VBAK untouched)
*   ...
*   "Activate" pressed    -> Activate   (now VBAK is written)
*   "Discard" pressed     -> Discard    (drops the draft, releases lock)
*
* The session stays stateless. The draft survives in SAP's own
* draft-shadow table between roundtrips. The lock is held by the BO
* framework as long as the draft exists; closing the browser without
* discarding leaves the draft so the same user can resume it later.
*
* Field names below (SalesOrder, SalesOrderType) match the released
* CDS view I_SalesOrderTP on current S/4HANA. On older releases the
* BO name or fields may differ — check the released-objects list in
* your system.

CLASS z2ui5_test_lock_09 DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    DATA sales_order      TYPE c LENGTH 10 VALUE `0000004711`.
    DATA sales_order_type TYPE c LENGTH 4.
    DATA draft_open       TYPE abap_bool.
    DATA status_text      TYPE string.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_init.
    METHODS on_event_save_draft.
    METHODS on_event_activate.
    METHODS on_event_discard.
    METHODS draft_acquire.
    METHODS draft_read.
    METHODS view_display.

  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_test_lock_09 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.

    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( `SAVE_DRAFT` ).
      on_event_save_draft( ).
    ELSEIF client->check_on_event( `ACTIVATE` ).
      on_event_activate( ).
    ELSEIF client->check_on_event( `DISCARD` ).
      on_event_discard( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_init.

    draft_acquire( ).
    draft_read( ).
    view_display( ).

  ENDMETHOD.


  METHOD draft_acquire.

    " Edit is idempotent: if the user already has a draft for this
    " sales order, SAP returns it instead of failing.

    MODIFY ENTITIES OF i_salesordertp
      ENTITY SalesOrder
      EXECUTE Edit
        FROM VALUE #( ( %key-SalesOrder        = sales_order
                        %param-PreserveChanges = abap_true ) )
      FAILED   DATA(failed)
      REPORTED DATA(reported).

    IF failed IS NOT INITIAL.
      draft_open  = abap_false.
      status_text = `Could not open draft — locked by another user, or no authorization.`.
      RETURN.
    ENDIF.

    COMMIT ENTITIES.

    draft_open  = abap_true.
    status_text = `Draft open — changes are saved as a draft until you press Activate.`.

  ENDMETHOD.


  METHOD draft_read.

    IF draft_open = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF i_salesordertp
      ENTITY SalesOrder
      FIELDS ( SalesOrderType )
      WITH VALUE #( ( %key-SalesOrder     = sales_order
                      %key-IsActiveEntity = abap_false ) )
      RESULT DATA(drafts).

    IF drafts IS NOT INITIAL.
      sales_order_type = drafts[ 1 ]-SalesOrderType.
    ENDIF.

  ENDMETHOD.


  METHOD on_event_save_draft.

    " Persists progress to the draft only. VBAK is NOT touched.
    " The user can press Save Draft many times across many roundtrips.

    MODIFY ENTITIES OF i_salesordertp
      ENTITY SalesOrder
      UPDATE FIELDS ( SalesOrderType )
      WITH VALUE #( ( %tky-SalesOrder         = sales_order
                      %tky-IsActiveEntity     = abap_false
                      SalesOrderType          = sales_order_type
                      %control-SalesOrderType = if_abap_behv=>mk-on ) )
      FAILED   DATA(failed)
      REPORTED DATA(reported).

    IF failed IS NOT INITIAL.
      client->message_box_display( `Draft update failed.` ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES.
    client->message_toast_display( `Draft saved.` ).

  ENDMETHOD.


  METHOD on_event_activate.

    " Writes the draft through to the active sales order (VBAK) and
    " deletes the draft. Lock is released by the framework.

    MODIFY ENTITIES OF i_salesordertp
      ENTITY SalesOrder
      EXECUTE Activate
        FROM VALUE #( ( %key-SalesOrder     = sales_order
                        %key-IsActiveEntity = abap_false ) )
      FAILED   DATA(failed)
      REPORTED DATA(reported).

    IF failed IS NOT INITIAL.
      client->message_box_display( `Activation failed — see application log.` ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES.
    client->message_toast_display( `Sales order activated.` ).
    client->nav_app_leave( ).

  ENDMETHOD.


  METHOD on_event_discard.

    MODIFY ENTITIES OF i_salesordertp
      ENTITY SalesOrder
      EXECUTE Discard
        FROM VALUE #( ( %key-SalesOrder     = sales_order
                        %key-IsActiveEntity = abap_false ) )
      FAILED   DATA(failed)
      REPORTED DATA(reported).

    COMMIT ENTITIES.
    client->nav_app_leave( ).

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_xml_view=>factory( ).
    view->shell(
        )->page(
            title          = `Edit Sales Order — Standard BO Draft via EML`
            shownavbutton  = client->check_app_prev_stack( )
            navbuttonpress = client->_event( `DISCARD` )
            )->simple_form(
                title    = `Header (draft)`
                editable = draft_open
                )->content( `form`
                )->label( `Sales Order`
                )->input(
                    value   = sales_order
                    enabled = abap_false
                )->label( `Type`
                )->input( client->_bind_edit( sales_order_type )
                )->label( `Status`
                )->input(
                    value   = status_text
                    enabled = abap_false
                )->button(
                    text    = `Save Draft`
                    press   = client->_event( `SAVE_DRAFT` )
                    enabled = draft_open
                )->button(
                    text    = `Activate`
                    type    = `Emphasized`
                    press   = client->_event( `ACTIVATE` )
                    enabled = draft_open
                )->button(
                    text  = `Discard`
                    press = client->_event( `DISCARD` ) ).
    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
