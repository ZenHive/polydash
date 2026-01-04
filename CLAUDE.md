# CLAUDE.md

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

- Use `mix precommit` before finishing changes
- Use `:req` (Req) for HTTP requests, not HTTPoison/Tesla/httpc
- Router scopes auto-alias modules (no manual alias needed)
- Never nest multiple modules in the same file
- Never use `@apply` in CSS - write Tailwind classes directly
