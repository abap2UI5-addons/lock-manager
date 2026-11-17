CLASS z2ui5_cl_lock_manager DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_param,
        name  TYPE char30,
        " optional: without it the type is read from the lock module's interface
        type  TYPE char50,
        value TYPE char200,
      END OF ty_param,
      ty_params TYPE STANDARD TABLE OF ty_param WITH DEFAULT KEY,

      BEGIN OF ty_result,
        msg_type  TYPE char10,
        msg_title TYPE char100,
        msg_desc  TYPE char200,
      END OF ty_result,

      BEGIN OF ty_sm12_lock,
        lock_object TYPE string,
        argument    TYPE string,
        user        TYPE sy-uname,
        mode        TYPE char1,
        client      TYPE sy-mandt,
        date        TYPE sy-datum,
        time        TYPE sy-uzeit,
      END OF ty_sm12_lock,
      ty_sm12_locks TYPE STANDARD TABLE OF ty_sm12_lock WITH DEFAULT KEY,

      BEGIN OF ty_lock_entry,
        req_id     TYPE guid_32,
        obj_type   TYPE char30,
        obj_key    TYPE char50,
        function   TYPE char30,
        process    TYPE char1,
        lock_mode  TYPE char1,
        status     TYPE char10,
        created_by TYPE sy-uname,
        created_at TYPE timestampl,
        msg_text   TYPE char200,
      END OF ty_lock_entry,
      ty_lock_entries TYPE STANDARD TABLE OF ty_lock_entry WITH DEFAULT KEY.

    CONSTANTS:
      " what a request asks for
      c_process_enqueue TYPE char1  VALUE 'E',
      c_process_dequeue TYPE char1  VALUE 'D',
      c_process_promote TYPE char1  VALUE 'R',
      " the kernel lock modes an enqueue can take
      c_mode_exclusive  TYPE char1  VALUE 'E',
      c_mode_shared     TYPE char1  VALUE 'S',
      c_mode_optimistic TYPE char1  VALUE 'O',
      " the life of a registry row
      c_status_pending  TYPE char10 VALUE 'PENDING',
      c_status_active   TYPE char10 VALUE 'ACTIVE',
      c_status_done     TYPE char10 VALUE 'DONE',
      c_status_error    TYPE char10 VALUE 'ERROR',
      c_status_released TYPE char10 VALUE 'RELEASED',
      c_status_lost     TYPE char10 VALUE 'LOST'.

    CLASS-METHODS:

      request
        IMPORTING
          iv_process          TYPE clike
          iv_obj_type         TYPE clike
          iv_obj_key          TYPE clike
          iv_function         TYPE clike     OPTIONAL
          it_params           TYPE ty_params OPTIONAL
          iv_mode             TYPE clike     DEFAULT c_mode_exclusive
          iv_wait             TYPE abap_bool DEFAULT abap_false
          iv_timeout          TYPE i         DEFAULT 10
          iv_client_dependent TYPE abap_bool DEFAULT abap_false
        RETURNING
          VALUE(rs_result)    TYPE ty_result,

      run_handler
        IMPORTING
          iv_wait_seconds    TYPE i DEFAULT 2
          iv_release_minutes TYPE i DEFAULT 0
        RETURNING
          VALUE(rv_log)      TYPE string,

      process_pending_requests,

      recover_locks,

      auto_release_locks
        IMPORTING
          iv_minutes TYPE i,

      read_sm12_locks
        IMPORTING
          iv_lock_object  TYPE char30   OPTIONAL
          iv_user         TYPE sy-uname OPTIONAL
        RETURNING
          VALUE(rt_locks) TYPE ty_sm12_locks,

      read_lock_requests
        IMPORTING
          iv_status         TYPE char10   OPTIONAL
          iv_obj_type       TYPE char30   OPTIONAL
          iv_obj_key        TYPE char50   OPTIONAL
          iv_user           TYPE sy-uname OPTIONAL
        RETURNING
          VALUE(rt_entries) TYPE ty_lock_entries.

  PROTECTED SECTION.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_interface,
        parameter TYPE c LENGTH 30,
        structure TYPE c LENGTH 132,
      END OF ty_interface,
      ty_interfaces TYPE STANDARD TABLE OF ty_interface WITH DEFAULT KEY.

    CONSTANTS c_guard_key TYPE c LENGTH 12 VALUE 'LOCK_HANDLER'.

    CLASS-METHODS:

      process_enqueue
        IMPORTING
          is_req TYPE z2ui5_t_05,

      process_dequeue
        IMPORTING
          is_req TYPE z2ui5_t_05,

      process_promote
        IMPORTING
          is_req TYPE z2ui5_t_05,

      finish_request
        IMPORTING
          is_req            TYPE z2ui5_t_05
          iv_status         TYPE char10
          iv_msg            TYPE clike
        RETURNING
          VALUE(rv_updated) TYPE abap_bool,

      release_holder
        IMPORTING
          is_holder TYPE z2ui5_t_05
          iv_status TYPE char10
          iv_msg    TYPE clike,

      call_lock_function
        IMPORTING
          iv_function       TYPE clike
          iv_req_id         TYPE guid_32
          iv_mode           TYPE char1
          iv_enqueue        TYPE abap_bool
          iv_wait           TYPE abap_bool DEFAULT abap_false
        EXPORTING
          ev_msg            TYPE string
        RETURNING
          VALUE(rv_success) TYPE abap_bool,

      create_value
        IMPORTING
          iv_type         TYPE clike
          iv_value        TYPE any
        RETURNING
          VALUE(rr_value) TYPE REF TO data,

      to_dequeue
        IMPORTING
          iv_function        TYPE clike
        RETURNING
          VALUE(rv_function) TYPE char30,

      is_compatible
        IMPORTING
          iv_held              TYPE char1
          iv_requested         TYPE char1
        RETURNING
          VALUE(rv_compatible) TYPE abap_bool,

      find_conflict
        IMPORTING
          iv_obj_type      TYPE clike
          iv_obj_key       TYPE clike
          iv_user          TYPE sy-uname
          iv_mode          TYPE char1
        RETURNING
          VALUE(rv_locker) TYPE sy-uname,

      has_open_work
        RETURNING
          VALUE(rv_open) TYPE abap_bool,

      guard_lock
        RETURNING
          VALUE(rv_subrc) TYPE sy-subrc,

      guard_unlock,

      " the registry table's name, read from its type - a namespace rename
      " rewrites the type, never a literal
      registry_name
        RETURNING
          VALUE(rv_name) TYPE rstable-tabname,

      is_handler_running
        RETURNING
          VALUE(rv_running) TYPE abap_bool,

      write_request
        IMPORTING
          iv_function      TYPE clike
          iv_process       TYPE char1
          iv_obj_type      TYPE clike
          iv_obj_key       TYPE clike
          iv_mode          TYPE char1
          iv_wait          TYPE abap_bool
          it_params        TYPE ty_params
        RETURNING
          VALUE(rv_req_id) TYPE guid_32,

      raise_event
        IMPORTING
          iv_client_dependent TYPE abap_bool,

      wait_for_result
        IMPORTING
          iv_req_id        TYPE guid_32
          iv_timeout       TYPE i
          iv_withdraw      TYPE abap_bool
        RETURNING
          VALUE(rs_result) TYPE ty_result.

