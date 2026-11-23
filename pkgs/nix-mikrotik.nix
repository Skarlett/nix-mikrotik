{ lib, stdenv, python3, openssh, nix, rsc, makeWrapper }:

stdenv.mkDerivation {
  pname = "nix-mikrotik";
  version = "0.3.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  # Point the shebang at the interpreter directly. Relying on patchShebangs
  # works only while the interpreter is a *native* build input, and this script
  # is wrapped afterwards (postFixup), which is exactly the case where the
  # patched copy can be missed.
  postPatch = ''
    substituteInPlace nix_mikrotik.py \
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3'
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 nix_mikrotik.py $out/bin/nix-mikrotik
    runHook postInstall
  '';

  # What the tool needs from outside: an ssh client for the transport, nix
  # itself for `render`, which builds the script rather than reimplementing the
  # renderer, and `rsc` -- the differ `deploy` computes its patch with. Both
  # halves of a deploy come from this one package, so a consumer that pins
  # nix-mikrotik gets the differ that matches it.
  postFixup = ''
    wrapProgram $out/bin/nix-mikrotik \
      --prefix PATH : ${lib.makeBinPath [ openssh nix rsc ]}
  '';

  meta = {
    description = "Build, secret-deliver and deploy RouterOS scripts";
    mainProgram = "nix-mikrotik";
    platforms = lib.platforms.unix;
  };
}
