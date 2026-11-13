# Relay of <role>, <YYYY-MM-DD HH:MM> (from `date`)

Pilot template. The role writes it to `$FM_HOME/work/<role>/relay/<YYYY-MM-DD-HHMM>.md`, in 60 lines at most, and sends the path to the Coordinator, who closes the old session and relaunches the role with `founder-mode <role> --new`. The new session reads it whole before anything else.

## Previous conversation
- Id and path of the transcript: <id>, <path>.
- To search it: `founder-mode find-conversation "<text>"` (capped fragments; `--list` gives the role's conversations). Never read it whole.
- Reason for the relay: topic closed, or the threshold.

## Founders' orders still in force
Word for word, in quotes, with the date and where they are (path:line, or "chat of <role>, YYYY-MM-DD HH:MM"). Only the ones that aren't already in the org chart, your role file or your memory.

## Authorizations
None carries over. A founder's approval for one case (a send, a merge, a payment) doesn't pass to the new session: ask again.

## Topic in progress
What you were doing, where it stands and the next concrete step, with paths.

## Pending items
Not copied here: `founder-mode db pending --owner <role>`. If one isn't logged yet, log it before you write the relay.

## Open ends
Files half written, branches not pushed and messages waiting for an answer, with whom.
