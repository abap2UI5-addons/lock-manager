CLASS z2ui5_cl_lock_sample DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

  PRIVATE SECTION.

    " Input
    DATA mv_vbeln        TYPE vbak-vbeln.
    DATA mv_lock         TYPE abap_bool VALUE abap_true.
    DATA mv_unlock       TYPE abap_bool.
    DATA mv_read_sm12    TYPE abap_bool VALUE abap_true.
    DATA mv_read_ztab    TYPE abap_bool VALUE abap_true.

    " Result message strip
    DATA mv_msg_text     TYPE string.
    DATA mv_msg_type     TYPE string.
    DATA mv_msg_visible  TYPE abap_bool.

    " Table data
    DATA mt_sm12         TYPE z2ui5_cl_lock_manager=>ty_sm12_locks.
    DATA mt_entries      TYPE z2ui5_cl_lock_manager=>ty_lock_entries.

    METHODS:
      on_execute
        IMPORTING io_client TYPE REF TO z2ui5_if_client,
      on_refresh
        IMPORTING io_client TYPE REF TO z2ui5_if_client,
      on_clear
        IMPORTING io_client TYPE REF TO z2ui5_if_client,
      build_view
        IMPORTING io_client TYPE REF TO z2ui5_if_client.

ENDCLASS.

