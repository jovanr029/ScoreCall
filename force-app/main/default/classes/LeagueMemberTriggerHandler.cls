public with sharing class LeagueMemberTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    UniqueKeyService.setKeys((List<League_Member__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    UniqueKeyService.setKeys((List<League_Member__c>) newRecords);
  }
}
