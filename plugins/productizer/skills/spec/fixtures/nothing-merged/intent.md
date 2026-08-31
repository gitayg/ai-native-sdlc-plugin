Incoming intent — contradicts R1 of the spec beside this file.

The sentence below is the incoming behaviour. It is deliberately a decidable
conflict rather than a judgement call: same trigger, same system, two different
answers, which `contradiction-check.py` settles arithmetically. The check reads
the LAST non-empty line of this file as the statement, so the prose above is
commentary and the line below is the intent.

If a request body fails schema validation, then the service shall reject it with 422.
