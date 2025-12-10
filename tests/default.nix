# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  libSecurix,
  nixpkgs,
}:
{
  minimal = import ./minimal.nix { inherit pkgs libSecurix nixpkgs; };
  auto-updates = import ./auto-updates.nix { inherit pkgs libSecurix nixpkgs; };
}
