public with sharing class PredictionTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    UniqueKeyService.setKeys((List<Prediction__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    UniqueKeyService.setKeys((List<Prediction__c>) newRecords);
  }
}
