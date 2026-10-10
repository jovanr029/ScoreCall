trigger GameweekTrigger on Gameweek__c(before insert, before update) {
  new GameweekTriggerHandler().run();
}
