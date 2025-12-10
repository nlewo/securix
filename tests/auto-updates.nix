# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  libSecurix,
  nixpkgs,
}:
let
  infra = import ./infra-auto-updates.nix { inherit pkgs; };
  defaultNix = pkgs.writeText "default.nix" (builtins.readFile ./infra-auto-updates.nix);

  gitRepository = pkgs.runCommand "git-repository" { buildInputs = [ pkgs.git ]; } ''
    mkdir $out
    cd $out
    git init -b main
    git config user.name "John"
    git config user.email "john@doe.com"
    cp ${defaultNix} default.nix
    git add default.nix
    git commit -m "init"
  '';

  terminal = libSecurix.mkTerminal {
    name = "minimal";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          ssh.tpm-agent = {
            hostKeys = true;
            sshKeys = true;
          };
          auto-updates = {
            enable = true;
            repoUrl = "ssh://git@git-server/home/git/repository";
            repoSubdir = ".";
          };
          graphical-interface.variant = "sway";
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              serialNumber = "000000";
            };
          };
        };
      }
    ];
  };
  test = pkgs.testers.nixosTest {
    name = "minimal";
    interactive.sshBackdoor.enable = true;
    nodes = {
      git-server =
        { pkgs, ... }:
        {
          environment.systemPackages = [
            pkgs.git
            pkgs.vim
          ];
          services.openssh.enable = true;
          users.users.git = {
            isNormalUser = true;
            description = "git user";
            createHome = true;
            home = "/home/git";
            shell = "${pkgs.git}/bin/git-shell";
          };
        };
      securix-unbranded-000000 = {
        imports = terminal.modules ++ [
          {
            # This is to provide a <nixpkgs> into the test vm to allow building the system
            nix.settings.nix-path = nixpkgs;
            # This is to prefill the store with the closure of this toplevel to avoid having to fetch github
            # Otherwise, comin will have to build this before the test deployment
            environment.systemPackages = [ infra.terminals.minimal.system.toplevel ];
            virtualisation.qemu.options = [
              "-chardev socket,id=chrtpm,path=$NIX_BUILD_TOP/swtpm-sock"
              "-tpmdev emulator,id=tpm0,chardev=chrtpm"
              "-device tpm-tis,tpmdev=tpm0"
            ];
          }
        ];
      };
    };
    testScript = ''
      import os
      import subprocess

      tmpdir = os.environ['NIX_BUILD_TOP']

      class Tpm:
            def __init__(self):
                self.start()

            def start(self):
                print(f"starting swtpm listening on {tmpdir}/swtpm-sock")
                self.proc = subprocess.Popen(["${pkgs.swtpm}/bin/swtpm",
                    "socket",
                    "--tpmstate", f"dir={tmpdir}/swtpm",
                    "--ctrl", f"type=unixio,path={tmpdir}/swtpm-sock",
                    "--tpm2"
                    ])

                # Check whether starting swtpm failed
                try:
                    exit_code = self.proc.wait(timeout=0.2)
                    if exit_code is not None and exit_code != 0:
                        raise Exception("failed to start swtpm")
                except subprocess.TimeoutExpired:
                    pass

      os.mkdir(f"{tmpdir}/swtpm")
      tpm = Tpm()
      start_all()

      securix_unbranded_000000.wait_for_unit("default.target")
      securix_unbranded_000000.wait_for_file("/etc/ssh/ssh_tpm_host_ecdsa_key.pub", 120)
      # I tried to provision swtpm but i didn't succeed. It seems pretty
      # hard because the private key is not only in the TPM but IIUC,
      # encrypted by the TPM and store on the disk in /etc/ssh.
      securix_unbranded_000000.copy_from_vm("/etc/ssh/ssh_tpm_host_ecdsa_key.pub", f"{tmpdir}/")
      git_server.wait_for_unit("default.target")
      git_server.succeed("mkdir /home/git/.ssh")
      git_server.copy_from_host(f"{tmpdir}/ssh_tpm_host_ecdsa_key.pub", "/home/git/.ssh/authorized_keys")
      git_server.succeed("chown git /home/git/.ssh/authorized_keys")

      git_server.succeed("mkdir /home/git/repository")
      git_server.succeed("cp -r ${gitRepository}/* ${gitRepository}/.* /home/git/repository/")

      # Copy the git-server host key
      # It would be better to be able to inject these keys
      git_server.wait_for_file("/etc/ssh/ssh_host_ed25519_key.pub", 120)
      git_server.copy_from_vm("/etc/ssh/ssh_host_ed25519_key.pub", f"{tmpdir}/")
      securix_unbranded_000000.copy_from_host(f"{tmpdir}/ssh_host_ed25519_key.pub", "/root/ssh_host_ed25519_key.pub")
      securix_unbranded_000000.succeed("mkdir -p /root/.ssh && echo -n 'git-server ' > /root/.ssh/known_hosts && cat /root/ssh_host_ed25519_key.pub >> /root/.ssh/known_hosts")


      # Run a comin fetch and ensure the deployment succeeded
      securix_unbranded_000000.succeed("comin fetch")
      securix_unbranded_000000.wait_until_succeeds("comin status --json | jq -e '.deployer.deployment.status == \"done\"'", 120)
    '';
  };
in
test
