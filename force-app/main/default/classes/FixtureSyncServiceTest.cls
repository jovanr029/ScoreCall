/**
 * Uses FootballDataMock's season: 4 teams; match 1001 (MD1, Fri 21 Aug 19:00,
 * finished 3-0), 1002 (MD2, Sat 29 Aug 14:00, in play 1-1), 1003 (MD3,
 * Sat 5 Sep 14:00, timed) and 1004 (MD3, Sat 5 Sep 16:30, postponed).
 *
 * A callout can't follow DML in the same transaction, so most tests skip the
 * callouts: sync() feeds the mock's JSON straight into apply(), which allows
 * several syncs in one test. Tests of run() itself make the (mocked) callouts
 * before any DML.
 */
@IsTest
private class FixtureSyncServiceTest {
  private static final Datetime DURING_SEASON = Datetime.newInstanceGmt(
    2026,
    9,
    1,
    12,
    0,
    0
  );

  /** One sync of the mock's payloads, without callouts. */
  private static FixtureSyncService.SyncResult sync(
    FootballDataMock mock,
    Datetime now
  ) {
    FixtureSyncService.nowOverride = now;
    FootballDataClient.MatchesResponse matches = (FootballDataClient.MatchesResponse) JSON.deserialize(
      mock.bodyByPath.get('/matches'),
      FootballDataClient.MatchesResponse.class
    );
    FootballDataClient.StandingsResponse standings = (FootballDataClient.StandingsResponse) JSON.deserialize(
      mock.bodyByPath.get('/standings'),
      FootballDataClient.StandingsResponse.class
    );
    return new FixtureSyncService().apply(matches.matches, standings);
  }

  /** One sync through the real run(): mocked callouts, then DML. */
  private static FixtureSyncService.SyncResult run(
    FootballDataMock mock,
    Datetime now
  ) {
    Test.setMock(HttpCalloutMock.class, mock);
    FixtureSyncService.nowOverride = now;
    return new FixtureSyncService().run();
  }

  @IsTest
  static void runFetchesFromTheApiAndSyncs() {
    System.runAs(TestDataFactory.adminUser()) {
      FootballDataMock mock = new FootballDataMock();

      Test.startTest();
      FixtureSyncService.SyncResult result = run(mock, DURING_SEASON);
      Test.stopTest();

      Assert.areEqual(2, mock.requests.size(), 'matches + standings');
      Assert.areEqual(4, result.fixturesChanged);
      Assert.isNotNull(result.seasonId);
      Assert.isTrue(result.summary().contains('Fixtures changed: 4'));
    }
  }

  private static Fixture__c fixture(String externalId) {
    return [
      SELECT
        Name,
        Status__c,
        Home_Goals__c,
        Away_Goals__c,
        Kickoff__c,
        Gameweek__r.Number__c,
        Home_Team__r.Name
      FROM Fixture__c
      WHERE External_Id__c = :externalId
    ];
  }

  private static Gameweek__c gameweek(Integer gameweekNumber) {
    return [
      SELECT Id, Locked__c, Deadline__c
      FROM Gameweek__c
      WHERE Number__c = :gameweekNumber
    ];
  }

  @IsTest
  static void firstRunCreatesTheWholeSeason() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      FixtureSyncService.SyncResult result = sync(
        new FootballDataMock(),
        DURING_SEASON
      );
      Test.stopTest();

      Season__c season = [
        SELECT Name, External_Id__c, Status__c, Start_Date__c, End_Date__c
        FROM Season__c
      ];
      Assert.areEqual('2026/27', season.Name);
      Assert.areEqual('2502', season.External_Id__c);
      Assert.areEqual('Active', season.Status__c);
      Assert.areEqual(Date.newInstance(2027, 5, 30), season.End_Date__c);

      Team__c arsenal = [
        SELECT Name, Short_Name__c, Crest_URL__c
        FROM Team__c
        WHERE External_Id__c = '57'
      ];
      Assert.areEqual(
        'Arsenal',
        arsenal.Name,
        'Team Name is the API shortName'
      );
      Assert.areEqual('ARS', arsenal.Short_Name__c);
      Assert.areEqual(
        'https://crests.football-data.org/57.png',
        arsenal.Crest_URL__c
      );

      Assert.areEqual(3, [SELECT COUNT() FROM Gameweek__c]);
      Assert.areEqual(
        '2026/27 GW 3',
        [SELECT Name FROM Gameweek__c WHERE Number__c = 3].Name
      );

