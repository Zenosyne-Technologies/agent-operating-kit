---
name: stress-test
description: Plan, develop, and execute a comprehensive stress/performance test for the project — scale dimensions, beyond-comfort multipliers, and the extreme/edge cases that only appear past demo scale. Use when the user asks for stress testing, performance testing, load testing, or to verify the project holds up at scale.
---

# Stress-test the project

Orchestrator-level planning, agent-level execution. The point is the failure mode the demo never showed: a form tested with 3-5 repeater items that collapses at 10-15 from recalculation cost is the canonical case — comfort-scale testing validates nothing about scale.

1. **Map the scale dimensions**: walk the project (and `.docs/handbooks/developer/` if present) and list every axis that grows in production — collection sizes, repeaters/nested forms, concurrent users/sessions, payload and file sizes, query result widths, background queue depth, integration fan-out. For each: the scale demos used, the scale production will see, and the scale where you'd EXPECT trouble.
2. **Set beyond-comfort targets**: for every dimension, test at 3-5× the expected production scale (minimum 10× the demo scale) plus one deliberate extreme (the 99th-percentile abuse case). Client-side recalculation, re-render, and validation costs count as much as server latency — measure where the USER feels it.
3. **Plan as tracker work**: per `ticket-filing.md` + `label-syntax.md`, file one task per dimension group under a stress-test story/epic (type:investigation, area per surface, sized) with `## Scope / ## DoD` — the DoD names the target numbers (e.g. "form remains interactive at 20 repeater items; p95 save < 2s at 5× data").
4. **Build the harness** (heavy/small workers per dispatch rules): data seeders, load scripts (native tooling — k6/locust/artillery equivalents), and browser-level scenarios (Playwright or direct browser driving) for the client-side dimensions — API-level load alone is NOT a stress test of the user experience.
5. **Execute and measure**: run each dimension to its target and past it until degradation; record the knee point (where it degrades), the failure mode (slow, broken, corrupted, crashed), and resource signatures. Fresh validators verify the runs happened as briefed.
6. **Report and file**: findings per `ticket-filing.md` — each degradation below target is a bug (sev per impact) with repro scale attached; the summary lands as an issue comment on the story and, where reporting is installed, a note in the architect digest. Update the developer handbook page of any unit whose real limits were learned (`handbooks.md` discovery).
