* Function group: Z_LOCK_MANAGER
* Function module: Z_REQUEST_LOCKING
*
* A reusable wrapper around the standard SAP ENQUEUE_* / DEQUEUE_* family.
* The caller passes:
*   - WA_HEADER:    object type/key + which kernel FM to call + process ('E'/'D')
*   - IT_PARAMETERS: the parameters to forward to that kernel FM
* The wrapper:
*   - dispatches dynamically to WA_HEADER-FUNCTION via CALL FUNCTION
*     ... PARAMETER-TABLE ... EXCEPTION-TABLE
*   - on a successful Enqueue, writes an entry to ZTLOCK_REGISTRY
*   - on a successful Dequeue, removes the entry from ZTLOCK_REGISTRY
*   - on FOREIGN_LOCK, looks up the current owner in ZTLOCK_REGISTRY and
*     returns it in MSG_DESCRIPTION
*
* The DDIC objects ZTLOCK_REGISTRY / ZS_LOCK_HEADER / ZS_LOCK_PARAM must
* exist; see README.md in this folder.


*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(WA_HEADER)        TYPE  ZS_LOCK_HEADER
*"     VALUE(CLIENT_DEPENDENT) TYPE  CHAR1 DEFAULT 'X'
*"  EXPORTING
*"     VALUE(MSG_CODE)         TYPE  STRING
*"     VALUE(MSG_TYPE)         TYPE  CHAR1
*"     VALUE(MSG_TITLE)        TYPE  STRING
*"     VALUE(MSG_DESCRIPTION)  TYPE  STRING
*"  TABLES
*"     IT_PARAMETERS           STRUCTURE ZS_LOCK_PARAM
*"----------------------------------------------------------------------
FUNCTION z_request_locking.

  CLEAR: msg_code, msg_type, msg_title, msg_description.

  " ------------------------------------------------------------------
  " 1. Pre-check: on a lock request, see if the registry already
  "    shows the object as held by someone else. Return early with
  "    the owner info if so — saves a kernel call.
  " ------------------------------------------------------------------
  IF wa_header-process = 'E'.

    SELECT SINGLE username, locked_at
      FROM ztlock_registry
      WHERE obj_type = @wa_header-obj_type
        AND obj_key  = @wa_header-obj_key
      INTO ( @DATA(existing_user), @DATA(existing_at) ).

    IF sy-subrc = 0 AND existing_user <> sy-uname.
      msg_code        = 'FOREIGN_LOCK'.
      msg_type        = 'E'.
      msg_title       = 'Object locked'.
      msg_description = |Locked by { existing_user } since { existing_at TIMESTAMP = USER }|.
      RETURN.
    ENDIF.

  ENDIF.

  " ------------------------------------------------------------------
  " 2. Build dynamic parameter-binding table from IT_PARAMETERS.
  "    Each row's NAME / TYPE / VALUE becomes one EXPORTING parameter
  "    of the kernel FM. A typed data object is created on the fly
  "    so the kernel FM receives the correct data type.
  " ------------------------------------------------------------------
  DATA ptab TYPE abap_func_parmbind_tab.
  DATA etab TYPE abap_func_excpbind_tab.

  LOOP AT it_parameters INTO DATA(param).

    DATA dref TYPE REF TO data.

    TRY.
        CREATE DATA dref TYPE (param-type).
      CATCH cx_sy_create_data_error.
        msg_code        = 'BAD_PARAMETER_TYPE'.
        msg_type        = 'E'.
        msg_title       = 'Lock request rejected'.
        msg_description = |Unknown parameter type { param-type } for { param-name }|.
        RETURN.
    ENDTRY.

    ASSIGN dref->* TO FIELD-SYMBOL(<val>).
    <val> = param-value.

    INSERT VALUE #( name  = param-name
                    kind  = abap_func_exporting
                    value = dref )
      INTO TABLE ptab.

  ENDLOOP.

  IF client_dependent = 'X'
     AND NOT line_exists( ptab[ name = 'MANDT' ] )
     AND NOT line_exists( ptab[ name = 'mandt' ] ).
    DATA dref_mandt TYPE REF TO data.
    CREATE DATA dref_mandt TYPE mandt.
    ASSIGN dref_mandt->* TO FIELD-SYMBOL(<mandt>).
    <mandt> = sy-mandt.
    INSERT VALUE #( name  = 'MANDT'
                    kind  = abap_func_exporting
                    value = dref_mandt )
      INTO TABLE ptab.
  ENDIF.

  etab = VALUE #(
    ( name = 'FOREIGN_LOCK'   value = 1 )
    ( name = 'SYSTEM_FAILURE' value = 2 )
    ( name = 'OTHERS'         value = 99 ) ).

  " ------------------------------------------------------------------
  " 3. Dispatch to the actual kernel FM.
  " ------------------------------------------------------------------
  TRY.

      CALL FUNCTION wa_header-function
        PARAMETER-TABLE ptab
        EXCEPTION-TABLE etab.

    CATCH cx_root INTO DATA(lx).
      msg_code        = 'CALL_FAILED'.
      msg_type        = 'E'.
      msg_title       = 'Lock request failed'.
      msg_description = lx->get_text( ).
      RETURN.
  ENDTRY.

  IF sy-subrc <> 0.

    IF sy-subrc = 1.
      " Kernel says foreign_lock but our registry was clean — orphaned
      " kernel lock from a crashed session. Surface it generically.
      msg_code        = 'FOREIGN_LOCK'.
      msg_type        = 'E'.
      msg_title       = 'Object locked'.
      msg_description = |Object { wa_header-obj_type } / { wa_header-obj_key } is locked by another session|.
    ELSE.
      msg_code        = 'SYSTEM_FAILURE'.
      msg_type        = 'E'.
      msg_title       = 'Lock request failed'.
      msg_description = |Kernel FM { wa_header-function } returned sy-subrc = { sy-subrc }|.
    ENDIF.

    RETURN.
  ENDIF.

  " ------------------------------------------------------------------
  " 4. Sync the registry to reflect the new state.
  " ------------------------------------------------------------------
  CASE wa_header-process.

    WHEN 'E'.
      DATA reg TYPE ztlock_registry.
      reg-obj_type = wa_header-obj_type.
      reg-obj_key  = wa_header-obj_key.
      reg-username = sy-uname.
      reg-function = wa_header-function.
      GET TIME STAMP FIELD reg-locked_at.

      MODIFY ztlock_registry FROM @reg.
      COMMIT WORK.

    WHEN 'D'.
      DELETE FROM ztlock_registry
        WHERE obj_type = @wa_header-obj_type
          AND obj_key  = @wa_header-obj_key
          AND username = @sy-uname.
      COMMIT WORK.

  ENDCASE.

  msg_code  = 'OK'.
  msg_type  = 'S'.
  msg_title = COND #( WHEN wa_header-process = 'E' THEN 'Locked' ELSE 'Unlocked' ).

ENDFUNCTION.