ENDCLASS.

CLASS z2ui5_cl_lock_manager IMPLEMENTATION.

  METHOD request.

    DATA temp1 TYPE char1.
    DATA lv_process LIKE temp1.
    DATA temp2 TYPE char1.
    DATA lv_mode LIKE temp2.
    DATA temp3 TYPE string.
    DATA lv_error LIKE temp3.
      DATA lv_locker TYPE sy-uname.
    DATA lv_req_id TYPE guid_32.
    DATA temp4 TYPE xsdboolean.
    temp1 = to_upper( iv_process ).

    lv_process = temp1.

    temp2 = to_upper( iv_mode ).

    lv_mode = temp2.
    IF lv_mode IS INITIAL.
      lv_mode = c_mode_exclusive.
    ENDIF.


    IF lv_process <> c_process_enqueue AND lv_process <> c_process_dequeue AND lv_process <> c_process_promote.
      temp3 = `iv_process must be E (enqueue), D (dequeue) or R (promote)`.
    ELSEIF iv_obj_type IS INITIAL OR iv_obj_key IS INITIAL.
      temp3 = `iv_obj_type and iv_obj_key are mandatory`.
    ELSEIF lv_process = c_process_enqueue AND iv_function IS INITIAL.
      temp3 = `iv_function is mandatory for an enqueue`.
    ELSEIF lv_process = c_process_enqueue AND lv_mode <> c_mode_exclusive AND lv_mode <> c_mode_shared AND lv_mode <> c_mode_optimistic.
      temp3 = `iv_mode must be E (exclusive), S (shared) or O (optimistic)`.
    ELSE.
      CLEAR temp3.
    ENDIF.

    lv_error = temp3.

    IF lv_error IS NOT INITIAL.
      CLEAR rs_result.
      rs_result-msg_type = 'Error'.
      rs_result-msg_title = 'Invalid request'.
      rs_result-msg_desc = lv_error.
      RETURN.
    ENDIF.

    " A fast answer for the common case. It is not the decision: two requests
    " can pass it at the same moment, and the handler, which works through the
    " queue one request at a time, is the one that arbitrates.
    IF lv_process = c_process_enqueue.

      lv_locker = find_conflict(
        iv_obj_type = iv_obj_type
        iv_obj_key  = iv_obj_key
        iv_user     = sy-uname
        iv_mode     = lv_mode
      ).
      IF lv_locker IS NOT INITIAL.
        CLEAR rs_result.
        rs_result-msg_type = 'Error'.
        rs_result-msg_title = 'Object locked'.
        rs_result-msg_desc = |Locked by { lv_locker }|.
        RETURN.
      ENDIF.
    ENDIF.


    lv_req_id = write_request(
      iv_function = iv_function
      iv_process  = lv_process
      iv_obj_type = iv_obj_type
      iv_obj_key  = iv_obj_key
      iv_mode     = lv_mode
      iv_wait     = iv_wait
      it_params   = it_params
    ).

    " a running handler polls the queue anyway - the event is only needed to
    " start one
    IF is_handler_running( ) = abap_false.
      raise_event( iv_client_dependent ).
    ENDIF.


    temp4 = boolc( lv_process = c_process_enqueue ).
    rs_result = wait_for_result(
      iv_req_id   = lv_req_id
      iv_timeout  = iv_timeout
      iv_withdraw = temp4
    ).

  ENDMETHOD.


  METHOD run_handler.
    DATA temp4 TYPE i.
    DATA lv_wait LIKE temp4.

    IF guard_lock( ) <> 0.
      rv_log = `Another lock handler is already running in this client - nothing to do`.
      RETURN.
    ENDIF.

    " The kernel locks of a previous handler died with its session. Every row
    " the registry still calls ACTIVE is taken again before anything else.
    recover_locks( ).


    IF iv_wait_seconds > 0.
      temp4 = iv_wait_seconds.
    ELSE.
      temp4 = 1.
    ENDIF.

    lv_wait = temp4.

    DO.
      process_pending_requests( ).

      IF iv_release_minutes > 0.
        auto_release_locks( iv_release_minutes ).
      ENDIF.

      IF has_open_work( ) = abap_true.
        WAIT UP TO lv_wait SECONDS.
        CONTINUE.
      ENDIF.

      " Nothing pending and no lock held: stop, which frees the background
      " work process. The guard is released before the last look at the
      " queue - a request committed before that look is seen here, and one
      " committed after it finds the guard free and starts a new handler.
      guard_unlock( ).
      IF has_open_work( ) = abap_false OR guard_lock( ) <> 0.
        EXIT.
      ENDIF.
      recover_locks( ).
    ENDDO.

    rv_log = `No request pending and no lock held - handler stopped`.

  ENDMETHOD.


  METHOD process_pending_requests.

    " first come, first served: the queue order is the arbitration
    TYPES temp1 TYPE STANDARD TABLE OF z2ui5_t_05 WITH DEFAULT KEY.
