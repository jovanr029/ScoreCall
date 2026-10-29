@IsTest
private class FootballDataClientTest {
  @IsTest
  static void getMatchesParsesTheFieldsWeUse() {
    FootballDataMock mock = new FootballDataMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    List<FootballDataClient.ApiMatch> matches = new FootballDataClient()
      .getMatches()
      .matches;
    Test.stopTest();

    Assert.areEqual(4, matches.size());
    FootballDataClient.ApiMatch finished = matches[0];
    Assert.areEqual(1001, finished.id);
    Assert.areEqual('FINISHED', finished.status);
    Assert.areEqual(1, finished.matchday);
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 8, 21, 19, 0, 0),
      finished.utcDate
    );
    Assert.areEqual(3, finished.score.fullTime.home);
    Assert.areEqual(0, finished.score.fullTime.away);
    Assert.areEqual('Arsenal', finished.homeTeam.shortName);
    Assert.areEqual('ARS', finished.homeTeam.tla);
    Assert.areEqual(
      'https://crests.football-data.org/57.png',
      finished.homeTeam.crest
    );
    Assert.areEqual(2502, finished.season.id);
    Assert.areEqual(Date.newInstance(2026, 8, 21), finished.season.startDate);
    Assert.isNull(matches[2].score.fullTime.home, 'Not started yet: no goals');
  }

  @IsTest
  static void getStandingsReturnsTotalTable() {
    Test.setMock(HttpCalloutMock.class, new FootballDataMock());

    Test.startTest();
    FootballDataClient.StandingsResponse standings = new FootballDataClient()
      .getStandings();
    Test.stopTest();

    List<FootballDataClient.ApiTableRow> table = standings.totalTable();
    Assert.areEqual(4, table.size());
    Assert.areEqual(1, table[0].position);
    Assert.areEqual('ARS', table[0].team.tla);
    Assert.areEqual(1, table[0].playedGames);
    Assert.areEqual(3, table[0].points);
    Assert.areEqual(2502, standings.season.id);
  }

  @IsTest
  static void totalTableIsEmptyWhenOnlyOtherTablesExist() {
    FootballDataMock mock = new FootballDataMock();
    mock.bodyByPath.put(
      '/standings',
      '{"standings":[{"type":"HOME","table":[{"position":1}]}]}'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    List<FootballDataClient.ApiTableRow> table = new FootballDataClient()
      .getStandings()
      .totalTable();
    Test.stopTest();

    Assert.isTrue(table.isEmpty());
  }

  @IsTest
  static void callsTheNamedCredentialWithGet() {
    FootballDataMock mock = new FootballDataMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    new FootballDataClient().getMatches();
    Test.stopTest();

    Assert.areEqual(1, mock.requests.size());
    Assert.areEqual(
      'callout:FootballData/v4/competitions/PL/matches',
      mock.requests[0].getEndpoint()
    );
    Assert.areEqual('GET', mock.requests[0].getMethod());
  }

  @IsTest
  static void errorResponseThrowsWithStatusAndMessage() {
    FootballDataMock mock = new FootballDataMock();
    mock.statusByPath.put('/matches', 429);
    mock.bodyByPath.put(
      '/matches',
      '{"message":"You reached your request limit.","errorCode":429}'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    try {
      new FootballDataClient().getMatches();
      Assert.fail('Expected a FootballDataException');
    } catch (FootballDataClient.FootballDataException e) {
      Assert.isTrue(e.getMessage().contains('HTTP 429'), e.getMessage());
      Assert.isTrue(e.getMessage().contains('request limit'), e.getMessage());
    }
    Test.stopTest();
  }
}
