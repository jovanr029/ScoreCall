/**
 * Base class for trigger handlers. Each trigger does one thing:
 *
 *   new GameweekTriggerHandler().run();
 *
 * run() routes the current trigger event to the matching method, and a
 * handler overrides only the events it cares about. The trigger itself must
 * still subscribe to the event (e.g. "after update") for it to fire.
 */
public virtual with sharing class TriggerHandler {
  public void run() {
    dispatch(Trigger.operationType, Trigger.new, Trigger.old, Trigger.oldMap);
  }

  // Separate from run() so tests can simulate every event without real DML.
  @TestVisible
  private void dispatch(
    System.TriggerOperation operation,
    List<SObject> newRecords,
    List<SObject> oldRecords,
    Map<Id, SObject> oldMap
  ) {
    switch on operation {
      when BEFORE_INSERT {
        beforeInsert(newRecords);
      }
      when BEFORE_UPDATE {
        beforeUpdate(newRecords, oldMap);
      }
      when BEFORE_DELETE {
        beforeDelete(oldRecords);
      }
      when AFTER_INSERT {
        afterInsert(newRecords);
      }
      when AFTER_UPDATE {
        afterUpdate(newRecords, oldMap);
      }
      when AFTER_DELETE {
        afterDelete(oldRecords);
      }
      when AFTER_UNDELETE {
        afterUndelete(newRecords);
      }
    }
  }

  protected virtual void beforeInsert(List<SObject> newRecords) {
  }
  protected virtual void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
  }
  protected virtual void beforeDelete(List<SObject> oldRecords) {
  }
  protected virtual void afterInsert(List<SObject> newRecords) {
  }
  protected virtual void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
  }
  protected virtual void afterDelete(List<SObject> oldRecords) {
  }
  protected virtual void afterUndelete(List<SObject> newRecords) {
  }
}
