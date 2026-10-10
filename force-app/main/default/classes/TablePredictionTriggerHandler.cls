public with sharing class TablePredictionTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    UniqueKeyService.setKeys((List<Table_Prediction__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    UniqueKeyService.setKeys((List<Table_Prediction__c>) newRecords);
  }
}
