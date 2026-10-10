@IsTest
private class SeasonTeamTriggerHandlerTest {
  @IsTest
  static void keySetOnInsertAndSameTeamTwiceRejected() {
    System.runAs(TestDataFactory.adminUser()) {
      Season__c season = TestDataFactory.createSeason();
      Team__c team = TestDataFactory.createTeams(1)[0];

      Season_Team__c seasonTeam = new Season_Team__c(
        Season__c = season.Id,
        Team__c = team.Id
      );
      insert seasonTeam;

      Assert.areEqual(
        season.Id + '-' + team.Id,
        [SELECT Unique_Key__c FROM Season_Team__c WHERE Id = :seasonTeam.Id]
        .Unique_Key__c
      );
      TestAssert.duplicateRejected(
        new Season_Team__c(Season__c = season.Id, Team__c = team.Id)
      );
    }
  }

  @IsTest
  static void keyFollowsTeamChangeOnUpdate() {
    System.runAs(TestDataFactory.adminUser()) {
      Season__c season = TestDataFactory.createSeason();
      List<Team__c> teams = TestDataFactory.createTeams(2);
      Season_Team__c seasonTeam = new Season_Team__c(
        Season__c = season.Id,
        Team__c = teams[0].Id
      );
      insert seasonTeam;

      // Send only the changed field: Season__c is a non-reparentable master-detail.
      update new Season_Team__c(Id = seasonTeam.Id, Team__c = teams[1].Id);

      Assert.areEqual(
        season.Id + '-' + teams[1].Id,
        [SELECT Unique_Key__c FROM Season_Team__c WHERE Id = :seasonTeam.Id]
        .Unique_Key__c
      );
    }
  }
}
