* Function group: Z_LOCK_MANAGER
* Function module: Z_REQUEST_LOCKING
*
* A reusable wrapper around the standard SAP ENQUEUE_* / DEQUEUE_* family.
* The caller passes:
*   - WA_HEADER:    object type/key + which kernel FM to call + process ('E'/'D')
*   - IT_PARAMETERS: the parameters to forward to that kernel FM
*
* The wrapper:
*   - dispatches dynamically to WA_HEADER-FUNCTION via CALL FUNCTION
*     ... DESTINATION 'NONE' PARAMETER-TABLE ... EXCEPTION-TABLE — so the
*     kernel enqueue runs in its own RFC session, isolated from any other
*     enqueues the caller may be holding
*   - on a successful Enqueue, writes an entry to ZTLOCK_REGISTRY
*   - on a successful Dequeue, removes the entry from ZTLOCK_REGISTRY
*   - on FOREIGN_LOCK, looks up the current owner in ZTLOCK_REGISTRY and
*     returns it in MSG_DESCRIPTION
*
* Persistence model — important:
*   The kernel SAP enqueue is bound to the calling session and is gone
*   when that session ends. The ZTLOCK_REGISTRY row, however, is a
*   normal database row and SURVIVES the session, so cross-session
*   "who holds this lock" lookups stay correct. The pre-check below
*   reads the registry first, so a still-registered lock from a
*   long-finished session keeps blocking new attempts.
*
*   To prevent stuck rows after a browser crash, every registry entry
*   carries LOCKED_AT and is treated as expired after TTL_SECONDS
*   (default 1800 = 30 minutes). The next lock request from any user
*   will overwrite an expired row.
*
* The DDIC objects ZTLOCK_REGISTRY / ZS_LOCK_HEADER / ZS_LOCK_PARAM must
* exist; see README.md in this folder.


*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(WA_HEADER)        TYPE  ZS_LOCK_HEADER
*"     VALUE(CLIENT_DEPENDENT) TYPE  CHAR1 DEFAULT 'X'
*"     VALUE(TTL_SECONDS)      TYPE  I     DEFAULT 1800
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
  "    shows the object as held by someone else and the entry has
  "    not yet expired. Return early with the owner info if so —
  "    saves the kernel call.
  " ------------------------------------------------------------------
  IF wa_header-process = 'E'.

    SELECT SINGLE username, locked_at
      FROM ztlock_registry
      WHERE obj_type = @wa_header-obj_type
        AND obj_key  = @wa_header-obj_key
      INTO ( @DATA(existing_user), @DATA(existing_at) ).

    IF sy-subrc = 0 AND existing_user <> sy-uname.

      DATA now_tstmp  TYPE timestampl.
      DATA age_secs   TYPE p LENGTH 8 DECIMALS 0.

      GET TIME STAMP FIELD now_tstmp.

      TRY.
          cl_abap_tstmp=>subtract(
            EXPORTING tstmp1    = now_tstmp
                      tstmp2    = existing_at
            RECEIVING r_seconds = age_secs ).
        CATCH cx_root.
          age_secs = 0.
      ENDTRY.

      IF age_secs <= ttl_seconds.
        msg_code        = 'FOREIGN_LOCK'.
        msg_type        = 'E'.
        msg_title       = 'Object locked'.
        msg_description = |Locked by { existing_user } since { existing_at TIMESTAMP = USER }|.
        RETURN.
      ENDIF.

      " Expired — fall through and let this user take over the lock.
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
    ( name = 'FOREIGN_LOCK'          value = 1 )
    ( name = 'SYSTEM_FAILURE'        value = 2 )
    ( name = 'COMMUNICATION_FAILURE' value = 3 )
    ( name = 'OTHERS'                value = 99 ) ).

  " ------------------------------------------------------------------
  " 3. Dispatch to the actual kernel FM in a separate RFC session.
  "    DESTINATION 'NONE' isolates the platform-manager enqueues from
  "    anything else the caller's session is doing.
  " ------------------------------------------------------------------
  TRY.

      CALL FUNCTION wa_header-function
        DESTINATION 'NONE'
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
