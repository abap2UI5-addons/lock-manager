* Scenario 7 — RAP draft (the modern alternative)
*
* On S/4HANA or BTP ABAP Environment (Steampunk) the canonical pattern
* is no longer "hold a lock during edit." Instead you create a draft
* instance of the sales order in a framework-managed shadow table.
* The active record is untouched until the user explicitly activates.
*
* This sidesteps the whole lock-during-think-time problem.


* ------------------------------------------------------------------
* 1) Behaviour definition (RAP BDEF)
* ------------------------------------------------------------------

managed implementation in class zbp_i_so unique;
strict ( 2 );

define behavior for ZI_SalesOrder alias SalesOrder
persistent table zsalesorder
draft table zsalesorder_d
lock master
authorization master ( instance )
etag master last_changed_at
with draft
{
  field ( readonly ) Vbeln;
  field ( mandatory ) Auart;

  create;
  update;
  delete;

  draft action Edit;
  draft action Activate;
  draft determine action Prepare;
}


* ------------------------------------------------------------------
* 2) Calling a draft-enabled BO from abap2UI5
* ------------------------------------------------------------------
* abap2UI5 calls the RAP entity manipulation language (EML) directly
* from an event handler. The framework handles ETag checks, draft
* persistence, and the activation enqueue for you.

METHOD on_event_save.

  MODIFY ENTITIES OF zi_salesorder
    ENTITY SalesOrder
    UPDATE FIELDS ( Auart )
      WITH VALUE #( ( Vbeln = vbeln
                      Auart = auart
                      %control-Auart = if_abap_behv=>mk-on ) )
    FAILED   DATA(failed)
    REPORTED DATA(reported).

  IF failed IS NOT INITIAL.
    client->message_box_display( `Update failed` ).
    RETURN.
  ENDIF.

  COMMIT ENTITIES.

  client->message_toast_display( `Saved.` ).

ENDMETHOD.