CLASS z2ui5_cl_lock_sample IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    CASE client->get( )-event.
      WHEN 'EXECUTE'.
        on_execute( client ).
      WHEN 'REFRESH'.
        on_refresh( client ).
      WHEN 'CLEAR'.
        on_clear( client ).
    ENDCASE.

    build_view( client ).

  ENDMETHOD.


  METHOD on_execute.

    CLEAR: mv_msg_text, mv_msg_type, mv_msg_visible,
           mt_sm12, mt_entries.

    IF mv_vbeln IS INITIAL.
      mv_msg_type    = 'Error'.
      mv_msg_text    = 'Please enter a Sales Order number'.
      mv_msg_visible = abap_true.
      RETURN.
    ENDIF.

    IF mv_lock = abap_false AND mv_unlock = abap_false
   AND mv_read_sm12 = abap_false AND mv_read_ztab = abap_false.
      mv_msg_type    = 'Warning'.
      mv_msg_text    = 'Please select at least one action'.
      mv_msg_visible = abap_true.
      RETURN.
    ENDIF.

    DATA(lt_params) = VALUE z2ui5_cl_lock_manager=>ty_params( (
      name  = 'VBELN'
      type  = 'VBAK-VBELN'
      value = mv_vbeln
    ) ).

    " Lock
    IF mv_lock = abap_true.
      DATA(ls_result) = z2ui5_cl_lock_manager=>request(
        iv_function = 'ENQUEUE_EVVBAKE'
        iv_process  = z2ui5_cl_lock_manager=>c_process_enqueue
        iv_obj_type = 'VBAK'
        iv_obj_key  = mv_vbeln
        it_params   = lt_params
      ).
      mv_msg_type    = ls_result-msg_type.
      mv_msg_text    = |Lock: { ls_result-msg_desc }|.
      mv_msg_visible = abap_true.
    ENDIF.

    " Unlock
    IF mv_unlock = abap_true.
      ls_result = z2ui5_cl_lock_manager=>request(
        iv_function = 'DEQUEUE_EVVBAKE'
        iv_process  = z2ui5_cl_lock_manager=>c_process_dequeue
        iv_obj_type = 'VBAK'
        iv_obj_key  = mv_vbeln
        it_params   = lt_params
      ).
      mv_msg_type    = ls_result-msg_type.
      mv_msg_text    = |Unlock: { ls_result-msg_desc }|.
      mv_msg_visible = abap_true.
    ENDIF.

    " Read SM12
    IF mv_read_sm12 = abap_true.
      mt_sm12 = z2ui5_cl_lock_manager=>read_sm12_locks( ).
    ENDIF.

    " Read Z-table
    IF mv_read_ztab = abap_true.
      mt_entries = z2ui5_cl_lock_manager=>read_lock_requests( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_refresh.

    CLEAR: mt_sm12, mt_entries.
    mt_sm12    = z2ui5_cl_lock_manager=>read_sm12_locks( ).
    mt_entries = z2ui5_cl_lock_manager=>read_lock_requests( ).

    mv_msg_type    = 'Information'.
    mv_msg_text    = 'Data refreshed'.
    mv_msg_visible = abap_true.

  ENDMETHOD.


  METHOD on_clear.

    CLEAR: mv_vbeln, mv_lock, mv_unlock,
           mv_read_sm12, mv_read_ztab,
           mv_msg_text, mv_msg_type, mv_msg_visible,
           mt_sm12, mt_entries.

    mv_lock      = abap_true.
    mv_read_sm12 = abap_true.
    mv_read_ztab = abap_true.

  ENDMETHOD.


  METHOD build_view.

    DATA(lo_view) = z2ui5_cl_xml_view=>factory( ).

    DATA(lo_page) = lo_view->page(
      title         = 'Lock Handler Demo'
      navbuttonpress = io_client->_event( 'BACK' )
      shownavbutton  = abap_true
    ).

    " ── Toolbar ───────────────────────────────────────────────
    DATA(lo_toolbar) = lo_page->toolbar( ).
    lo_toolbar->button(
      text  = 'Execute'
      press = io_client->_event( 'EXECUTE' )
      type  = 'Emphasized'
      icon  = 'sap-icon://play'
    ).
    lo_toolbar->button(
      text  = 'Refresh'
      press = io_client->_event( 'REFRESH' )
      type  = 'Default'
      icon  = 'sap-icon://refresh'
    ).
    lo_toolbar->button(
      text  = 'Clear'
      press = io_client->_event( 'CLEAR' )
      type  = 'Default'
      icon  = 'sap-icon://clear-all'
    ).

    " ── Input Panel ───────────────────────────────────────────
    DATA(lo_panel_in) = lo_page->panel( headertext = 'Input' expanded = 'true' ).
    DATA(lo_form)     = lo_panel_in->simple_form(
      layout   = 'ResponsiveGridLayout'
      editable = 'true'
    ).
    DATA(lo_content) = lo_form->content( ).

    lo_content->label( 'Sales Order (VBELN)' ).
    lo_content->input(
      value       = io_client->_bind( mv_vbeln )
      placeholder = 'e.g. 0050000005'
      maxlength   = '10'
    ).

    lo_content->label( 'Actions' ).
    DATA(lo_hbox) = lo_content->hbox( alignitems = 'Center' ).
    lo_hbox->checkbox(
      text     = 'Lock'
      selected = io_client->_bind( mv_lock )
    ).
    lo_hbox->checkbox(
      text     = 'Unlock'
      selected = io_client->_bind( mv_unlock )
    ).
    lo_hbox->checkbox(
      text     = 'Read SM12 Locks'
      selected = io_client->_bind( mv_read_sm12 )
    ).
    lo_hbox->checkbox(
      text     = 'Read Z-Table'
      selected = io_client->_bind( mv_read_ztab )
    ).

    " ── Message Strip ─────────────────────────────────────────
    lo_page->message_strip(
      text    = io_client->_bind( mv_msg_text )
      type    = io_client->_bind( mv_msg_type )
      visible = io_client->_bind( mv_msg_visible )
    ).

    " ── SM12 Locks Panel ──────────────────────────────────────
    DATA(lo_panel_sm12) = lo_page->panel(
      headertext = 'SM12 Active Locks'
      expanded   = 'true'
    ).

    DATA(lo_tab_sm12) = lo_panel_sm12->table(
      items      = io_client->_bind( mt_sm12 )
      mode       = 'None'
    ).

    DATA(lo_cols_sm12) = lo_tab_sm12->columns( ).
    lo_cols_sm12->column( width = '15rem' )->text( 'Lock Object' ).
    lo_cols_sm12->column( width = '10rem' )->text( 'User'        ).
    lo_cols_sm12->column( width = '5rem'  )->text( 'Mode'        ).
    lo_cols_sm12->column( width = '6rem'  )->text( 'Client'      ).
    lo_cols_sm12->column( width = '9rem'  )->text( 'Date'        ).
    lo_cols_sm12->column( width = '8rem'  )->text( 'Time'        ).
    lo_cols_sm12->column(                  )->text( 'Argument'    ).

    DATA(lo_row_sm12) = lo_tab_sm12->column_list_item( ).
    lo_row_sm12->text( '{lock_object}' ).
    lo_row_sm12->text( '{user}'        ).
    lo_row_sm12->text( '{mode}'        ).
    lo_row_sm12->text( '{client}'      ).
    lo_row_sm12->text( '{date}'        ).
    lo_row_sm12->text( '{time}'        ).
    lo_row_sm12->text( '{argument}'    ).

    " ── Z-Table Panel ─────────────────────────────────────────
    DATA(lo_panel_ztab) = lo_page->panel(
      headertext = 'Z-Table Lock Requests'
      expanded   = 'true'
    ).

    DATA(lo_tab_ztab) = lo_panel_ztab->table(
      items      = io_client->_bind( mt_entries )
      mode       = 'None'
    ).

    DATA(lo_cols_ztab) = lo_tab_ztab->columns( ).
    lo_cols_ztab->column( width = '8rem'  )->text( 'Status'     ).
    lo_cols_ztab->column( width = '6rem'  )->text( 'Process'    ).
    lo_cols_ztab->column( width = '10rem' )->text( 'Obj Type'   ).
    lo_cols_ztab->column( width = '12rem' )->text( 'Obj Key'    ).
    lo_cols_ztab->column( width = '18rem' )->text( 'Function'   ).
    lo_cols_ztab->column( width = '10rem' )->text( 'User'       ).
    lo_cols_ztab->column( width = '14rem' )->text( 'Timestamp'  ).
    lo_cols_ztab->column(                  )->text( 'Message'    ).

    DATA(lo_row_ztab) = lo_tab_ztab->column_list_item( ).
    lo_row_ztab->text( '{status}'     ).
    lo_row_ztab->text( '{process}'    ).
    lo_row_ztab->text( '{obj_type}'   ).
    lo_row_ztab->text( '{obj_key}'    ).
    lo_row_ztab->text( '{function}'   ).
    lo_row_ztab->text( '{created_by}' ).
    lo_row_ztab->text( '{created_at}' ).
    lo_row_ztab->text( '{msg_text}'   ).

    io_client->view_display( lo_view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
