trigger TablePredictionTrigger on Table_Prediction__c(
  before insert,
  before update
) {
  new TablePredictionTriggerHandler().run();
}