DATA lt_requests TYPE temp1.
    DATA ls_req LIKE LINE OF lt_requests.
    SELECT * FROM z2ui5_t_05 INTO TABLE lt_requests
      WHERE status = c_status_pending
      ORDER BY created_at ASCENDING
      .


    LOOP AT lt_requests INTO ls_req.

      CASE ls_req-process.
        WHEN c_process_enqueue.
          process_enqueue( ls_req ).
        WHEN c_process_dequeue.
          process_dequeue( ls_req ).
        WHEN c_process_promote.
          process_promote( ls_req ).
        WHEN OTHERS.
          finish_request( is_req    = ls_req
                          iv_status = c_status_error
                          iv_msg    = |Unknown process '{ ls_req-process }'| ).
      ENDCASE.

      " _SCOPE = 1 keeps the kernel locks of this session through a COMMIT
      " WORK, so every decision is made visible to the waiting web request
      " at once
      COMMIT WORK.

    ENDLOOP.

  ENDMETHOD.


  METHOD process_enqueue.

    DATA lv_msg TYPE string.

    TYPES temp2 TYPE STANDARD TABLE OF z2ui5_t_05 WITH DEFAULT KEY.
DATA lt_active TYPE temp2.
    DATA temp7 LIKE sy-subrc.
    DATA ls_held LIKE LINE OF lt_active.
    DATA lv_kernel TYPE abap_bool.
    DATA temp1 LIKE sy-subrc.
    DATA temp5 TYPE xsdboolean.
    SELECT * FROM z2ui5_t_05 INTO TABLE lt_active
      WHERE obj_type = is_req-obj_type
        AND obj_key  = is_req-obj_key
        AND status   = c_status_active
      .

    " the registry keeps one lock per user, object and mode - asking again is
    " not an error, and it does not stack up a second lock either

    READ TABLE lt_active WITH KEY created_by = is_req-created_by lock_mode = is_req-lock_mode TRANSPORTING NO FIELDS.
    temp7 = sy-subrc.
    IF temp7 = 0.
      finish_request( is_req    = is_req
                      iv_status = c_status_done
                      iv_msg    = `Already locked by you` ).
      RETURN.
    ENDIF.


    LOOP AT lt_active INTO ls_held WHERE created_by <> is_req-created_by.
      IF is_compatible( iv_held      = ls_held-lock_mode
                        iv_requested = is_req-lock_mode ) = abap_false.
        finish_request( is_req    = is_req
                        iv_status = c_status_error
                        iv_msg    = |Locked by { ls_held-created_by }| ).
        RETURN.
      ENDIF.
    ENDLOOP.

    " The kernel lock is taken once per object and mode. The handler is its
    " only owner, so further holders of a shared or optimistic lock only
    " join the registry - the kernel would merely count them up.


    READ TABLE lt_active WITH KEY lock_mode = is_req-lock_mode TRANSPORTING NO FIELDS.
    temp1 = sy-subrc.

    temp5 = boolc( NOT temp1 = 0 ).
    lv_kernel = temp5.

    " AND stops at a false operand, so the kernel is asked only if needed
    IF     lv_kernel = abap_true
       AND call_lock_function( EXPORTING iv_function = is_req-function
                                         iv_req_id   = is_req-req_id
                                         iv_mode     = is_req-lock_mode
                                         iv_enqueue  = abap_true
                                         iv_wait     = is_req-lock_wait
                               IMPORTING ev_msg      = lv_msg ) = abap_false.
      finish_request( is_req    = is_req
                      iv_status = c_status_error
                      iv_msg    = lv_msg ).
      RETURN.
    ENDIF.

    IF finish_request( is_req    = is_req
                       iv_status = c_status_active
                       iv_msg    = |Locked in mode { is_req-lock_mode }| ) = abap_false
       AND lv_kernel = abap_true.
      " the requester stopped waiting and withdrew the request meanwhile -
      " nobody knows about this lock, so it must not stay
      call_lock_function( iv_function = to_dequeue( is_req-function )
                          iv_req_id   = is_req-req_id
                          iv_mode     = is_req-lock_mode
                          iv_enqueue  = abap_false ).
    ENDIF.

  ENDMETHOD.


  METHOD process_dequeue.

    TYPES temp3 TYPE STANDARD TABLE OF z2ui5_t_05 WITH DEFAULT KEY.
DATA lt_own TYPE temp3.
    DATA ls_own LIKE LINE OF lt_own.
    SELECT * FROM z2ui5_t_05 INTO TABLE lt_own
      WHERE obj_type   = is_req-obj_type
        AND obj_key    = is_req-obj_key
        AND created_by = is_req-created_by
        AND status     = c_status_active
      .

    IF lt_own IS INITIAL.
      finish_request( is_req    = is_req
                      iv_status = c_status_done
                      iv_msg    = `Nothing to release - no lock held` ).
      RETURN.
    ENDIF.


    LOOP AT lt_own INTO ls_own.
      release_holder( is_holder = ls_own
                      iv_status = c_status_released
                      iv_msg    = |Released by { is_req-created_by }| ).
    ENDLOOP.

    finish_request( is_req    = is_req
                    iv_status = c_status_done
                    iv_msg    = `Released` ).

  ENDMETHOD.


  METHOD process_promote.

    DATA lv_msg TYPE string.

    TYPES temp4 TYPE STANDARD TABLE OF z2ui5_t_05 WITH DEFAULT KEY.
