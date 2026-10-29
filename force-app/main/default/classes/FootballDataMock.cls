/**
 * HttpCalloutMock for football-data.org. Returns small JSON payloads shaped
 * exactly like the real API (trimmed from real responses, see
 * docs/decisions/002-fixture-source.md). Tests can replace the payload or the
 * status code per path, and inspect the requests that were sent.
 */
@IsTest
public class FootballDataMock implements HttpCalloutMock {
  public Map<String, String> bodyByPath;
  public Map<String, Integer> statusByPath = new Map<String, Integer>();
  public List<HttpRequest> requests = new List<HttpRequest>();

  // Filled here, not in the declaration: an instance field initializer can't
  // reference static constants declared further down (illegal forward reference).
  public FootballDataMock() {
    bodyByPath = new Map<String, String>{
      '/matches' => MATCHES_JSON,
      '/standings' => STANDINGS_JSON
    };
  }

  public HttpResponse respond(HttpRequest request) {
    requests.add(request);
    String path = request.getEndpoint().substringAfter('/competitions/PL');
    HttpResponse response = new HttpResponse();
    response.setHeader('Content-Type', 'application/json');
    response.setStatusCode(
      statusByPath.containsKey(path) ? statusByPath.get(path) : 200
    );
    response.setBody(
      bodyByPath.containsKey(path)
        ? bodyByPath.get(path)
        : '{"message":"not mocked"}'
    );
    return response;
  }

  // Season 2026/27 with 4 teams: one finished match (MD1), one in play (MD2),
  // one timed (MD3) and one postponed (MD3).
  public static final String SEASON_JSON = '{"id":2502,"startDate":"2026-08-21","endDate":"2027-05-30","currentMatchday":2,"winner":null}';

  public static String team(Integer id, String shortName, String tla) {
    return '{"id":' +
      id +
      ',"name":"' +
      shortName +
      ' FC","shortName":"' +
      shortName +
      '","tla":"' +
      tla +
      '","crest":"https://crests.football-data.org/' +
      id +
      '.png"}';
  }

  public static String match(
    Integer id,
    String utcDate,
    String status,
    Integer matchday,
    String home,
    String away,
    Integer homeGoals,
    Integer awayGoals
  ) {
    return '{"id":' +
      id +
      ',"season":' +
      SEASON_JSON +
      ',"utcDate":"' +
      utcDate +
      '","status":"' +
      status +
      '","matchday":' +
      matchday +
      ',"homeTeam":' +
      home +
      ',"awayTeam":' +
      away +
      ',"score":{"winner":null,"duration":"REGULAR","fullTime":{"home":' +
      homeGoals +
      ',"away":' +
      awayGoals +
      '},"halfTime":{"home":null,"away":null}}}';
  }

  public static final String ARS = team(57, 'Arsenal', 'ARS');
  public static final String CHE = team(61, 'Chelsea', 'CHE');
  public static final String LIV = team(64, 'Liverpool', 'LIV');
  public static final String MCI = team(65, 'Man City', 'MCI');

  public static final String MATCHES_JSON =
    '{"filters":{"season":"2026"},"resultSet":{"count":4},"matches":[' +
    match(1001, '2026-08-21T19:00:00Z', 'FINISHED', 1, ARS, CHE, 3, 0) +
    ',' +
    match(1002, '2026-08-29T14:00:00Z', 'IN_PLAY', 2, LIV, MCI, 1, 1) +
    ',' +
    match(1003, '2026-09-05T14:00:00Z', 'TIMED', 3, CHE, LIV, null, null) +
    ',' +
    match(1004, '2026-09-05T16:30:00Z', 'POSTPONED', 3, MCI, ARS, null, null) +
    ']}';

  public static final String STANDINGS_JSON =
    '{"season":' +
    SEASON_JSON +
    ',"standings":[{"stage":"REGULAR_SEASON","type":"TOTAL","table":[' +
    '{"position":1,"team":' +
    ARS +
    ',"playedGames":1,"points":3},' +
    '{"position":2,"team":' +
    LIV +
    ',"playedGames":1,"points":1},' +
    '{"position":3,"team":' +
    MCI +
    ',"playedGames":1,"points":1},' +
    '{"position":4,"team":' +
    CHE +
    ',"playedGames":1,"points":0}]}]}';
}
