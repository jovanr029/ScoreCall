/**
 * The voiding rules, driven through real fixture updates (FixtureTrigger).
 */
@IsTest
private class PredictionStatusServiceTest {
  private static final Datetime KICKOFF = Datetime.newInstanceGmt(
    2026,
    10,
    17,
    14,
    0,
    0
  );

  @TestSetup
  static void setup() {
    System.runAs(TestDataFactory.adminUser()) {
      Season__c season = TestDataFactory.createSeason();
      List<Team__c> teams = TestDataFactory.createTeams(2);
      Gameweek__c gw8 = TestDataFactory.createGameweek(season.Id, 8);
      TestDataFactory.createGameweek(season.Id, 12);
      insert TestDataFactory.buildFixture(gw8.Id, teams[0], teams[1], KICKOFF);
    }
  }

  private static User admin() {
    return [SELECT Id FROM User WHERE Alias = 'scadmin' LIMIT 1];
  }

  private static Fixture__c theFixture() {
    return [SELECT Id, Gameweek__c, Status__c FROM Fixture__c LIMIT 1];
  }

  private static Id gameweekId(Integer gameweekNumber) {
    return [SELECT Id FROM Gameweek__c WHERE Number__c = :gameweekNumber].Id;
  }

  private static Prediction__c reload(Prediction__c prediction) {
    return [
      SELECT Status__c, Points__c
      FROM Prediction__c
      WHERE Id = :prediction.Id
    ];
  }

  @IsTest
  static void postponingVoidsOpenPredictions() {
    System.runAs(admin()) {
      Fixture__c fixture = theFixture();
      Prediction__c prediction = TestDataFactory.buildPrediction(fixture, 2, 1);
      insert prediction;

      Test.startTest();
      update new Fixture__c(Id = fixture.Id, Status__c = 'Postponed');
      Test.stopTest();

      Prediction__c result = reload(prediction);
      Assert.areEqual('Voided', result.Status__c);
      Assert.areEqual(0, result.Points__c);
    }
  }

  @IsTest
  static void movingToAnotherGameweekVoidsTheOldPredictionOnly() {
    System.runAs(admin()) {
      Fixture__c fixture = theFixture();
      Prediction__c old = TestDataFactory.buildPrediction(fixture, 2, 1);
      insert old;

      Test.startTest();
      update new Fixture__c(Id = fixture.Id, Gameweek__c = gameweekId(12));
      // Predicted again in the new gameweek
      Prediction__c renewed = TestDataFactory.buildPrediction(
        theFixture(),
        0,
        0
      );
      insert renewed;
      Test.stopTest();

      Assert.areEqual('Voided', reload(old).Status__c);
      Assert.areEqual('Open', reload(renewed).Status__c);
    }
  }

  @IsTest
  static void postponedThenBackInSameGameweekReopens() {
    System.runAs(admin()) {
      Fixture__c fixture = theFixture();
      Prediction__c prediction = TestDataFactory.buildPrediction(fixture, 2, 1);
      insert prediction;

      Test.startTest();
      update new Fixture__c(Id = fixture.Id, Status__c = 'Postponed');
      update new Fixture__c(
        Id = fixture.Id,
        Status__c = 'Scheduled',
        Kickoff__c = KICKOFF.addDays(1)
      );
      Test.stopTest();

      Prediction__c result = reload(prediction);
      Assert.areEqual('Open', result.Status__c);
      Assert.isNull(result.Points__c);
    }
  }

  @IsTest
  static void postponedThenMovedStaysVoided() {
    System.runAs(admin()) {
      Fixture__c fixture = theFixture();
      Prediction__c prediction = TestDataFactory.buildPrediction(fixture, 2, 1);
      insert prediction;

      Test.startTest();
      update new Fixture__c(Id = fixture.Id, Status__c = 'Postponed');
      update new Fixture__c(
        Id = fixture.Id,
        Status__c = 'Scheduled',
        Gameweek__c = gameweekId(12)
      );
      Test.stopTest();

      Assert.areEqual('Voided', reload(prediction).Status__c);
    }
  }

  @IsTest
  static void scoredPredictionsAreNeverTouched() {
    System.runAs(admin()) {
      Fixture__c fixture = theFixture();
      Prediction__c prediction = TestDataFactory.buildPrediction(fixture, 2, 1);
      prediction.Status__c = 'Scored';
      prediction.Points__c = 8;
      insert prediction;

      Test.startTest();
      update new Fixture__c(Id = fixture.Id, Status__c = 'Postponed');
      Test.stopTest();

      Prediction__c result = reload(prediction);
      Assert.areEqual('Scored', result.Status__c);
      Assert.areEqual(8, result.Points__c);
    }
  }

  @IsTest
  static void otherChangesDoNotTouchPredictions() {
    System.runAs(admin()) {
      Fixture__c fixture = theFixture();
      Prediction__c prediction = TestDataFactory.buildPrediction(fixture, 2, 1);
      insert prediction;

      Test.startTest();
      update new Fixture__c(
        Id = fixture.Id,
        Status__c = 'Live',
        Home_Goals__c = 1,
        Away_Goals__c = 0
      );
      Test.stopTest();

      Assert.areEqual('Open', reload(prediction).Status__c);
    }
  }

  @IsTest
  static void voidsAWholeGameweekInOneUpdate() {
    System.runAs(admin()) {
      List<Team__c> teams = TestDataFactory.createTeams(20);
      Id gw8 = gameweekId(8);
      List<Fixture__c> fixtures = new List<Fixture__c>();
      for (Integer i = 0; i < 10; i++) {
        fixtures.add(
          TestDataFactory.buildFixture(gw8, teams[i], teams[i + 10], KICKOFF)
        );
      }
      insert fixtures;
      List<Prediction__c> predictions = new List<Prediction__c>();
      for (Fixture__c fixture : fixtures) {
        predictions.add(TestDataFactory.buildPrediction(fixture, 1, 1));
      }
      insert predictions;

      for (Fixture__c fixture : fixtures) {
        fixture.Status__c = 'Postponed';
      }
      Test.startTest();
      update fixtures;
      Test.stopTest();

      Assert.areEqual(
        10,
        [SELECT COUNT() FROM Prediction__c WHERE Status__c = 'Voided']
      );
    }
  }
}
