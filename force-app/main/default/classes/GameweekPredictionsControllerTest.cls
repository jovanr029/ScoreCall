/**
 * Everyone's predictions after the deadline, read by a friend on the site
 * (Customer Community users carol and dave, internal player alice).
 *
 * GW6, GW7: deadline passed. GW8: still open.
 * GW7  match 1 (2-1): alice 2-1 (+8), carol 2-1 (+8), dave 1-0 (+3)
 *      match 2 (0-0): alice -,        carol 1-1 (+3), dave 0-0 (+8)
 * GW8  carol and dave have predicted; nobody may see the other's yet.
 */
@IsTest
private class GameweekPredictionsControllerTest {
  @TestSetup
  static void setup() {
    User owner = TestDataFactory.buildUser('owner', 'System Administrator');
    owner.UserRoleId = [
      SELECT Id
      FROM UserRole
      WHERE DeveloperName = 'ScoreCall_Admin'
    ]
    .Id;
    insert owner;
    TestDataFactory.assignPermissionSet(owner.Id, 'ScoreCall_Admin');

    User alice = TestDataFactory.buildUser(
      'alice',
      'Minimum Access - Salesforce'
    );
    alice.FirstName = 'Alice';
    insert alice;
    TestDataFactory.assignPermissionSet(alice.Id, 'ScoreCall_Player');

    // Separate System.runAs blocks keep users and data apart (MIXED_DML).
    List<Contact> friends = new List<Contact>();
    System.runAs(owner) {
      Account players = new Account(Name = 'ScoreCall Players');
      insert players;
      for (String alias : new List<String>{ 'carol', 'dave' }) {
        friends.add(
          new Contact(
            AccountId = players.Id,
            LastName = alias,
            Email = alias + '@scorecall.test'
          )
        );
      }
      insert friends;
    }
    System.runAs(owner) {
      List<User> siteUsers = new List<User>();
      for (Contact friend : friends) {
        User siteUser = TestDataFactory.buildUser(
          friend.LastName,
          'ScoreCall Friend'
        );
        siteUser.FirstName = friend.LastName.capitalize();
        siteUser.ContactId = friend.Id;
        siteUsers.add(siteUser);
      }
      insert siteUsers;
      for (User siteUser : siteUsers) {
        TestDataFactory.assignPermissionSet(siteUser.Id, 'ScoreCall_Player');
      }
    }

    System.runAs(owner) {
      Season__c season = TestDataFactory.createSeason();
      List<Team__c> teams = TestDataFactory.createTeams(4);
      Gameweek__c gw6 = TestDataFactory.createGameweek(season.Id, 6);
      Gameweek__c gw7 = TestDataFactory.createGameweek(season.Id, 7);
      Gameweek__c gw8 = TestDataFactory.createGameweek(season.Id, 8);

      Fixture__c gw6match = TestDataFactory.buildFixture(
        gw6.Id,
        teams[0],
        teams[3],
        System.now().addDays(-12)
      );
      Fixture__c match1 = finished(
        TestDataFactory.buildFixture(
          gw7.Id,
          teams[0],
          teams[1],
          System.now().addDays(-5)
        ),
        2,
        1
      );
      Fixture__c match2 = finished(
        TestDataFactory.buildFixture(
          gw7.Id,
          teams[2],
          teams[3],
          System.now().addDays(-5).addHours(3)
        ),
        0,
        0
      );
      Fixture__c open = TestDataFactory.buildFixture(
        gw8.Id,
        teams[0],
        teams[2],
        System.now().addDays(2)
      );
      insert new List<Fixture__c>{ gw6match, match1, match2, open };

      insert new List<Prediction__c>{
        scored(match1, player('alice'), 2, 1, 8),
        scored(match1, player('carol'), 2, 1, 8),
        scored(match1, player('dave'), 1, 0, 3),
        scored(match2, player('carol'), 1, 1, 3),
        scored(match2, player('dave'), 0, 0, 8),
        unscored(open, player('carol'), 3, 0),
        unscored(open, player('dave'), 0, 2)
      };
    }
  }

  private static Fixture__c finished(
    Fixture__c fixture,
    Integer homeGoals,
    Integer awayGoals
  ) {
    fixture.Status__c = 'Finished';
    fixture.Home_Goals__c = homeGoals;
    fixture.Away_Goals__c = awayGoals;
    return fixture;
  }

  private static Prediction__c scored(
    Fixture__c fixture,
    Id ownerId,
    Integer home,
    Integer away,
    Integer points
  ) {
    Prediction__c prediction = unscored(fixture, ownerId, home, away);
    prediction.Status__c = 'Scored';
    prediction.Points__c = points;
    prediction.Exact_Score__c = points == 8;
    return prediction;
  }

