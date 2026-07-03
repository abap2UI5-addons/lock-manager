CLASS z2ui5_cl_lock_manager DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_param,
        name  TYPE char30,
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
        function   TYPE char61,
        process    TYPE char1,
        status     TYPE char10,
        created_by TYPE sy-uname,
        created_at TYPE timestamp,
        msg_text   TYPE char200,
      END OF ty_lock_entry,
      ty_lock_entries TYPE STANDARD TABLE OF ty_lock_entry WITH DEFAULT KEY.

    CONSTANTS:
      c_process_enqueue TYPE char1  VALUE 'E',
      c_process_dequeue TYPE char1  VALUE 'D',
      c_status_pending  TYPE char10 VALUE 'PENDING',
      c_status_done     TYPE char10 VALUE 'DONE',
      c_status_error    TYPE char10 VALUE 'ERROR',
      c_status_released TYPE char10 VALUE 'RELEASED'.

    CLASS-METHODS:

      request
        IMPORTING
          iv_function         TYPE clike
          iv_process          TYPE clike
          iv_obj_type         TYPE clike
          iv_obj_key          TYPE clike
          it_params           TYPE ty_params
          iv_client_dependent TYPE abap_bool DEFAULT abap_false
        RETURNING
          VALUE(rs_result)    TYPE ty_result,

      process_pending_requests,

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

    CLASS-METHODS:

      check_existing_lock
        IMPORTING
          iv_obj_type      TYPE char30
          iv_obj_key       TYPE char50
        RETURNING
          VALUE(rv_locker) TYPE sy-uname,

      write_request
        IMPORTING
          iv_function      TYPE char61
          iv_process       TYPE char1
          iv_obj_type      TYPE char30
          iv_obj_key       TYPE char50
          it_params        TYPE ty_params
        RETURNING
          VALUE(rv_req_id) TYPE guid_32,

      raise_event
        IMPORTING
          iv_client_dependent TYPE abap_bool,

      wait_for_result
        IMPORTING
          iv_req_id        TYPE guid_32
        RETURNING
          VALUE(rs_result) TYPE ty_result.

ENDCLASS.

