trigger SeasonTrigger on Season__c(after update) {
  new SeasonTriggerHandler().run();
}
