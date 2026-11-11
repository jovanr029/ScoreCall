import { createElement } from "lwc";
import ScorecallHome from "c/scorecallHome";

describe("c-scorecall-home", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("offers Predict and Leaderboard as tabs, Predict first", () => {
    const element = createElement("c-scorecall-home", { is: ScorecallHome });
    document.body.appendChild(element);

    const tabs = [...element.shadowRoot.querySelectorAll("lightning-tab")];
    expect(tabs.map((tab) => tab.label)).toEqual(["Predict", "Leaderboard"]);
    expect(tabs[0].querySelector("c-prediction-entry")).not.toBeNull();
    expect(tabs[1].querySelector("c-leaderboard")).not.toBeNull();
  });
});
