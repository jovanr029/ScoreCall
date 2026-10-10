@IsTest
private class TriggerHandlerTest {
  // Records which event method was called.
  private class RecordingHandler extends TriggerHandler {
    String called;
    protected override void beforeInsert(List<SObject> newRecords) {
      called = 'beforeInsert';
    }
    protected override void beforeUpdate(
      List<SObject> newRecords,
      Map<Id, SObject> oldMap
    ) {
      called = 'beforeUpdate';
    }
    protected override void beforeDelete(List<SObject> oldRecords) {
      called = 'beforeDelete';
    }
    protected override void afterInsert(List<SObject> newRecords) {
      called = 'afterInsert';
    }
    protected override void afterUpdate(
      List<SObject> newRecords,
      Map<Id, SObject> oldMap
    ) {
      called = 'afterUpdate';
    }
    protected override void afterDelete(List<SObject> oldRecords) {
      called = 'afterDelete';
    }
    protected override void afterUndelete(List<SObject> newRecords) {
      called = 'afterUndelete';
    }
  }

  @IsTest
  static void dispatchesEachEventToItsMethod() {
    Map<System.TriggerOperation, String> expected = new Map<System.TriggerOperation, String>{
      System.TriggerOperation.BEFORE_INSERT => 'beforeInsert',
      System.TriggerOperation.BEFORE_UPDATE => 'beforeUpdate',
      System.TriggerOperation.BEFORE_DELETE => 'beforeDelete',
      System.TriggerOperation.AFTER_INSERT => 'afterInsert',
      System.TriggerOperation.AFTER_UPDATE => 'afterUpdate',
      System.TriggerOperation.AFTER_DELETE => 'afterDelete',
      System.TriggerOperation.AFTER_UNDELETE => 'afterUndelete'
    };

    for (System.TriggerOperation operation : expected.keySet()) {
      RecordingHandler handler = new RecordingHandler();
      handler.dispatch(
        operation,
        new List<SObject>(),
        new List<SObject>(),
        new Map<Id, SObject>()
      );
      Assert.areEqual(
        expected.get(operation),
        handler.called,
        String.valueOf(operation)
      );
    }
  }

  @IsTest
  static void baseClassMethodsDoNothing() {
    TriggerHandler handler = new TriggerHandler();
    for (System.TriggerOperation operation : System.TriggerOperation.values()) {
      handler.dispatch(
        operation,
        new List<SObject>(),
        new List<SObject>(),
        new Map<Id, SObject>()
      );
    }
    Assert.isTrue(true, 'No exception for any event');
  }

  @IsTest
  static void runOutsideTriggerDoesNothing() {
    RecordingHandler handler = new RecordingHandler();
    handler.run();
    Assert.isNull(handler.called);
  }
}
