# Wiring a `mikrotikModule` into clan's service model

**Scope:** how a clan *service* could contribute a MikroTik router configuration, the way it
contributes a NixOS module today — and what that costs in clan-core.

**Read at:** clan-core `49bdb2dcb11ac855f9d74e81e3ee03e873f45928`
(`/nix/store/izy146p09d658z11h05zlbv94x64x9xm-source`). That is the rev **both** `ccpkgs`
(`flake.nix:42`) and the fleet (`lunix/flake.lock`, nodes `clan-core` and `clan-core_2`) pin, so
one rev is the only thing to hold in your head.

---

## 1. How `perInstance.nixosModule` / `darwinModule` actually get called

They are **never called**. They are module *values* that get collected into a per-machine list,
and the machine's module-system class decides which list is imported. The only function call in
the chain is the `perInstance` **function itself**.

**Step 1 — declared as options on the role submodule.**
`lib/inventory/distributed-service/service-module.nix:512` declares `options.perInstance` with type
`deferredModuleWith { staticModules = [ … ]; }`, whose declared options are `exports` (:575),
`nixosModule` (:606) and `darwinModule` (:634). `perMachine` is the same shape at :714, with its own
`nixosModule` (:779) / `darwinModule` (:802).

**Step 2 — the function is applied, once per (role, instance, machine).**
`service-module.nix:950`:

```nix
instanceRes = roleCfg.perInstance instanceName machineName;
```

and :952-978 does `instanceRes // { nixosModule = { imports = [ instanceRes.nixosModule ] ++ extraModules; }; darwinModule = …; }`.
Two things matter here: the value is wrapped into a module with `imports` (so `extraModules` from
the inventory land in the same list), and the **spread at :952 means any *other* attribute the
service returned survives** into `result.allRoles`.

**Step 3 — aggregated per machine, and pruned.**
`service-module.nix:1089` `result.final` folds `result.allRoles` per machine into two accumulators
(`nixosModules`, `darwinModules`, seeded at :1131-1135) and returns a **fresh attrset**
`:1138-1177`:

```nix
{ inherit instanceResults machineResult;
  nixosModule = { imports = [ …assertions/perMachine… ] ++ instanceResults.nixosModules; };
  darwinModule = { imports = [ … ] ++ instanceResults.darwinModules; }; }
```

So anything a service returns beyond `nixosModule`/`darwinModule` is **dropped here** — the doc
comment at :926-941 mentions a `services :: { }` member that the code does not carry.

**Step 4 — collected across services, per machine.**
`modules/clan/distributed-services.nix:152-163` folds over every service instance:

```nix
machineImports  = … acc ++ [ serviceModule.result.final.${machineName}.nixosModule  or { } ] …   # :156
darwinImports   = … acc ++ [ serviceModule.result.final.${machineName}.darwinModule or { } ] …   # :161
```

published as `clanInternals.inventoryClass.machines` (:167).

**Step 5 — imported into the machine, selected by `_class`.**
`modules/clan/module.nix:57` takes that set as `allMachines`; the per-machine module's imports end
with (:195-217):

```nix
++ lib.optionals (_class == "nixos")  (v.machineImports  or [ ])
++ lib.optionals (_class == "darwin") (v.darwinImports or [ ])
```

