# Stack advisory — recommending a greenfield stack

Factory-side reference for the `install-agent-os` skill's greenfield interview (step 2, question 4).
Like `templates/pm/INSTALL.md`, the skill READS this and applies it — it is **never copied into a
consumer project**. It lives under `skills/` (factory machinery), so it is structurally outside the
`templates/` payload and cannot land in any copy step. Only the CHOSEN stack is written into the
consumer, as `stack` (and `dev_command`) in `.marvin/PROJECT-INFO.md`. Reached only when the user has
no stack in mind and asks for a recommendation.

## Principles

- Propose ONLY popular, actively-maintained, widely-known technologies — names a first-time reader
  recognises, with abundant docs, a real community and a hiring pool.
- Every proposed combination carries its ONE-LINE reason: why this stack, for THIS project.
- Niche or specialised tech only when a stated requirement genuinely justifies it (hard realtime,
  heavy numerics, embedded targets, a regulated runtime) — and then FLAG it explicitly as niche,
  naming the requirement that forced it.
- Coherence over novelty: the pieces must fit — one language across tiers where sensible, a
  framework used to its own conventions, a datastore that matches the size answer.
- Re-derive at install time. The examples below are illustrations, not a frozen menu; re-check that
  each named technology is still popular and maintained before you propose it.

## How to build the four options

Key the proposal off the three answers already gathered — app type (Q3), size (Q2), audience (Q1):

- **app type** picks the surface: web → a web framework (SPA or SSR as size dictates); desktop →
  Tauri/Electron or a native toolkit; mobile → React Native/Flutter or native. A *combination*
  often collapses to ONE stack — web + mobile via a responsive web app or React Native, web +
  desktop via one Tauri/Electron shell — so say that rather than proposing three parallel stacks.
- **size** picks the depth: tiny/small → a lightweight framework + file/SQLite persistence, no auth
  machinery; medium → a full framework + a real database + a maintained auth library; large/huge →
  a battle-tested framework, a managed/scalable datastore, first-class authn/authz, and room for
  integrations and background work.
- **audience** tightens security/ops: personal/intra-team tolerate simpler auth; restricted-public
  and public pull in hardened auth, rate limiting and deployment maturity.

Produce exactly **four coherent combinations** plus a fifth **"you choose"** option (the user names
their own stack; record it verbatim). For each of the four give: the pieces (language, framework,
datastore, notable libraries), the one-line reason, and a niche flag if any piece is niche.

## Illustrative combinations (re-derive from the answers; do not paste as-is)

- **Small web, intra-team** — Next.js + SQLite (Prisma): one language front-to-back, zero-config
  persistence, deploys anywhere, grows into Postgres without a rewrite.
- **Medium web, restricted-public** — Django + Postgres: batteries-included auth/admin, a mature
  ORM, a clear path to many integrations.
- **Medium web, public (JS shop)** — Next.js + Postgres (Prisma) + Auth.js: SSR for reach, managed
  Postgres for scale, a maintained auth library instead of hand-rolled sessions.
- **Desktop, small** — Tauri + a web frontend: native footprint, one web skill set, smaller and
  safer than Electron.
- **Mobile, medium** — React Native (Expo) + a hosted backend: one codebase for iOS and Android, a
  large ecosystem, fast iteration.
- **Combination web + desktop** — one web app packaged with Tauri/Electron: build once, ship both —
  state the single stack, not two.