  private static Prediction__c unscored(
    Fixture__c fixture,
    Id ownerId,
    Integer home,
    Integer away
  ) {
    Prediction__c prediction = TestDataFactory.buildPrediction(
      fixture,
      home,
      away
    );
    prediction.OwnerId = ownerId;
    return prediction;
  }

  private static Id player(String alias) {
    return [
      SELECT Id
      FROM User
      WHERE Alias = :alias AND Email = :(alias + '@scorecall.test')
    ]
    .Id;
  }

  private static User friend(String alias) {
    return [SELECT Id FROM User WHERE Id = :player(alias)];
  }

  private static Id gameweekId(Integer gameweekNumber) {
    return [SELECT Id FROM Gameweek__c WHERE Number__c = :gameweekNumber].Id;
  }

  private static String refusal(Id gameweekId) {
    String message;
    System.runAs(friend('carol')) {
      try {
        GameweekPredictionsController.getGameweekPredictions(gameweekId);
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }
    return message;
  }

  @IsTest
  static void aFriendSeesEveryonesPredictionsAfterTheDeadline() {
    GameweekPredictionsController.GameweekPredictionsView view;
    System.runAs(friend('carol')) {
      view = GameweekPredictionsController.getGameweekPredictions(null);
    }

    Assert.areEqual(gameweekId(7), view.gameweekId, 'Latest past deadline');
    Assert.areEqual(3, view.players.size());
    Assert.areEqual(2, view.matches.size());

    // Players sorted by gameweek points: carol 11 (1 exact), dave 11
    // (1 exact), alice 8 (1 exact); carol before dave by name.
    Assert.isTrue(view.players[0].name.startsWith('Carol'));
    Assert.isTrue(view.players[0].isCurrentUser);
    Assert.areEqual(11, view.players[0].points);
    Assert.isTrue(view.players[1].name.startsWith('Dave'));
    Assert.isTrue(view.players[2].name.startsWith('Alice'));
    Assert.areEqual(8, view.players[2].points);

    GameweekPredictionsController.MatchView match1 = view.matches[0];
    Assert.areEqual(2, match1.homeGoals);
    Assert.areEqual(1, match1.awayGoals);
    GameweekPredictionsController.PlayerPrediction dave = match1.predictions[1];
    Assert.areEqual(1, dave.homeGoals, 'Another player\'s prediction');
    Assert.areEqual(0, dave.awayGoals);
    Assert.areEqual(3, dave.points);
  }

  @IsTest
  static void aMissingPredictionIsEmpty() {
    GameweekPredictionsController.GameweekPredictionsView view;
    System.runAs(friend('dave')) {
      view = GameweekPredictionsController.getGameweekPredictions(
        gameweekId(7)
      );
    }
    GameweekPredictionsController.PlayerPrediction alice = view.matches[1]
      .predictions[2];
    Assert.isTrue(alice.name.startsWith('Alice'));
    Assert.isNull(alice.homeGoals);
    Assert.isNull(alice.points);
  }

  @IsTest
  static void beforeTheDeadlineOtherPredictionsAreRefused() {
    Assert.areEqual(
      'Other players\' predictions are visible after the gameweek deadline.',
      refusal(gameweekId(8)),
      'Checked in Apex, whatever the browser asks for'
    );
  }

  @IsTest
  static void gameweeksPastTheDeadlineCanBeBrowsed() {
    GameweekPredictionsController.GameweekPredictionsView gw7;
    GameweekPredictionsController.GameweekPredictionsView gw6;
    System.runAs(friend('carol')) {
      gw7 = GameweekPredictionsController.getGameweekPredictions(null);
      gw6 = GameweekPredictionsController.getGameweekPredictions(
        gw7.previousGameweekId
      );
    }
    Assert.areEqual(gameweekId(6), gw7.previousGameweekId);
    Assert.isNull(gw7.nextGameweekId, 'GW8 is still open');
    Assert.areEqual(gameweekId(6), gw6.gameweekId);
    Assert.areEqual(gameweekId(7), gw6.nextGameweekId);
    Assert.isNull(gw6.previousGameweekId);
    Assert.areEqual(0, gw6.players.size(), 'Nobody predicted GW6');
    Assert.areEqual(1, gw6.matches.size());
  }

  @IsTest
  static void nothingToShowBeforeTheFirstDeadline() {
    User owner = [
      SELECT Id
      FROM User
      WHERE Alias = 'owner' AND IsActive = TRUE
      LIMIT 1
    ];
    System.runAs(owner) {
      Season__c season = [SELECT Id FROM Season__c];
      season.Status__c = 'Finished';
      update season;
    }
    GameweekPredictionsController.GameweekPredictionsView view;
    System.runAs(friend('carol')) {
      view = GameweekPredictionsController.getGameweekPredictions(null);
    }
    Assert.isNull(view.gameweekId);
    Assert.areEqual(0, view.matches.size());
    Assert.isNotNull(refusal(gameweekId(7)), 'No active season: refused');
  }
}