where `_class` is nixpkgs' module class (args `_class`, :183-192, added in nixpkgs #395141).
Instantiation is a two-entry map `moduleSystemConstructor = { nixos = nixpkgs.lib.nixosSystem; darwin = nix-darwin.lib.darwinSystem; }` (:51-55), the class read from
`inventory.machines.<name>.machineClass` (:59), and each machine is built with **only**
`outputs.moduleForMachine.<name>` as its module (:61-72, with the "ATTENTION!: Dont add any modules
here" comment). `outputs.moduleForMachine` is `attrsOf deferredModule` (:162-167).

**Summary of the seam:** the class selection is two hardcoded `optionals` plus a two-entry
constructor map. There is no generic "modules by class" hook.

---

## 2. What already works, and what is missing, for a mikrotik class

**Already works.**

* A service *can* return extra attributes from `perInstance`/`perMachine` — `result.allRoles`
  spreads them (`service-module.nix:952`).
* A service *can* declare its own option inside the role submodule, so a `mikrotikModule` does not
  need clan-core to declare it. **Measured**, not assumed: a value-module passed to a
  `submoduleWith { modules = [ …nixosModule/darwinModule… ]; }` declared
  `options.mikrotikModule` and read it back —
  `{"declared":{"imports":[{"_file":"… via option perInstance.mikrotikModule","imports":[{"hostname":"from-module"}]}]},"undeclared-is-error":{"success":true,"value":"absent"}}`.
* A mikrotik configuration is already a first-class artefact *outside* clan: `Infra/nix-mikrotik`
  evaluates and renders it (`lib.evalMikrotik`, `lib.mkRouterScript`), and the fleet already
  produces `flake.mikrotikConfigurations` (lunix #131).

**Missing.**

* No collection point for a third class: `result.final` (:1138-1177) has no place for it, and
  `distributed-services.nix` only builds `machineImports`/`darwinImports`.
* `machineClass` is closed: `types.enum [ "nixos" "darwin" ]` (`modules/inventoryClass/inventory.nix:274-285`).
* Nothing evaluates a router: routers have no `nixosConfiguration`, no inventory entry, no
  generators. A router is not a clan machine today.
* `module.nix:214` looks up `clan-core."${_class}Modules".clanCore` — a fourth class would be asked
  for `mikrotikModules.clanCore`, which has no meaning.

---

## 3. Options

| # | How | Cost | What it silently changes |
|---|---|---|---|
| **1** | Service declares `mikrotikModule` itself; the fleet collects it from `result.allRoles` in a flake-parts module | ~0 clan-core; a few lines each side | Rides `_services`: `visible = false`, and its own doc says *"Do not rely on this API yet… structure will change"* (`distributed-services.nix:95-104`). A clan refactor breaks the fleet's router build with no deprecation. |
| **2** | Clan-core PR: generic `perInstance.modules.<class>` (+ `perMachine.modules.<class>`), collected in `result.final` and published as `flake.mikrotikModules.<machine>` | one upstream PR at `49bdb2dc`, then both pins move | The two `optionals` at `module.nix:216-217` become a class lookup — nixos/darwin behaviour is preserved only if the collection is generic, so the PR must keep both lists byte-identical. |
| **3** | Fork clan-core (a tarball rev is already the pin) and carry #2 locally | same code as 2, no upstream review | Divergence on a dependency pinned by *two* repos, and every future clan bump becomes a rebase. Only worth it if upstream is unresponsive. |
| **4** | Routers become clan machines with `machineClass = "mikrotik"` | largest: widen the enum (`inventory.nix:274`), a third constructor, `clan-core.mikrotikModules.clanCore` (`module.nix:214`), the two filters (`module.nix:78-83,95-96`), `computed-tags.nix:15-18`, inventory entries for devices that cannot host a NixOS | Puts routers in `clan.machines`/`machineClass` semantics that assume an installable machine — `installedAt`, tags, `nixosConfigurations`. A router has none of those, so the inventory gains a device kind that is not a machine. |
| **5** | Touch clan not at all: routers stay a fleet flake output (today), and a clan service only carries the *deploy* half through `perMachine.nixosModule` (`services.mikrotik`, ccpkgs #80) | ~0 | A service can deploy a router config but cannot **own** it; the config stays in the fleet's `modules/mikrotik/routers.nix`, so "this service configures this router" is a convention, not a declaration. |

### Recommendation

**Target #2, interim #5.** #2 is the only option where "this service configures this router" is a
declaration rather than a convention, and it is a small generic change at a rev both repos already
pin. Until it lands, #5 is what is deployed today and needs nothing.

Rejected as the durable answer: **#1**, because it hard-codes a dependency on an internal API that
the project documents as unstable — the fleet's router config would break on a clan refactor with
no signal. **#3** unless upstream declines. **#4** for cost: it extends machine semantics to a
device that has none.

What #5 does not buy: a service cannot ship a router's configuration, so a router configured by
`@ccpkgs/mikrotik` is indistinguishable from one configured by hand.

---

## 4. Ordered work, so each PR lands green alone

| Step | Repo | Change | The test that catches its gap |
|---|---|---|---|
| 1 | clan-core (PR) | `perInstance.modules.<class>` / `perMachine.modules.<class>`; collect in `result.final`; publish `flake.mikrotikModules.<machine>`; replace the two `optionals` at `module.nix:216-217` with a lookup | extend `lib/inventory/distributed-service/tests/per_instance_args.nix` with a third-class case, **and** keep `nixosModules`/`darwinModules` derivations byte-identical for an existing machine (compare `drvPath` before/after) |
| 2 | `Infra/nix-mikrotik` | document `mikrotikModule` as "a list of `mikrotik`-class modules", add `lib.evalMikrotikModules = modules: evalMikrotik { inherit modules; }` so a service-shaped input is one call | eval a fixture that arrives only as a service would pass it, and render it |
| 3 | `ComputerClub/ccpkgs` | `@ccpkgs/mikrotik` clan service: roles with `mikrotikModule`, deploy via the existing `services.mikrotik`, and the secret generator moved here from the fleet (a generator belongs to the service that declares it) | clanTest: an instance whose role returns a `mikrotikModule` renders the expected script, and `vars check` names the generator's files |
| 4 | `Infra/lunix` | routers move from `modules/mikrotik/routers.nix` into inventory instances; `flake.mikrotikConfigurations` becomes a projection of the clan evaluation; the fleet-side generator is removed once step 3 lands | the rendered `homelab-router` script must stay **identical** to today's output (diff against the current `mikrotikConfigurations.homelab-router.script`), plus a line-by-line diff against `routers/homelab-router.rsc` |
| 5 | `Infra/lunix` | delete the manual path once deploys are unit-driven | `nix eval … .config.clan.core.vars.generators` no longer names the fleet-side generator |

Dependency worth stating: **step 3 pays off only after step 1** — without a collection point, the
service's `mikrotikModule` is invisible to anything but a hand-written walk over `result.allRoles`,
which is exactly option #1. Doing 3 before 1 locks in the internal API.

---

## 5. Open decisions (not picked here)

1. **The durable shape:** #1 (service-declared, internal API), #2 (upstream generic class, wait for
   it) or #5 (never; routers stay a fleet output). Everything downstream depends on this.
2. **Are routers clan machines at all?** #4 makes them `machineClass` citizens; #2 keeps them
   outside the inventory, with `flake.mikrotikModules` as the only visibility. A router in
   `clan.machines` is visible to `clan machines list` and to anything that assumes an installable
   host.
3. **Who owns the router secret generator** — the service (ccpkgs, where a clan service declares its
   own vars) or the fleet (as it is today in `modules/vars/generators/mikrotik.nix`)? Step 3 assumes
   the service; that is a reversal of lunix #131.

## 6. Unverified, with the command that settles each

| Claim | Status | Command |
|---|---|---|
| A clan *service module* (not just a fixture) can declare an option inside the role submodule in practice — the probe used `submoduleWith` directly, not a real service through `resolveModule` | **unverified** | define the option in `@ccpkgs/mikrotik` on a branch and `nix eval` an instance |
| `clan._services` is reachable from a consuming flake's `perSystem`/flake-parts module (option #1's reading path) | **unverified** | add a probe module to lunix that evals `config._services` and print the attr names |
| Upstream has no existing proposal for a generic class hook | **unverified** | `curl` the clan-core issue/PR list at git.clan.lol and search for `perInstance`/`modules.<class>` |
| clan-core's `clanTest` harness can carry a non-nixos class (step 3's test) | **unverified** | `lib/clanTest/flake-module.nix` — read whether the node class is fixed to nixos/darwin |

A downstream card may legitimately return "checked, it does not work, stopping here" on any of
these; that is a result, not a failure.