trigger SeasonTeamTrigger on Season_Team__c(before insert, before update) {
  new SeasonTeamTriggerHandler().run();
}
