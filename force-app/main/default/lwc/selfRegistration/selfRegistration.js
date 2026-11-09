import { LightningElement } from "lwc";
import basePath from "@salesforce/community/basePath";
import register from "@salesforce/apex/SelfRegistrationController.register";
import login from "@salesforce/apex/SelfRegistrationController.login";

/**
 * The ScoreCall_Player permission set is assigned by a platform event trigger
 * a moment after register(). The guest user can't check for it, so wait this
 * long before logging in (it normally takes well under a second).
 */
export const SETUP_WAIT_MS = 3000;

/**
 * Sign-up form for the site's Register page (#28). The visitor isn't logged
 * in, so every Apex call runs as the site's guest user.
 *
 *   register()  creates the friend (checks the invite code in Apex)
 *   (wait)      until the ScoreCall_Player permission set is assigned
 *   login()     logs the friend in; the browser then goes to the returned URL
 */
export default class SelfRegistration extends LightningElement {
  firstName = "";
  lastName = "";
  email = "";
  password = "";
  confirmPassword = "";
  inviteCode = "";

  error;
  /** "form" -> "working" (creating + waiting) -> "redirecting" */
  step = "form";

  get isForm() {
    return this.step === "form";
  }

  get isWorking() {
    return this.step !== "form";
  }

  get workingMessage() {
    return this.step === "redirecting"
      ? "Logging you in…"
      : "Setting up your account…";
  }

  get loginUrl() {
    return `${basePath}/login`;
  }

  // One handler for every field: data-field names the property to set.
  handleChange(event) {
    this[event.target.dataset.field] = event.target.value;
  }

  handleConfirmBlur() {
    const confirm = this.template.querySelector(
      '[data-field="confirmPassword"]'
    );
    confirm.setCustomValidity(
      this.confirmPassword && this.confirmPassword !== this.password
        ? "The passwords don't match."
        : ""
    );
    confirm.reportValidity();
  }

  async handleSubmit(event) {
    event.preventDefault();
    this.error = undefined;
    this.handleConfirmBlur();
    if (!this.allInputsValid()) {
      return;
    }
    if (this.password !== this.confirmPassword) {
      this.error = "The passwords don't match.";
      return;
    }

    this.step = "working";
    try {
      await register({
        firstName: this.firstName,
        lastName: this.lastName,
        email: this.email,
        password: this.password,
        inviteCode: this.inviteCode,
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone
      });
      await sleep(SETUP_WAIT_MS);
      this.step = "redirecting";
      const url = await login({
        email: this.email,
        password: this.password,
        startUrl: `${basePath}/`
      });
      window.location.assign(url);
    } catch (error) {
      this.step = "form";
      this.error = reduceError(error);
    }
  }

  allInputsValid() {
    return [...this.template.querySelectorAll("lightning-input")].reduce(
      (valid, input) => input.reportValidity() && valid,
      true
    );
  }
}

function sleep(milliseconds) {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- see SETUP_WAIT_MS
    setTimeout(resolve, milliseconds);
  });
}

/**
 * Salesforce's generic reply when creating the user fails inside
 * Site.createExternalUser (Apex can't catch it). The usual cause is an email
 * that already has an account; the guest user isn't allowed to check that in
 * advance, and Salesforce deliberately doesn't say.
 */
const GENERIC_SITE_ERROR = "cannot be processed at this time";
export const CREATE_FAILED =
  "We couldn't create your account. If you already have one, log in or use " +
  '"Forgot your password?". Otherwise, ask the organiser.';

export function reduceError(error) {
  const message =
    error?.body?.message || error?.message || "Something went wrong.";
  return message.includes(GENERIC_SITE_ERROR) ? CREATE_FAILED : message;
}
