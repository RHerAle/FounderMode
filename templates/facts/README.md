# facts/

A fact about the company lives in one line of one file, and only its owner changes it.

- Topics and owners: `product.tsv` (engineering), `business.tsv` (finance), `legal.tsv` (legal), `structure.tsv` (coordinator). Rename them to fit your roles; the topic is the file name.
- Columns, tab-separated: `id`, `fact`, `since` (YYYY-MM-DD), `source` (path:line, a founder's order or a URL), `summary` (yes or no). A `#` at the start comments a line out.
- When a fact changes, its owner edits its line, with a new date and source. Memories and notes cite the `id` and never copy the fact.
- `summary=yes` puts the fact in the org chart's "What the company is today" block: `founder-mode summary --dry` shows the diff and `founder-mode summary` writes it (10 facts at most).
- `retired.tsv` keeps the phrases that no longer hold (`old`, `new`, `since`, `who`, `source`). Nobody adds a row by hand: `founder-mode retire "<old>" "<new>" --by <role> --source <...>` adds it, lists each place where the old phrase is still written and opens a pending item for each owner (`--dry` only counts).
- The deliverable hook flags a retired phrase in a deliverable, and in a memory, a role file or the org chart.
- Retire a phrase that is wrong, never one that is still true of part of the company: every place that says it would be flagged for nothing.
- Queries: `founder-mode db q "SELECT * FROM facts"` and `founder-mode db q "SELECT * FROM retired"`. A bad line is skipped with a warning and exit code 3.
