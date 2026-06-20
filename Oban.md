# Replacing Oban Pro with Vanilla Oban in Glific Backend

This document describes all changes made to the Glific backend repository to replace **Oban Pro** (paid license) with **vanilla Oban** (free/open-source), enabling local development without an Oban Pro key.

> **Why?** Oban Pro requires a paid license key. For frontend contributors who only need the backend running locally, vanilla Oban provides enough functionality to serve the API.

---

## Summary of Changes

| File | Change | Reason |
|------|--------|--------|
| `mix.exs` | Commented out `oban_pro` and `oban_web` deps, set `@oban_envs` to `[:prod]` | These packages require the paid Oban hex repo which we don't have access to |
| `mix.lock` | Removed `oban_pro`, `oban_web`, `oban_met` entries | Lock file referenced packages from the `oban` private hex repo |
| `config/config.exs` | Replaced Pro engine, plugins, and queue configs | Pro features (Smart engine, DynamicPruner, etc.) don't exist in vanilla Oban |
| `lib/glific/appsignal.ex` | Changed `DynamicLifeline` → `Lifeline` in ignore list | The Pro plugin module doesn't exist without `oban_pro` |
| `lib/glific/erase.ex` | Commented out `oban_producers` VACUUM | The `oban_producers` table is created by Oban Pro and doesn't exist in vanilla |
| `priv/repo/migrations/20250109212933_add_oban_pro.exs` | Replaced `Oban.Pro.Migration` → `Oban.Migration` | Pro migration module doesn't exist without `oban_pro` |
| `priv/repo/migrations/20260429150747_upgrade_oban_pro_to_v1_6.exs` | Made into a no-op migration | Pro migration versions don't apply to vanilla Oban |

---

## Detailed Changes

### 1. `mix.exs` — Remove Oban Pro/Web Dependencies

**What changed:**
```diff
-  @oban_envs [:prod, :dev] ++ @test_envs
+  # @oban_envs [:prod, :dev] ++ @test_envs
   # comment above line
   # if you don't have Oban pro license, this is your best hack
   # uncomment below line
-  # @oban_envs [:prod]
+  @oban_envs [:prod]
```

And in the deps list:
```diff
-      {:oban_web, "~> 2.11", only: @oban_envs},
-      {:oban_pro, "~> 1.5", repo: "oban", only: @oban_envs},
+      # {:oban_web, "~> 2.11", only: @oban_envs},
+      # {:oban_pro, "~> 1.5", repo: "oban", only: @oban_envs},
```

**Why:** 
- `oban_pro` is fetched from a private hex repo (`repo: "oban"`) that requires an auth key we don't have
- `oban_web` depends on `oban_met` which is also from the private repo
- The codebase already had a built-in mechanism for this (commented lines 8-11 in the original `mix.exs`)
- Simply setting `@oban_envs` to `[:prod]` wasn't enough because Mix still parses all dep lines during `mix deps.get`, so the dep lines themselves had to be commented out

---

### 2. `mix.lock` — Remove Private Repo Entries

**What changed:** Removed three lines:
```diff
-  "oban_met": {:hex, :oban_met, "1.0.2", ...},
-  "oban_pro": {:hex, :oban_pro, "1.6.14", ... "oban", ...},
-  "oban_web": {:hex, :oban_web, "2.11.1", ...},
```

**Why:** The `oban_pro` entry in `mix.lock` references `"oban"` as its repo (the private Oban hex repository). When Mix tries to resolve dependencies, it attempts to contact this repo and fails with `Unknown repository "oban"`.

---

### 3. `config/config.exs` — Replace Pro Engine, Plugins, and Queue Configs

#### 3a. Queue Definitions (simplified)

**What changed:**
```diff
 oban_queues = [
   bigquery: 10,
   crontab: 10,
-  default: [
-    limit: 10,
-    rate_limit: [allowed: 30, period: {1, :minute}, partition: [:worker, args: :organization_id]]
-  ],
+  default: 10,
   ...
-  webhook: [
-    local_limit: 20,
-    global_limit: [allowed: 3, burst: true, partition: [args: :organization_id]]
-  ],
+  webhook: 20,
   ...
-  custom_certificate: [
-    limit: 10,
-    rate_limit: [allowed: 60, period: {1, :minute}, partition: [:worker, args: :organization_id]]
-  ],
-  gpt_webhook_queue: [
-    local_limit: 20,
-    global_limit: [allowed: 3, burst: true, partition: [args: :organization_id]]
-  ],
+  custom_certificate: 10,
+  gpt_webhook_queue: 20,
```

**Why:** The `rate_limit`, `local_limit`, and `global_limit` options are **Oban Pro features**. Vanilla Oban queues only accept a simple integer for the concurrency limit. The integer values chosen match the `limit` or `local_limit` values from the Pro config.

#### 3b. Engine

```diff
-oban_engine = Oban.Pro.Engines.Smart
+oban_engine = Oban.Engines.Basic
```

