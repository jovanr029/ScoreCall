public with sharing class SeasonTeamTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    UniqueKeyService.setKeys((List<Season_Team__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    UniqueKeyService.setKeys((List<Season_Team__c>) newRecords);
  }
}