DATA lt_active TYPE temp4.
    DATA temp10 LIKE sy-subrc.
    DATA temp11 LIKE sy-subrc.
    DATA ls_own TYPE z2ui5_t_05.
      DATA lv_lost TYPE z2ui5_t_05-msg_text.
      DATA temp12 TYPE string.
    DATA ls_held LIKE LINE OF lt_active.
    SELECT * FROM z2ui5_t_05 INTO TABLE lt_active
      WHERE obj_type = is_req-obj_type
        AND obj_key  = is_req-obj_key
        AND status   = c_status_active
      .

    " a repeated promote after a timeout finds the work already done


    temp11 = sy-subrc.
    READ TABLE lt_active WITH KEY created_by = is_req-created_by lock_mode = c_mode_exclusive TRANSPORTING NO FIELDS.
    temp10 = sy-subrc.
    sy-subrc = temp11.
    IF temp10 = 0.
      finish_request( is_req    = is_req
                      iv_status = c_status_done
                      iv_msg    = `Already exclusive` ).
      RETURN.
    ENDIF.


    READ TABLE lt_active INTO ls_own
      WITH KEY created_by = is_req-created_by
               lock_mode  = c_mode_optimistic.
    IF sy-subrc <> 0.
      " the optimistic lock may have been invalidated by someone faster

      SELECT msg_text FROM z2ui5_t_05 INTO lv_lost
        WHERE obj_type   = is_req-obj_type
          AND obj_key    = is_req-obj_key
          AND created_by = is_req-created_by
          AND status     = c_status_lost
        ORDER BY created_at DESCENDING

        UP TO 1 ROWS.
      ENDSELECT.

      IF lv_lost IS NOT INITIAL.
        temp12 = |Optimistic lock lost: { lv_lost }|.
      ELSE.
        temp12 = `No optimistic lock held - enqueue in mode O first`.
      ENDIF.
      finish_request( is_req    = is_req
                      iv_status = c_status_error
                      iv_msg    = temp12 ).
      RETURN.
    ENDIF.

    " other optimistic holders do not block a promotion - they lose to it

    LOOP AT lt_active INTO ls_held
         WHERE created_by <> is_req-created_by
           AND lock_mode  <> c_mode_optimistic.
      finish_request( is_req    = is_req
                      iv_status = c_status_error
                      iv_msg    = |Locked by { ls_held-created_by }| ).
      RETURN.
    ENDLOOP.

    " mode R converts the optimistic kernel lock into an exclusive one
    IF call_lock_function( EXPORTING iv_function = ls_own-function
                                     iv_req_id   = ls_own-req_id
                                     iv_mode     = 'R'
                                     iv_enqueue  = abap_true
                                     iv_wait     = is_req-lock_wait
                           IMPORTING ev_msg      = lv_msg ) = abap_false.
      finish_request( is_req    = is_req
                      iv_status = c_status_error
                      iv_msg    = lv_msg ).
      RETURN.
    ENDIF.

    UPDATE z2ui5_t_05 SET lock_mode = c_mode_exclusive,
                          msg_text  = 'Promoted to exclusive'
      WHERE req_id = ls_own-req_id.

    " the kernel deletes the optimistic locks of other owners on promotion;
    " here all of them belong to the handler, so the registry does it
    lv_msg = |Changed by { is_req-created_by } first|.
    LOOP AT lt_active INTO ls_held
         WHERE created_by <> is_req-created_by
           AND lock_mode  =  c_mode_optimistic.
      UPDATE z2ui5_t_05 SET status   = c_status_lost,
                            msg_text = lv_msg
        WHERE req_id = ls_held-req_id.
    ENDLOOP.

    finish_request( is_req    = is_req
                    iv_status = c_status_done
                    iv_msg    = `Promoted to exclusive` ).

  ENDMETHOD.


  METHOD finish_request.

    DATA lv_msg TYPE char200.
    DATA temp6 TYPE xsdboolean.
    lv_msg = iv_msg.

    " only a request that is still pending - the requester may have
    " withdrawn it after its timeout
    UPDATE z2ui5_t_05 SET status   = iv_status,
                          msg_text = lv_msg
      WHERE req_id = is_req-req_id
        AND status = c_status_pending.


    temp6 = boolc( sy-dbcnt = 1 ).
    rv_updated = temp6.

  ENDMETHOD.


  METHOD release_holder.

    DATA lv_msg TYPE char200.
    DATA lv_shared TYPE abap_bool.
    DATA temp2 TYPE z2ui5_t_05-obj_type.
      DATA lv_optimistic TYPE abap_bool.
      DATA temp3 TYPE z2ui5_t_05-obj_type.
    lv_msg = iv_msg.

    " the kernel lock goes with the last holder of its object and mode


    SELECT SINGLE obj_type FROM z2ui5_t_05 INTO temp2
      WHERE obj_type  = is_holder-obj_type
        AND obj_key   = is_holder-obj_key
        AND lock_mode = is_holder-lock_mode
        AND status    = c_status_active
        AND req_id   <> is_holder-req_id
      .
CLEAR lv_shared.
IF sy-subrc = 0.
  lv_shared = abap_true.
