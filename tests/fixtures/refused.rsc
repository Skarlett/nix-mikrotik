# A script the device refuses, and the refusal the deploy check depends on.
#
# This is the shape the renderer must never produce: a value RouterOS ends the
# command on, left unquoted. A WireGuard private key is 32 bytes, so base64 of
# it always ends in `=` padding -- and unquoted, that `=` reads as the start of
# another attribute. The device stops at parse time, nothing in the script
# applies, and `/import` still exits 0, which is exactly why a deploy needs the
# sentinel and why this fixture exists.
#
# `tests/chr-deploy.nix` deploys it and requires the deploy to fail; a check
# whose subject is a script that always applies cannot be shown to fail.
/system identity
set name="chr-deploy-refused"
/interface wireguard
add name=broken-wg private-key=QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=