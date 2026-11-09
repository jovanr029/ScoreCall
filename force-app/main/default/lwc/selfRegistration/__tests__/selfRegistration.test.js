import { createElement } from "lwc";
import SelfRegistration, {
  reduceError,
  CREATE_FAILED,
  SETUP_WAIT_MS
} from "c/selfRegistration";
import register from "@salesforce/apex/SelfRegistrationController.register";
import login from "@salesforce/apex/SelfRegistrationController.login";

jest.mock(
  "@salesforce/apex/SelfRegistrationController.register",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SelfRegistrationController.login",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/scorecall" }),
  {
    virtual: true
  }
);

const DETAILS = {
  firstName: "Carol",
  lastName: "Friend",
  email: "carol@example.com",
  password: "Test-Only-Pass-123",
  confirmPassword: "Test-Only-Pass-123",
  inviteCode: "GoalGoal26"
};

/** Lets pending promises and re-renders settle. */
async function flush(times = 5) {
  for (let i = 0; i < times; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

function mount() {
  const element = createElement("c-self-registration", {
    is: SelfRegistration
  });
  document.body.appendChild(element);
  return element;
}

function field(element, name) {
  return element.shadowRoot.querySelector(`[data-field="${name}"]`);
}

/** Fills the form; the lightning-input stub needs real-looking validity methods. */
function fill(element, details = DETAILS) {
  element.shadowRoot.querySelectorAll("lightning-input").forEach((input) => {
    input.reportValidity = jest.fn(() => true);
  });
  Object.entries(details).forEach(([name, value]) => {
    const input = field(element, name);
    input.value = value;
    input.dispatchEvent(new CustomEvent("change"));
  });
}

function submit(element) {
  element.shadowRoot
    .querySelector("form")
    .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
}

describe("c-self-registration", () => {
  const originalLocation = window.location;

  beforeEach(() => {
    // jsdom can't navigate: replace location with a spy.
    delete window.location;
    window.location = { assign: jest.fn() };
  });

  afterEach(() => {
    window.location = originalLocation;
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("signs up, waits while the account is set up, then logs in", async () => {
    jest.useFakeTimers();
    register.mockResolvedValue("005NEW");
    login.mockResolvedValue("https://site.example/secur/frontdoor.jsp?x");
    const element = mount();

    fill(element);
    submit(element);
    await flush(10);

    expect(register).toHaveBeenCalledWith(
      expect.objectContaining({
        firstName: "Carol",
        lastName: "Friend",
        email: "carol@example.com",
        password: "Test-Only-Pass-123",
        inviteCode: "GoalGoal26",
        timeZone: expect.any(String)
      })
    );
    // The permission set is assigned asynchronously: wait before logging in.
    expect(login).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector(".working-message").textContent
    ).toBe("Setting up your account…");

    jest.advanceTimersByTime(SETUP_WAIT_MS);
    await flush(10);

    expect(login).toHaveBeenCalledWith({
      email: "carol@example.com",
      password: "Test-Only-Pass-123",
      startUrl: "/scorecall/"
    });
    expect(window.location.assign).toHaveBeenCalledWith(
      "https://site.example/secur/frontdoor.jsp?x"
    );
  });

  it("shows the Apex message and keeps the form when sign-up is refused", async () => {
    register.mockRejectedValue({
      body: { message: "That invite code isn't right." }
    });
    const element = mount();

    fill(element);
    submit(element);
    await flush(10);

    expect(element.shadowRoot.querySelector(".error").textContent).toContain(
      "That invite code isn't right."
    );
    expect(element.shadowRoot.querySelector("form")).not.toBeNull();
    expect(field(element, "firstName").value).toBe("Carol");
    expect(login).not.toHaveBeenCalled();
  });

  it("doesn't call Apex while a field is invalid", async () => {
    const element = mount();
    fill(element);
    field(element, "email").reportValidity = jest.fn(() => false);

    submit(element);
    await flush();

    expect(register).not.toHaveBeenCalled();
  });

  it("stops when the passwords don't match", async () => {
    const element = mount();
    fill(element, { ...DETAILS, confirmPassword: "something-else" });

    submit(element);
    await flush();

    expect(element.shadowRoot.querySelector(".error").textContent).toContain(
      "The passwords don't match."
    );
    expect(register).not.toHaveBeenCalled();
  });

  it("links to the login page", () => {
    const element = mount();
    expect(element.shadowRoot.querySelector("a").getAttribute("href")).toBe(
      "/scorecall/login"
    );
  });
});

describe("reduceError", () => {
  it("prefers the Apex message", () => {
    expect(reduceError({ body: { message: "From Apex" } })).toBe("From Apex");
    expect(reduceError(undefined)).toBe("Something went wrong.");
  });

  it("explains Salesforce's generic error (usually: the email already has an account)", () => {
    expect(
      reduceError({
        body: {
          message:
            "Your request cannot be processed at this time. The site administrator has been alerted."
        }
      })
    ).toBe(CREATE_FAILED);
  });
});
