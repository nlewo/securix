# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
#
# SPDX-License-Identifier: MIT

{
  pkgs ? import <nixpkgs> { },
}:
let
  dummySwitchToConfiguration = pkgs.writeShellScriptBin "switch-to-configuration" "echo 'switch-to-configuration script executed'";
in
{
  terminals.minimal.system = {
    toplevel = dummySwitchToConfiguration;
    config.services.comin.machineId = "";
  };
}
