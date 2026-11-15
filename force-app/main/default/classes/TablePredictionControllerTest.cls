/**
 * The table prediction screen (#18), used by friends on the site (Customer
 * Community users carol and dave): starting order, saving and reordering,
 * the deadline enforced in Apex, everyone's tables after the deadline, and
 * "if the season ended today" points.
 *
 * A small season of 4 teams; the current table is Team 1, 2, 3, 4.
 */
@IsTest
private class TablePredictionControllerTest {
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
      season.Table_Prediction_Deadline__c = System.now().addDays(7);
      update season;
      List<Team__c> teams = TestDataFactory.createTeams(4);
      List<Season_Team__c> table = new List<Season_Team__c>();
      for (Integer i = 0; i < teams.size(); i++) {
        table.add(
          new Season_Team__c(
            Season__c = season.Id,
            Team__c = teams[i].Id,
            Position__c = i + 1
          )
        );
      }
      insert table;
    }
  }

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

  private static User friend(String alias) {
    return [
      SELECT Id
      FROM User
      WHERE Alias = :alias AND Email = :(alias + '@scorecall.test')
    ];
  }

  private static User owner() {
    return [SELECT Id FROM User WHERE Alias = 'owner' LIMIT 1];
  }

  private static Id seasonId() {
    return [SELECT Id FROM Season__c].Id;
  }

  /** Team Ids in the given order of team numbers, e.g. (4, 1, 2, 3). */
  private static List<Id> teams(List<Integer> numbers) {
    Map<String, Id> byName = new Map<String, Id>();
    for (Team__c team : [SELECT Id, Name FROM Team__c]) {
      byName.put(team.Name, team.Id);
    }
    List<Id> ordered = new List<Id>();
    for (Integer n : numbers) {
      ordered.add(byName.get('Team ' + n));
    }
    return ordered;
  }

  private static List<String> names(
    List<TablePredictionController.TableRow> rows
  ) {
    List<String> names = new List<String>();
    for (TablePredictionController.TableRow row : rows) {
      names.add(row.teamName);
    }
    return names;
  }

  private static void setDeadline(Datetime deadline) {
    System.runAs(owner()) {
      update new Season__c(
        Id = seasonId(),
        Table_Prediction_Deadline__c = deadline
      );
    }
  }

  private static String saveError(User player, List<Id> teamIds) {
    String message;
    System.runAs(player) {
      try {
        TablePredictionController.saveTablePrediction(seasonId(), teamIds);
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }
    Assert.isNotNull(message, 'Expected the save to be refused');
    return message;
  }

  @IsTest
  static void aNewPlayerStartsFromTheCurrentTable() {
    TablePredictionController.TableView view;
    System.runAs(friend('carol')) {
      view = TablePredictionController.getTablePrediction();
    }
    Assert.isTrue(view.isOpen);
    Assert.isFalse(view.hasSaved);
    Assert.areEqual(
      new List<String>{ 'Team 1', 'Team 2', 'Team 3', 'Team 4' },
      names(view.myTable)
    );
    Assert.areEqual(1, view.myTable[0].predictedPosition);
    Assert.areEqual(0, view.players.size(), 'Nobody else\'s before deadline');
  }

  @IsTest
  static void aFriendSavesAndReordersTheirTable() {
    pinRules();
    TablePredictionController.TableView saved;
    TablePredictionController.TableView reordered;
    System.runAs(friend('carol')) {
      saved = TablePredictionController.saveTablePrediction(
        seasonId(),
        teams(new List<Integer>{ 4, 3, 2, 1 })
      );
      // Swapping positions must not trip the unique position key.
      reordered = TablePredictionController.saveTablePrediction(
        seasonId(),
        teams(new List<Integer>{ 3, 4, 2, 1 })
      );
    }
    Assert.isTrue(saved.hasSaved);
    Assert.areEqual(
      new List<String>{ 'Team 3', 'Team 4', 'Team 2', 'Team 1' },
      names(reordered.myTable)
    );
    Assert.areEqual(
      4,
      [
        SELECT COUNT()
        FROM Table_Prediction__c
        WHERE OwnerId = :friend('carol').Id
      ],
      'Still one row per team'
    );
    // "If the season ended today": Team 3 predicted 1st, now 3rd -> 2 off
    Assert.areEqual(10, reordered.myTable[0].points);
    Assert.areEqual(3, reordered.myTable[0].currentPosition);
  }

  @IsTest
  static void aTableMustContainEveryTeamOnce() {
    Assert.areEqual(
      'Put all 4 teams in order, each once.',
      saveError(friend('carol'), teams(new List<Integer>{ 1, 2, 3 }))
    );
    Assert.areEqual(
      'Put all 4 teams in order, each once.',
      saveError(friend('carol'), teams(new List<Integer>{ 1, 2, 3, 3 }))
    );
  }

  @IsTest
  static void theDeadlineIsEnforcedInApex() {
    setDeadline(System.now().addMinutes(-1));
    Assert.areEqual(
      'The table prediction deadline has passed.',
      saveError(friend('carol'), teams(new List<Integer>{ 1, 2, 3, 4 }))
    );
  }

  @IsTest
  static void notOpenUntilTheDeadlineIsSet() {
    setDeadline(null);
    TablePredictionController.TableView view;
    System.runAs(friend('carol')) {
      view = TablePredictionController.getTablePrediction();
    }
    Assert.isFalse(view.isOpen);
    Assert.areEqual(
      'Table predictions aren\'t open yet.',
      saveError(friend('carol'), teams(new List<Integer>{ 1, 2, 3, 4 }))
    );
  }

  @IsTest
  static void afterTheDeadlineEveryonesTablesAreVisible() {
    pinRules();
    System.runAs(friend('carol')) {
      TablePredictionController.saveTablePrediction(
        seasonId(),
        teams(new List<Integer>{ 1, 2, 3, 4 })
      );
    }
    System.runAs(friend('dave')) {
      TablePredictionController.saveTablePrediction(
        seasonId(),
        teams(new List<Integer>{ 4, 3, 2, 1 })
      );
    }
    setDeadline(System.now().addMinutes(-1));

    TablePredictionController.TableView view;
    System.runAs(friend('carol')) {
      view = TablePredictionController.getTablePrediction();
    }
    Assert.isFalse(view.isOpen);
    Assert.areEqual(2, view.players.size());
    // carol: all exact today = 80; dave: 3 off (5) + 1 off (15) x2 + 3 off (5) = 40
    Assert.isTrue(view.players[0].name.startsWith('Carol'));
    Assert.isTrue(view.players[0].isCurrentUser);
    Assert.areEqual(80, view.players[0].points);
    Assert.isTrue(view.players[1].name.startsWith('Dave'));
    Assert.areEqual(40, view.players[1].points);
    Assert.areEqual(
      new List<String>{ 'Team 4', 'Team 3', 'Team 2', 'Team 1' },
      names(view.players[1].rows),
      'Another player\'s table, after the deadline'
    );
  }

  @IsTest
  static void aSavedTableKeepsItsOrderOnReload() {
    pinRules();
    System.runAs(friend('dave')) {
      TablePredictionController.saveTablePrediction(
        seasonId(),
        teams(new List<Integer>{ 2, 1, 4, 3 })
      );
    }
    TablePredictionController.TableView view;
    System.runAs(friend('dave')) {
      view = TablePredictionController.getTablePrediction();
    }
    Assert.isTrue(view.hasSaved);
    Assert.areEqual(
      new List<String>{ 'Team 2', 'Team 1', 'Team 4', 'Team 3' },
      names(view.myTable)
    );
  }

  @IsTest
  static void anotherSeasonCannotBeSaved() {
    Assert.areEqual(
      'This season isn\'t open for table predictions.',
      saveErrorForSeason(null)
    );
  }

  private static String saveErrorForSeason(Id otherSeasonId) {
    String message;
    System.runAs(friend('carol')) {
      try {
        TablePredictionController.saveTablePrediction(
          otherSeasonId,
          teams(new List<Integer>{ 1, 2, 3, 4 })
        );
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }
    return message;
  }
}
