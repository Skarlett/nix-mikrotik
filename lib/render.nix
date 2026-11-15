# The RouterOS script renderer.
#
# This is a pure function: an evaluated mikrotik configuration in, a `.rsc`
# script out. It is deliberately the only place that knows RouterOS syntax, so
# that the module layer can stay typed and the deploy tool can stay dumb.
#
# The value formatting is ported from upstream's `mikrotik.nix` (the
# `formatValue`/`formatSection` pair), so a configuration written for the
# original single-file generator renders here with every `add`/`set` line
# unchanged -- which `tests/golden/legacy-upstream.rsc`, produced by upstream's
# own generator, is what proves. The additions are: secret placeholders,
# booleans/ints, comment quoting, section ordering, `/system identity` first,
# and a generated-file header. They are listed with the golden (see
# `tests/golden/README.md`) rather than described as byte-identity.
{ lib }:
let
  inherit (lib)
    concatStringsSep concatMap filter mapAttrsToList isAttrs isBool isInt
    isList isString optional optionals;

  # A secret reference is a value, not a string: it renders as a placeholder
  # that the deploy tool substitutes on the machine that holds the secret.
  # Keeping it out of the rendered text is the whole point -- the .rsc lives in
  # the world-readable nix store, the value never does.
  isSecret = v: isAttrs v && v ? __mikrotikSecret;

  placeholder = name: "__MIKROTIK_SECRET_${name}__";

  # RouterOS spells booleans yes/no, and takes bare numbers.
  scalar = v:
    if isBool v then (if v then "yes" else "no")
    else if isInt v then toString v
    else if isString v then v
    else throw "nix-mikrotik: unsupported scalar value ${builtins.toJSON v}";

  # A quoted value (comments) may contain a quote; RouterOS escapes with a
  # backslash, and an unescaped one truncates the value silently. A `$` inside
  # double quotes starts a variable reference, so it is escaped as well. All
  # three are escaped the way RouterOS reads them back: verified on 7.15.3 by
  # importing a comment carrying `"`, `\` and `$` and reading it back
  # byte-identical (the deploy tool's substitution path is the same escaping).
  # replaceStrings is simultaneous, so the backslash pass cannot double up.
  escape = s: builtins.replaceStrings [ "\\" "\"" "$" ] [ "\\\\" "\\\"" "\\$" ] s;
  quoted = v: "\"${escape (scalar v)}\"";

  # RouterOS parses `key=value` with its own grammar and a value that contains
  # a space, `=`, `;`, a quote, a backslash or a `$` ends the command early:
  #   add ... public-key=l0VH8y3T0nKz...hkA=
  #   script error: expected end of command (line 41 column 186)
  # An exported configuration quotes exactly those (`public-key="…="`), so
  # mirror it rather than quoting everything, which would change the output for
  # values that are already fine unquoted (addresses, lists, names).
  needsQuote = s: builtins.match ''.*[ =;"\\$].*'' s != null;

  # RouterOS spells a list-valued argument as one comma-separated string --
  # `allowed-address=0.0.0.0/0,::/0`, `servers=1.1.1.1,8.8.8.8`,
  # `interfaces=wg0,wg1`. Writing the argument as a Nix list is the whole point
  # of accepting a list in a cell: the join happens here, in the one place that
  # knows RouterOS syntax, instead of every configuration building the string by
  # hand and getting the separator or the spacing wrong.
  cellText = v:
    if isList v then concatStringsSep "," (map cellText v)
    else if isSecret v then placeholder v.__mikrotikSecret
    else scalar v;

  formatValue = key: value:
    if isSecret value then
      # The placeholder goes in *bare*, and the deploy tool decides how the
      # value it stands for has to be spelled -- it holds the value, and the
      # value is what has to be quoted and escaped (a base64 key always ends in
      # `=`). Rendering the marker quoted here would substitute a value into a
      # slot that is already a string, which is a different question.
      (if key == null then placeholder value.__mikrotikSecret
       else "${key}=${placeholder value.__mikrotikSecret}")
    else if key == "comment" then
      "${key}=${quoted value}"
    else if key == "no_label" then
      # `no_label` drops the attribute name: `{ no_label = { a = "b"; }; }`
      # renders as `a=b` rather than `no_label=a=b`. It is how a menu that
      # takes `set` arguments as one line is written upstream.
      formatValue null value
    else if isList value then
      let joined = cellText value;
      in if key == null then
        (if needsQuote joined then quoted joined else joined)
      else if needsQuote joined then
        "${key}=${quoted joined}"
      else
        "${key}=${joined}"
    else if isAttrs value && key != null then
      concatStringsSep " " ([ key ] ++ mapAttrsToList (k: v: formatValue k v) value)
    else if isAttrs value then
      concatStringsSep " " (mapAttrsToList (k: v: formatValue k v) value)
    else if isString value && needsQuote value then
      "${key}=${quoted value}"
    else
      "${key}=${scalar value}";

  formatSection = name: opts:
    [ name ] ++ (if isAttrs opts then
      (mapAttrsToList (k: v: "set ${formatValue k v}") opts)
    else
      (map (x: "add ${formatValue null x}") opts));

  # Section order matters on RouterOS: an `add` that references an object
  # created later in the same script fails. Attrset order is alphabetical,
  # which is usually right and occasionally not, so a config can pin the
  # sections that must come first.
  orderedNames = sections: order:
    let
      pinned = filter (n: sections ? ${n}) order;
      rest = filter (n: !(builtins.elem n pinned)) (builtins.attrNames sections);
    in
    pinned ++ rest;

  # Every secret placeholder a rendered script will contain, for the deploy
  # tool's completeness check.
  referencedSecrets = sections:
    let
      walk = v:
        if isSecret v then [ v.__mikrotikSecret ]
        else if isAttrs v then concatMap walk (builtins.attrValues v)
        else if isList v then concatMap walk v
        else [ ];
    in
    lib.unique (concatMap (s: walk s) (builtins.attrValues sections));

in
{
  inherit formatValue formatSection referencedSecrets isSecret placeholder;

  # config: the evaluated `config` of a mikrotik module evaluation.
  render = config:
    let
      cfg = config.mikrotik;
      names = orderedNames cfg.sections cfg.sectionOrder;
      body = concatMap (n: formatSection n cfg.sections.${n}) names;
      lines =
        [ "# Generated by nix-mikrotik -- do not edit." ]
        ++ optional (cfg.comment != null) "# ${cfg.comment}"
        ++ [ "/system identity" "set name=${quoted cfg.hostname}" ]
        ++ body
        ++ cfg.extraScript;
    in
    concatStringsSep "\n" lines + "\n";
}
