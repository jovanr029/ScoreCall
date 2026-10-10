/**
 * Proves what the ScoreCall_Player permission set and the Private sharing on
 * Prediction__c allow. Runs as test users with a minimum-access profile plus
 * only ScoreCall_Player, and uses USER_MODE so CRUD, FLS and sharing are
 * enforced like they will be for real players.
 */
@IsTest
private class ScoreCallPlayerAccessTest {
  private static final Datetime KICKOFF = Datetime.newInstanceGmt(
    2026,
    10,
    18,
    15,
    0,
    0
  );

  @TestSetup
  static void setup() {
    // Users and permission set assignments are setup objects. Create them all
    // first; the game data is inserted inside System.runAs, a separate context,
    // which avoids MIXED_DML_OPERATION.
    User admin = TestDataFactory.adminUser();
    for (String alias : new List<String>{ 'alice', 'bob' }) {
      User player = TestDataFactory.buildUser(
        alias,
        'Minimum Access - Salesforce'
      );
      insert player;
      TestDataFactory.assignPermissionSet(player.Id, 'ScoreCall_Player');
    }

    System.runAs(admin) {
      Season__c season = TestDataFactory.createSeason();
      List<Team__c> teams = TestDataFactory.createTeams(2);
      Gameweek__c gameweek = TestDataFactory.createGameweek(season.Id, 8);
      insert TestDataFactory.buildFixture(
        gameweek.Id,
        teams[0],
        teams[1],
        KICKOFF
      );
    }
  }

  @IsTest
  static void playerCanReadGameDataAndCreateOwnPrediction() {
    System.runAs(player('alice')) {
      Fixture__c fixture = [
        SELECT Id, Gameweek__c
        FROM Fixture__c
        WITH USER_MODE
        LIMIT 1
      ];

      Database.insert(
        TestDataFactory.buildPrediction(fixture, 2, 1),
        AccessLevel.USER_MODE
      );

      Assert.areEqual(1, [SELECT COUNT() FROM Prediction__c WITH USER_MODE]);
    }
  }

  @IsTest
  static void playerCannotSetPoints() {
    System.runAs(player('alice')) {
      Fixture__c fixture = [
        SELECT Id, Gameweek__c
        FROM Fixture__c
        WITH USER_MODE
        LIMIT 1
      ];
      Prediction__c cheat = TestDataFactory.buildPrediction(fixture, 2, 1);
      cheat.Points__c = 8;

      try {
        Database.insert(cheat, AccessLevel.USER_MODE);
        Assert.fail('A player must not be able to set Points__c');
      } catch (DmlException e) {
        // USER_MODE rejects the whole record when it contains a field the
        // user can't edit (Points__c is read-only in ScoreCall_Player).
        Assert.isTrue(
          e.getMessage().contains('fields being inaccessible'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void playerCannotSeeAnotherPlayersPrediction() {
    System.runAs(player('bob')) {
      Fixture__c fixture = [
        SELECT Id, Gameweek__c
        FROM Fixture__c
        WITH USER_MODE
        LIMIT 1
      ];
      Database.insert(
        TestDataFactory.buildPrediction(fixture, 0, 3),
        AccessLevel.USER_MODE
      );
    }

    System.runAs(player('alice')) {
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Prediction__c WITH USER_MODE],
        'Predictions are private to their owner'
      );
    }
  }

  @IsTest
  static void playerCannotChangeGameData() {
    System.runAs(player('alice')) {
      Fixture__c fixture = [SELECT Id FROM Fixture__c WITH USER_MODE LIMIT 1];
      fixture.Home_Goals__c = 5;

      try {
        Database.update(fixture, AccessLevel.USER_MODE);
        Assert.fail('A player must not be able to edit fixtures');
      } catch (TypeException e) {
        // Without object-level Edit, USER_MODE refuses the DML before it runs.
        Assert.isTrue(
          e.getMessage().contains('DML operation UPDATE not allowed'),
          e.getMessage()
        );
      }
    }
  }

  private static User player(String alias) {
    return [
      SELECT Id
      FROM User
      WHERE Alias = :alias AND Email = :(alias + '@scorecall.test')
    ];
  }
}
