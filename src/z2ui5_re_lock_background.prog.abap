*&---------------------------------------------------------------------*
*& Report z2ui5_re_lock_background
*&---------------------------------------------------------------------*
*& The lock handler. Started by the event LOCK_HANDLER (or
*& LOCK_HANDLER_<client>), it owns every kernel lock requested through
*& z2ui5_cl_lock_manager and keeps running - and holding them - for as
*& long as any lock is active. It stops by itself once nothing is pending
*& and nothing is held. A second instance started meanwhile stops at once.
*&---------------------------------------------------------------------*
REPORT z2ui5_re_lock_background.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
PARAMETERS:
  p_wait TYPE i        DEFAULT 2 OBLIGATORY, " Seconds between checks
  p_user TYPE sy-uname OBLIGATORY,           " Background user
  p_time TYPE i.                             " Auto-release in minutes

*----------------------------------------------------------------------*
* Selection Screen Texts
*----------------------------------------------------------------------*
SELECTION-SCREEN COMMENT /1(79) sc_txt1.
SELECTION-SCREEN COMMENT /1(79) sc_txt2.
SELECTION-SCREEN COMMENT /1(79) sc_txt3.

INITIALIZATION.
  sc_txt1 = 'p_wait: Seconds between two looks at the request queue (default: 2)'.
  sc_txt2 = 'p_user: Must match the user running this background job'.
  sc_txt3 = 'p_time: Minutes until a lock is released automatically (empty: never)'.

*----------------------------------------------------------------------*
* Start of Selection
*----------------------------------------------------------------------*
START-OF-SELECTION.

  " Validate that executing user matches configured background user
  IF p_user <> sy-uname.
    WRITE: / |ERROR: Configured user '{ p_user }' does not match | &
             |executing user '{ sy-uname }'.|.
    RETURN.
  ENDIF.

  WRITE: / |Lock handler started at { sy-datum DATE = USER } | &
           |{ sy-uzeit TIME = USER } by { sy-uname }.|.

  " loops until no request is pending and no lock is held
  DATA(gv_log) = z2ui5_cl_lock_manager=>run_handler(
    iv_wait_seconds    = p_wait
    iv_release_minutes = p_time ).

  WRITE: / gv_log.
  GET TIME.
  WRITE: / |Lock handler ended at { sy-datum DATE = USER } | &
           |{ sy-uzeit TIME = USER }.|.
