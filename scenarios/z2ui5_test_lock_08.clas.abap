* Scenario 8 — Platform lock manager
*
* Uses the reusable function module Z_REQUEST_LOCKING (see folder
* ../platform-lock-manager/) instead of calling ENQUEUE_EVVBAK and
* DEQUEUE_EVVBAK directly. The wrapper:
*   - dispatches to the kernel enqueue/dequeue FM dynamically,
*   - keeps a persistent ZTLOCK_REGISTRY row of "who is editing what",
*   - returns the current owner in msg_description on a foreign lock.
*
* When to use this:
*   - Your platform already ships such a wrapper — use it everywhere
*     for a uniform "locked by X since Y" overview.
*   - You want soft-lock semantics without writing the Z table, the
*     cleanup logic, and the lookup query yourself.
*
* Pair with the optimistic timestamp check at save time. The wrapper
* keeps the UX-level lock honest; the timestamp check protects the
* database from anything that bypasses your app.

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

    CONSTANTS c_object_type TYPE char30 VALUE 'VBAK'.

    METHODS on_init.
    METHODS on_event_save.
    METHODS on_event_release.

    METHODS request_lock
      IMPORTING
        process         TYPE c
      EXPORTING
        success         TYPE abap_bool
        msg_description TYPE string.

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
    ENDIF.

  ENDMETHOD.


  METHOD on_init.

    request_lock(
      EXPORTING
        process         = 'E'
      IMPORTING
        success         = DATA(ok)
        msg_description = DATA(why) ).

    IF ok = abap_true.
      editable    = abap_true.
      lock_status = `Editing`.
    ELSE.
      editable    = abap_false.
      lock_status = why.
    ENDIF.

    data_read( ).
    view_display( ).

  ENDMETHOD.


  METHOD request_lock.

    " Builds the call to Z_REQUEST_LOCKING. Same parameters table for
    " lock ('E') and unlock ('D'); only the FUNCTION and PROCESS differ.

    DATA wa_header     TYPE zs_lock_header.
    DATA it_parameters TYPE STANDARD TABLE OF zs_lock_param.

    wa_header-obj_type = c_object_type.
    wa_header-obj_key  = vbeln.
    wa_header-process  = process.
    wa_header-function = COND #( WHEN process = 'E' THEN 'ENQUEUE_EVVBAK' ELSE 'DEQUEUE_EVVBAK' ).

    APPEND VALUE #( name = 'MODE_VBAK' type = 'CHAR1'      value = 'E' )           TO it_parameters.
    APPEND VALUE #( name = 'MANDT'     type = 'MANDT'      value = sy-mandt )      TO it_parameters.
    APPEND VALUE #( name = 'VBELN'     type = 'VBAK-VBELN' value = vbeln )         TO it_parameters.

    DATA msg_type TYPE c LENGTH 1.

    CALL FUNCTION 'Z_REQUEST_LOCKING'
      EXPORTING
        wa_header        = wa_header
        client_dependent = 'X'
      IMPORTING
        msg_type         = msg_type
        msg_description  = msg_description
      TABLES
        it_parameters    = it_parameters.

    success = COND #( WHEN msg_type = 'S' THEN abap_true ELSE abap_false ).

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

    " Optimistic timestamp guard — catches anything that bypassed the
    " platform lock (SE16, batch job, classic GUI).
    DATA current_aedat TYPE vbak-aedat.
    DATA current_aezet TYPE vbak-aezet.

    SELECT SINGLE aedat, aezet
      FROM vbak
      WHERE vbeln = @vbeln
      INTO ( @current_aedat, @current_aezet ).

    IF current_aedat <> token_aedat OR current_aezet <> token_aezet.
      request_lock( EXPORTING process = 'D'
                    IMPORTING success         = DATA(unused_ok)
                              msg_description = DATA(unused_msg) ).
      client->message_box_display( `Record changed by another user. Please refresh.` ).
      RETURN.
    ENDIF.

    UPDATE vbak
      SET auart = @auart,
          aedat = @sy-datum,
          aezet = @sy-uzeit
      WHERE vbeln = @vbeln.
    COMMIT WORK.

    request_lock( EXPORTING process = 'D'
                  IMPORTING success         = DATA(released_ok)
                            msg_description = DATA(released_msg) ).

    client->message_toast_display( `Saved.` ).
    client->nav_app_leave( ).

  ENDMETHOD.


  METHOD on_event_release.

    request_lock( EXPORTING process = 'D'
                  IMPORTING success         = DATA(released_ok)
                            msg_description = DATA(released_msg) ).
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
