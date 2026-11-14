import { LightningElement, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import basePath from "@salesforce/community/basePath";
import userId from "@salesforce/user/Id";
import USER_NAME from "@salesforce/schema/User.Name";

/**
 * The friends' site Home page: a header with Log out, and Predict,
 * Leaderboard and All predictions as tabs.
 */
export default class ScorecallHome extends LightningElement {
  // Lightning Data Service: reads the logged-in user's own record, no Apex.
  @wire(getRecord, { recordId: userId, fields: [USER_NAME] })
  user;

  get userName() {
    return this.user?.data ? getFieldValue(this.user.data, USER_NAME) : "";
  }

  /** Ends the site session and comes back to the site's login page. */
  get logoutUrl() {
    return `${basePath}/secur/logout.jsp?retUrl=${encodeURIComponent(
      `${basePath}/login`
    )}`;
  }
}
