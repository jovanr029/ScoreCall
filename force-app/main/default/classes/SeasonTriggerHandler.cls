public with sharing class SeasonTriggerHandler extends TriggerHandler {
  /** A season becoming Finished (or no longer Finished) scores its tables. */
  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    Set<Id> statusChanged = new Set<Id>();
    for (Season__c season : (List<Season__c>) newRecords) {
      Season__c old = (Season__c) oldMap.get(season.Id);
      if (season.Status__c != old.Status__c) {
        statusChanged.add(season.Id);
      }
    }
    TableScoringService.refresh(statusChanged);
  }
}
