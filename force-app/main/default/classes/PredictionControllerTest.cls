/**
 * Runs as real players (minimum-access profile + ScoreCall_Player only), so
 * USER_MODE, field-level security and sharing are really exercised.
 *
 * Data: an active season with GW7 (played, deadline passed), GW8 (open,
 * kickoffs in 2 days) and GW9 (open, in 9 days); two fixtures per gameweek.
 */
@IsTest
private class PredictionControllerTest {
  @TestSetup
  static void setup() {
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
      List<Team__c> teams = TestDataFactory.createTeams(4);
      Map<Integer, Datetime> kickoffs = new Map<Integer, Datetime>{
        7 => System.now().addDays(-5),
        8 => System.now().addDays(2),
        9 => System.now().addDays(9)
      };
      List<Fixture__c> fixtures = new List<Fixture__c>();
      for (Integer gameweekNumber : kickoffs.keySet()) {
        Gameweek__c gameweek = TestDataFactory.createGameweek(
          season.Id,
          gameweekNumber
        );
        Datetime kickoff = kickoffs.get(gameweekNumber);
        fixtures.add(
          TestDataFactory.buildFixture(gameweek.Id, teams[0], teams[1], kickoff)
        );
        fixtures.add(
          TestDataFactory.buildFixture(
            gameweek.Id,
            teams[2],
            teams[3],
            kickoff.addHours(3)
          )
        );
      }
      insert fixtures;
    }
  }

  private static User player(String alias) {
    return [
      SELECT Id
      FROM User
      WHERE Alias = :alias AND Email = :(alias + '@scorecall.test')
    ];
  }

  private static User admin() {
    return [SELECT Id FROM User WHERE Alias = 'scadmin' LIMIT 1];
  }

  private static Id gameweekId(Integer gameweekNumber) {
    return [SELECT Id FROM Gameweek__c WHERE Number__c = :gameweekNumber].Id;
  }

  private static PredictionController.PredictionInput input(
    Id fixtureId,
    Integer home,
    Integer away
  ) {
    PredictionController.PredictionInput input = new PredictionController.PredictionInput();
    input.fixtureId = fixtureId;
    input.homeGoals = home;
    input.awayGoals = away;
    return input;
  }

  private static String saveError(
    Id gameweekId,
    List<PredictionController.PredictionInput> inputs
  ) {
    try {
      PredictionController.saveGameweekPredictions(gameweekId, inputs);
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
    Assert.fail('Expected the save to be rejected');
    return null;
  }

  @IsTest
  static void defaultIsTheNextOpenGameweek() {
    System.runAs(player('alice')) {
      PredictionController.GameweekView view = PredictionController.getGameweek(
        null
      );

      Assert.areEqual(8, view.gameweekNumber);
      Assert.isFalse(view.locked);
      Assert.isNotNull(view.deadline);
      Assert.areEqual(2, view.fixtures.size());
      Assert.areEqual('Team 1', view.fixtures[0].homeTeam);
      Assert.areEqual('T1', view.fixtures[0].homeShort, 'Code for phones');
      Assert.areEqual('T2', view.fixtures[0].awayShort);
      Assert.areEqual('Team 2', view.fixtures[0].awayTeam);
      Assert.isNull(view.fixtures[0].predictedHome, 'Nothing predicted yet');
      Assert.areEqual(gameweekId(7), view.previousGameweekId);
      Assert.areEqual(gameweekId(9), view.nextGameweekId);
    }
  }

  @IsTest
  static void playerSavesAndSeesOnlyTheirOwnPredictions() {
    Id gw8 = gameweekId(8);
    System.runAs(player('alice')) {
      PredictionController.GameweekView view = PredictionController.getGameweek(
        gw8
      );
      PredictionController.GameweekView saved = PredictionController.saveGameweekPredictions(
        gw8,
        new List<PredictionController.PredictionInput>{
          input(view.fixtures[0].fixtureId, 2, 1)
        }
      );

      Assert.areEqual(2, saved.fixtures[0].predictedHome);
      Assert.areEqual(1, saved.fixtures[0].predictedAway);
      Assert.areEqual('Open', saved.fixtures[0].predictionStatus);
    }

    System.runAs(player('bob')) {
      PredictionController.GameweekView view = PredictionController.getGameweek(
        gw8
      );
      Assert.isNull(
        view.fixtures[0].predictedHome,
        'Bob must not see Alice\'s prediction'
      );
    }
  }

  @IsTest
  static void savingAgainUpdatesInsteadOfDuplicating() {
    Id gw8 = gameweekId(8);
    System.runAs(player('alice')) {
      Id fixtureId = PredictionController.getGameweek(gw8)
        .fixtures[0]
        .fixtureId;
      PredictionController.saveGameweekPredictions(
        gw8,
        new List<PredictionController.PredictionInput>{ input(fixtureId, 2, 1) }
      );
      PredictionController.GameweekView view = PredictionController.saveGameweekPredictions(
        gw8,
        new List<PredictionController.PredictionInput>{ input(fixtureId, 0, 0) }
      );

      Assert.areEqual(0, view.fixtures[0].predictedHome);
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Prediction__c WHERE Fixture__c = :fixtureId]
      );
    }
  }

  @IsTest
  static void emptyFixturesAreSkipped() {
    Id gw8 = gameweekId(8);
    System.runAs(player('alice')) {
      PredictionController.GameweekView view = PredictionController.getGameweek(
        gw8
      );
      PredictionController.saveGameweekPredictions(
        gw8,
        new List<PredictionController.PredictionInput>{
          input(view.fixtures[0].fixtureId, 1, 0),
          input(view.fixtures[1].fixtureId, null, null)
        }
      );

      Assert.areEqual(1, [SELECT COUNT() FROM Prediction__c]);
    }
  }

  @IsTest
  static void saveAfterTheDeadlineIsRejected() {
    Id gw7 = gameweekId(7);
    System.runAs(player('alice')) {
      PredictionController.GameweekView view = PredictionController.getGameweek(
        gw7
      );
      Assert.isTrue(view.locked);

      String message = saveError(
        gw7,
        new List<PredictionController.PredictionInput>{
          input(view.fixtures[0].fixtureId, 1, 1)
        }
      );
      Assert.isTrue(message.contains('locked'), message);
    }
  }

  @IsTest
  static void lockedGameweekIsRejectedEvenBeforeItsDeadline() {
    Id gw9 = gameweekId(9);
    System.runAs(admin()) {
      update new Gameweek__c(Id = gw9, Locked__c = true);
    }
    System.runAs(player('alice')) {
      PredictionController.GameweekView view = PredictionController.getGameweek(
        gw9
      );
      Assert.isTrue(view.locked);
      String message = saveError(
        gw9,
        new List<PredictionController.PredictionInput>{
          input(view.fixtures[0].fixtureId, 1, 1)
        }
      );
      Assert.isTrue(message.contains('locked'), message);
    }
  }

  @IsTest
  static void invalidScoresAreRejected() {
    Id gw8 = gameweekId(8);
    System.runAs(player('alice')) {
      Id fixtureId = PredictionController.getGameweek(gw8)
        .fixtures[0]
        .fixtureId;

      for (
        List<Integer> score : new List<List<Integer>>{
          new List<Integer>{ -1, 0 },
          new List<Integer>{ 0, PredictionController.MAX_GOALS + 1 },
          new List<Integer>{ 2, null }
        }
      ) {
        String message = saveError(
          gw8,
          new List<PredictionController.PredictionInput>{
            input(fixtureId, score[0], score[1])
          }
        );
        Assert.isTrue(message.contains('Enter both scores'), message);
      }
      Assert.areEqual(0, [SELECT COUNT() FROM Prediction__c]);
    }
  }

  @IsTest
  static void fixtureFromAnotherGameweekIsRejected() {
    Id gw8 = gameweekId(8);
    Id gw9Fixture = [
      SELECT Id
      FROM Fixture__c
      WHERE Gameweek__r.Number__c = 9
      LIMIT 1
    ]
    .Id;
    System.runAs(player('alice')) {
      String message = saveError(
        gw8,
        new List<PredictionController.PredictionInput>{
          input(gw9Fixture, 1, 0)
        }
      );
      Assert.isTrue(message.contains('isn\'t part of the gameweek'), message);
    }
  }

  @IsTest
  static void postponedFixtureIsRejected() {
    Id gw8 = gameweekId(8);
    Fixture__c fixture = [
      SELECT Id
      FROM Fixture__c
      WHERE Gameweek__c = :gw8
      ORDER BY Kickoff__c DESC
      LIMIT 1
    ];
    System.runAs(admin()) {
      update new Fixture__c(Id = fixture.Id, Status__c = 'Postponed');
    }
    System.runAs(player('alice')) {
      String message = saveError(
        gw8,
        new List<PredictionController.PredictionInput>{
          input(fixture.Id, 1, 0)
        }
      );
      Assert.isTrue(message.contains('postponed'), message);
    }
  }

  @IsTest
  static void scoredPredictionShowsItsPoints() {
    Id gw8 = gameweekId(8);
    Fixture__c fixture = [
      SELECT Id
      FROM Fixture__c
      WHERE Gameweek__c = :gw8
      ORDER BY Kickoff__c
      LIMIT 1
    ];
    System.runAs(player('alice')) {
      PredictionController.saveGameweekPredictions(
        gw8,
        new List<PredictionController.PredictionInput>{
          input(fixture.Id, 2, 1)
        }
      );
    }
    System.runAs(admin()) {
      update new Fixture__c(
        Id = fixture.Id,
        Status__c = 'Finished',
        Home_Goals__c = 2,
        Away_Goals__c = 1
      );
    }
    System.runAs(player('alice')) {
      PredictionController.FixtureView row = PredictionController.getGameweek(
          gw8
        )
        .fixtures[0];
      Assert.areEqual('Scored', row.predictionStatus);
      Assert.areEqual(8, row.points);
      Assert.isTrue(row.exactScore);
      Assert.areEqual(2, row.homeGoals);
    }
  }

  @IsTest
  static void latestGameweekWhenNothingIsOpen() {
    System.runAs(admin()) {
      List<Gameweek__c> all = [SELECT Id FROM Gameweek__c];
      for (Gameweek__c gameweek : all) {
        gameweek.Locked__c = true;
      }
      update all;
    }
    System.runAs(player('alice')) {
      PredictionController.GameweekView view = PredictionController.getGameweek(
        null
      );
      Assert.areEqual(9, view.gameweekNumber);
      Assert.isNull(view.nextGameweekId);
    }
  }

  @IsTest
  static void unknownGameweekReturnsNullAndCannotBeSaved() {
    Id deleted;
    System.runAs(admin()) {
      Season__c other = new Season__c(Name = 'Other', Status__c = 'Finished');
      insert other;
      Gameweek__c gameweek = TestDataFactory.createGameweek(other.Id, 1);
      deleted = gameweek.Id;
      delete gameweek;
    }
    System.runAs(player('alice')) {
      Assert.isNull(PredictionController.getGameweek(deleted));
      String message = saveError(
        deleted,
        new List<PredictionController.PredictionInput>()
      );
      Assert.isTrue(message.contains('doesn\'t exist'), message);
    }
  }
}
