@IsTest
private class ScoringServiceTest {
  private static final Datetime KICKOFF = Datetime.newInstanceGmt(
    2026,
    10,
    17,
    14,
    0,
    0
  );

  // Every test uses 3 / 5, whatever the org's Default record says, so changing
  // the points in Scoring_Rule__mdt never breaks these tests.
  static {
    useRules(3, 5);
  }

  private static void useRules(Integer outcomePoints, Integer exactBonus) {
    ScoringService.rulesOverride = new Scoring_Rule__mdt(
      Outcome_Points__c = outcomePoints,
      Exact_Score_Bonus__c = exactBonus
    );
  }

  // ---------- points(): pure logic ----------

  @IsTest
  static void exactScoreIsEightPoints() {
    Assert.areEqual(8, ScoringService.points(2, 1, 2, 1));
    Assert.areEqual(8, ScoringService.points(0, 0, 0, 0), 'Exact draw');
  }

  @IsTest
  static void correctOutcomeIsThreePoints() {
    Assert.areEqual(3, ScoringService.points(2, 0, 3, 1), 'Home win');
    Assert.areEqual(3, ScoringService.points(0, 1, 1, 4), 'Away win');
  }

  @IsTest
  static void correctDrawIsThreePoints() {
    Assert.areEqual(3, ScoringService.points(1, 1, 2, 2));
  }

  @IsTest
  static void wrongOutcomeIsZero() {
    Assert.areEqual(
      0,
      ScoringService.points(2, 0, 0, 1),
      'Home win predicted, away win'
    );
    Assert.areEqual(
      0,
      ScoringService.points(1, 1, 1, 0),
      'Draw predicted, home win'
    );
    Assert.areEqual(
      0,
      ScoringService.points(0, 2, 2, 2),
      'Away win predicted, draw'
    );
  }