      Fixture__c finished = fixture('1001');
      Assert.areEqual('ARS v CHE', finished.Name);
      Assert.areEqual('Finished', finished.Status__c);
      Assert.areEqual(3, finished.Home_Goals__c);
      Assert.areEqual(0, finished.Away_Goals__c);
      Assert.areEqual(1, finished.Gameweek__r.Number__c);
      Assert.areEqual(
        Datetime.newInstanceGmt(2026, 8, 21, 19, 0, 0),
        finished.Kickoff__c
      );
      Assert.areEqual('Live', fixture('1002').Status__c);
      Assert.areEqual('Scheduled', fixture('1003').Status__c);
      Assert.isNull(fixture('1003').Home_Goals__c);
      Assert.areEqual('Postponed', fixture('1004').Status__c);

      Assert.areEqual(
        1,
        [
          SELECT Position__c
          FROM Season_Team__c
          WHERE Team__r.Short_Name__c = 'ARS'
        ]
        .Position__c
      );
      Assert.areEqual(4, [SELECT COUNT() FROM Season_Team__c]);

      Assert.areEqual(4, result.fixturesChanged);
      Assert.areEqual(4, result.teamsChanged);
      Assert.areEqual(3, result.gameweeksCreated);
      Assert.areEqual(4, result.seasonTeamsChanged);
    }
  }

  @IsTest
  static void secondRunWithSameDataChangesNothing() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      sync(new FootballDataMock(), DURING_SEASON);
      FixtureSyncService.SyncResult second = sync(
        new FootballDataMock(),
        DURING_SEASON
      );
      Test.stopTest();

      Assert.areEqual(0, second.fixturesChanged);
      Assert.areEqual(0, second.teamsChanged);
      Assert.areEqual(0, second.gameweeksCreated);
      Assert.areEqual(0, second.seasonTeamsChanged);
      Assert.areEqual(4, [SELECT COUNT() FROM Fixture__c], 'No duplicates');
      Assert.areEqual(1, [SELECT COUNT() FROM Season__c]);
    }
  }

  @IsTest
  static void newResultUpdatesOnlyThatFixture() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      sync(new FootballDataMock(), DURING_SEASON);

      FootballDataMock later = new FootballDataMock();
      later.bodyByPath.put(
        '/matches',
        matchesJson(
          new List<String>{
            FootballDataMock.match(
              1001,
              '2026-08-21T19:00:00Z',
              'FINISHED',
              1,
              FootballDataMock.ARS,
              FootballDataMock.CHE,
              3,
              0
            ),
            FootballDataMock.match(
              1002,
              '2026-08-29T14:00:00Z',
              'FINISHED',
              2,
              FootballDataMock.LIV,
              FootballDataMock.MCI,
              2,
              1
            ),
            FootballDataMock.match(
              1003,
              '2026-09-05T14:00:00Z',
              'TIMED',
              3,
              FootballDataMock.CHE,
              FootballDataMock.LIV,
              null,
              null
            ),
            FootballDataMock.match(
              1004,
              '2026-09-05T16:30:00Z',
              'POSTPONED',
              3,
              FootballDataMock.MCI,
              FootballDataMock.ARS,
              null,
              null
            )
          }
        )
      );
      FixtureSyncService.SyncResult result = sync(later, DURING_SEASON);
      Test.stopTest();

      Assert.areEqual(1, result.fixturesChanged);
      Fixture__c updated = fixture('1002');
      Assert.areEqual('Finished', updated.Status__c);
      Assert.areEqual(2, updated.Home_Goals__c);
      Assert.areEqual(1, updated.Away_Goals__c);
    }
  }

  @IsTest
  static void rescheduledMatchMovesToTheGameweekItIsPlayedIn() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      sync(new FootballDataMock(), DURING_SEASON);

      // 1004 (MD3) rescheduled to Sunday 30 Aug: after GW2's deadline, before GW3's.
      FootballDataMock later = new FootballDataMock();
      later.bodyByPath.put(
        '/matches',
        matchesJson(
          new List<String>{
            FootballDataMock.match(
              1001,
              '2026-08-21T19:00:00Z',
              'FINISHED',
              1,
              FootballDataMock.ARS,
              FootballDataMock.CHE,
              3,
              0
            ),
            FootballDataMock.match(
              1002,
              '2026-08-29T14:00:00Z',
              'IN_PLAY',
              2,
              FootballDataMock.LIV,
              FootballDataMock.MCI,
              1,
              1
            ),
            FootballDataMock.match(
              1003,
              '2026-09-05T14:00:00Z',
              'TIMED',
              3,
              FootballDataMock.CHE,
              FootballDataMock.LIV,
              null,
              null
            ),
            FootballDataMock.match(
              1004,
              '2026-08-30T15:00:00Z',
              'TIMED',
              3,
              FootballDataMock.MCI,
              FootballDataMock.ARS,
              null,
              null
            )
          }
        )
      );
      sync(later, DURING_SEASON);
      Test.stopTest();

      Fixture__c moved = fixture('1004');
      Assert.areEqual(2, moved.Gameweek__r.Number__c, 'Reparented to GW2');
      Assert.areEqual('Scheduled', moved.Status__c);
    }
  }

  @IsTest
  static void gameweekLocksOnceItsDeadlineHasPassed() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      // Between GW2's deadline (29 Aug 13:00) and GW3's (5 Sep 13:00)
      FixtureSyncService.SyncResult result = sync(
        new FootballDataMock(),
        DURING_SEASON
      );
      Test.stopTest();

      Assert.isTrue(gameweek(1).Locked__c);
      Assert.isTrue(gameweek(2).Locked__c);
      Assert.isFalse(gameweek(3).Locked__c);
      Assert.areEqual(2, result.gameweeksLocked);
    }
  }

  @IsTest
  static void lastMinutePostponementDoesNotReopenTheGameweek() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      // Run 1, before GW3's deadline: GW3 open. First kickoff 14:00, deadline 13:00.
      sync(
        new FootballDataMock(),
        Datetime.newInstanceGmt(2026, 9, 5, 12, 0, 0)
      );
      Assert.isFalse(gameweek(3).Locked__c);

      // 13:50: GW3's first match (1003, 14:00) is postponed. Next sync at 14:00.
      FootballDataMock later = new FootballDataMock();
      later.bodyByPath.put(
        '/matches',
        matchesJson(
          new List<String>{
            FootballDataMock.match(
              1001,
              '2026-08-21T19:00:00Z',
              'FINISHED',
              1,
              FootballDataMock.ARS,
              FootballDataMock.CHE,
              3,
              0
            ),
            FootballDataMock.match(
              1002,
              '2026-08-29T14:00:00Z',
              'FINISHED',
              2,
              FootballDataMock.LIV,
              FootballDataMock.MCI,
              1,
              1
            ),
            FootballDataMock.match(
              1003,
              '2026-09-05T14:00:00Z',
              'POSTPONED',
              3,
              FootballDataMock.CHE,
              FootballDataMock.LIV,
              null,
              null
            ),
            FootballDataMock.match(
              1004,
              '2026-09-05T16:30:00Z',
              'TIMED',
              3,
              FootballDataMock.MCI,
              FootballDataMock.ARS,
              null,
              null
            )
          }
        )
      );
      sync(later, Datetime.newInstanceGmt(2026, 9, 5, 14, 0, 0));
      Test.stopTest();

      Gameweek__c gw3 = gameweek(3);
      Assert.areEqual(
        Datetime.newInstanceGmt(2026, 9, 5, 15, 30, 0),
        gw3.Deadline__c,
        'The deadline moved later (first kickoff is now 16:30)...'
      );
      Assert.isTrue(gw3.Locked__c, '...but the gameweek stays locked');
    }
  }

  @IsTest
  static void lockedGameweekCannotBeUnlocked() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      sync(new FootballDataMock(), DURING_SEASON);
      Test.stopTest();

      try {
        update new Gameweek__c(Id = gameweek(1).Id, Locked__c = false);
        Assert.fail('Unlocking must be rejected');
      } catch (DmlException e) {
        Assert.areEqual(
          StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
          e.getDmlType(0)
        );
      }
    }
  }

  @IsTest
  static void upcomingSeasonGetsTablePredictionDeadline() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      sync(
        new FootballDataMock(),
        Datetime.newInstanceGmt(2026, 8, 1, 12, 0, 0)
      );
      Test.stopTest();

      Season__c season = [
        SELECT Status__c, Table_Prediction_Deadline__c
        FROM Season__c
      ];
      Assert.areEqual('Upcoming', season.Status__c);
      Assert.areEqual(
        Datetime.newInstanceGmt(2026, 8, 21, 18, 0, 0),
        season.Table_Prediction_Deadline__c
      );
    }
  }

  @IsTest
  static void existingTablePredictionDeadlineIsKept() {
    System.runAs(TestDataFactory.adminUser()) {
      Datetime launch = Datetime.newInstanceGmt(2026, 10, 30, 18, 0, 0);
      insert new Season__c(
        Name = '2026/27',
        External_Id__c = '2502',
        Status__c = 'Active',
        Table_Prediction_Deadline__c = launch
      );

      Test.startTest();
      sync(new FootballDataMock(), DURING_SEASON);
      Test.stopTest();

      Assert.areEqual(
        launch,
        [SELECT Table_Prediction_Deadline__c FROM Season__c]
        .Table_Prediction_Deadline__c
      );
    }
  }

  @IsTest
  static void allFinishedMeansSeasonFinished() {
    System.runAs(TestDataFactory.adminUser()) {
      FootballDataMock mock = new FootballDataMock();
      mock.bodyByPath.put(
        '/matches',
        matchesJson(
          new List<String>{
            FootballDataMock.match(
              1001,
              '2026-08-21T19:00:00Z',
              'FINISHED',
              1,
              FootballDataMock.ARS,
              FootballDataMock.CHE,
              3,
              0
            ),
            FootballDataMock.match(
              1002,
              '2026-08-29T14:00:00Z',
              'AWARDED',
              2,
              FootballDataMock.LIV,
              FootballDataMock.MCI,
              3,
              0
            )
          }
        )
      );

      Test.startTest();
      sync(mock, Datetime.newInstanceGmt(2027, 6, 1, 12, 0, 0));
      Test.stopTest();

      Assert.areEqual('Finished', [SELECT Status__c FROM Season__c].Status__c);
    }
  }

  @IsTest
  static void apiErrorWritesNothing() {
    System.runAs(TestDataFactory.adminUser()) {
      FootballDataMock mock = new FootballDataMock();
      mock.statusByPath.put('/standings', 500);

      Test.startTest();
      try {
        run(mock, DURING_SEASON);
        Assert.fail('Expected an exception');
      } catch (FootballDataClient.FootballDataException e) {
        Assert.isTrue(e.getMessage().contains('HTTP 500'), e.getMessage());
      }
      Test.stopTest();

      Assert.areEqual(0, [SELECT COUNT() FROM Fixture__c]);
      Assert.areEqual(0, [SELECT COUNT() FROM Season__c]);
    }
  }

  @IsTest
  static void emptyMatchListIsAnError() {
    System.runAs(TestDataFactory.adminUser()) {
      FootballDataMock mock = new FootballDataMock();
      mock.bodyByPath.put('/matches', '{"matches":[]}');

      Test.startTest();
      try {
        sync(mock, DURING_SEASON);
        Assert.fail('Expected an exception');
      } catch (FootballDataClient.FootballDataException e) {
        Assert.isTrue(e.getMessage().contains('no matches'), e.getMessage());
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void failureDuringWritesRollsEverythingBack() {
    System.runAs(TestDataFactory.adminUser()) {
      // A finished match without a score breaks the Finished_Requires_Score
      // validation rule after season, teams and gameweeks were already written.
      FootballDataMock mock = new FootballDataMock();
      mock.bodyByPath.put(
        '/matches',
        matchesJson(
          new List<String>{
            FootballDataMock.match(
              1001,
              '2026-08-21T19:00:00Z',
              'FINISHED',
              1,
              FootballDataMock.ARS,
              FootballDataMock.CHE,
              null,
              null
            )
          }
        )
      );

      Test.startTest();
      try {
        sync(mock, DURING_SEASON);
        Assert.fail('Expected a DmlException');
      } catch (DmlException e) {
        Assert.areEqual(
          StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
          e.getDmlType(0)
        );
      }
      Test.stopTest();

      Assert.areEqual(0, [SELECT COUNT() FROM Season__c], 'Rolled back');
      Assert.areEqual(0, [SELECT COUNT() FROM Team__c], 'Rolled back');
    }
  }

  @IsTest
  static void mapsEveryApiStatus() {
    Map<String, String> expected = new Map<String, String>{
      'SCHEDULED' => 'Scheduled',
      'TIMED' => 'Scheduled',
      'IN_PLAY' => 'Live',
      'PAUSED' => 'Live',
      'FINISHED' => 'Finished',
      'AWARDED' => 'Finished',
      'POSTPONED' => 'Postponed',
      'SUSPENDED' => 'Postponed',
      'CANCELLED' => 'Postponed',
      'SOMETHING_NEW' => 'Scheduled'
    };
    for (String apiStatus : expected.keySet()) {
      Assert.areEqual(
        expected.get(apiStatus),
        FixtureSyncService.fixtureStatus(apiStatus),
        apiStatus
      );
    }
  }

  private static String matchesJson(List<String> matches) {
    return '{"matches":[' + String.join(matches, ',') + ']}';
  }
}