ENDIF. "#EC CI_NOORDER

    IF lv_shared = abap_false.
      call_lock_function( iv_function = to_dequeue( is_holder-function )
                          iv_req_id   = is_holder-req_id
                          iv_mode     = is_holder-lock_mode
                          iv_enqueue  = abap_false ).
    ENDIF.

    " An exclusive lock may be a promoted optimistic one. Whatever the kernel
    " kept of the optimistic part must not outlive it - dequeuing a lock that
    " does not exist is a no-op.
    IF is_holder-lock_mode = c_mode_exclusive.


      SELECT SINGLE obj_type FROM z2ui5_t_05 INTO temp3
        WHERE obj_type  = is_holder-obj_type
          AND obj_key   = is_holder-obj_key
          AND lock_mode = c_mode_optimistic
          AND status    = c_status_active
        .
CLEAR lv_optimistic.
IF sy-subrc = 0.
  lv_optimistic = abap_true.
ENDIF. "#EC CI_NOORDER
      IF lv_optimistic = abap_false.
        call_lock_function( iv_function = to_dequeue( is_holder-function )
                            iv_req_id   = is_holder-req_id
                            iv_mode     = c_mode_optimistic
                            iv_enqueue  = abap_false ).
      ENDIF.
    ENDIF.

    UPDATE z2ui5_t_05 SET status   = iv_status,
                          msg_text = lv_msg
      WHERE req_id = is_holder-req_id.

  ENDMETHOD.


  METHOD recover_locks.

    TYPES temp5 TYPE STANDARD TABLE OF z2ui5_t_05 WITH DEFAULT KEY.
DATA lt_taken TYPE temp5.
    DATA lv_msg   TYPE string.
    DATA lv_text  TYPE char200.

    TYPES temp6 TYPE STANDARD TABLE OF z2ui5_t_05 WITH DEFAULT KEY.
DATA lt_active TYPE temp6.
    DATA ls_row LIKE LINE OF lt_active.
      DATA temp14 LIKE sy-subrc.
    SELECT * FROM z2ui5_t_05 INTO TABLE lt_active
      WHERE status = c_status_active
      ORDER BY created_at ASCENDING
      .


    LOOP AT lt_active INTO ls_row.

      " one kernel lock per object and mode, as in process_enqueue

      READ TABLE lt_taken WITH KEY obj_type = ls_row-obj_type obj_key = ls_row-obj_key lock_mode = ls_row-lock_mode TRANSPORTING NO FIELDS.
      temp14 = sy-subrc.
      IF temp14 = 0.
        CONTINUE.
      ENDIF.
      APPEND ls_row TO lt_taken.

      IF call_lock_function( EXPORTING iv_function = ls_row-function
                                       iv_req_id   = ls_row-req_id
                                       iv_mode     = ls_row-lock_mode
                                       iv_enqueue  = abap_true
                             IMPORTING ev_msg      = lv_msg ) = abap_false.
        " someone took the object while no handler was running
        lv_text = |Lost while no handler ran - { lv_msg }|.
        UPDATE z2ui5_t_05 SET status   = c_status_lost,
                              msg_text = lv_text
          WHERE obj_type  = ls_row-obj_type
            AND obj_key   = ls_row-obj_key
            AND lock_mode = ls_row-lock_mode
            AND status    = c_status_active.
      ENDIF.

    ENDLOOP.

    COMMIT WORK.

  ENDMETHOD.


  METHOD auto_release_locks.

    DATA lv_now TYPE timestampl.
    DATA lv_threshold TYPE tzntstmpl.
    TYPES temp7 TYPE STANDARD TABLE OF z2ui5_t_05 WITH DEFAULT KEY.
DATA lt_old TYPE temp7.
    DATA ls_old LIKE LINE OF lt_old.
    GET TIME STAMP FIELD lv_now.

    lv_threshold = cl_abap_tstmp=>subtractsecs(
      tstmp = lv_now
      secs  = iv_minutes * 60
    ).



    SELECT * FROM z2ui5_t_05 INTO TABLE lt_old
      WHERE status     = c_status_active
        AND created_at < lv_threshold
      .


    LOOP AT lt_old INTO ls_old.
      release_holder( is_holder = ls_old
                      iv_status = c_status_released
                      iv_msg    = |Auto-released after { iv_minutes } minutes| ).
      COMMIT WORK.
    ENDLOOP.

  ENDMETHOD.


  METHOD call_lock_function.

    DATA lt_bind      TYPE abap_func_parmbind_tab.
    DATA lt_exception TYPE abap_func_excpbind_tab.
    DATA lt_interface TYPE ty_interfaces.
    DATA ls_interface TYPE ty_interface.
    DATA lv_type      TYPE string.
    DATA lv_subrc     TYPE sy-subrc.
    DATA temp16 TYPE char30.
    DATA lv_function LIKE temp16.
TYPES BEGIN OF temp17.
TYPES name TYPE z2ui5_t_06-name.
TYPES type TYPE z2ui5_t_06-type.
TYPES value TYPE z2ui5_t_06-value.
TYPES END OF temp17.
    TYPES temp8 TYPE STANDARD TABLE OF temp17 WITH DEFAULT KEY.
