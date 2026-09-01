# Fixture — a contradiction stopped in conversation

A committed input to `check-ruling-requested.sh`'s own self-assertion. The
script copies one of these two trees into a temporary root and runs itself
against it. The files are data; nothing here is executed and nothing here is
written to.

`stopped/` is the B11 failure: intake classified an intent as `contradict`,
recorded that classification, and then asked in the session instead of writing
anything. There is no ruling file and no concern row, so a check that reads
only the spec and the rulings directory finds an empty repository and calls it
clean. It must be refused.

`asked/` is the same contradiction written up as `references/rulings.md`
requires: the classification, the concern row and the ruling file, in that
order. It must be clean. Without this half the assertion would pass for a check
that simply refuses every `contradict` record it sees.
