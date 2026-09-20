<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# CLAUDE.md

<!-- @-import: ~/.claude/includes/verification-policy.md -->
## Verification scope — focused runs, full post-merge QA

This is the canonical policy for **when** checks run. Project command catalogs describe **how** to run them; an alias name such as `precommit` or `check.dispatch` does not require its execution. Apply this policy to implementers, reviewers, orchestrators and hooks. Explicit operator requests and concrete task acceptance criteria can require additional checks.

| Work / role | Required verification |
|---|---|
| Docs, roadmap, comments, text-only changes | Validate the changed artifact (for example rmap validation or AGENTS generation); no code suite, coverage or analyzers. |
| Implementation | Format changed code, compile where relevant, and add/run focused tests for the changed behavior and regression. |
| Reviewer | Independently assess the diff and acceptance criteria; run focused checks for affected behavior and relevant integration boundaries. The reviewer remains the acceptance gate. |
| Post-merge audit + QA | On the landed revision, run the full project suite, coverage and applicable analyzers: Dialyzer, Reach, Sobelow, Credo, Doctor, clone detection and language-specific equivalents. Review the integrated surface against roadmap intent and domain invariants. |

- **Commit, push, PR creation, reviewer handoff, branch switch, rebase, merge and `deps.get` are not by themselves reasons to run full QA.** Do not run full-project gates on every small change or every implementer/reviewer run. No project exception, including aave_sim.
- **Choose checks by changed behavior and risk.** Signing, money, authorization, crypto and external-provider changes still require their relevant security, boundary and live integration tests before acceptance. Missing credentials or failed checks are reported honestly, never converted into a green result. Preserve tests and thresholds; change when they run.
- **Broaden only for a named reason:** explicit request/acceptance criterion, or concrete evidence that focused checks cannot resolve a cross-module regression. State that reason and run the smallest additional check that resolves it. “To be safe” or an alias name is not a reason.
- **Coverage belongs to full QA.** Keep project thresholds (at least 80% standard / 95% critical unless a documented project baseline applies). Do not demand a whole-module coverage uplift before an unrelated edit. Add meaningful tests for the behavior being changed.
- **Inspect aliases before using them.** If `check.dispatch`, `precommit`, `ci`, a registered hint or an inherited hook bundles full tests/coverage/analyzers, use the explicit scoped commands for the run and report the configuration mismatch. Do not claim the alias became lightweight merely because the instructions changed.
- **Reuse evidence for the same revision and scope.** Capture command output once; do not rerun solely for readable logs or to repeat a passed check. A reviewer supplies independent judgment and relevant verification, not an automatic full-suite repetition.
- **Full QA is a separate, nonblocking post-merge audit responsibility.** Record revision/range, commands, results and missing checks. Failures produce visible findings and repair work; they do not retroactively unmerge or become a blanket next-wave/deployment gate. If automatic QA is not configured or has not run, say so; never infer success from the existence of this policy.

Maintain this policy in `~/.claude/includes/verification-policy.md`. Import it from project `CLAUDE.md`; regenerate `AGENTS.md` with `claude-marketplace/scripts/sync-agents-md.sh`. Keep scheduling rules here, project-specific commands and justified risk checks in the project. Do not duplicate the policy in project prose.


This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@include ~/.claude/includes/across-instances.md
@include ~/.claude/includes/critical-rules.md
@include ~/.claude/includes/task-prioritization.md
@include ~/.claude/includes/task-writing.md
@include ~/.claude/includes/web-command.md
@include ~/.claude/includes/code-style.md
@include ~/.claude/includes/development-philosophy.md
@include ~/.claude/includes/documentation-guidelines.md
@include ~/.claude/includes/api-integration.md
@include ~/.claude/includes/development-commands.md
@include ~/.claude/includes/elixir-patterns.md
@include ~/.claude/includes/phoenix-setup.md
@include ~/.claude/includes/phoenix-patterns.md
@include ~/.claude/includes/phoenix-scope.md

## Project Overview

Polydash is a Phoenix 1.8 web application using:
- **Elixir 1.15+** with Phoenix 1.8.3
- **PostgreSQL** via Ecto with binary_id (UUID) primary keys
- **Phoenix LiveView 1.1** for real-time UI
- **Tailwind CSS v4** for styling (no tailwind.config.js needed)
- **Bandit** as the HTTP server
- **Req** for HTTP requests (preferred over HTTPoison/Tesla)

## Development Commands

```bash
mix setup              # Install deps, create DB, run migrations, setup assets
mix phx.server         # Start Phoenix server (localhost:4000)
iex -S mix phx.server  # Start with interactive shell
mix test               # Run tests (auto-migrates)
mix test path/to/test.exs:42  # Run specific test at line
mix precommit          # Compile (warnings-as-errors), unlock unused deps, format, test
```

## Architecture

```
lib/
├── polydash/           # Business logic (contexts)
│   ├── application.ex  # OTP supervision tree
│   ├── repo.ex         # Ecto repository
│   └── mailer.ex       # Email via Swoosh
├── polydash_web/       # Web layer
│   ├── router.ex       # Routes and pipelines
│   ├── endpoint.ex     # HTTP endpoint config
│   ├── components/     # Reusable UI components
│   │   ├── core_components.ex  # <.input>, <.button>, <.icon>, etc.
│   │   └── layouts.ex          # <Layouts.app>, <Layouts.root>
│   └── controllers/    # Request handlers
└── polydash_web.ex     # Web module macros and imports
```

## Key Patterns

### LiveView Templates
Always wrap content with `<Layouts.app>`:
```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <!-- your content -->
</Layouts.app>
```

### Forms
Use `to_form/2` in LiveView and `<.input>` component in templates:
```elixir
# In LiveView
socket |> assign(form: to_form(changeset))
```
```heex
<.form for={@form} id="my-form" phx-submit="save">
  <.input field={@form[:field]} type="text" />
</.form>
```

### Streams for Collections
Always use streams instead of list assigns:
```elixir
socket |> stream(:items, items)
```
```heex
<div id="items" phx-update="stream">
  <div :for={{id, item} <- @streams.items} id={id}>{item.name}</div>
</div>
```

### Icons
Use the built-in `<.icon>` component:
```heex
<.icon name="hero-x-mark" class="w-5 h-5" />
```

## Project Guidelines

- Select scoped checks using the imported verification policy
- Use `:req` (Req) for HTTP requests, not HTTPoison/Tesla/httpc
- Router scopes auto-alias modules (no manual alias needed)
- Never nest multiple modules in the same file
- Never use `@apply` in CSS - write Tailwind classes directly
