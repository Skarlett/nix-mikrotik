# The module class

`lib.evalMikrotik` evaluates modules of class `mikrotik`: ordinary module
semantics — `imports`, typed options, composition, assertions — over
RouterOS's own data model.

`_class = "mikrotik"` modules are evaluated by `lib.evalMikrotik`, which is
`lib.evalModules` with `class = "mikrotik"` plus the base module. That means
normal module semantics: `imports` composes, options have types and defaults,
and a section defined in two modules merges rather than colliding.

| option | |
|---|---|
| `mikrotik.hostname` | `/system identity`; rendered first, and read back by the deploy tool |
| `mikrotik.sections` | RouterOS menus keyed by command path — upstream's data model, unchanged |
| `mikrotik.<menu>` | the same menus as options, one per menu, e.g. `mikrotik.ip."dhcp-server".network` (see below) |
| `mikrotik.sectionOrder` | sections to render first, for objects that must exist before they are referenced |
| `clan.core.vars.generators` | the values the configuration needs, as generators — clan's own interface, so a declaration moves between a clan machine and a router unchanged |
| `mikrotik.extraScript` | raw lines appended verbatim, for anything the data model cannot express |
| `mikrotik.checkMenuAttributes` | reject an attribute name a menu does not list (on) |

Assertions fail the *evaluation*, not a device: an empty hostname, a section
path that is not a RouterOS command path, a secret placeholder with no matching
generator file, or a `/system identity` section that would fight the option.

Booleans render as `yes`/`no` and integers bare, so a configuration reads like
Nix rather than like a stringly-typed script.
