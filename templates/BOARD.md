# Advisory board

The board audits big decisions through adversarial debate and a vote. It recommends; only the founders authorize.

## Members

- **Coordinator**: writes the case file, moderates, writes the minutes and votes on every case, its own proposals included. When the proposal is the Coordinator's, the minutes say so.
- **Advisor1** and **Advisor2**: own no topic. They have no file-editing tools and work read-only by instruction, since their shell could still write. The Coordinator opens them for each case in a fresh conversation (`founder-mode advisor1`, `founder-mode advisor2`) and closes them when the case ends.

## What comes to the board

- Changes to the session system: the org chart, the roles, the launcher and the shared rules.
- ADRs, and architecture or project decisions that are hard to undo: licenses, data governance, security, deployment, what the company sells.
- Day-to-day work stays out, and so does anything its owner can undo alone. Two advisors on the strongest model, checking facts at the source, can use about a seventh of a five-hour window in half an hour: a case has to be worth that.

A founder or the Coordinator convenes the board. Any owner can ask the Coordinator for a case.

## Procedure

1. **Case file.** The Coordinator writes `$FM_HOME/board/cases/YYYY-MM-DD-topic/case.md`: the question, the options, the facts with `path:line`, the constraints, who decides in the end and the deadline. It quotes whatever the advisors need from a connector, since they have none. It checks who proposed each option before naming them, and it cites no note that holds a vote.
2. **Blind round.** Each member checks the facts on their own and votes without seeing the other votes. Until the round closes, no vote goes in the case folder or in any file the case file cites. The Coordinator writes its own vote first, keeps it outside the case folder, puts its sha256 in the case file, and files the three votes together once the advisors' votes are in. Each vote carries the chosen option, the reasons with sources, the strongest argument against it and the fact that would change it.
3. **Rebuttal.** When all three members vote for the same option, the case goes to the minutes. Otherwise the Coordinator shares the three votes, and each member answers the strongest arguments of the other two. A member keeps or changes their vote and says why.
4. **Limit.** Two rebuttal rounds at most. Without agreement after the second, the case goes to a founder with each position, and the founder decides. When a member votes that the question needs a founder's judgment, the case goes to a founder at once, without more rounds.
5. **Minutes.** `minutes.md` records the votes of every round (first votes stay), who changed and why, the result ("unanimous" or "split"), the recommendation and the checked facts. The Coordinator then puts the result on the founders' decision list, adds one line to `$FM_HOME/board/precedents.md` and closes the advisors' sessions.

The advisors' votes reach the Coordinator by message, and the Coordinator files them in the case folder.
