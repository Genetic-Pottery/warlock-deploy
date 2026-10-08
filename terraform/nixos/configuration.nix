{
  lib,
  pkgs,
  modulesPath,
  warlock,
  ...
}:

let
  # Per-person values. Terraform writes this file from terraform.tfvars.
  box = builtins.fromJSON (builtins.readFile ./box.json);

  # CI already runs warlock's tests; skipping them here keeps first boot shorter.
  warlockPkg = warlock.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs {
    doCheck = false;
  };

  rebuild = ''
    if [ "$(id -u)" -ne 0 ]; then exec sudo "$0" "$@"; fi
    export PATH=${
      lib.makeBinPath [
        pkgs.nix
        pkgs.git
        pkgs.nixos-rebuild
      ]
    }:$PATH
  '';

  warlockUpdate = pkgs.writeShellScriptBin "warlock-update" ''
    set -euo pipefail
    ${rebuild}
    nix flake update warlock --flake /etc/nixos
    nixos-rebuild switch --flake /etc/nixos#box
  '';

  boxUpdate = pkgs.writeShellScriptBin "box-update" ''
    set -euo pipefail
    ${rebuild}
    nix flake update --flake /etc/nixos
    nixos-rebuild switch --flake /etc/nixos#box
  '';

  boxStatus = pkgs.writeShellScriptBin "box-status" ''
    ok()   { printf '  [x] %s\n' "$1"; }
    todo() { printf '  [ ] %s\n' "$1"; }
    echo
    echo "warlock box"
    if ${pkgs.gh}/bin/gh auth status >/dev/null 2>&1; then ok "GitHub: logged in"; else todo "GitHub: run 'gh auth login'"; fi
    if [ -s "$HOME/.claude/.credentials.json" ]; then ok "Claude: logged in"; else todo "Claude: run 'claude' and log in"; fi
    echo "  warlock: $(${warlockPkg}/bin/warlock --version 2>/dev/null || echo installed)"
    echo
  '';
in
{
  imports = [ "${modulesPath}/virtualisation/amazon-image.nix" ];

  nixpkgs.hostPlatform = box.host_platform;
  system.stateVersion = box.state_version;
  networking.hostName = box.hostname;

  # User-data already did its job on first boot; don't run it again.
  virtualisation.amazon-init.enable = false;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];

  # Rust builds need more memory than small instances have.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4096;
    }
  ];

  users.users.${box.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ box.ssh_public_key ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = lib.mkForce "no";
  };

  environment.systemPackages = with pkgs; [
    claude-code
    curl
    fd
    gh
    jq
    ripgrep
    rsync
    warlockPkg
    warlockUpdate
    boxUpdate
    boxStatus
  ];

  programs.git = {
    enable = true;
    config = {
      user = {
        name = box.git_user_name;
        email = box.git_user_email;
      };
      init.defaultBranch = "main";
      pull.rebase = false;
      # gh supplies GitHub credentials once you run `gh auth login`.
      credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
      credential."https://gist.github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
    };
  };

  programs.tmux = {
    enable = true;
    historyLimit = 50000;
    terminal = "tmux-256color";
    escapeTime = 10;
    extraConfig = ''
      set -g mouse on
      set -as terminal-features ",*:RGB"
    '';
  };

  # On SSH login, show what's left to set up, then attach to one persistent
  # tmux session. Detach with Ctrl-b d; Claude keeps running inside tmux.
  programs.bash.interactiveShellInit = ''
    if [[ -n "$SSH_CONNECTION" && -z "$TMUX" ]]; then
      box-status
      ${lib.optionalString box.auto_tmux "tmux new-session -A -s main"}
    fi
  '';

  # Track warlock's main branch: pull the newest commit and rebuild daily.
  systemd.services.warlock-update = lib.mkIf box.auto_update {
    description = "Update warlock to the latest commit on main";
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = "${warlockUpdate}/bin/warlock-update";
    restartIfChanged = false;
  };
  systemd.timers.warlock-update = lib.mkIf box.auto_update {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
