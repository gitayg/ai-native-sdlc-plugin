"""Fixture payload: a repo-local script handed to an interpreter as an OPERAND.

R18's argv[0]-only ancestor read `value[0]`, saw `python3` - a name that is not
a path inside the repository - and let this through. The script under test then
opened a file the REPOSITORY BEING EXAMINED chose, which is the whole of P4.

Its only effect is a marker file in the temporary repository it runs in. The
check asserts that marker is ABSENT after the gated run, and proves the payload
is live by running this same argv once in a throwaway directory first - a
payload that turned out to be inert would make the absence prove nothing.
"""
open("marker-interpreter-operand", "w").close()
