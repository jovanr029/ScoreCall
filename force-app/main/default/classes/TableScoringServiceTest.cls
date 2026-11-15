/**
 * Table prediction points (#18): the 20/15/10/5/0 rule, and scoring when the
 * season is Finished, re-scoring a corrected final table, clearing when a
 * season is no longer Finished. Tests pin their own points, so changing the
 * Default Scoring_Rule__mdt record never breaks them.
 */
@IsTest
private class TableScoringServiceTest {
  private static void pinRules() {
    ScoringService.rulesOverride = new Scoring_Rule__mdt(
      Outcome_Points__c = 3,
      Exact_Score_Bonus__c = 5,
      Table_Exact_Points__c = 20,
      Table_One_Off_Points__c = 15,
      Table_Two_Off_Points__c = 10,
      Table_Three_Off_Points__c = 5
    );
  }

  @TestSetup
  static void setup() {
    User admin = TestDataFactory.adminUser();
    User carol = TestDataFactory.buildUser(
      'carol',
      'Minimum Access - Salesforce'
    );
    insert carol;

    System.runAs(admin) {
      Season__c season = TestDataFactory.createSeason();
      List<Team__c> teams = TestDataFactory.createTeams(5);
      List<Season_Team__c> table = new List<Season_Team__c>();
      for (Integer i = 0; i < teams.size(); i++) {
        table.add(
          new Season_Team__c(
            Season__c = season.Id,
            Team__c = teams[i].Id,
            Position__c = i + 1 // Team 1 is 1st ... Team 5 is 5th
          )
        );
      }
      insert table;

      // carol predicts the table in reverse: 5 1 2 3 4 -> T5 1st, T1 2nd...
      List<Integer> predicted = new List<Integer>{ 2, 3, 4, 5, 1 };
      List<Table_Prediction__c> predictions = new List<Table_Prediction__c>();
      for (Integer i = 0; i < teams.size(); i++) {
        predictions.add(
          new Table_Prediction__c(
            OwnerId = carol.Id,
            Season__c = season.Id,
            Team__c = teams[i].Id,
            Predicted_Position__c = predicted[i]
          )
        );
      }
      insert predictions;
    }
  }

  private static Map<String, Decimal> pointsByTeam() {
    Map<String, Decimal> points = new Map<String, Decimal>();
    for (Table_Prediction__c prediction : [
      SELECT Team__r.Name, Points__c
      FROM Table_Prediction__c
    ]) {
      points.put(prediction.Team__r.Name, prediction.Points__c);
    }
    return points;
  }

  private static void setStatus(String status) {
    System.runAs(TestDataFactory.adminUser()) {
      Season__c season = [SELECT Id FROM Season__c];
      season.Status__c = status;
      update season;
    }
  }

  @IsTest
  static void pointsByDistanceFromTheFinalPosition() {
    pinRules();
    Assert.areEqual(20, ScoringService.tablePoints(7, 7), 'exact');
    Assert.areEqual(15, ScoringService.tablePoints(7, 8), '1 off');
    Assert.areEqual(15, ScoringService.tablePoints(8, 7), '1 off, other way');
    Assert.areEqual(10, ScoringService.tablePoints(5, 7), '2 off');
    Assert.areEqual(5, ScoringService.tablePoints(10, 7), '3 off');
    Assert.areEqual(0, ScoringService.tablePoints(11, 7), '4 off');
    Assert.areEqual(0, ScoringService.tablePoints(7, null), 'no position');
  }

  @IsTest
  static void defaultRulesRecordHasTablePoints() {
    Scoring_Rule__mdt rules = Scoring_Rule__mdt.getInstance('Default');
    Assert.isNotNull(rules.Table_Exact_Points__c);
    Assert.isNotNull(rules.Table_Three_Off_Points__c);
  }

  @IsTest
  static void noPointsWhileTheSeasonIsRunning() {
    pinRules();
    for (Decimal points : pointsByTeam().values()) {
      Assert.isNull(points);
    }
  }

  @IsTest
  static void finishingTheSeasonScoresEveryTable() {
    pinRules();
    Test.startTest();
    setStatus('Finished');
    Test.stopTest();

    // final 1..5; carol: T1 2nd (1 off), T2 3rd (1 off), T3 4th (1 off),
    // T4 5th (1 off), T5 1st (4 off)
    Map<String, Decimal> points = pointsByTeam();
    Assert.areEqual(15, points.get('Team 1'));
    Assert.areEqual(15, points.get('Team 4'));
    Assert.areEqual(0, points.get('Team 5'));
  }

  @IsTest
  static void aCorrectedFinalTableIsRescored() {
    pinRules();
    setStatus('Finished');

    Test.startTest();
    System.runAs(TestDataFactory.adminUser()) {
      // Team 1 and Team 2 swap places in the final table
      List<Season_Team__c> table = [
        SELECT Id, Team__r.Name, Position__c
        FROM Season_Team__c
        WHERE Team__r.Name IN ('Team 1', 'Team 2')
      ];
      for (Season_Team__c seasonTeam : table) {
        seasonTeam.Position__c = seasonTeam.Team__r.Name == 'Team 1' ? 2 : 1;
      }
      update table;
    }
    Test.stopTest();

    Map<String, Decimal> points = pointsByTeam();
    Assert.areEqual(
      20,
      points.get('Team 1'),
      'carol had Team 1 2nd: now exact'
    );
    Assert.areEqual(10, points.get('Team 2'), 'carol had Team 2 3rd: 2 off');
  }

  @IsTest
  static void aSeasonThatIsNoLongerFinishedLosesItsPoints() {
    pinRules();
    setStatus('Finished');

    Test.startTest();
    setStatus('Active');
    Test.stopTest();

    for (Decimal points : pointsByTeam().values()) {
      Assert.isNull(points);
    }
  }
}
