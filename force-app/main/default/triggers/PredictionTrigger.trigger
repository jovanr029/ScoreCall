trigger PredictionTrigger on Prediction__c(before insert, before update) {
  new PredictionTriggerHandler().run();
}