DATA lt_params TYPE temp8.
        DATA ls_param LIKE LINE OF lt_params.
          DATA temp18 TYPE char30.
          DATA lv_name LIKE temp18.
          DATA temp19 TYPE abap_func_parmbind.
          DATA temp20 TYPE abap_func_parmbind.
          DATA temp21 LIKE sy-subrc.
          DATA temp22 LIKE sy-subrc.
            DATA temp23 TYPE abap_func_parmbind.
          DATA temp24 LIKE sy-subrc.
          DATA temp25 LIKE sy-subrc.
            DATA temp26 TYPE abap_func_parmbind.
          DATA temp27 TYPE abap_func_excpbind.
          DATA temp28 TYPE abap_func_excpbind.
        DATA temp29 TYPE abap_func_excpbind.
        DATA lx_error TYPE REF TO cx_root.

    CLEAR ev_msg.

    temp16 = to_upper( iv_function ).

    lv_function = temp16.

    " the parameters are always the ones the lock was taken with, so a
    " release or a recovery hits exactly the same lock argument



    SELECT name type value FROM z2ui5_t_06 INTO TABLE lt_params
      WHERE req_id = iv_req_id
      .

    " the interface says which parameters exist and how each one is typed
    SELECT parameter structure FROM fupararef INTO TABLE lt_interface
      WHERE funcname  = lv_function
        AND r3state   = 'A'
        AND paramtype = 'I'
      .

    TRY.


        LOOP AT lt_params INTO ls_param.

          temp18 = to_upper( condense( ls_param-name ) ).

          lv_name = temp18.
          " a key field must reach the module in its own type - a string
          " where VBAK-VBELN is expected fails the call
          lv_type = ls_param-type.
          IF lv_type IS INITIAL.
            READ TABLE lt_interface INTO ls_interface WITH KEY parameter = lv_name.
            IF sy-subrc = 0.
              lv_type = ls_interface-structure.
            ENDIF.
          ENDIF.

          CLEAR temp19.
          temp19-name = lv_name.
          temp19-kind = abap_func_exporting.
          temp19-value = create_value( iv_type = lv_type iv_value = ls_param-value ).
          INSERT temp19 INTO TABLE lt_bind.
        ENDLOOP.

        " one MODE_<table> parameter per base table of the lock object
        LOOP AT lt_interface INTO ls_interface WHERE parameter CP 'MODE_*'.

          CLEAR temp20.
          temp20-name = ls_interface-parameter.
          temp20-kind = abap_func_exporting.
          temp20-value = create_value( iv_type = `CHAR1` iv_value = iv_mode ).
          INSERT temp20 INTO TABLE lt_bind.
        ENDLOOP.

        IF iv_enqueue = abap_true.
          " _SCOPE = 1: the lock belongs to this session alone and is not
          " handed to an update task - with the default 2 the next COMMIT
          " WORK would release it


          temp22 = sy-subrc.
          READ TABLE lt_interface WITH KEY parameter = '_SCOPE' TRANSPORTING NO FIELDS.
          temp21 = sy-subrc.
          sy-subrc = temp22.
          IF temp21 = 0.

            CLEAR temp23.
            temp23-name = '_SCOPE'.
            temp23-kind = abap_func_exporting.
            temp23-value = create_value( iv_type = `CHAR1` iv_value = '1' ).
            INSERT temp23 INTO TABLE lt_bind.
          ENDIF.
          " _WAIT = X: on a collision the kernel retries for a while before
          " it gives up


          temp25 = sy-subrc.
          READ TABLE lt_interface WITH KEY parameter = '_WAIT' TRANSPORTING NO FIELDS.
          temp24 = sy-subrc.
          sy-subrc = temp25.
          IF iv_wait = abap_true AND temp24 = 0.

            CLEAR temp26.
            temp26-name = '_WAIT'.
            temp26-kind = abap_func_exporting.
            temp26-value = create_value( iv_type = `CHAR1` iv_value = abap_true ).
            INSERT temp26 INTO TABLE lt_bind.
          ENDIF.

          CLEAR temp27.
          temp27-name = 'FOREIGN_LOCK'.
          temp27-value = 1.
          INSERT temp27 INTO TABLE lt_exception.

          CLEAR temp28.
          temp28-name = 'SYSTEM_FAILURE'.
          temp28-value = 2.
          INSERT temp28 INTO TABLE lt_exception.
        ENDIF.

        CLEAR temp29.
        temp29-name = 'OTHERS'.
        temp29-value = 3.
        INSERT temp29 INTO TABLE lt_exception.

        CALL FUNCTION lv_function
          PARAMETER-TABLE lt_bind
          EXCEPTION-TABLE lt_exception.
        lv_subrc = sy-subrc.

        CASE lv_subrc.
          WHEN 0.
            rv_success = abap_true.
          WHEN 1.
            " the kernel names the holder in the first message variable
            ev_msg = |Locked by { sy-msgv1 }|.
          WHEN OTHERS.
            IF sy-msgid IS NOT INITIAL.
              MESSAGE ID sy-msgid TYPE 'E' NUMBER sy-msgno
                WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO ev_msg.
            ELSE.
              ev_msg = |{ lv_function } failed with sy-subrc { lv_subrc }|.
            ENDIF.
        ENDCASE.


      CATCH cx_root INTO lx_error.
        ev_msg = |{ lv_function }: { lx_error->get_text( ) }|.
    ENDTRY.

  ENDMETHOD.


  METHOD create_value.

    FIELD-SYMBOLS <lv_value> TYPE any.

    IF iv_type IS INITIAL.
      CREATE DATA rr_value TYPE string.
    ELSE.
      TRY.
          CREATE DATA rr_value TYPE (iv_type).
        CATCH cx_sy_create_data_error.
          CREATE DATA rr_value TYPE string.
      ENDTRY.
    ENDIF.

    ASSIGN rr_value->* TO <lv_value>.
    <lv_value> = iv_value.

  ENDMETHOD.


  METHOD to_dequeue.

    rv_function = replace( val  = to_upper( iv_function )
                           sub  = `ENQUEUE_`
                           with = `DEQUEUE_` ).

  ENDMETHOD.


  METHOD is_compatible.

    " between different owners only shared and optimistic locks coexist -
    " an optimistic lock collides like a shared one
    DATA temp7 TYPE xsdboolean.
    temp7 = boolc( ( iv_held = c_mode_shared OR iv_held = c_mode_optimistic ) AND ( iv_requested = c_mode_shared OR iv_requested = c_mode_optimistic ) ).
    rv_compatible = temp7.

  ENDMETHOD.


  METHOD find_conflict.

    TYPES: BEGIN OF temp30,
            created_by TYPE z2ui5_t_05-created_by,
            lock_mode TYPE z2ui5_t_05-lock_mode,
          END OF temp30.
    TYPES temp9 TYPE STANDARD TABLE OF temp30 WITH DEFAULT KEY.
