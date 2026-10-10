public with sharing class GameweekTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    UniqueKeyService.setKeys((List<Gameweek__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    UniqueKeyService.setKeys((List<Gameweek__c>) newRecords);
  }
}
