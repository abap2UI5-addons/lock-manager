CLASS z2ui5_cl_lock_sample DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

  PROTECTED SECTION.

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

    DATA(lo_view) = z2ui5_cl_ui5_view_builder=>factory( 
                        )->ele( n = `View` ns = `mvc` 
                        )->a( n = `xmlns` v = `sap.m` 
                        )->a( n = `xmlns:mvc` v = `sap.ui.core.mvc` 
                        )->a( n = `xmlns:core` v = `sap.ui.core` 
                        )->a( n = `xmlns:form` v = `sap.ui.layout.form` 
                        )->a( n = `displayBlock` v = `true` 
                        )->a( n = `height` v = `100%` ).

    DATA(lo_page) = lo_view->ele( `Page` 
                        )->a( n = `title` v = 'Lock Handler Demo' 
                        )->a( n = `navButtonPress` v = io_client->_event_nav_app_leave( ) 
                        )->a( n = `showNavButton` b = io_client->check_app_prev_stack( ) ).

    " ── Toolbar ───────────────────────────────────────────────
    DATA(lo_toolbar) = lo_page->ele( `Toolbar` ).
    lo_toolbar->tag( `Button` 
        )->a( n = `text` v = 'Execute' 
        )->a( n = `press` v = io_client->_event( 'EXECUTE' ) 
        )->a( n = `type` v = 'Emphasized' 
        )->a( n = `icon` v = 'sap-icon://play' ).
    lo_toolbar->tag( `Button` 
        )->a( n = `text` v = 'Refresh' 
        )->a( n = `press` v = io_client->_event( 'REFRESH' ) 
        )->a( n = `type` v = 'Default' 
        )->a( n = `icon` v = 'sap-icon://refresh' ).
    lo_toolbar->tag( `Button` 
        )->a( n = `text` v = 'Clear' 
        )->a( n = `press` v = io_client->_event( 'CLEAR' ) 
        )->a( n = `type` v = 'Default' 
        )->a( n = `icon` v = 'sap-icon://clear-all' ).

    " ── Input Panel ───────────────────────────────────────────
    DATA(lo_panel_in) = lo_page->ele( `Panel` 
                            )->a( n = `headerText` v = 'Input' 
                            )->a( n = `expanded` v = 'true' ).
    DATA(lo_form)     = lo_panel_in->ele( n = `SimpleForm` ns = `form` 
                            )->a( n = `layout` v = 'ResponsiveGridLayout' 
                            )->a( n = `editable` v = 'true' ).
    " an aggregation tag takes the namespace of its own control, so a
    " SimpleForm's content is form:content - unprefixed it resolves against
    " the default xmlns and UI5 goes looking for a sap.m.content control
    DATA(lo_content) = lo_form->ele( n = `content` ns = `form` ).

    lo_content->tag( `Label` 
        )->a( n = `text` v = 'Sales Order (VBELN)' ).
    lo_content->tag( `Input` 
        )->a( n = `value` v = io_client->_bind_edit( mv_vbeln ) 
        )->a( n = `placeholder` v = 'e.g. 0050000005' 
        )->a( n = `maxLength` v = '10' ).

    lo_content->tag( `Label` 
        )->a( n = `text` v = 'Actions' ).
    DATA(lo_hbox) = lo_content->ele( `HBox` 
                        )->a( n = `alignItems` v = 'Center' ).
    lo_hbox->tag( `CheckBox` 
        )->a( n = `text` v = 'Lock' 
        )->a( n = `selected` v = io_client->_bind_edit( mv_lock ) ).
    lo_hbox->tag( `CheckBox` 
        )->a( n = `text` v = 'Unlock' 
        )->a( n = `selected` v = io_client->_bind_edit( mv_unlock ) ).
    lo_hbox->tag( `CheckBox` 
        )->a( n = `text` v = 'Read SM12 Locks' 
        )->a( n = `selected` v = io_client->_bind_edit( mv_read_sm12 ) ).
    lo_hbox->tag( `CheckBox` 
        )->a( n = `text` v = 'Read Z-Table' 
        )->a( n = `selected` v = io_client->_bind_edit( mv_read_ztab ) ).

    " ── Message Strip ─────────────────────────────────────────
    lo_page->tag( `MessageStrip` 
        )->a( n = `text` v = io_client->_bind( mv_msg_text ) 
        )->a( n = `type` v = io_client->_bind( mv_msg_type ) 
        )->a( n = `visible` v = io_client->_bind( mv_msg_visible ) ).

    " ── SM12 Locks Panel ──────────────────────────────────────
    DATA(lo_panel_sm12) = lo_page->ele( `Panel` 
                              )->a( n = `headerText` v = 'SM12 Active Locks' 
                              )->a( n = `expanded` v = 'true' ).

    DATA(lo_tab_sm12) = lo_panel_sm12->ele( `Table` 
                            )->a( n = `items` v = io_client->_bind( mt_sm12 ) 
                            )->a( n = `mode` v = 'None' ).

    DATA(lo_cols_sm12) = lo_tab_sm12->ele( `columns` ).
    lo_cols_sm12->ele( `Column` 
        )->a( n = `width` v = '15rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Lock Object' ).
    lo_cols_sm12->ele( `Column` 
        )->a( n = `width` v = '10rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'User' ).
    lo_cols_sm12->ele( `Column` 
        )->a( n = `width` v = '5rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Mode' ).
    lo_cols_sm12->ele( `Column` 
        )->a( n = `width` v = '6rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Client' ).
    lo_cols_sm12->ele( `Column` 
        )->a( n = `width` v = '9rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Date' ).
    lo_cols_sm12->ele( `Column` 
        )->a( n = `width` v = '8rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Time' ).
    lo_cols_sm12->ele( `Column` 
        )->tag( `Text` 
        )->a( n = `text` v = 'Argument' ).

    DATA(lo_row_sm12) = lo_tab_sm12->ele( `ColumnListItem` ).
    lo_row_sm12->tag( `Text` 
        )->a( n = `text` v = '{lock_object}' ).
    lo_row_sm12->tag( `Text` 
        )->a( n = `text` v = '{user}' ).
    lo_row_sm12->tag( `Text` 
        )->a( n = `text` v = '{mode}' ).
    lo_row_sm12->tag( `Text` 
        )->a( n = `text` v = '{client}' ).
    lo_row_sm12->tag( `Text` 
        )->a( n = `text` v = '{date}' ).
    lo_row_sm12->tag( `Text` 
        )->a( n = `text` v = '{time}' ).
    lo_row_sm12->tag( `Text` 
        )->a( n = `text` v = '{argument}' ).

    " ── Z-Table Panel ─────────────────────────────────────────
    DATA(lo_panel_ztab) = lo_page->ele( `Panel` 
                              )->a( n = `headerText` v = 'Z-Table Lock Requests' 
                              )->a( n = `expanded` v = 'true' ).

    DATA(lo_tab_ztab) = lo_panel_ztab->ele( `Table` 
                            )->a( n = `items` v = io_client->_bind( mt_entries ) 
                            )->a( n = `mode` v = 'None' ).

    DATA(lo_cols_ztab) = lo_tab_ztab->ele( `columns` ).
    lo_cols_ztab->ele( `Column` 
        )->a( n = `width` v = '8rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Status' ).
    lo_cols_ztab->ele( `Column` 
        )->a( n = `width` v = '6rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Process' ).
    lo_cols_ztab->ele( `Column` 
        )->a( n = `width` v = '10rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Obj Type' ).
    lo_cols_ztab->ele( `Column` 
        )->a( n = `width` v = '12rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Obj Key' ).
    lo_cols_ztab->ele( `Column` 
        )->a( n = `width` v = '18rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Function' ).
    lo_cols_ztab->ele( `Column` 
        )->a( n = `width` v = '10rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'User' ).
    lo_cols_ztab->ele( `Column` 
        )->a( n = `width` v = '14rem' 
        )->tag( `Text` 
        )->a( n = `text` v = 'Timestamp' ).
    lo_cols_ztab->ele( `Column` 
        )->tag( `Text` 
        )->a( n = `text` v = 'Message' ).

    DATA(lo_row_ztab) = lo_tab_ztab->ele( `ColumnListItem` ).
    lo_row_ztab->tag( `Text` 
        )->a( n = `text` v = '{status}' ).
    lo_row_ztab->tag( `Text` 
        )->a( n = `text` v = '{process}' ).
    lo_row_ztab->tag( `Text` 
        )->a( n = `text` v = '{obj_type}' ).
    lo_row_ztab->tag( `Text` 
        )->a( n = `text` v = '{obj_key}' ).
    lo_row_ztab->tag( `Text` 
        )->a( n = `text` v = '{function}' ).
    lo_row_ztab->tag( `Text` 
        )->a( n = `text` v = '{created_by}' ).
    lo_row_ztab->tag( `Text` 
        )->a( n = `text` v = '{created_at}' ).
    lo_row_ztab->tag( `Text` 
        )->a( n = `text` v = '{msg_text}' ).

    io_client->view_display( lo_view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
