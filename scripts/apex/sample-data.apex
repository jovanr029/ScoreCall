// ScoreCall sample data for scratch orgs.
//
//   sf org assign permset --name ScoreCall_Admin
//   sf apex run --file scripts/apex/sample-data.apex
//
// Creates a sample season with 20 teams, a league table, and three gameweeks
// relative to today: one finished (with results), one open for predictions,
// and one upcoming. Re-running it deletes the previous sample data first.
// It refuses to run anywhere except a scratch org.

Organization org = [SELECT IsSandbox, TrialExpirationDate FROM Organization];
if (org.TrialExpirationDate == null) {
  throw new IllegalArgumentException(
    'sample-data.apex only runs in scratch orgs, never in UAT or production.'
  );
}

// ---- Clean up previous sample data (children before parents) ----
delete [SELECT Id FROM Prediction__c];
delete [SELECT Id FROM Table_Prediction__c];
delete [SELECT Id FROM League__c];
delete [SELECT Id FROM Season__c]; // cascades to gameweeks, fixtures, season teams
delete [SELECT Id FROM Team__c];

// ---- Season ----
Season__c season = new Season__c(
  Name = '2026/27',
  Status__c = 'Active',
  Start_Date__c = Date.newInstance(2026, 8, 22),
  End_Date__c = Date.newInstance(2027, 5, 23),
  Table_Prediction_Deadline__c = Datetime.now().addDays(7)
);
insert season;

// ---- Teams (sample list, not necessarily the real 2026/27 line-up) ----
List<List<String>> clubs = new List<List<String>>{
  new List<String>{ 'Arsenal', 'ARS' },
  new List<String>{ 'Aston Villa', 'AVL' },
  new List<String>{ 'Bournemouth', 'BOU' },
  new List<String>{ 'Brentford', 'BRE' },
  new List<String>{ 'Brighton & Hove Albion', 'BHA' },
  new List<String>{ 'Burnley', 'BUR' },
  new List<String>{ 'Chelsea', 'CHE' },
  new List<String>{ 'Crystal Palace', 'CRY' },
  new List<String>{ 'Everton', 'EVE' },
  new List<String>{ 'Fulham', 'FUL' },
  new List<String>{ 'Leeds United', 'LEE' },
  new List<String>{ 'Liverpool', 'LIV' },
  new List<String>{ 'Manchester City', 'MCI' },
  new List<String>{ 'Manchester United', 'MUN' },
  new List<String>{ 'Newcastle United', 'NEW' },
  new List<String>{ 'Nottingham Forest', 'NFO' },
  new List<String>{ 'Sunderland', 'SUN' },
  new List<String>{ 'Tottenham Hotspur', 'TOT' },
  new List<String>{ 'West Ham United', 'WHU' },
  new List<String>{ 'Wolverhampton Wanderers', 'WOL' }
};
List<Team__c> teams = new List<Team__c>();
for (List<String> club : clubs) {
  teams.add(
    new Team__c(
      Name = club[0],
      Short_Name__c = club[1],
      External_Id__c = 'SAMPLE-' + club[1]
    )
  );
}
insert teams;

// ---- League table (sample positions) ----
List<Season_Team__c> table = new List<Season_Team__c>();
for (Integer i = 0; i < teams.size(); i++) {
  table.add(
    new Season_Team__c(
      Season__c = season.Id,
      Team__c = teams[i].Id,
      Position__c = i + 1,
      Played__c = 7,
      Points__c = 21 - i
    )
  );
}
insert table;

// ---- Gameweeks: finished (7), open (8), upcoming (9) ----
// 14:00 GMT = 15:00 UK time (BST). Datetime.newInstance() would use the running
// user's time zone, which in a scratch org is US Pacific by default.
Datetime base = Datetime.newInstanceGmt(
  Date.today(),
  Time.newInstance(14, 0, 0, 0)
);
Map<Integer, Datetime> firstKickoff = new Map<Integer, Datetime>{
  7 => base.addDays(-4),
  8 => base.addDays(3),
  9 => base.addDays(10)
};
List<Gameweek__c> gameweeks = new List<Gameweek__c>();
for (Integer gw : firstKickoff.keySet()) {
  gameweeks.add(
    new Gameweek__c(
      Name = '2026/27 GW ' + gw,
      Season__c = season.Id,
      Number__c = gw
    )
  );
}
insert gameweeks;

// ---- Fixtures: 10 per gameweek, pairing teams differently each week ----
List<Fixture__c> fixtures = new List<Fixture__c>();
for (Gameweek__c gameweek : gameweeks) {
  Integer gw = gameweek.Number__c.intValue();
  for (Integer i = 0; i < 10; i++) {
    Team__c home = teams[Math.mod(i + gw, 20)];
    Team__c away = teams[Math.mod(i + gw + 10, 20)];
    Fixture__c fixture = new Fixture__c(
      Name = home.Short_Name__c + ' v ' + away.Short_Name__c,
      Gameweek__c = gameweek.Id,
      Home_Team__c = home.Id,
      Away_Team__c = away.Id,
      // Saturday-style spread: matches over ~2 days
      Kickoff__c = firstKickoff.get(gw).addHours(i * 4),
      External_Id__c = 'SAMPLE-' + gw + '-' + i
    );
    if (gw == 7) {
      fixture.Status__c = 'Finished';
      fixture.Home_Goals__c = Math.mod(i * 7 + 3, 4);
      fixture.Away_Goals__c = Math.mod(i * 5 + 1, 3);
    }
    fixtures.add(fixture);
  }
}
insert fixtures;

// ---- League with the current user ----
League__c league = new League__c(
  Name = 'Friends',
  Description__c = 'Sample league'
);
insert league;
insert new League_Member__c(
  League__c = league.Id,
  User__c = UserInfo.getUserId()
);

// ---- A few predictions for the current user ----
List<Prediction__c> predictions = new List<Prediction__c>();
for (Fixture__c fixture : fixtures) {
  if (
    fixture.Gameweek__c == gameweeks[0].Id ||
    fixture.Gameweek__c == gameweeks[1].Id
  ) {
    predictions.add(
      new Prediction__c(
        Fixture__c = fixture.Id,
        Gameweek__c = fixture.Gameweek__c,
        Home_Goals__c = 1,
        Away_Goals__c = 1
      )
    );
  }
}
insert predictions;

System.debug(
  'ScoreCall sample data: 1 season, ' +
    teams.size() +
    ' teams, ' +
    gameweeks.size() +
    ' gameweeks, ' +
    fixtures.size() +
    ' fixtures, 1 league, ' +
    predictions.size() +
    ' predictions.'
);
