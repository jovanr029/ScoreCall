/**
 * Calls the football-data.org API v4 for the Premier League through the
 * FootballData named credential (the API key never appears in code).
 *
 * The inner classes mirror only the parts of the JSON we use; JSON.deserialize
 * ignores every other field. See docs/decisions/002-fixture-source.md.
 */
public with sharing class FootballDataClient {
  @TestVisible
  private static final String BASE_PATH = 'callout:FootballData/v4/competitions/PL';

  public class FootballDataException extends Exception {
  }

  /** All matches of the current season (about 380). */
  public MatchesResponse getMatches() {
    return (MatchesResponse) get('/matches', MatchesResponse.class);
  }

  /** The current league table. */
  public StandingsResponse getStandings() {
    return (StandingsResponse) get('/standings', StandingsResponse.class);
  }

  private Object get(String path, System.Type responseType) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(BASE_PATH + path);
    request.setMethod('GET');
    request.setTimeout(30000);

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != 200) {
      throw new FootballDataException(
        'football-data.org ' +
          path +
          ' returned HTTP ' +
          response.getStatusCode() +
          ': ' +
          response.getBody().left(300)
      );
    }
    return JSON.deserialize(response.getBody(), responseType);
  }

  // ---------- Response shapes ----------

  public class MatchesResponse {
    public List<ApiMatch> matches;
  }

  public class StandingsResponse {
    public ApiSeason season;
    public List<ApiStanding> standings;

    /** The overall table (the API also has HOME and AWAY tables for some competitions). */
    public List<ApiTableRow> totalTable() {
      for (ApiStanding standing : standings) {
        if (standing.type == 'TOTAL') {
          return standing.table;
        }
      }
      return new List<ApiTableRow>();
    }
  }

  public class ApiSeason {
    public Integer id;
    public Date startDate;
    public Date endDate;
    public Integer currentMatchday;
    public ApiTeam winner;
  }

  public class ApiTeam {
    public Integer id;
    public String name;
    public String shortName;
    public String tla;
    public String crest;
  }

  public class ApiMatch {
    public Integer id;
    public ApiSeason season;
    public Datetime utcDate;
    public String status;
    public Integer matchday;
    public ApiTeam homeTeam;
    public ApiTeam awayTeam;
    public ApiScore score;
  }

  public class ApiScore {
    public ApiGoals fullTime;
  }

  public class ApiGoals {
    public Integer home;
    public Integer away;
  }

  public class ApiStanding {
    public String type;
    public List<ApiTableRow> table;
  }

  public class ApiTableRow {
    public Integer position;
    public ApiTeam team;
    public Integer playedGames;
    public Integer points;
  }
}
