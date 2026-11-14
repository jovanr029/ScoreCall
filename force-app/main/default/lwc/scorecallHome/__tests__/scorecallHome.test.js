import { createElement } from "lwc";
import ScorecallHome from "c/scorecallHome";
import { getRecord } from "lightning/uiRecordApi";

jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/scorecall" }),
  { virtual: true }
);

function mount() {
  const element = createElement("c-scorecall-home", { is: ScorecallHome });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe("c-scorecall-home", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("offers Predict, Leaderboard and All predictions as tabs, Predict first", () => {
    const element = mount();

    const tabs = [...element.shadowRoot.querySelectorAll("lightning-tab")];
    expect(tabs.map((tab) => tab.label)).toEqual([
      "Predict",
      "Leaderboard",
      "All predictions"
    ]);
    expect(tabs[0].querySelector("c-prediction-entry")).not.toBeNull();
    expect(tabs[1].querySelector("c-leaderboard")).not.toBeNull();
    expect(tabs[2].querySelector("c-gameweek-predictions")).not.toBeNull();
  });

  it("logs out of the site and comes back to its login page", () => {
    const element = mount();
    expect(
      element.shadowRoot.querySelector("a.logout").getAttribute("href")
    ).toBe("/scorecall/secur/logout.jsp?retUrl=%2Fscorecall%2Flogin");
  });

  it("shows the logged-in user's name", async () => {
    const element = mount();
    expect(element.shadowRoot.querySelector(".user-name")).toBeNull();

    getRecord.emit({
      apiName: "User",
      fields: { Name: { value: "Carol Friend" } }
    });
    await flush();

    expect(element.shadowRoot.querySelector(".user-name").textContent).toBe(
      "Carol Friend"
    );
  });
});