CLASS z2ui5_cl_lock_manager IMPLEMENTATION.

  METHOD request.

    IF iv_function IS INITIAL OR iv_process IS INITIAL.
      rs_result = VALUE #(
        msg_type  = 'Error'
        msg_title = 'Missing parameters'
        msg_desc  = 'iv_function and iv_process are mandatory'
      ).
      RETURN.
    ENDIF.

    IF iv_process = c_process_enqueue.
      DATA(lv_locker) = check_existing_lock(
        iv_obj_type = iv_obj_type
        iv_obj_key  = iv_obj_key
      ).

      IF lv_locker IS NOT INITIAL.
        rs_result = VALUE #(
          msg_type  = 'Error'
          msg_title = 'Object locked'
          msg_desc  = |Locked by: { lv_locker }|
        ).
        RETURN.
      ENDIF.
    ENDIF.

    DATA(lv_req_id) = write_request(
      iv_function = iv_function
      iv_process  = iv_process
      iv_obj_type = iv_obj_type
      iv_obj_key  = iv_obj_key
      it_params   = it_params
    ).

    raise_event( iv_client_dependent = iv_client_dependent ).

    rs_result = wait_for_result( iv_req_id = lv_req_id ).

  ENDMETHOD.


  METHOD process_pending_requests.

    SELECT * FROM z2ui5_t_05
      INTO TABLE @DATA(lt_requests)
      WHERE status = @c_status_pending
      ORDER BY created_at ASCENDING.

    LOOP AT lt_requests INTO DATA(ls_req).

      SELECT * FROM z2ui5_t_06
        INTO TABLE @DATA(lt_params)
        WHERE req_id = @ls_req-req_id.

      DATA(lt_lock_params) = VALUE z2ui5_cl_util=>ty_t_lock_param(
        FOR ls_p IN lt_params (
          name  = ls_p-name
          value = ls_p-value
        )
      ).

      DATA(lv_success) = COND abap_bool(
        WHEN ls_req-process = c_process_dequeue
        THEN z2ui5_cl_util=>lock_delete(
               val     = ls_req-function
               t_param = lt_lock_params )
        ELSE z2ui5_cl_util=>lock_set(
               val     = ls_req-function
               t_param = lt_lock_params ) ).

      IF lv_success = abap_true.
        ls_req-status = c_status_done.
      ELSE.
        ls_req-status = c_status_error.
      ENDIF.

      UPDATE z2ui5_t_05 FROM ls_req.

    ENDLOOP.

  ENDMETHOD.


  METHOD auto_release_locks.

    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    DATA(lv_threshold) = cl_abap_tstmp=>subtractsecs(
      tstmp = lv_now
      secs  = iv_minutes * 60
    ).

    SELECT * FROM z2ui5_t_05
      INTO TABLE @DATA(lt_old)
      WHERE status     = @c_status_done
        AND process    = @c_process_enqueue
        AND created_at < @lv_threshold.

    LOOP AT lt_old INTO DATA(ls_old).
      z2ui5_cl_util=>lock_delete( ls_old-function ).
      UPDATE z2ui5_t_05 SET status = @c_status_released
        WHERE req_id = @ls_old-req_id.
    ENDLOOP.

  ENDMETHOD.


  METHOD read_sm12_locks.

    TRY.
        DATA(lt_locks) = z2ui5_cl_util=>lock_read(
          lock_object = iv_lock_object
          user        = iv_user
        ).
      CATCH cx_root.
        RETURN.
    ENDTRY.

    rt_locks = VALUE #(
      FOR ls_lock IN lt_locks (
        lock_object = ls_lock-lock_object
        argument    = ls_lock-argument
        user        = ls_lock-user
        mode        = ls_lock-mode
        client      = ls_lock-client
        date        = ls_lock-date
        time        = ls_lock-time
      )
    ).

  ENDMETHOD.


  METHOD read_lock_requests.

    SELECT req_id, obj_type, obj_key, function, process,
           status, created_by, created_at, msg_text
      FROM z2ui5_t_05
      WHERE ( @iv_status   IS INITIAL OR status     = @iv_status   )
        AND ( @iv_obj_type IS INITIAL OR obj_type   = @iv_obj_type )
        AND ( @iv_obj_key  IS INITIAL OR obj_key    = @iv_obj_key  )
        AND ( @iv_user     IS INITIAL OR created_by = @iv_user     )
      ORDER BY created_at DESCENDING
            INTO TABLE @rt_entries.

  ENDMETHOD.


  METHOD check_existing_lock.

    SELECT SINGLE created_by FROM z2ui5_t_05
      INTO @rv_locker
      WHERE obj_type = @iv_obj_type
        AND obj_key  = @iv_obj_key
        AND process  = @c_process_enqueue
        AND status   = @c_status_done.

  ENDMETHOD.


  METHOD write_request.

    CALL FUNCTION 'GUID_CREATE'
      IMPORTING
        ev_guid_32 = rv_req_id.

    DATA(ls_req) = VALUE z2ui5_t_05(
      req_id     = rv_req_id
      obj_type   = iv_obj_type
      obj_key    = iv_obj_key
      function   = iv_function
      process    = iv_process
      created_by = sy-uname
      status     = c_status_pending
    ).
    GET TIME STAMP FIELD ls_req-created_at.

    INSERT z2ui5_t_05 FROM ls_req.

    LOOP AT it_params INTO DATA(ls_p).
      INSERT z2ui5_t_06 FROM @( VALUE #(
        req_id = rv_req_id
        name   = ls_p-name
        type   = ls_p-type
        value  = ls_p-value
      ) ).
    ENDLOOP.

    COMMIT WORK.

  ENDMETHOD.


  METHOD raise_event.

    DATA(lv_event) = COND btceventid(
      WHEN iv_client_dependent = abap_true
      THEN |LOCK_HANDLER_{ sy-mandt }|
      ELSE 'LOCK_HANDLER'
    ).

    CALL FUNCTION 'BP_EVENT_RAISE'
      EXPORTING
        eventid = lv_event
      EXCEPTIONS
        OTHERS  = 1.

  ENDMETHOD.


  METHOD wait_for_result.

    DO 10 TIMES.
      WAIT UP TO 1 SECONDS.

      SELECT SINGLE status, msg_text FROM z2ui5_t_05
        INTO @DATA(ls_result)
        WHERE req_id = @iv_req_id.

      IF ls_result-status <> c_status_pending.
        EXIT.
      ENDIF.
    ENDDO.

    rs_result = COND #(
      WHEN ls_result-status = c_status_done
      THEN VALUE #(
             msg_type  = 'Success'
             msg_title = 'OK'
             msg_desc  = 'Lock request processed successfully'
           )
      WHEN ls_result-status = c_status_error
      THEN VALUE #(
             msg_type  = 'Error'
             msg_title = 'Error'
             msg_desc  = ls_result-msg_text
           )
      ELSE VALUE #(
             msg_type  = 'Error'
             msg_title = 'Timeout'
             msg_desc  = 'Background job did not respond in time'
           )
    ).

  ENDMETHOD.

ENDCLASS.
