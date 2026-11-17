# The typed menu surface as a library: an option tree, and the compiler that
# turns what was set into `sections`.
#
# It is a library rather than a module because there are two places a router's
# menus are written -- `mikrotik.<menu>` for the single-router form and
# `mikrotik.routers.<name>.<menu>` for the fleet form -- and the two have to be
# the same surface, not two declarations that drift. `modules/base.nix` splices
# `optionTree` into the option set it uses for both forms, and
# `modules/menus.nix` compiles both with `compile`.
#
# Everything here is a function of one router's config subtree, never of
# `config.mikrotik` itself, so the caller decides which router it is talking
# about.
{ lib }:
let
  inherit (lib)
    concatMap concatStringsSep filter filterAttrs foldl' getAttrFromPath hasPrefix
    isString listToAttrs mkOption nameValuePair optional optionalString recursiveUpdate
    setAttrByPath splitString subtractLists;

  typeLib = import ./types.nix { inherit lib; };
  menus = import ./menus.nix;

  # `/ip dhcp-server network` -> [ "ip" "dhcp-server" "network" ]. The segment
  # keeps RouterOS' spelling, dashes and all: it is the option *name*, so it
  # only needs quoting in Nix source (`ip."dhcp-server"`), never rewriting.
  segments = m: splitString " " (lib.removePrefix "/" m.path);

  # A menu has children when another menu's path extends it by a whole segment.
  hasChildren = m:
    lib.any (o: o.path != m.path && hasPrefix "${m.path} " o.path) menus;

  # Where the user writes this menu's body: at the menu's own attribute path,
  # plus `items` when the menu has submenus.
  #
  # This is not a stylistic choice. A submenu needs `interface.6to4` to be an
  # attribute *set of options*, so the parent cannot also be a single option at
  # that path -- and that is true whether the parent's body is a list or a `set`
  # body. `/interface` is the case that proves it: it is a real `set`-able menu
  # (`/interface set mtu=…` applies to every port) *and* the parent of 96 menus,
  # so without `items` the option tree and the body collide and nothing
  # evaluates.
  #
  # The cost is real -- a full generated table gives nine menus a submenu nobody
  # writes and therefore an `items` wrapper -- and it is paid once, in the
  # configurations that write those menus, rather than by making the option tree
  # depend on where the collision happens to be.
  needsItems = hasChildren;

  accessPath = m: segments m ++ optional (needsItems m) "items";

  bodyType = m: if m.kind == "list" then typeLib.menuItems else typeLib.menuObject;

  emptyBody = m: if m.kind == "list" then [ ] else { };

  renderVerb = m: if m.kind == "list" then "repeated `add …` lines" else "`set …` lines";

  # The attributes the device reports as multi-value: RouterOS spells them
  # `interfaces=ether1,ether2` and stores two values, so the typed menu wants
  # `interfaces = [ "ether1" "ether2" ]`. The table comes from the router
  # (`scripts/probe-menu-lists.py`), not from a guess.
  listsOf = m: m.lists or [ ];

  menuOption = m: mkOption {
    type = bodyType m;
    default = emptyBody m;
    description = ''
      RouterOS `${m.path}`, rendered as ${renderVerb m}.
      ${optionalString (needsItems m) ''
        Written under `items`: this attribute set holds the menu's submenus,
        and `items` holds its own objects, because the two cannot share one
        attribute set.
      ''}
      ${optionalString (m.attrs != null) ''
        Known attribute names: ${concatStringsSep ", " (map (a: "`${a}`") m.attrs)}.
      ''}
      ${optionalString (listsOf m != [ ]) ''
        Multi-value attributes, written as a list: ${concatStringsSep ", " (map (a: "`${a}`") (listsOf m))}.
        RouterOS stores these as separate values (`${builtins.head (listsOf m)}=a,b`), so
        `${builtins.head (listsOf m)} = [ "a" "b" ]` is the spelling that says so.
      ''}
      ${optionalString (m.attrs == null) ''
        Attribute names are not checked for this menu.
      ''}
      The same menu is expressible as `sections."${m.path}"`; both render
      identically, so a configuration can mix the two spellings.
    '';
  };

  # The attribute names the user wrote for a menu, at the level they wrote them:
  # element keys for a list menu, body keys for a `set` menu.
  writtenFor = cfg: m:
    let body = getAttrFromPath (accessPath m) cfg;
    in if m.kind == "list" then lib.concatMap lib.attrNames body else lib.attrNames body;
