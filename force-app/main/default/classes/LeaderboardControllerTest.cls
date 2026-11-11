/**
 * Standings and the tie-breaker, read by a friend on the site: two Customer
 * Community users (carol, dave) and one internal player (alice). The friend
 * must see everyone's totals and names, but predictions stay private.
 *
 * GW7 (deadline passed):  alice 8 + 8 = 16 (2 exact)
 *                         carol 8 + 3 = 11 (1 exact)
 *                         dave  3 + 8 = 11 (1 exact)   -> carol and dave share 2nd
 * GW8 (still open): nothing scored, and not offered in the gameweek picker.
 */
@IsTest
private class LeaderboardControllerTest {
  @TestSetup
  static void setup() {
    // A site user's account must be owned by a user with a role.
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

    // Each System.runAs block is a separate context, so users and data don't
    // mix (MIXED_DML_OPERATION).
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
      Gameweek__c played = TestDataFactory.createGameweek(season.Id, 7);
      Gameweek__c open = TestDataFactory.createGameweek(season.Id, 8);
      List<Fixture__c> fixtures = new List<Fixture__c>{
        TestDataFactory.buildFixture(
          played.Id,
          teams[0],
          teams[1],
          System.now().addDays(-5)
        ),
        TestDataFactory.buildFixture(
          played.Id,
          teams[2],
          teams[3],
          System.now().addDays(-5)
        ),
        TestDataFactory.buildFixture(
          open.Id,
          teams[0],
          teams[2],
          System.now().addDays(2)
        )
      };
      insert fixtures;

      List<Prediction__c> predictions = new List<Prediction__c>();
      predictions.add(scored(fixtures[0], player('alice'), 8));
      predictions.add(scored(fixtures[1], player('alice'), 8));
      predictions.add(scored(fixtures[0], player('carol'), 8));
      predictions.add(scored(fixtures[1], player('carol'), 3));
      predictions.add(scored(fixtures[0], player('dave'), 3));
      predictions.add(scored(fixtures[1], player('dave'), 8));
      Prediction__c open8 = TestDataFactory.buildPrediction(fixtures[2], 1, 0);
      open8.OwnerId = player('carol');
      predictions.add(open8);
      insert predictions;
    }
  }

  private static Prediction__c scored(
    Fixture__c fixture,
    Id ownerId,
    Integer points
  ) {
    Prediction__c prediction = TestDataFactory.buildPrediction(fixture, 1, 0);
    prediction.OwnerId = ownerId;
    prediction.Status__c = 'Scored';
    prediction.Points__c = points;
    prediction.Exact_Score__c = points == 8;
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

  private static User owner() {
    return [SELECT Id FROM User WHERE Alias = 'owner' LIMIT 1];
  }

  private static User friend(String alias) {
    return [SELECT Id FROM User WHERE Id = :player(alias)];
  }

  private static Id gameweekId(Integer gameweekNumber) {
    return [SELECT Id FROM Gameweek__c WHERE Number__c = :gameweekNumber].Id;
  }

  @IsTest
  static void aFriendSeesTheSeasonStandingsWithSharedPlaces() {
    LeaderboardController.LeaderboardView view;
    System.runAs(friend('carol')) {
      view = LeaderboardController.getLeaderboard(null);
    }

    Assert.areEqual('2026/27', view.seasonName);
    Assert.areEqual(3, view.rows.size());

    LeaderboardController.Row first = view.rows[0];
    Assert.areEqual(1, first.rank);
    Assert.isTrue(first.name.startsWith('Alice'), first.name);
    Assert.areEqual(16, first.points);
    Assert.areEqual(2, first.exactScores);

    // carol and dave: 11 points, 1 exact each -> both 2nd, in name order
    Assert.areEqual(2, view.rows[1].rank);
    Assert.areEqual(2, view.rows[2].rank);
    Assert.isTrue(view.rows[1].name.startsWith('Carol'), view.rows[1].name);
    Assert.isTrue(view.rows[1].isCurrentUser, 'The friend\'s own row');
    Assert.isFalse(view.rows[2].isCurrentUser);
    Assert.areEqual(11, view.rows[2].points);
  }

  @IsTest
  static void onlyGameweeksPastTheirDeadlineCanBePicked() {
    LeaderboardController.LeaderboardView view;
    System.runAs(friend('dave')) {
      view = LeaderboardController.getLeaderboard(null);
    }
    Assert.areEqual(1, view.gameweeks.size());
    Assert.areEqual(gameweekId(7), view.gameweeks[0].gameweekId);
  }

  @IsTest
  static void moreExactScoresBreakATie() {
    // dave gets 5 table prediction points: 16 like alice, but 1 exact vs 2.
    System.runAs(owner()) {
      insert new Table_Prediction__c(
        OwnerId = player('dave'),
        Season__c = [SELECT Id FROM Season__c]
        .Id,
        Team__c = [SELECT Id FROM Team__c LIMIT 1]
        .Id,
        Predicted_Position__c = 1,
        Points__c = 5
      );
    }

    LeaderboardController.LeaderboardView view;
    System.runAs(friend('carol')) {
      view = LeaderboardController.getLeaderboard(null);
    }
    Assert.areEqual(16, view.rows[1].points);
    Assert.areEqual(2, view.rows[1].rank, 'Fewer exact scores: 2nd, not 1st');
    Assert.isTrue(view.rows[1].name.startsWith('Dave'), view.rows[1].name);
    Assert.areEqual(3, view.rows[2].rank);
  }

  @IsTest
  static void gameweekViewCountsOnlyThatGameweek() {
    System.runAs(owner()) {
      insert new Table_Prediction__c(
        OwnerId = player('dave'),
        Season__c = [SELECT Id FROM Season__c]
        .Id,
        Team__c = [SELECT Id FROM Team__c LIMIT 1]
        .Id,
        Predicted_Position__c = 1,
        Points__c = 20
      );
    }

    LeaderboardController.LeaderboardView view;
    System.runAs(friend('carol')) {
      view = LeaderboardController.getLeaderboard(gameweekId(7));
    }
    Assert.areEqual(gameweekId(7), view.gameweekId);
    Assert.areEqual(16, view.rows[0].points, 'Table points are season-only');
    Assert.areEqual(11, view.rows[1].points);
    Assert.areEqual(11, view.rows[2].points);
  }

  @IsTest
  static void ranksAreSharedOnlyWhenPointsAndExactScoresAreEqual() {
    List<LeaderboardController.Row> rows = new List<LeaderboardController.Row>{
      row('B', 10, 1),
      row('A', 10, 1),
      row('C', 12, 0),
      row('D', 10, 0)
    };
    List<LeaderboardController.Row> ranked = LeaderboardController.rank(rows);

    Assert.areEqual('C', ranked[0].name);
    Assert.areEqual(1, ranked[0].rank);
    Assert.areEqual('A', ranked[1].name);
    Assert.areEqual(2, ranked[1].rank);
    Assert.areEqual('B', ranked[2].name);
    Assert.areEqual(2, ranked[2].rank);
    Assert.areEqual('D', ranked[3].name);
    Assert.areEqual(4, ranked[3].rank);
  }

  @IsTest
  static void noActiveSeasonMeansAnEmptyTable() {
    System.runAs(owner()) {
      Season__c season = [SELECT Id FROM Season__c];
      season.Status__c = 'Finished';
      update season;
    }
    LeaderboardController.LeaderboardView view;
    System.runAs(friend('carol')) {
      view = LeaderboardController.getLeaderboard(null);
    }
    Assert.isNull(view.seasonName);
    Assert.areEqual(0, view.rows.size());
  }

  private static LeaderboardController.Row row(
    String name,
    Integer points,
    Integer exactScores
  ) {
    LeaderboardController.Row row = new LeaderboardController.Row();
    row.name = name;
    row.points = points;
    row.exactScores = exactScores;
    return row;
  }
}
