trigger SeasonTeamTrigger on Season_Team__c(
  before insert,
  before update,
  after insert,
  after update
) {
  new SeasonTeamTriggerHandler().run();
}
