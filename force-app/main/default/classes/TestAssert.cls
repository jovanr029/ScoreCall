/**
 * Shared assertions for ScoreCall tests.
 */
@IsTest
public class TestAssert {
  /** Inserts the record and asserts the database rejects it as a duplicate. */
  public static void duplicateRejected(SObject duplicate) {
    try {
      insert duplicate;
      Assert.fail(
        'Duplicate ' + duplicate.getSObjectType() + ' should have been rejected'
      );
    } catch (DmlException e) {
      Assert.areEqual(StatusCode.DUPLICATE_VALUE, e.getDmlType(0));
    }
  }
}
