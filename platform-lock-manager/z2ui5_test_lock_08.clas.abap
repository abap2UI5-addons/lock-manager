* Scenario 8 — Platform lock manager
*
* If your installation ships with a platform lock manager — a reusable
* class that wraps ENQUEUE_* / DEQUEUE_* and a persistence table
* behind a single API — prefer it over rolling your own enqueue +
* soft-lock combo by hand.
*
* A platform lock manager typically gives you:
*   - A single API for both transient (ENQUEUE_*) and persistent
*     (Z-table-backed) locks
*   - Automatic heartbeat / expiry, so a crashed browser does not
*     leave a permanent lock
*   - A uniform "locked by X since Y" lookup that any app on the
*     platform can consume
*   - Lock-by-key for arbitrary business object types
*
* Method names vary across platforms — common shapes are lock( ) /
* unlock( ) / check( ) / get_info( ) on a class like
* cl_platform_lock_manager (often invoked via singleton, e.g.
* cl_platform_lock_manager=>get_instance( ) ). The example below uses
* generic placeholders; swap in whatever your platform actually
* exposes.

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
