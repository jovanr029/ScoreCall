@IsTest
private class FixtureTriggerHandlerTest {
  private static final Datetime KICKOFF = Datetime.newInstanceGmt(
    2026,
    10,
    17,
    14,
    0,
    0
  );

  @IsTest
  static void reconcilesOnlyWhenGameweekOrPostponementChanges() {
    System.runAs(TestDataFactory.adminUser()) {
      Season__c season = TestDataFactory.createSeason();
      List<Team__c> teams = TestDataFactory.createTeams(2);
      Gameweek__c gw8 = TestDataFactory.createGameweek(season.Id, 8);
      Fixture__c fixture = TestDataFactory.buildFixture(
        gw8.Id,
        teams[0],
        teams[1],
        KICKOFF
      );
      insert fixture;
      Prediction__c prediction = TestDataFactory.buildPrediction(fixture, 2, 1);
      insert prediction;

      Test.startTest();
      update new Fixture__c(Id = fixture.Id, Kickoff__c = KICKOFF.addHours(2));
      Assert.areEqual(
        'Open',
        [SELECT Status__c FROM Prediction__c].Status__c,
        'Kickoff change alone: no effect'
      );

      update new Fixture__c(Id = fixture.Id, Status__c = 'Postponed');
      Test.stopTest();

      Assert.areEqual(
        'Voided',
        [SELECT Status__c FROM Prediction__c].Status__c
      );
    }
  }
}
