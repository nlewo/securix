# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.securix.auto-updates;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.securix.auto-updates = {
    enable = mkEnableOption "la mise à jour automatique du code d'infrastructure de Sécurix";
    enableRebuild = mkEnableOption "la reconstruction automatique du système";

    repoUrl = mkOption {
      type = types.str;
      description = "URL de clonage du repo d'infrastructure Sécurix";
    };

    branch = mkOption {
      type = types.str;
      default = "main";
      description = "Branche du dépôt d'infrastructure Sécurix à mettre à jour";
    };

    repoSubdir = mkOption {
      type = types.str;
      default = "securix";
      description = "Sous-répertoire de la souche Sécurix";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.comin.serviceConfig.Environment = [
      "SSH_AUTH_SOCK=/var/tmp/ssh-tpm-agent.sock"
      # This is used by the SSH transport to get the known hosts
      # This is a workaround and comin should be able to take a list of host keys as parameter
      "HOME=/root"
    ];
    services.comin = {
      enable = true;
      repositoryType = "nix";
      repositorySubdir = cfg.repoSubdir;
      configurationAttr = ''terminals."${config.securix.self.machine.identifier}".system'';
      debug = true;
      remotes = [
        {
          name = "origin";
          url = cfg.repoUrl;
          branches.main.name = cfg.branch;
          # To disable the testing branch feature
          branches.testing.name = "";
          poller.period = 300;
        }
      ];
    };
  };
}
