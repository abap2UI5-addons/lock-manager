*&---------------------------------------------------------------------*
*& Report z2ui5_re_lock_background
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT z2ui5_re_lock_background.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
PARAMETERS:
  p_wait TYPE i       DEFAULT 2  OBLIGATORY, " Seconds between checks
  p_user TYPE sy-uname            OBLIGATORY, " Background user
  p_time TYPE i                   .   " Auto-release in minutes

*----------------------------------------------------------------------*
* Selection Screen Texts
*----------------------------------------------------------------------*
SELECTION-SCREEN COMMENT /1(79) sc_txt1.
SELECTION-SCREEN COMMENT /1(79) sc_txt2.
SELECTION-SCREEN COMMENT /1(79) sc_txt3.

INITIALIZATION.
  sc_txt1 = 'p_wait: Seconds between lock request checks (default: 2)'.
  sc_txt2 = 'p_user: Must match the user running this background job'.
  sc_txt3 = 'p_time: Leave empty to disable automatic lock release'.

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

  WRITE: / |Lock Handler started at { sy-datum DATE = USER } | &
           |{ sy-uzeit TIME = USER } by { sy-uname }.|.

  " Process any requests that are already pending at job start
  z2ui5_cl_lock_manager=>process_pending_requests( ).

  IF p_time IS NOT INITIAL.
    z2ui5_cl_lock_manager=>auto_release_locks( iv_minutes = p_time ).
  ENDIF.

  WRITE: / 'Initial processing done. Waiting for events...'.
