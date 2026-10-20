# warlock-deploy

Terraform that runs a personal NixOS box on EC2 with Claude Code, the GitHub
CLI, git, and the [Warlock](https://github.com/Genetic-Pottery/warlock) plugin.
The box runs a Claude Code Remote Control server, so you can start and drive
Claude sessions from the Claude mobile app while your laptop is off. For a
terminal, SSH in over Tailscale and you land in a persistent tmux session.

## What you get

The box comes with the following:

- NixOS on a `t3.medium` with a 40 GiB encrypted disk.
- No inbound ports. You reach the box through Tailscale, and Remote Control
  connects out to Anthropic. The public IP carries outbound traffic only, so
  you don't pay for a NAT gateway.
- A Remote Control server in `~/Projects` that restarts on its own, including
  after a reboot.
- Claude Code, `gh`, git, Python 3, tmux, ripgrep, fd, and jq.
- A `warlock-install` command that installs the Warlock plugin from a pinned
  ref, and a daily refresh from that ref.
- A `warlock-pull` command that runs `/warlock:pull` headless.
- git set up with your name and email, using `gh` for GitHub credentials.
- A login banner that lists the setup steps you haven't finished.

The whole system is declared in `terraform/nixos/`. Terraform fills in your
details as `/etc/nixos/box.json` on the box.

## Before you start

You need the following:

- A computer with Terraform 1.6 or later, and AWS credentials the AWS CLI can
  use (`aws sts get-caller-identity` succeeds). You need it only to create the
  box.
- A phone with these apps:
  - [Tailscale](https://tailscale.com), signed in to your tailnet.
  - The Claude app, signed in to the account you use on the box.
  - An SSH app. Termius works on iOS and Android, and its free tier covers
    this setup. You can skip the Pro trial it offers.
- A Claude Pro, Max, Team, or Enterprise plan. Remote Control needs a claude.ai
  login; API keys don't work with it. On Team and Enterprise, an owner must turn
  on Remote Control in the admin settings.
- A GitHub account.
- A Linear or Jira Cloud workspace, connected to your Claude account. See
  Warlock's [Get started](https://github.com/Genetic-Pottery/warlock/blob/main/GETTING-STARTED.md)
  guide for the tracker setup.

You don't need Nix, an SSH key, or Tailscale on your computer.

## Set up the box

You create the box from your computer, then finish setup from your phone. The
phone steps work the same from any terminal on your tailnet.

### Create the box from your computer

1. In the Tailscale admin console, open
   [Keys](https://login.tailscale.com/admin/settings/keys) and click
   **Generate auth key**. Use these settings:

   - **Reusable:** off. The box uses the key once, on first boot.
   - **Expiration:** one day.
   - **Ephemeral:** off. Tailscale removes an ephemeral device when it goes
     offline, so stopping the instance would drop it.
   - **Tags:** none. Tailscale's default SSH rule covers only devices you own,
     and a tagged device isn't one.

1. Fill in your details:

   ```sh
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

   Edit `terraform.tfvars`. The required values are `git_user_name`,
   `git_user_email`, and `tailscale_auth_key`. Keep the key in the file after
   setup. If you leave it out, every `terraform apply` asks for it, and a
   different key replaces the box.

1. Create the box:

   ```sh
   terraform init
   terraform apply
   ```

### Finish setup from your phone

1. Wait for `warlock-box` to appear in the Tailscale app. The box joins your
   tailnet when its first NixOS build finishes, which takes several minutes.

1. In your SSH app, add a host with these values:

   - **Host:** `warlock-box`, or the `100.x.y.z` address the Tailscale app
     shows for it.
   - **Username:** `warlock`.

   Leave the port at 22, and leave the password and key empty. Tailscale SSH
   checks your tailnet identity instead.

1. Connect. Tailscale prints a URL the first time. Open it in your browser and
   approve the login, and the session continues.

1. Log in to GitHub:

   ```sh
   gh auth login
   ```

   Choose GitHub.com, HTTPS, and login with a web browser. Copy the code, open
   the URL in your browser, and enter the code.

1. Log in to Claude:

   ```sh
   cd ~/Projects
   claude
   ```

   Copy the login URL to your browser, then paste the code back. When Claude
   asks whether you trust `~/Projects`, answer yes. Exit with `/exit`.

   Logins happen on the box, not in Terraform. Anything passed through
   Terraform ends up in the state file and the instance metadata.

1. Install Warlock, then sign in to your tracker:

   ```sh
   warlock-install
   claude
   ```

   In Claude, run `/mcp`, select Linear or Atlassian, and complete sign-in.
   Exit with `/exit`.

1. Turn on Remote Control:

   ```sh
   remote-control-enable
   ```

   The command runs in the foreground so you can answer its prompts. When
   `warlock-box` appears in the Claude app, switch back to the SSH app and
   press `Ctrl-C`. The command then hands the server to a system service that
   keeps it running.

1. Check the server:

   ```sh
   systemctl status remote-control
   ```

   The output shows `active (running)`. You can close the SSH app; you don't
   need it for daily use.

If you changed `username` or `name`, use those values instead of `warlock` and
`warlock-box`.

To skip the browser approval on each SSH login, change the SSH rule's `action`
from `check` to `accept` in your tailnet policy file. The default asks again at
most every 12 hours.

### Optional: copy your Claude Code setup

To copy your local `CLAUDE.md`, settings, skills, plugins, and themes to the
box, run this from a computer on your tailnet:

```sh
scripts/sync-claude-config.sh warlock@warlock-box
```

The script never copies credentials, history, or project memory. Check your
`settings.json` before you sync. Settings that describe your own machine, such
as auto mode's environment notes, are copied as they are.

## Use the box from your phone

Open the Claude app and pick the box. Each session you start runs in
`~/Projects` on the box. Tell Claude which repository to work in, or ask it to
clone one. For example: "Clone my-org/api and draft a fix for the login
timeout."

Sessions that run at the same time share the same checkouts. If two sessions
work in one repository, ask one of them to use a git worktree.

The server runs up to four sessions at once. To change that, edit `--capacity`
in `terraform/nixos/configuration.nix`.

## Use the box from a terminal

Every SSH login attaches to a tmux session named `main`. Start `claude` there
and close your laptop. The session keeps running. To reach that session from
the Claude app too, run `/remote-control` inside it.

| To | Do |
|---|---|
| Detach and leave Claude running | Press `Ctrl-b d` |
| Reattach | SSH in again |
| Resume an earlier conversation | Run `claude --resume` |
| Work one ticket with nobody watching | In a repository, run `warlock-pull [scope or ticket key]` |
| Check the Remote Control server | Run `systemctl status remote-control` |
| Update the Warlock plugin now | Run `warlock-update` |
| Update everything, including Claude Code | Run `box-update` |
| Check what's left to set up | Run `box-status` |

`warlock-pull` runs `/warlock:pull` once, headless, and tells it nobody can
answer questions. It ends in a pull request, a paused ticket, or a halted
ticket, the same as an interactive pull. To keep working tickets as they
arrive, run it in a loop inside tmux:

```sh
while true; do warlock-pull; sleep 600; done
```

Each pass costs a short Claude session even when the queue is empty. If you
pull tickets on demand from your phone instead, you don't need the loop.

`warlock-update` refreshes the plugin from `warlock_ref`, which defaults to the
moving `v0` tag, so new `0.x` releases arrive on their own. To stay on one
release, set `warlock_ref = "v0.1.0"`. A timer runs `warlock-update` once a day.
To turn the timer off, set `auto_update = false`.

`box-update` also updates nixpkgs, which brings new versions of Claude Code,
`gh`, and everything else. Claude Code's built-in updater doesn't work on
NixOS, so run `box-update` to get new releases. After an update, restart the
server with `sudo systemctl restart remote-control`.

To turn off the automatic tmux session, set `auto_tmux = false`.

## Manage cost

The instance bills for every hour it runs, and AWS bills for its public IPv4
address. To pay only for the disk while you aren't using it, stop the
instance:

```sh
aws ec2 stop-instances --instance-ids $(terraform output -raw instance_id)
aws ec2 start-instances --instance-ids $(terraform output -raw instance_id)
```

A stopped box can't take sessions from your phone, and you can't start it from
the Claude app. The disk, logins, and tailnet membership survive a stop, and
the Remote Control server starts again on boot.

To cut cost further, use a Graviton instance. Set `instance_type = "t4g.medium"`
and `architecture = "arm64"`.

To delete everything, run `terraform destroy`. Then remove the box from the
[Machines](https://login.tailscale.com/admin/machines) page in Tailscale.

## Change the box

Changes to the NixOS files or to the values in `box.json` (`git_user_*`,
`username`, `auto_*`, or `warlock_ref`) replace the instance. So does a new
`tailscale_auth_key`. A replacement wipes the disk, so plan for the following:

- Before you apply, generate a new auth key and put it in `terraform.tfvars`.
  The old key is spent, so a new box can't join your tailnet with it.
- After the new box joins, remove the old one from the Machines page in
  Tailscale. Until you do, the new box gets a suffixed name such as
  `warlock-box-1`.
- Log in to `gh` and `claude`, run `warlock-install`, sign in to your tracker,
  and run `remote-control-enable` again.

To change a running box without replacing it, edit the files in `/etc/nixos`
on the box and run `sudo nixos-rebuild switch --flake /etc/nixos#box`. Copy
the change back to `terraform/nixos/` so the next rebuild keeps it.

New NixOS images don't trigger a replacement. The flake keeps the running
system current instead.

## Troubleshoot

If the box never joins your tailnet, the first-boot build might have failed.
With no inbound ports, you can't log in to look. Read the boot log from the
EC2 console instead:

```sh
aws ec2 get-console-output --latest --output text \
  --instance-id $(terraform output -raw instance_id)
```

If the auth key expired before first boot, generate a new one and apply again.

If the Remote Control server keeps restarting, read its log with
`journalctl -u remote-control`.

## Security notes

- Claude on this box can do anything your GitHub token allows. Warlock's hooks
  keep its file edits inside a ticket's scope, but they don't stop it from
  running `git push` or `gh` itself. We recommend a fine-grained token limited
  to the repositories you want it to touch, with no rights to push to protected
  branches. To use one, run `gh auth login --with-token` and paste the token.
- In each repository it works on, make Warlock's CI check a required status
  check. That check is what stops an out-of-scope pull request from merging.
- Anyone signed in to your Claude account can drive the box through Remote
  Control. Protect that account the way you protect your GitHub account.
- Remote Control stores session transcripts on Anthropic's servers. Code runs
  and files stay on the box.
- Anyone who can SSH to the box over your tailnet gets a shell. Keep your
  tailnet's SSH rule limited to your own devices.
- The box has no AWS permissions, so it can't touch your AWS account.
- The Tailscale auth key stays in the instance's user data and in Terraform
  state. It's one-time, so it's useless after first boot.
- Don't store anything on the box that you can't afford to lose or leak.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
