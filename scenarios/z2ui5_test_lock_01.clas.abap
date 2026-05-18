* Scenario 1 — Naive editing (no locking)
*
* The simplest possible starting point. The user can change a sales
* order and save. There is no lock and no conflict check. Last save
* wins, silently.
*
* When to use this:
*   - Personal sandboxes, throwaway demos, internal tools where only
*     one user ever touches a record.

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
