{
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  # Per-person values. Terraform writes this file from terraform.tfvars.
  box = builtins.fromJSON (builtins.readFile ./box.json);

  # The tools Warlock's skills drive. A headless run sees only this PATH.
  claudeTools = lib.makeBinPath [
    pkgs.claude-code
    pkgs.gh
    pkgs.git
    pkgs.jq
    pkgs.python3
  ];

  # Warlock is a Claude Code plugin, so it lives in the user's ~/.claude, not
  # in the Nix store. These scripts manage it as that user.
  warlockInstall = pkgs.writeShellScriptBin "warlock-install" ''
    set -euo pipefail
    export PATH=${claudeTools}:$PATH
    if ! claude plugin marketplace list --json | jq -e 'any(.[]; .name == "warlock")' >/dev/null; then
      claude plugin marketplace add 'https://github.com/Genetic-Pottery/warlock.git#${box.warlock_ref}'
    fi
    if ! claude plugin list --json | jq -e 'any(.[]; .id == "warlock@warlock")' >/dev/null; then
      claude plugin install warlock@warlock
    fi
    echo "warlock is installed. Next, run 'claude', then '/mcp' to sign in to Linear or Jira."
  '';

  warlockUpdate = pkgs.writeShellScriptBin "warlock-update" ''
    set -euo pipefail
    export PATH=${claudeTools}:$PATH
    claude plugin marketplace update warlock
    claude plugin update warlock@warlock
  '';

  # Runs /warlock:pull once, headless, in the repository you're in.
  warlockPull = pkgs.writeShellScriptBin "warlock-pull" ''
    set -euo pipefail
    export PATH=${claudeTools}:$PATH
    exec claude -p "/warlock:pull $* No person is available." \
      --allowedTools "Bash,Read,Grep,Glob,Edit,Write,Agent,mcp__claude_ai_Linear,mcp__claude_ai_Atlassian_MCP"
  '';

  # remote-control-enable creates this file; the service doesn't start without it.
  remoteControlMarker = "/home/${box.username}/.local/state/warlock-box/remote-control";

  # Remote Control asks two questions on its first run: whether to turn it on,
  # and whether to trust ~/Projects. Answer them here in a terminal; after that
  # the remote-control service runs it unattended.
  remoteControlEnable = pkgs.writeShellScriptBin "remote-control-enable" ''
    set -euo pipefail
    export PATH=${claudeTools}:$PATH
    cd "$HOME/Projects"
    echo "Starting Remote Control in ~/Projects. Answer its prompts, check that"
    echo "this box shows up in the Claude app, then press Ctrl-C."
    # Keep this script alive through Ctrl-C so it can finish the setup below.
    trap : INT
    claude remote-control || true
    trap - INT
    mkdir -p "$(dirname ${remoteControlMarker})"
    touch ${remoteControlMarker}
    sudo systemctl restart remote-control
    echo "Remote Control is running and restarts on its own, including after a reboot."
  '';

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
    if PATH=${claudeTools}:$PATH claude plugin list --json 2>/dev/null | ${pkgs.jq}/bin/jq -e 'any(.[]; .id == "warlock@warlock")' >/dev/null; then ok "warlock: installed"; else todo "warlock: run 'warlock-install'"; fi
    if systemctl is-active --quiet remote-control; then ok "Remote Control: running"; else todo "Remote Control: run 'remote-control-enable'"; fi
    echo "  Trackers: in claude, run '/mcp' and sign in to Linear or Jira"
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

  # Headroom for long Claude Code sessions and their subagents.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4096;
    }
  ];

  users.users.${box.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;

  # The only way in. Tailscale SSH checks your tailnet identity, so no SSH keys
  # live on the box, and the security group allows no inbound traffic.
  services.tailscale = {
    enable = true;
    authKeyFile = "/var/lib/tailscale-authkey";
    extraUpFlags = [ "--ssh" ];
  };
  services.openssh.enable = lib.mkForce false;

  # Remote Control sessions start here. Ask Claude to clone or edit any repo
  # under it.
  systemd.tmpfiles.rules = [ "d /home/${box.username}/Projects 0755 ${box.username} users -" ];

  environment.systemPackages = with pkgs; [
    claude-code
    curl
    fd
    gh
    jq
    python3
    ripgrep
    rsync
    warlockInstall
    warlockUpdate
    warlockPull
    remoteControlEnable
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

  # Refresh the warlock plugin from its pinned ref once a day. A moving tag such
  # as `v0` picks up new releases; a fixed one such as `v0.1.0` never changes.
  systemd.services.warlock-update = lib.mkIf box.auto_update {
    description = "Update the warlock Claude Code plugin";
    serviceConfig = {
      Type = "oneshot";
      User = box.username;
      ExecStart = "${warlockUpdate}/bin/warlock-update";
    };
    environment.HOME = "/home/${box.username}";
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

  # One Remote Control server for every session you start from the Claude app.
  # It waits for remote-control-enable, which answers its first-run prompts.
  systemd.services.remote-control = {
    description = "Claude Code Remote Control server";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig = {
      ConditionPathExists = remoteControlMarker;
      StartLimitIntervalSec = 0;
    };
    # Claude's tools need the same commands you have in a login shell.
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];
    environment.HOME = "/home/${box.username}";
    serviceConfig = {
      User = box.username;
      WorkingDirectory = "/home/${box.username}/Projects";
      # --capacity keeps concurrent sessions within a t3.medium's memory.
      ExecStart = "${pkgs.claude-code}/bin/claude remote-control --spawn same-dir --capacity 4";
      # The server exits after a long network outage; bring it back.
      Restart = "always";
      RestartSec = 30;
    };
  };
}
