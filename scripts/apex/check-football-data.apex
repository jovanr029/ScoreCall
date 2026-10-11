// Checks that the FootballData named credential works in an org.
// Read-only: one GET to the football-data.org API, nothing is saved.
//
//   sf apex run --file scripts/apex/check-football-data.apex --target-org <alias>
//
// Needs: ScoreCall_Admin assigned to the running user, and the API key entered
// in Setup > Named Credentials > External Credentials > Football Data >
// Principals > FootballDataPrincipal > Authentication Parameters (ApiKey).

HttpRequest request = new HttpRequest();
request.setEndpoint('callout:FootballData/v4/competitions/PL/standings');
request.setMethod('GET');
request.setTimeout(20000);

HttpResponse response = new Http().send(request);

if (response.getStatusCode() != 200) {
  System.debug(
    'FOOTBALL_DATA_CHECK FAILED: HTTP ' +
      response.getStatusCode() +
      ' ' +
      response.getBody().left(300)
  );
} else {
  Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
    response.getBody()
  );
  Map<String, Object> season = (Map<String, Object>) body.get('season');
  List<Object> standings = (List<Object>) body.get('standings');
  List<Object> table = (List<Object>) ((Map<String, Object>) standings[0])
    .get('table');
  Map<String, Object> leader = (Map<String, Object>) ((Map<String, Object>) table[0])
    .get('team');
  System.debug(
    'FOOTBALL_DATA_CHECK OK: season ' +
      season.get('startDate') +
      ' to ' +
      season.get('endDate') +
      ', matchday ' +
      season.get('currentMatchday') +
      ', ' +
      table.size() +
      ' teams, leader ' +
      leader.get('shortName') +
      ', requests left this minute: ' +
      response.getHeader('x-requests-available-minute')
  );
}
