/**
 * Builds ScoreCall test data. Methods named create* insert the records;
 * methods named build* only instantiate them, so a test can change fields
 * before inserting.
 */
@IsTest
public class TestDataFactory {
  public static Season__c createSeason() {
    Season__c season = new Season__c(Name = '2026/27', Status__c = 'Active');
    insert season;
    return season;
  }

  public static List<Team__c> createTeams(Integer count) {
    List<Team__c> teams = new List<Team__c>();
    for (Integer i = 1; i <= count; i++) {
      teams.add(new Team__c(Name = 'Team ' + i, Short_Name__c = 'T' + i));
    }
    insert teams;
    return teams;
  }

  public static Gameweek__c createGameweek(
    Id seasonId,
    Integer gameweekNumber
  ) {
    Gameweek__c gameweek = new Gameweek__c(
      Name = 'GW ' + gameweekNumber,
      Season__c = seasonId,
      Number__c = gameweekNumber
    );
    insert gameweek;
    return gameweek;
  }

  public static Fixture__c buildFixture(
    Id gameweekId,
    Team__c home,
    Team__c away,
    Datetime kickoff
  ) {
    return new Fixture__c(
      Name = home.Short_Name__c + ' v ' + away.Short_Name__c,
      Gameweek__c = gameweekId,
      Home_Team__c = home.Id,
      Away_Team__c = away.Id,
      Kickoff__c = kickoff
    );
  }

  public static Prediction__c buildPrediction(
    Fixture__c fixture,
    Integer homeGoals,
    Integer awayGoals
  ) {
    return new Prediction__c(
      Fixture__c = fixture.Id,
      Gameweek__c = fixture.Gameweek__c,
      Home_Goals__c = homeGoals,
      Away_Goals__c = awayGoals
    );
  }

  public static League__c createLeague(String name) {
    League__c league = new League__c(Name = name);
    insert league;
    return league;
  }
}
