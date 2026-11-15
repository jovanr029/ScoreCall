public with sharing class SeasonTeamTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    UniqueKeyService.setKeys((List<Season_Team__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    UniqueKeyService.setKeys((List<Season_Team__c>) newRecords);
  }

  /** A changed final table re-scores the season's table predictions. */
  protected override void afterInsert(List<SObject> newRecords) {
    Set<Id> seasonIds = new Set<Id>();
    for (Season_Team__c seasonTeam : (List<Season_Team__c>) newRecords) {
      seasonIds.add(seasonTeam.Season__c);
    }
    TableScoringService.refresh(seasonIds);
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    Set<Id> seasonIds = new Set<Id>();
    for (Season_Team__c seasonTeam : (List<Season_Team__c>) newRecords) {
      Season_Team__c old = (Season_Team__c) oldMap.get(seasonTeam.Id);
      if (seasonTeam.Position__c != old.Position__c) {
        seasonIds.add(seasonTeam.Season__c);
      }
    }
    TableScoringService.refresh(seasonIds);
  }
}
