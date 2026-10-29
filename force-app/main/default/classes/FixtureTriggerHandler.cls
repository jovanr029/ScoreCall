public with sharing class FixtureTriggerHandler extends TriggerHandler {
  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    List<Fixture__c> movedOrPostponed = new List<Fixture__c>();
    for (Fixture__c fixture : (List<Fixture__c>) newRecords) {
      Fixture__c old = (Fixture__c) oldMap.get(fixture.Id);
      Boolean gameweekChanged = fixture.Gameweek__c != old.Gameweek__c;
      Boolean postponedChanged =
        (fixture.Status__c == 'Postponed') != (old.Status__c == 'Postponed');
      if (gameweekChanged || postponedChanged) {
        movedOrPostponed.add(fixture);
      }
    }
    if (!movedOrPostponed.isEmpty()) {
      PredictionStatusService.reconcile(movedOrPostponed);
    }
  }
}