**Why:** `Oban.Pro.Engines.Smart` is the Pro engine that supports features like global rate limiting and smart partitioning. `Oban.Engines.Basic` is the vanilla equivalent that handles standard job processing.

#### 3c. Plugins

```diff
 oban_plugins = [
-  {Oban.Pro.Plugins.DynamicPruner, mode: {:max_age, 5 * 60}, limit: 25_000},
+  {Oban.Plugins.Pruner, max_age: 300},
   {Oban.Plugins.Cron, crontab: oban_crontab},
-  Oban.Pro.Plugins.DynamicLifeline,
-  {Oban.Pro.Plugins.DynamicPrioritizer,
-   after: :infinity, queue_overrides: [gpt_webhook_queue: :timer.minutes(5)]}
+  {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
 ]
```

**Why:**

| Pro Plugin | Vanilla Replacement | Notes |
|---|---|---|
| `DynamicPruner` | `Oban.Plugins.Pruner` | Both prune completed jobs. Pro version supports dynamic config; vanilla uses static `max_age` |
| `DynamicLifeline` | `Oban.Plugins.Lifeline` | Both rescue stuck/orphaned jobs. Pro version is dynamic; vanilla uses fixed `rescue_after` |
| `DynamicPrioritizer` | *(removed)* | No vanilla equivalent. This reprioritized jobs in specific queues. Not critical for local dev |

---

### 4. `lib/glific/appsignal.ex` — Fix Plugin Reference in Ignore List

```diff
   @ignore_plugins [
     Elixir.Oban.Plugins.Stager,
-    Elixir.Oban.Pro.Plugins.DynamicLifeline,
+    Elixir.Oban.Plugins.Lifeline,
     Elixir.Oban.Plugins.Pruner,
     Elixir.Oban.Plugins.Reindexer
   ]
```

**Why:** This list tells AppSignal to ignore telemetry events from these frequently-executing plugins. Since we replaced `DynamicLifeline` with `Lifeline`, the ignore list must reference the correct module name.

---

### 5. `lib/glific/erase.ex` — Remove `oban_producers` Table Reference

```diff
-      "VACUUM (FULL, ANALYZE) global.oban_producers",
+      # "VACUUM (FULL, ANALYZE) global.oban_producers", # Oban Pro table - not available with vanilla Oban
```

**Why:** The `oban_producers` table is created by Oban Pro's Smart engine to track producer state. Vanilla Oban doesn't create this table, so attempting to VACUUM it would cause a PostgreSQL error.

---

### 6. Migration Files

#### `priv/repo/migrations/20250109212933_add_oban_pro.exs`

```diff
-  def up, do: Oban.Pro.Migration.up(version: "1.5.0", prefix: "global")
-  def down, do: Oban.Pro.Migration.down(prefix: "global")
+  def up, do: Oban.Migration.up(prefix: "global")
+  def down, do: Oban.Migration.down(prefix: "global")
```

**Why:** `Oban.Pro.Migration` doesn't exist without the `oban_pro` package. `Oban.Migration` from vanilla Oban creates the standard `oban_jobs` table which is sufficient.

#### `priv/repo/migrations/20260429150747_upgrade_oban_pro_to_v1_6.exs`

```diff
-  def up, do: Oban.Pro.Migration.up(version: "1.6.0", prefix: "global")
-  def down, do: Oban.Pro.Migration.down(version: "1.5.0", prefix: "global")
+  def up, do: :ok
+  def down, do: :ok
```

**Why:** This migration upgrades Oban Pro-specific tables from v1.5 to v1.6. Since we're using vanilla Oban, there's nothing to upgrade — making it a no-op prevents compilation errors.

---

## What Still Uses Oban Pro (Left Unchanged)

### Test Files (~20+ files)

Many test files use `use Oban.Pro.Testing, repo: Glific.Repo`. These were **intentionally left unchanged** because:
- The goal is only to run the backend for frontend development, not to run tests
- These files are not compiled in `:dev` environment
- If you need to run tests, replace `use Oban.Pro.Testing` with `use Oban.Testing` in each test file

### `lib/glific_web/misc/inject_oban.ex`

This file conditionally loads `Oban.Web.Router` only if the module is available (`Code.ensure_loaded?`). Since `oban_web` is not installed, the macro simply returns `nil` — no changes needed.

---

## How to Revert (If You Get an Oban Pro Key)

1. Uncomment the `@oban_envs` line in `mix.exs` (line 7) and comment line 11
2. Uncomment the `oban_web` and `oban_pro` dep lines in `mix.exs`
3. Run `mix hex.repo add oban https://getoban.pro/repo --fetch-public-key <KEY> --auth-key <KEY>`
4. Revert `config/config.exs` to use `Oban.Pro.Engines.Smart` and Pro plugins
5. Revert migration files to use `Oban.Pro.Migration`
6. Revert `appsignal.ex` and `erase.ex`
7. Run `mix deps.get && mix setup`