DATA lt_held TYPE temp9.
    DATA ls_held LIKE LINE OF lt_held.
    SELECT created_by lock_mode FROM z2ui5_t_05 INTO TABLE lt_held
      WHERE obj_type    = iv_obj_type
        AND obj_key     = iv_obj_key
        AND status      = c_status_active
        AND created_by <> iv_user
      .


    LOOP AT lt_held INTO ls_held.
      IF is_compatible( iv_held      = ls_held-lock_mode
                        iv_requested = iv_mode ) = abap_false.
        rv_locker = ls_held-created_by.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD has_open_work.

    DATA temp31 TYPE z2ui5_t_05-status.
    SELECT SINGLE status FROM z2ui5_t_05 INTO temp31
      WHERE status = c_status_pending
         OR status = c_status_active
      .
CLEAR rv_open.
IF sy-subrc = 0.
  rv_open = abap_true.
ENDIF. "#EC CI_NOORDER

  ENDMETHOD.


  METHOD guard_lock.

    " One handler per client. The guard is an ordinary exclusive lock on the
    " registry table, so a second job started by the same event sees it and
    " stops - and so can a web request that wants to know whether to raise
    " the event at all.
    " typed like the module's parameters - a static call checks them too
    DATA lv_tabname TYPE rstable-tabname.
    DATA lv_varkey  TYPE rstable-varkey.
    lv_tabname = registry_name( ).
    lv_varkey  = |{ sy-mandt }{ c_guard_key }|.

    CALL FUNCTION 'ENQUEUE_E_TABLE'
      EXPORTING
        mode_rstable   = 'E'
        tabname        = lv_tabname
        varkey         = lv_varkey
        _scope         = '1'
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    rv_subrc = sy-subrc.

  ENDMETHOD.


  METHOD registry_name.

    DATA ls_registry TYPE z2ui5_t_05.
    rv_name = cl_abap_typedescr=>describe_by_data( ls_registry )->get_relative_name( ).

  ENDMETHOD.


  METHOD guard_unlock.

    DATA lv_tabname TYPE rstable-tabname.
    DATA lv_varkey  TYPE rstable-varkey.
    lv_tabname = registry_name( ).
    lv_varkey  = |{ sy-mandt }{ c_guard_key }|.

    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        mode_rstable = 'E'
        tabname      = lv_tabname
        varkey       = lv_varkey
        _scope       = '1'.

  ENDMETHOD.


  METHOD is_handler_running.

    CASE guard_lock( ).
      WHEN 0.
        guard_unlock( ).
        rv_running = abap_false.
      WHEN 1.
        rv_running = abap_true.
      WHEN OTHERS.
        " the enqueue server did not answer - raising the event once too
        " often costs nothing, a missed start costs the request
        rv_running = abap_false.
    ENDCASE.

  ENDMETHOD.


  METHOD write_request.
    DATA temp32 TYPE z2ui5_t_05.
    DATA ls_req LIKE temp32.
    DATA ls_p TYPE ty_param.
    DATA ls_row TYPE z2ui5_t_06.

    CALL FUNCTION 'GUID_CREATE'
      IMPORTING
        ev_guid_32 = rv_req_id.


    CLEAR temp32.
    temp32-req_id = rv_req_id.
    temp32-obj_type = iv_obj_type.
    temp32-obj_key = iv_obj_key.
    temp32-function = to_upper( iv_function ).
    temp32-process = iv_process.
    temp32-lock_mode = iv_mode.
    temp32-lock_wait = iv_wait.
    temp32-created_by = sy-uname.
    temp32-status = c_status_pending.

    ls_req = temp32.
    GET TIME STAMP FIELD ls_req-created_at.

    INSERT z2ui5_t_05 FROM ls_req.



    LOOP AT it_params INTO ls_p.
      CLEAR ls_row.
      ls_row-req_id = rv_req_id.
      ls_row-name   = to_upper( ls_p-name ).
      ls_row-type   = to_upper( ls_p-type ).
      ls_row-value  = ls_p-value.
      INSERT z2ui5_t_06 FROM ls_row.
    ENDLOOP.

    " the handler runs in another session and must see the row
    COMMIT WORK.

  ENDMETHOD.


  METHOD raise_event.

    DATA temp33 TYPE btceventid.
    DATA lv_event LIKE temp33.
    IF iv_client_dependent = abap_true.
      temp33 = |LOCK_HANDLER_{ sy-mandt }|.
    ELSE.
      temp33 = 'LOCK_HANDLER'.
    ENDIF.

    lv_event = temp33.

    CALL FUNCTION 'BP_EVENT_RAISE'
      EXPORTING
        eventid = lv_event
      EXCEPTIONS
        OTHERS  = 1.

  ENDMETHOD.


  METHOD wait_for_result.

    DATA ls_row TYPE ty_lock_entry.
    DATA temp34 TYPE z2ui5_cl_lock_manager=>ty_result.
    DATA temp4 TYPE z2ui5_cl_lock_manager=>ty_result.
    DATA temp1 TYPE z2ui5_cl_lock_manager=>ty_result.
    DATA temp2 TYPE z2ui5_cl_lock_manager=>ty_result.

    " read before every wait, not only after it: with a timeout of 0 the
    " request was never read - no answer, an empty error text, and an
    " enqueue left queued instead of withdrawn
    DO.
      CLEAR ls_row.
      SELECT SINGLE status msg_text FROM z2ui5_t_05 INTO CORRESPONDING FIELDS OF ls_row
        WHERE req_id = iv_req_id
        . "#EC CI_NOORDER
      IF sy-subrc <> 0.
        CLEAR rs_result.
        rs_result-msg_type = 'Error'.
        rs_result-msg_title = 'Error'.
        rs_result-msg_desc = 'The request is no longer in the lock queue'.
        RETURN.
      ENDIF.

      IF ls_row-status <> c_status_pending OR sy-index > iv_timeout.
        EXIT.
      ENDIF.
      WAIT UP TO 1 SECONDS.
    ENDDO.

    IF ls_row-status = c_status_pending AND iv_withdraw = abap_true.
      " A lock granted after the requester gave up would be held by nobody
      " who knows about it. Withdraw the request - unless the handler got to
      " it in the very last moment, then its answer counts.
      UPDATE z2ui5_t_05 SET status   = c_status_error,
                            msg_text = 'Withdrawn - the background handler did not respond in time'
        WHERE req_id = iv_req_id
          AND status = c_status_pending.
      IF sy-dbcnt = 1.
        COMMIT WORK.
        CLEAR rs_result.
        rs_result-msg_type = 'Error'.
        rs_result-msg_title = 'Timeout'.
        rs_result-msg_desc = 'Background handler did not respond in time - request withdrawn'.
        RETURN.
      ENDIF.
      SELECT SINGLE status msg_text FROM z2ui5_t_05 INTO CORRESPONDING FIELDS OF ls_row
        WHERE req_id = iv_req_id
        . "#EC CI_NOORDER
    ENDIF.


    CLEAR temp34.
    temp34-msg_type = 'Success'.
    temp34-msg_title = 'OK'.
    temp34-msg_desc = ls_row-msg_text.

    CLEAR temp4.
    temp4-msg_type = 'Error'.
    temp4-msg_title = 'Timeout'.
    temp4-msg_desc = 'Background handler did not respond in time - the request stays queued'.

    CLEAR temp1.
    temp1-msg_type = 'Error'.
    temp1-msg_title = 'Error'.
    temp1-msg_desc = ls_row-msg_text.

    CASE ls_row-status.
      WHEN c_status_active OR c_status_done.
        temp2 = temp34.
      WHEN c_status_pending.
        temp2 = temp4.
      WHEN OTHERS.
        temp2 = temp1.
    ENDCASE.
    rs_result = temp2.

  ENDMETHOD.


  METHOD read_sm12_locks.
        DATA lt_locks TYPE z2ui5_cl_lock_context=>ty_t_lock.
    DATA temp35 TYPE z2ui5_cl_lock_manager=>ty_sm12_locks.
    DATA ls_lock LIKE LINE OF lt_locks.
      DATA temp36 LIKE LINE OF temp35.

    TRY.

        lt_locks = z2ui5_cl_lock_context=>lock_read(
          lock_object = iv_lock_object
          user        = iv_user
        ).
      CATCH cx_root.
        RETURN.
    ENDTRY.


    CLEAR temp35.

    LOOP AT lt_locks INTO ls_lock.

      temp36-lock_object = ls_lock-lock_object.
      temp36-argument = ls_lock-argument.
      temp36-user = ls_lock-user.
      temp36-mode = ls_lock-mode.
      temp36-client = ls_lock-client.
      temp36-date = ls_lock-date.
      temp36-time = ls_lock-time.
      INSERT temp36 INTO TABLE temp35.
    ENDLOOP.
    rt_locks = temp35.

  ENDMETHOD.


  METHOD read_lock_requests.

    " An empty filter matches every row: each one is a range that stays empty
    " when its parameter is initial. (A host expression such as
    " @iv_status IS INITIAL in the WHERE clause needs 7.54.)
    TYPES temp10 TYPE RANGE OF char10.
