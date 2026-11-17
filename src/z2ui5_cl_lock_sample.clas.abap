CLASS z2ui5_cl_lock_sample DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    " Input
    " c LENGTH 10, not vbak-vbeln: the sample has to activate on systems
    " without SD as well - the handler types the value for the lock module
    DATA mv_vbeln        TYPE c LENGTH 10.
    DATA mv_mode         TYPE char1 VALUE 'E'.
    DATA mv_lock         TYPE abap_bool VALUE abap_true.
    DATA mv_promote      TYPE abap_bool.
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

  PROTECTED SECTION.

  PRIVATE SECTION.

    METHODS:
      on_execute,
      on_refresh,
      on_clear,
      build_view
        IMPORTING io_client TYPE REF TO z2ui5_if_client.

ENDCLASS.

CLASS z2ui5_cl_lock_sample IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    CASE client->get( )-event.
      WHEN 'EXECUTE'.
        on_execute( ).
      WHEN 'REFRESH'.
        on_refresh( ).
      WHEN 'CLEAR'.
        on_clear( ).
    ENDCASE.

    build_view( client ).

  ENDMETHOD.


  METHOD on_execute.
    DATA temp1 TYPE string.
    DATA temp2 TYPE z2ui5_cl_lock_manager=>ty_params.
    DATA temp3 LIKE LINE OF temp2.
    DATA lt_params LIKE temp2.
      DATA ls_result TYPE z2ui5_cl_lock_manager=>ty_result.

    CLEAR: mv_msg_text, mv_msg_type, mv_msg_visible,
           mt_sm12, mt_entries.

    IF mv_vbeln IS INITIAL.
      mv_msg_type    = 'Error'.
      mv_msg_text    = 'Please enter a Sales Order number'.
      mv_msg_visible = abap_true.
      RETURN.
    ENDIF.

    " the input carries no conversion exit: 4711 must lock 0000004711, the
    " argument VA02 locks - not a key no sales order has

    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        input  = mv_vbeln
      IMPORTING
        output = temp1.
