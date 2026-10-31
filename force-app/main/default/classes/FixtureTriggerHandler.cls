public with sharing class FixtureTriggerHandler extends TriggerHandler {
  /**
   * 1. Void / re-open predictions when a fixture moves gameweek or is
   *    (un)postponed (PredictionStatusService).
   * 2. Score / re-score / un-score predictions when the result changes
   *    (ScoringService).
   */
  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    List<Fixture__c> movedOrPostponed = new List<Fixture__c>();
    List<Fixture__c> resultChanged = new List<Fixture__c>();

    for (Fixture__c fixture : (List<Fixture__c>) newRecords) {
      Fixture__c old = (Fixture__c) oldMap.get(fixture.Id);

      Boolean gameweekChanged = fixture.Gameweek__c != old.Gameweek__c;
      Boolean postponedChanged = isPostponed(fixture) != isPostponed(old);
      if (gameweekChanged || postponedChanged) {
        movedOrPostponed.add(fixture);
      }

      Boolean finishedChanged = isFinished(fixture) != isFinished(old);
      Boolean scoreCorrected =
        isFinished(fixture) &&
        (fixture.Home_Goals__c != old.Home_Goals__c ||
        fixture.Away_Goals__c != old.Away_Goals__c);
      if (finishedChanged || scoreCorrected) {
        resultChanged.add(fixture);
      }
    }

    if (!movedOrPostponed.isEmpty()) {
      PredictionStatusService.reconcile(movedOrPostponed);
    }
    if (!resultChanged.isEmpty()) {
      ScoringService.score(resultChanged);
    }
  }

  private static Boolean isPostponed(Fixture__c fixture) {
    return fixture.Status__c == 'Postponed';
  }

  private static Boolean isFinished(Fixture__c fixture) {
    return fixture.Status__c == 'Finished';
  }
}