  // ---------- score(): through real fixture updates (FixtureTrigger) ----------

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
    return [SELECT Id, Gameweek__c FROM Fixture__c LIMIT 1];
  }

  private static Prediction__c predict(Integer home, Integer away) {
    Prediction__c prediction = TestDataFactory.buildPrediction(
      theFixture(),
      home,
      away
    );
    insert prediction;
    return prediction;
  }

  private static Prediction__c reload(Prediction__c prediction) {
    return [
      SELECT Status__c, Points__c, Exact_Score__c
      FROM Prediction__c
      WHERE Id = :prediction.Id
    ];
  }

  private static void finish(Integer home, Integer away) {
    update new Fixture__c(
      Id = theFixture().Id,
      Status__c = 'Finished',
      Home_Goals__c = home,
      Away_Goals__c = away
    );
  }

  @IsTest
  static void finishingAFixtureScoresItsPredictions() {
    System.runAs(admin()) {
      Prediction__c prediction = predict(2, 1);

      Test.startTest();
      finish(2, 1);
      Test.stopTest();

      Prediction__c result = reload(prediction);
      Assert.areEqual('Scored', result.Status__c);
      Assert.areEqual(8, result.Points__c);
      Assert.isTrue(result.Exact_Score__c);
    }
  }

  @IsTest
  static void correctedResultIsRescored() {
    System.runAs(admin()) {
      Prediction__c prediction = predict(2, 1);

      Test.startTest();
      finish(2, 1);
      finish(2, 2); // the result was corrected
      Test.stopTest();

      Prediction__c result = reload(prediction);
      Assert.areEqual(0, result.Points__c);
      Assert.isFalse(result.Exact_Score__c);
    }
  }

  @IsTest
  static void annulledResultReopensThePrediction() {
    System.runAs(admin()) {
      Prediction__c prediction = predict(2, 1);

      Test.startTest();
      finish(2, 1);
      update new Fixture__c(Id = theFixture().Id, Status__c = 'Live');
      Test.stopTest();

      Prediction__c result = reload(prediction);
      Assert.areEqual('Open', result.Status__c);
      Assert.isNull(result.Points__c);
      Assert.isFalse(result.Exact_Score__c);
    }
  }

  @IsTest
  static void liveScoreUpdatesDoNotScore() {
    System.runAs(admin()) {
      Prediction__c prediction = predict(1, 0);

      Test.startTest();
      update new Fixture__c(
        Id = theFixture().Id,
        Status__c = 'Live',
        Home_Goals__c = 1,
        Away_Goals__c = 0
      );
      Test.stopTest();

      Assert.areEqual('Open', reload(prediction).Status__c);
    }
  }

  @IsTest
  static void voidedPredictionsAreNeverScored() {
    System.runAs(admin()) {
      Prediction__c old = predict(2, 1);
      Id gw12 = [SELECT Id FROM Gameweek__c WHERE Number__c = 12].Id;

      Test.startTest();
      // Moved to GW12 (old prediction voided), predicted again there, then finished.
      update new Fixture__c(Id = theFixture().Id, Gameweek__c = gw12);
      Prediction__c renewed = predict(2, 1);
      finish(2, 1);
      Test.stopTest();

      Prediction__c oldResult = reload(old);
      Assert.areEqual('Voided', oldResult.Status__c);
      Assert.areEqual(0, oldResult.Points__c);
      Assert.areEqual(
        8,
        reload(renewed).Points__c,
        'Only the GW12 prediction counts'
      );
    }
  }

  @IsTest
  static void wholeGameweekFinishingAtOnceIsScored() {
    System.runAs(admin()) {
      List<Team__c> teams = TestDataFactory.createTeams(20);
      Id gw8 = theFixture().Gameweek__c;
      List<Fixture__c> fixtures = new List<Fixture__c>();
      for (Integer i = 0; i < 10; i++) {
        fixtures.add(
          TestDataFactory.buildFixture(gw8, teams[i], teams[i + 10], KICKOFF)
        );
      }
      insert fixtures;
      List<Prediction__c> predictions = new List<Prediction__c>();
      for (Fixture__c fixture : fixtures) {
        predictions.add(TestDataFactory.buildPrediction(fixture, 1, 0));
      }
      insert predictions;

      for (Fixture__c fixture : fixtures) {
        fixture.Status__c = 'Finished';
        fixture.Home_Goals__c = 2;
        fixture.Away_Goals__c = 0;
      }
      Test.startTest();
      update fixtures;
      Test.stopTest();

      AggregateResult total = [
        SELECT COUNT(Id) scored, SUM(Points__c) points
        FROM Prediction__c
        WHERE Status__c = 'Scored'
      ];
      Assert.areEqual(10, total.get('scored'));
      Assert.areEqual(30, total.get('points'), '10 x correct outcome');
    }
  }

  @IsTest
  static void unchangedResultWritesNothing() {
    System.runAs(admin()) {
      predict(2, 1);
      finish(2, 1);

      Test.startTest();
      // Same status and result again: the trigger doesn't even call scoring.
      finish(2, 1);
      Integer dmlBefore = Limits.getDmlRows();
      ScoringService.score(
        new List<Fixture__c>{
          [
            SELECT Id, Gameweek__c, Status__c, Home_Goals__c, Away_Goals__c
            FROM Fixture__c
            LIMIT 1
          ]
        }
      );
      // Read the limit before stopTest(): stopTest() switches back to the
      // outer context's limits.
      Integer dmlAfter = Limits.getDmlRows();
      Test.stopTest();

      Assert.areEqual(
        dmlBefore,
        dmlAfter,
        'Already scored correctly: no update'
      );
    }
  }

  // ---------- configurable points (Scoring_Rule__mdt) ----------

  @IsTest
  static void defaultRulesRecordIsDeployed() {
    ScoringService.rulesOverride = null;

    Scoring_Rule__mdt rules = ScoringService.rules();

    Assert.isNotNull(rules.Outcome_Points__c);
    Assert.isNotNull(rules.Exact_Score_Bonus__c);
  }

  @IsTest
  static void pointsFollowTheRules() {
    useRules(2, 4);

    Assert.areEqual(6, ScoringService.points(2, 1, 2, 1), 'Exact: 2 + 4');
    Assert.areEqual(2, ScoringService.points(1, 0, 3, 0), 'Outcome: 2');
    Assert.areEqual(0, ScoringService.points(1, 0, 0, 1));
  }

  @IsTest
  static void exactFlagComparesScoresNotPoints() {
    System.runAs(admin()) {
      useRules(3, 0); // no bonus: exact and outcome give the same points
      Prediction__c prediction = predict(2, 1);

      Test.startTest();
      finish(2, 1);
      Test.stopTest();

      Prediction__c result = reload(prediction);
      Assert.areEqual(3, result.Points__c);
      Assert.isTrue(result.Exact_Score__c, 'Still an exact score');
    }
  }

  @IsTest
  static void rescoreSeasonAppliesChangedRules() {
    System.runAs(admin()) {
      Prediction__c exact = predict(2, 1);
      finish(2, 1);
      Assert.areEqual(8, reload(exact).Points__c);

      Test.startTest();
      useRules(2, 4); // the PO changed the points
      ScoringService.rescoreSeason([SELECT Id FROM Season__c LIMIT 1].Id);
      Test.stopTest();

      Assert.areEqual(6, reload(exact).Points__c);
    }
  }
}
