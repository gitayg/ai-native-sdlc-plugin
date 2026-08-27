---
name: secure-api-review
description: Triggers when creating or modifying an externally reachable endpoint
---

1. Authentication — every endpoint requires a gateway-issued JWT. No exceptions
   for internal callers.
2. Input validation — validate the request body against the schema before any
   business logic runs.
3. Audit — emit an audit event carrying actor, action, entity and timestamp.
4. Data classification — PII fields never appear in logs or error responses.

Owner: <policy owner>. Source of truth: <link to the policy>.
