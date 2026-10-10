trigger LeagueMemberTrigger on League_Member__c(before insert, before update) {
  new LeagueMemberTriggerHandler().run();
}
