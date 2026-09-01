# Living spec — fixture, extended

The same file with five active requirements instead of three. Two builds of the
same repository differing only in this file must render two different figures;
a figure that does not move when the file moves was not read from the file.

## Requirements

- **R1** — The fixture shall hold a countable number of active requirements.
- **R2** — The fixture shall name no absolute path, so it reads the same in a fresh clone.
- **R3** — The fixture shall be readable, so that making it unreadable is a change of state.
- **R4** — The fixture shall be cheap enough to build several times in one check.
- **R5** — The fixture shall be copied before use, so nothing is written to the tree under test.