DATA lr_status   TYPE temp10.
    TYPES temp11 TYPE RANGE OF char30.
DATA lr_obj_type TYPE temp11.
    TYPES temp12 TYPE RANGE OF char50.
DATA lr_obj_key  TYPE temp12.
    TYPES temp13 TYPE RANGE OF sy-uname.
DATA lr_user     TYPE temp13.
    DATA ls_status   LIKE LINE OF lr_status.
    DATA ls_obj_type LIKE LINE OF lr_obj_type.
    DATA ls_obj_key  LIKE LINE OF lr_obj_key.
    DATA ls_user     LIKE LINE OF lr_user.

    IF iv_status IS NOT INITIAL.
      ls_status-sign   = 'I'.
      ls_status-option = 'EQ'.
      ls_status-low    = iv_status.
      APPEND ls_status TO lr_status.
    ENDIF.
    IF iv_obj_type IS NOT INITIAL.
      ls_obj_type-sign   = 'I'.
      ls_obj_type-option = 'EQ'.
      ls_obj_type-low    = iv_obj_type.
      APPEND ls_obj_type TO lr_obj_type.
    ENDIF.
    IF iv_obj_key IS NOT INITIAL.
      ls_obj_key-sign   = 'I'.
      ls_obj_key-option = 'EQ'.
      ls_obj_key-low    = iv_obj_key.
      APPEND ls_obj_key TO lr_obj_key.
    ENDIF.
    IF iv_user IS NOT INITIAL.
      ls_user-sign   = 'I'.
      ls_user-option = 'EQ'.
      ls_user-low    = iv_user.
      APPEND ls_user TO lr_user.
    ENDIF.

    SELECT req_id obj_type obj_key function process lock_mode
           status created_by created_at msg_text
      FROM z2ui5_t_05 INTO TABLE rt_entries
      WHERE status     IN lr_status
        AND obj_type   IN lr_obj_type
        AND obj_key    IN lr_obj_key
        AND created_by IN lr_user
      ORDER BY created_at DESCENDING
      .

  ENDMETHOD.

ENDCLASS.