mv_vbeln = |{ temp1 }|.

    IF mv_lock = abap_false AND mv_promote = abap_false AND mv_unlock = abap_false
       AND mv_read_sm12 = abap_false AND mv_read_ztab = abap_false.
      mv_msg_type    = 'Warning'.
      mv_msg_text    = 'Please select at least one action'.
      mv_msg_visible = abap_true.
      RETURN.
    ENDIF.


    CLEAR temp2.

    temp3-name = 'VBELN'.
    temp3-type = 'VBAK-VBELN'.
    temp3-value = mv_vbeln.
    INSERT temp3 INTO TABLE temp2.

    lt_params = temp2.

    " Lock
    IF mv_lock = abap_true.

      ls_result = z2ui5_cl_lock_manager=>request(
        iv_function = 'ENQUEUE_EVVBAKE'
        iv_process  = z2ui5_cl_lock_manager=>c_process_enqueue
        iv_obj_type = 'VBAK'
        iv_obj_key  = mv_vbeln
        it_params   = lt_params
        iv_mode     = mv_mode
      ).
      mv_msg_type    = ls_result-msg_type.
      mv_msg_text    = |Lock ({ mv_mode }): { ls_result-msg_desc }|.
      mv_msg_visible = abap_true.
    ENDIF.

    " Promote - turns an optimistic lock into an exclusive one right before
    " saving; whoever promotes first wins, the other optimistic holders lose
    IF mv_promote = abap_true.
      ls_result = z2ui5_cl_lock_manager=>request(
        iv_process  = z2ui5_cl_lock_manager=>c_process_promote
        iv_obj_type = 'VBAK'
        iv_obj_key  = mv_vbeln
      ).
      mv_msg_type    = ls_result-msg_type.
      mv_msg_text    = |Promote: { ls_result-msg_desc }|.
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

    CLEAR: mv_vbeln, mv_lock, mv_promote, mv_unlock,
           mv_read_sm12, mv_read_ztab,
           mv_msg_text, mv_msg_type, mv_msg_visible,
           mt_sm12, mt_entries.

    mv_mode      = 'E'.
    mv_lock      = abap_true.
    mv_read_sm12 = abap_true.
    mv_read_ztab = abap_true.

  ENDMETHOD.


  METHOD build_view.

    DATA lo_view TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_page TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_toolbar TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_panel_in TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_form TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_content TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_modes TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_hbox TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_panel_sm12 TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_tab_sm12 TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_cols_sm12 TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_row_sm12 TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_panel_ztab TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_tab_ztab TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_cols_ztab TYPE REF TO z2ui5_cl_ui5_view_builder.
    DATA lo_row_ztab TYPE REF TO z2ui5_cl_ui5_view_builder.
    lo_view = z2ui5_cl_ui5_view_builder=>factory(
                        )->ele( n = `View` ns = `mvc`
                        )->a( n = `xmlns` v = `sap.m`
                        )->a( n = `xmlns:mvc` v = `sap.ui.core.mvc`
                        )->a( n = `xmlns:form` v = `sap.ui.layout.form`
                        )->a( n = `displayBlock` v = `true`
                        )->a( n = `height` v = `100%` ).


    lo_page = lo_view->ele( `Page`
                        )->a( n = `title` v = 'Lock Handler Demo'
                        )->a( n = `navButtonPress` v = io_client->_event_nav_app_leave( )
                        )->a( n = `showNavButton` b = io_client->check_app_prev_stack( ) ).

    " -- Toolbar -----------------------------------------------

    lo_toolbar = lo_page->ele( `Toolbar` ).
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
        )->a( n = `icon` v = 'sap-icon://eraser' ).

    " -- Input Panel -------------------------------------------

    lo_panel_in = lo_page->ele( `Panel`
                            )->a( n = `headerText` v = 'Input'
                            )->a( n = `expanded` v = 'true' ).

    lo_form     = lo_panel_in->ele( n = `SimpleForm` ns = `form`
                            )->a( n = `layout` v = 'ResponsiveGridLayout'
                            )->a( n = `editable` v = 'true' ).
    " an aggregation tag takes the namespace of its own control, so a
    " SimpleForm's content is form:content - unprefixed it resolves against
    " the default xmlns and UI5 goes looking for a sap.m.content control

    lo_content = lo_form->ele( n = `content` ns = `form` ).

    lo_content->tag( `Label`
        )->a( n = `text` v = 'Sales Order (VBELN)' ).
    lo_content->tag( `Input`
        )->a( n = `value` v = io_client->_bind_edit( mv_vbeln )
        )->a( n = `placeholder` v = 'e.g. 0050000005'
        )->a( n = `maxLength` v = '10' ).

    lo_content->tag( `Label`
        )->a( n = `text` v = 'Lock Mode' ).

    lo_modes = lo_content->ele( `SegmentedButton`
                         )->a( n = `selectedKey` v = io_client->_bind_edit( mv_mode )
                         )->ele( `items` ).
    lo_modes->tag( `SegmentedButtonItem`
        )->a( n = `key` v = 'E'
        )->a( n = `text` v = 'Exclusive (E)' ).
    lo_modes->tag( `SegmentedButtonItem`
        )->a( n = `key` v = 'S'
        )->a( n = `text` v = 'Shared (S)' ).
    lo_modes->tag( `SegmentedButtonItem`
        )->a( n = `key` v = 'O'
        )->a( n = `text` v = 'Optimistic (O)' ).

    lo_content->tag( `Label`
        )->a( n = `text` v = 'Actions' ).

    lo_hbox = lo_content->ele( `HBox`
                        )->a( n = `alignItems` v = 'Center' ).
    lo_hbox->tag( `CheckBox`
        )->a( n = `text` v = 'Lock'
        )->a( n = `selected` v = io_client->_bind_edit( mv_lock ) ).
    lo_hbox->tag( `CheckBox`
        )->a( n = `text` v = 'Promote'
        )->a( n = `selected` v = io_client->_bind_edit( mv_promote ) ).
    lo_hbox->tag( `CheckBox`
        )->a( n = `text` v = 'Unlock'
        )->a( n = `selected` v = io_client->_bind_edit( mv_unlock ) ).
    lo_hbox->tag( `CheckBox`
        )->a( n = `text` v = 'Read SM12 Locks'
        )->a( n = `selected` v = io_client->_bind_edit( mv_read_sm12 ) ).
    lo_hbox->tag( `CheckBox`
        )->a( n = `text` v = 'Read Z-Table'
        )->a( n = `selected` v = io_client->_bind_edit( mv_read_ztab ) ).

    " -- Message Strip -----------------------------------------
    " abap2ui5lint-disable-next-line unresolved-attribute-value -- mv_msg_type only ever holds Error, Warning, Information or Success, set here and in z2ui5_cl_lock_manager
    lo_page->tag( `MessageStrip`
        )->a( n = `text` v = io_client->_bind( mv_msg_text )
        )->a( n = `type` v = io_client->_bind( mv_msg_type )
        )->a( n = `visible` v = io_client->_bind( mv_msg_visible ) ).

    " -- SM12 Locks Panel --------------------------------------

    lo_panel_sm12 = lo_page->ele( `Panel`
                              )->a( n = `headerText` v = 'SM12 Active Locks'
                              )->a( n = `expanded` v = 'true' ).


    lo_tab_sm12 = lo_panel_sm12->ele( `Table`
                            )->a( n = `items` v = io_client->_bind( mt_sm12 )
                            )->a( n = `mode` v = 'None' ).


    lo_cols_sm12 = lo_tab_sm12->ele( `columns` ).
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


    lo_row_sm12 = lo_tab_sm12->ele( `ColumnListItem` ).
    lo_row_sm12->tag( `Text`
        )->a( n = `text` v = '{LOCK_OBJECT}' ).
    lo_row_sm12->tag( `Text`
        )->a( n = `text` v = '{USER}' ).
    lo_row_sm12->tag( `Text`
        )->a( n = `text` v = '{MODE}' ).
    lo_row_sm12->tag( `Text`
        )->a( n = `text` v = '{CLIENT}' ).
    lo_row_sm12->tag( `Text`
        )->a( n = `text` v = '{DATE}' ).
    lo_row_sm12->tag( `Text`
        )->a( n = `text` v = '{TIME}' ).
    lo_row_sm12->tag( `Text`
        )->a( n = `text` v = '{ARGUMENT}' ).

    " -- Z-Table Panel -----------------------------------------

    lo_panel_ztab = lo_page->ele( `Panel`
                              )->a( n = `headerText` v = 'Z-Table Lock Requests'
                              )->a( n = `expanded` v = 'true' ).


    lo_tab_ztab = lo_panel_ztab->ele( `Table`
                            )->a( n = `items` v = io_client->_bind( mt_entries )
                            )->a( n = `mode` v = 'None' ).


    lo_cols_ztab = lo_tab_ztab->ele( `columns` ).
    lo_cols_ztab->ele( `Column`
        )->a( n = `width` v = '8rem'
        )->tag( `Text`
        )->a( n = `text` v = 'Status' ).
    lo_cols_ztab->ele( `Column`
        )->a( n = `width` v = '6rem'
        )->tag( `Text`
        )->a( n = `text` v = 'Process' ).
    lo_cols_ztab->ele( `Column`
        )->a( n = `width` v = '5rem'
        )->tag( `Text`
        )->a( n = `text` v = 'Mode' ).
    lo_cols_ztab->ele( `Column`
        )->a( n = `width` v = '10rem'
        )->tag( `Text`
        )->a( n = `text` v = 'Object Type' ).
    lo_cols_ztab->ele( `Column`
        )->a( n = `width` v = '12rem'
        )->tag( `Text`
        )->a( n = `text` v = 'Object Key' ).
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


    lo_row_ztab = lo_tab_ztab->ele( `ColumnListItem` ).
    lo_row_ztab->tag( `Text`
        )->a( n = `text` v = '{STATUS}' ).
    lo_row_ztab->tag( `Text`
        )->a( n = `text` v = '{PROCESS}' ).
    lo_row_ztab->tag( `Text`
        )->a( n = `text` v = '{LOCK_MODE}' ).
    lo_row_ztab->tag( `Text`
        )->a( n = `text` v = '{OBJ_TYPE}' ).
    lo_row_ztab->tag( `Text`
        )->a( n = `text` v = '{OBJ_KEY}' ).
    lo_row_ztab->tag( `Text`
        )->a( n = `text` v = '{FUNCTION}' ).
    lo_row_ztab->tag( `Text`
        )->a( n = `text` v = '{CREATED_BY}' ).
    lo_row_ztab->tag( `Text`
        )->a( n = `text` v = '{CREATED_AT}' ).
    lo_row_ztab->tag( `Text`
        )->a( n = `text` v = '{MSG_TEXT}' ).

    io_client->view_display( lo_view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
