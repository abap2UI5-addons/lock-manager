CLASS z2ui5_cl_app_sm12 DEFINITION
  PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    " Filter inputs (bound to UI inputs)
    DATA mv_lock_object TYPE seqg3-gname.
    DATA mv_user        TYPE seqg3-guname.
    DATA mv_client      TYPE sy-mandt.

    " Result table - holds full SEQG3 fields + selection flag.
    " GUSR/GUSRVB are kept because ENQUE_DELETE needs them to identify the lock owner.
    TYPES:
      BEGIN OF ty_lock_row,
        selkz   TYPE abap_bool,
        gname   TYPE seqg3-gname,
        garg    TYPE seqg3-garg,
        guname  TYPE seqg3-guname,
        gmode   TYPE seqg3-gmode,
        gclient TYPE seqg3-gclient,
        gtdate  TYPE seqg3-gtdate,
        gttime  TYPE seqg3-gttime,
        gusr    TYPE seqg3-gusr,
        gusrvb  TYPE seqg3-gusrvb,
      END OF ty_lock_row,
      ty_lock_rows TYPE STANDARD TABLE OF ty_lock_row WITH EMPTY KEY.

    DATA mt_locks TYPE ty_lock_rows.

    " Suggestion data for value helps
    TYPES:
      BEGIN OF ty_suggestion,
        value TYPE string,
        descr TYPE string,
      END OF ty_suggestion,
      ty_suggestions TYPE STANDARD TABLE OF ty_suggestion WITH EMPTY KEY.

    DATA mt_lock_objects TYPE ty_suggestions.
    DATA mt_users        TYPE ty_suggestions.
    DATA mt_clients      TYPE ty_suggestions.

  PROTECTED SECTION.
    DATA mo_client TYPE REF TO z2ui5_if_client.

    METHODS view_display.
    METHODS show_delete_confirm.
    METHODS on_search.
    METHODS on_delete.
    METHODS load_suggestions.
    METHODS check_auth_display
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS check_auth_admin
      RETURNING VALUE(rv_ok) TYPE abap_bool.

  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_cl_app_sm12 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->mo_client = client.

    IF client->check_on_init( ).
      mv_client = sy-mandt.
      load_suggestions( ).
      view_display( ).
      RETURN.
    ENDIF.

    IF client->check_on_event( `BUTTON_SEARCH` ).
      on_search( ).
      client->view_model_update( ).
      RETURN.
    ENDIF.

    IF client->check_on_event( `BUTTON_DELETE` ).
      show_delete_confirm( ).
      RETURN.
    ENDIF.

    IF client->check_on_event( `CONFIRM_DELETE` ).
      client->popup_destroy( ).
      on_delete( ).
      client->view_model_update( ).
      RETURN.
    ENDIF.

  ENDMETHOD.


  METHOD show_delete_confirm.

    DATA lv_count TYPE i.
    LOOP AT mt_locks TRANSPORTING NO FIELDS WHERE selkz = abap_true.
      lv_count = lv_count + 1.
    ENDLOOP.

    IF lv_count = 0.
      mo_client->message_toast_display( `No locks selected.` ).
      RETURN.
    ENDIF.

    DATA(popup) = z2ui5_cl_xml_view=>factory_popup( ).
    popup = popup->dialog(
        title        = `Confirm Delete`
        type         = `Message`
        contentwidth = `25rem` ).

    popup->vbox( class = `sapUiSmallMargin`
        )->text( |Are you sure you want to delete { lv_count } selected lock(s)? This action cannot be undone.| ).

    popup->footer( )->overflow_toolbar(
        )->toolbar_spacer(
        )->button(
            text  = `Cancel`
            press = mo_client->_event_client( mo_client->cs_event-popup_close )
        )->button(
            text  = `Delete`
            press = mo_client->_event( `CONFIRM_DELETE` )
            type  = `Reject` ).

    mo_client->popup_display( popup->stringify( ) ).

  ENDMETHOD.


  METHOD on_search.

    IF check_auth_display( ) = abap_false.
      mo_client->message_box_display(
        text = `You are not authorized to display lock entries (S_ADMI_FCD = ENQ).`
        type = `error` ).
      RETURN.
    ENDIF.

    TRY.
        DATA(lt_locks) = z2ui5_cl_util=>lock_read(
          lock_object = mv_lock_object
          user        = mv_user
          client      = mv_client ).
      CATCH cx_root.
        mo_client->message_box_display(
          text = `Could not read lock table (ENQUEUE_READ failed).`
          type = `error` ).
        CLEAR mt_locks.
        RETURN.
    ENDTRY.

    mt_locks = VALUE #(
      FOR ls_lock IN lt_locks (
        gname   = ls_lock-lock_object
        garg    = ls_lock-argument
        guname  = ls_lock-user
        gmode   = ls_lock-mode
        gclient = ls_lock-client
        gtdate  = ls_lock-date
        gttime  = ls_lock-time
        gusr    = ls_lock-owner
        gusrvb  = ls_lock-owner_vb
      ) ).

    mo_client->message_toast_display( |Found { lines( mt_locks ) } lock(s).| ).

  ENDMETHOD.


  METHOD on_delete.

    IF check_auth_admin( ) = abap_false.
      mo_client->message_box_display(
        text = `You are not authorized to delete lock entries (S_ADMI_FCD = ENQA).`
        type = `error` ).
      RETURN.
    ENDIF.

    DATA lt_lock  TYPE z2ui5_cl_util=>ty_t_lock.
    DATA lv_count TYPE i.

    LOOP AT mt_locks INTO DATA(ls_lock) WHERE selkz = abap_true.
      APPEND VALUE z2ui5_cl_util=>ty_s_lock(
        lock_object = ls_lock-gname
        argument    = ls_lock-garg
        mode        = ls_lock-gmode
        user        = ls_lock-guname
        client      = ls_lock-gclient
        owner       = ls_lock-gusr
        owner_vb    = ls_lock-gusrvb
      ) TO lt_lock.
      lv_count = lv_count + 1.
    ENDLOOP.

    IF lt_lock IS INITIAL.
      mo_client->message_toast_display( `No locks selected.` ).
      RETURN.
    ENDIF.

    IF z2ui5_cl_util=>lock_delete_entries( lt_lock ) = abap_true.
      DELETE mt_locks WHERE selkz = abap_true.
      mo_client->message_toast_display( |{ lv_count } lock(s) deleted.| ).
    ELSE.
      mo_client->message_box_display(
        text = `Lock deletion failed.`
        type = `error` ).
    ENDIF.

  ENDMETHOD.


  METHOD check_auth_display.

    AUTHORITY-CHECK OBJECT 'S_ADMI_FCD'
      ID 'S_ADMI_FCD' FIELD 'ENQ'.
    rv_ok = xsdbool( sy-subrc = 0 ).

    " ENQA implicitly grants display rights too.
    IF rv_ok = abap_false.
      AUTHORITY-CHECK OBJECT 'S_ADMI_FCD'
        ID 'S_ADMI_FCD' FIELD 'ENQA'.
      rv_ok = xsdbool( sy-subrc = 0 ).
    ENDIF.

  ENDMETHOD.


  METHOD check_auth_admin.

    AUTHORITY-CHECK OBJECT 'S_ADMI_FCD'
      ID 'S_ADMI_FCD' FIELD 'ENQA'.
    rv_ok = xsdbool( sy-subrc = 0 ).

  ENDMETHOD.


  METHOD load_suggestions.

    " Lock table names that belong to SAP enqueue objects (e.g., MARA, VBAK)
    SELECT DISTINCT s~tabname, l~viewname
      FROM dd26s AS s
      INNER JOIN dd25l AS l ON l~viewname = s~viewname
      WHERE l~aggtype = 'E'
      INTO TABLE @DATA(lt_lock_tables)
      UP TO 500 ROWS.

    mt_lock_objects = VALUE #( FOR ls IN lt_lock_tables (
      value = ls-tabname
      descr = ls-viewname ) ).

    " SAP clients from T000
    SELECT mandt, mtext
      FROM t000
      INTO TABLE @DATA(lt_clients).

    mt_clients = VALUE #( FOR lc IN lt_clients (
      value = lc-mandt
      descr = lc-mtext ) ).

    " Active SAP users (limited set)
    SELECT bname
      FROM usr02
      INTO TABLE @DATA(lt_users)
      UP TO 200 ROWS.

    mt_users = VALUE #( FOR lu IN lt_users (
      value = lu-bname
      descr = `` ) ).

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_xml_view=>factory( ).

    DATA(page) = view->shell(
        )->page(
            title          = `Lock Manager (SM12)`
            navbuttonpress = mo_client->_event_nav_app_leave( )
            shownavbutton  = mo_client->check_app_prev_stack( ) ).

    " ----- Filter form -----
    DATA(form) = page->simple_form(
                       title    = `Filter`
                       editable = abap_true
                   )->content( `form` ).

    " Lock Object with suggestions (table names from lock objects)
    form->label( `Lock Object` )->input(
        value           = mo_client->_bind_edit( mv_lock_object )
        submit          = mo_client->_event( `BUTTON_SEARCH` )
        suggestionitems = mo_client->_bind( mt_lock_objects )
        showsuggestion  = abap_true
    )->get( )->suggestion_items( )->get( )->list_item(
        text           = `{VALUE}`
        additionaltext = `{DESCR}` ).

    " ABAP User with suggestions
    form->label( `ABAP User` )->input(
        value           = mo_client->_bind_edit( mv_user )
        submit          = mo_client->_event( `BUTTON_SEARCH` )
        suggestionitems = mo_client->_bind( mt_users )
        showsuggestion  = abap_true
    )->get( )->suggestion_items( )->get( )->list_item(
        text           = `{VALUE}`
        additionaltext = `{DESCR}` ).

    " Client with suggestions
    form->label( `Client` )->input(
        value           = mo_client->_bind_edit( mv_client )
        submit          = mo_client->_event( `BUTTON_SEARCH` )
        suggestionitems = mo_client->_bind( mt_clients )
        showsuggestion  = abap_true
    )->get( )->suggestion_items( )->get( )->list_item(
        text           = `{VALUE}`
        additionaltext = `{DESCR}` ).

    form->button(
        text  = `Search`
        press = mo_client->_event( `BUTTON_SEARCH` )
        type  = `Emphasized` ).

    " ----- Results table with multi-select -----
    DATA(tab) = page->table(
            items = |\{path: '{ mo_client->_bind_edit( val = mt_locks path = abap_true ) }', templateShareable: false\}|
            mode  = `MultiSelect`
        )->header_toolbar(
            )->overflow_toolbar(
                )->title( `Lock Entries`
                )->toolbar_spacer(
                )->button(
                    icon  = `sap-icon://delete`
                    text  = `Delete Selected`
                    press = mo_client->_event( `BUTTON_DELETE` )
                    type  = `Reject`
        )->get_parent( )->get_parent( ).

    tab->columns(
        )->column( )->text( `Lock Object` )->get_parent(
        )->column( )->text( `Argument` )->get_parent(
        )->column( )->text( `User` )->get_parent(
        )->column( )->text( `Mode` )->get_parent(
        )->column( )->text( `Client` )->get_parent(
        )->column( )->text( `Date` )->get_parent(
        )->column( )->text( `Time` ).

    tab->items( )->column_list_item( selected = `{SELKZ}`
        )->cells(
            )->text( `{GNAME}`
            )->text( `{GARG}`
            )->text( `{GUNAME}`
            )->text( `{GMODE}`
            )->text( `{GCLIENT}`
            )->text( `{GTDATE}`
            )->text( `{GTTIME}` ).

    mo_client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
