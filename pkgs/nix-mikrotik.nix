{ lib, stdenv, python3, openssh, nix, makeWrapper }:

stdenv.mkDerivation {
  pname = "nix-mikrotik";
  version = "0.2.0";

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

  # What the tool needs from outside: an ssh client for the transport, and nix
  # itself for `render`, which builds the script rather than reimplementing the
  # renderer.
  postFixup = ''
    wrapProgram $out/bin/nix-mikrotik \
      --prefix PATH : ${lib.makeBinPath [ openssh nix ]}
  '';

  meta = {
    description = "Build, secret-deliver and deploy RouterOS scripts";
    mainProgram = "nix-mikrotik";
    platforms = lib.platforms.unix;
  };
}
