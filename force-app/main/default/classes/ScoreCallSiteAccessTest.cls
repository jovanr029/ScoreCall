/**
 * Friends play on the Experience Cloud site as Customer Community users. This
 * runs as two such users, set up the way scripts/apex/add-friend.apex does
 * (ScoreCall Friend profile + ScoreCall_Player), and proves that through the
 * site's Apex they can load a gameweek, save their own predictions, and never
 * see each other's.
 *
 * External users follow the external sharing model, not the internal one, so
 * ScoreCallPlayerAccessTest (internal users) doesn't cover this.
 */
@IsTest
private class ScoreCallSiteAccessTest {
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

    // Each System.runAs block is a separate context, so mixing setup objects
    // (User, PermissionSetAssignment) and data (Account, Contact) across
    // blocks avoids MIXED_DML_OPERATION.
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
      List<Team__c> teams = TestDataFactory.createTeams(2);
      Gameweek__c gameweek = TestDataFactory.createGameweek(season.Id, 8);
      insert TestDataFactory.buildFixture(
        gameweek.Id,
        teams[0],
        teams[1],
        System.now().addDays(2)
      );
    }
  }

  @IsTest
  static void friendLoadsTheGameweekAndSavesOwnPrediction() {
    User carol = friend('carol');
    System.runAs(carol) {
      PredictionController.GameweekView view = PredictionController.getGameweek(
        null
      );
      Assert.areEqual(8, view.gameweekNumber);
      Assert.areEqual(1, view.fixtures.size(), 'Game data is readable');
      Assert.areEqual('Team 1', view.fixtures[0].homeTeam);

      PredictionController.saveGameweekPredictions(
        view.gameweekId,
        new List<PredictionController.PredictionInput>{
          input(view.fixtures[0].fixtureId, 2, 1)
        }
      );
    }

    Prediction__c saved = [
      SELECT OwnerId, Home_Goals__c, Away_Goals__c
      FROM Prediction__c
    ];
    Assert.areEqual(carol.Id, saved.OwnerId, 'The friend owns the prediction');
    Assert.areEqual(2, saved.Home_Goals__c);
    Assert.areEqual(1, saved.Away_Goals__c);
  }

  @IsTest
  static void friendsDontSeeEachOthersPredictions() {
    System.runAs(friend('dave')) {
      PredictionController.GameweekView view = PredictionController.getGameweek(
        null
      );
      PredictionController.saveGameweekPredictions(
        view.gameweekId,
        new List<PredictionController.PredictionInput>{
          input(view.fixtures[0].fixtureId, 0, 3)
        }
      );
    }

    System.runAs(friend('carol')) {
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Prediction__c WITH USER_MODE],
        'Predictions are private to their owner, also between site users'
      );
      PredictionController.GameweekView view = PredictionController.getGameweek(
        null
      );
      Assert.isNull(
        view.fixtures[0].predictedHome,
        'The screen shows only the friend\'s own prediction'
      );
    }
  }

  private static User friend(String alias) {
    return [
      SELECT Id
      FROM User
      WHERE Alias = :alias AND Email = :(alias + '@scorecall.test')
    ];
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
}