in
{
  inherit menus accessPath segments;

  # The multi-value attributes of every menu: `modules/menus.nix` uses them to
  # reject a comma-joined string, and `menuOption` names them in every menu's
  # description. `commaStrings`/`messageForCommaStrings` below are the check.
  inherit listsOf;

  # The option tree, one leaf per menu. Nested attribute sets are how a module
  # system declares `foo.bar.baz` without a `foo` and a `foo.bar` option.
  optionTree = foldl' (acc: m: recursiveUpdate acc (setAttrByPath (accessPath m) (menuOption m))) { } menus;

  # The compiler: what was set, keyed the way the renderer wants it. Menus left
  # at their default are dropped, because an empty body is not the same router
  # configuration as no section at all -- `sections."/ip address" = [ ]` renders
  # the bare menu header, and a menu nobody set must not do that.
  compile = cfg: filterAttrs (_: body: body != [ ] && body != { })
    (listToAttrs (map
      (m: nameValuePair m.path (getAttrFromPath (accessPath m) cfg))
      menus));

  # A typo on the left of the `=` is the failure this layer exists to catch: as
  # a string the renderer would happily emit `add widht=80` and the router would
  # reject the script at deploy time, on the device.
  unknownAttributes = cfg: map
    (m: { inherit (m) path; inherit (m) attrs; names = subtractLists m.attrs (writtenFor cfg m); })
    (filter (m: m.attrs != null) menus);

  # The other half of the same idea, one level down: an attribute the device
  # reports as multi-value written as one comma-joined string. It renders the
  # same script, which is exactly why nothing catches it later -- a stray space
  # after the comma (`"ether1, ether2"`) is a `script error` on the device, and
  # a list is what says "these are two values" in the configuration.
  commaStrings = cfg: concatMap
    (m:
      let
        body = getAttrFromPath (accessPath m) cfg;
        elements = if m.kind == "list" then body else [ body ];
        offenders = lib.unique (concatMap
          (element: filter (a: isString (element.${a} or null)) (listsOf m))
          elements);
      in
      optional (offenders != [ ]) { inherit (m) path; attrs = listsOf m; names = offenders; })
    (filter (m: listsOf m != [ ]) menus);

  messageForCommaStrings = label: c:
    let
      one = builtins.length c.names == 1;
      names = concatStringsSep ", " c.names;
      example = a: "`${a} = [ \"a\" \"b\" ]`";
    in
    "${label}.${concatStringsSep "." (segments c)}: ${
      if one then "this menu stores `${names}` as several values" else "this menu stores all of ${names} as several values"
    }, and ${if one then "it is" else "they are"} written as one comma-joined string. "
    + "Write ${concatStringsSep " and " (map example c.names)} instead -- one value is still a list: `${builtins.head c.names} = [ \"one\" ]`. "
    + "RouterOS prints ${if one then "it" else "them"} comma-joined in `/export`, which is why the string renders the same script and nothing would catch it later; "
    + "`mikrotik.sections.\"${c.path}\"` still takes that form, so this is an assertion rather than a type error.";

  messageFor = label: u:
    "${label}.${concatStringsSep "." (segments u)}: ${u.path} has no "
    + (if builtins.length u.names == 1 then "attribute named " else "attributes named ")
    + "${concatStringsSep ", " u.names}. Known names for this menu: ${concatStringsSep ", " u.attrs}. "
    + "If that is a real RouterOS attribute, add it to lib/menus.nix; "
    + "otherwise write the menu as ${label}.sections.\"${u.path}\", or set "
    + "${label}.checkMenuAttributes = false to write it unchecked.";
}
