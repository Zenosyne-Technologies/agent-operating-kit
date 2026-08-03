# Severity mapping — Jira

The kit's sev labels (definitions in `ticket-filing.md`) are the canonical severity system across all trackers. When filing in Jira, mirror the native fields from the label per this table; on conflict the label wins.

| Kit label | Jira Priority | JSM Impact (when the field exists) |
|---|---|---|
| sev1-critical | Highest | Extensive |
| sev2-high | High | Significant |
| sev3-medium | Medium | Moderate |
| sev4-low | Low | Minor |

Convention: every supported tracker folder (`templates/<tracker>/`) ships a `severity-mapping.md` like this one, translating the kit's severity system to that tracker's native scheme. The intake brief bakes the table into the in-tracker guide.
