@IsTest
private class PredictionTriggerHandlerTest {
  private static final Datetime KICKOFF = Datetime.newInstanceGmt(
    2026,
    10,
    18,
    15,
    0,
    0
  );

  private static Fixture__c createFixture() {
    Season__c season = TestDataFactory.createSeason();
    List<Team__c> teams = TestDataFactory.createTeams(2);
    Gameweek__c gameweek = TestDataFactory.createGameweek(season.Id, 8);
    Fixture__c fixture = TestDataFactory.buildFixture(
      gameweek.Id,
      teams[0],
      teams[1],
      KICKOFF
    );
    insert fixture;
    return fixture;
  }

  @IsTest
  static void keySetOnInsertAndSecondPredictionRejected() {
    System.runAs(TestDataFactory.adminUser()) {
      Fixture__c fixture = createFixture();
      Prediction__c prediction = TestDataFactory.buildPrediction(fixture, 2, 1);
      insert prediction;

      Assert.areEqual(
        UserInfo.getUserId() + '-' + fixture.Id + '-' + fixture.Gameweek__c,
        [SELECT Unique_Key__c FROM Prediction__c WHERE Id = :prediction.Id]
        .Unique_Key__c
      );
      TestAssert.duplicateRejected(
        TestDataFactory.buildPrediction(fixture, 0, 0)
      );
    }
  }

  @IsTest
  static void editingScoreKeepsSameKey() {
    System.runAs(TestDataFactory.adminUser()) {
      Fixture__c fixture = createFixture();
      Prediction__c prediction = TestDataFactory.buildPrediction(fixture, 2, 1);
      insert prediction;

      prediction.Home_Goals__c = 3;
      update prediction;

      Assert.areEqual(
        UserInfo.getUserId() + '-' + fixture.Id + '-' + fixture.Gameweek__c,
        [SELECT Unique_Key__c FROM Prediction__c WHERE Id = :prediction.Id]
        .Unique_Key__c
      );
    }
  }

  @IsTest
  static void predictedAgainWhenFixtureMovedToAnotherGameweek() {
    System.runAs(TestDataFactory.adminUser()) {
      Fixture__c fixture = createFixture();
      insert TestDataFactory.buildPrediction(fixture, 2, 1);

      // The postponed fixture is moved to a later gameweek and predicted again there.
      Id seasonId = [
        SELECT Season__c
        FROM Gameweek__c
        WHERE Id = :fixture.Gameweek__c
      ]
      .Season__c;
      fixture.Gameweek__c = TestDataFactory.createGameweek(seasonId, 12).Id;
      update fixture;
      insert TestDataFactory.buildPrediction(fixture, 1, 1);

      Assert.areEqual(
        2,
        [SELECT COUNT() FROM Prediction__c WHERE Fixture__c = :fixture.Id],
        'One prediction per gameweek is allowed'
      );
    }
  }
}
