trigger FixtureTrigger on Fixture__c(after update) {
  new FixtureTriggerHandler().run();
}
