/**
 * Fills the Unique_Key__c style fields that enforce "one per ..." rules at
 * database level. Salesforce has no composite unique constraint, so each key
 * is a unique text field built from the record's identifying lookups.
 *
 * Called from the trigger handlers in before insert / before update, so keys
 * are set before the record is saved and follow changes (e.g. a new owner).
 */
public with sharing class UniqueKeyService {
  private static final String SEPARATOR = '-';

  /** One team per season: SeasonId-TeamId. */
  public static void setKeys(List<Season_Team__c> records) {
    for (Season_Team__c record : records) {
      record.Unique_Key__c = join(
        new List<Object>{ record.Season__c, record.Team__c }
      );
    }
  }

  /** One gameweek number per season: SeasonId-Number. */
  public static void setKeys(List<Gameweek__c> records) {
    for (Gameweek__c record : records) {
      record.Unique_Key__c = join(
        new List<Object>{ record.Season__c, toInteger(record.Number__c) }
      );
    }
  }

  /** One prediction per player per fixture per gameweek: OwnerId-FixtureId-GameweekId. */
  public static void setKeys(List<Prediction__c> records) {
    for (Prediction__c record : records) {
      record.Unique_Key__c = join(
        new List<Object>{
          record.OwnerId,
          record.Fixture__c,
          record.Gameweek__c
        }
      );
    }
  }

  /** Each team and each position once per player per season. */
  public static void setKeys(List<Table_Prediction__c> records) {
    for (Table_Prediction__c record : records) {
      record.Team_Key__c = join(
        new List<Object>{ record.OwnerId, record.Season__c, record.Team__c }
      );
      record.Position_Key__c = join(
        new List<Object>{
          record.OwnerId,
          record.Season__c,
          toInteger(record.Predicted_Position__c)
        }
      );
    }
  }

  /** One membership per player per league: LeagueId-UserId. */
  public static void setKeys(List<League_Member__c> records) {
    for (League_Member__c record : records) {
      record.Unique_Key__c = join(
        new List<Object>{ record.League__c, record.User__c }
      );
    }
  }

  // Number fields come back as Decimal (8 vs 8.0); normalise so keys are stable.
  private static Integer toInteger(Decimal value) {
    return value == null ? null : value.intValue();
  }

  private static String join(List<Object> parts) {
    return String.join(parts, SEPARATOR);
  }
}
