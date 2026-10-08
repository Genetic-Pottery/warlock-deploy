# warlock-deploy

Terraform that runs a personal NixOS box on EC2 with Claude Code, the GitHub
CLI, git, and [warlock](https://github.com/Genetic-Pottery/warlock). SSH in from
anywhere and you land in a persistent tmux session where you can run `claude`
and ask it to use warlock for you.

## What you get

The box comes with the following:

- NixOS on a `t3.medium` with a 40 GiB encrypted disk and a fixed public IP.
- SSH open only to the IP ranges you list, with key login only and no root
  login.
- Claude Code, `gh`, git, tmux, ripgrep, fd, and jq.
- warlock built from the flake on its `main` branch, updated daily.
- git set up with your name and email, using `gh` for GitHub credentials.
- A login banner that lists the setup steps you haven't finished.

The whole system is declared in `terraform/nixos/`. Terraform fills in your
details as `/etc/nixos/box.json` on the box.

## Before you start

You need the following on your own machine:

- An AWS account, with credentials the AWS CLI can use (`aws sts
  get-caller-identity` succeeds).
- Terraform 1.6 or later.
- An SSH key pair. To make one, run `ssh-keygen -t ed25519`.
- A Claude subscription or API key, and a GitHub account.

You don't need Nix on your machine.

## Set up the box

1. Fill in your details:

   ```sh
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

   Edit `terraform.tfvars`. The required values are `git_user_name`,
   `git_user_email`, and `allowed_ssh_cidrs`. To find your IP, run
   `curl -s https://checkip.amazonaws.com` and add `/32` to it.

1. Create the box:

   ```sh
   terraform init
   terraform apply
   ```

1. Wait for first boot to finish. The box builds its NixOS system and warlock
   from source, which can take 20 minutes or more:

   ```sh
   ../scripts/wait-for-box.sh warlock@$(terraform output -raw public_ip)
   ```

   Until the build finishes, you can log in only as `root`. To watch the build,
   run `ssh root@<ip> journalctl -fu amazon-init`.

1. Log in and authenticate:

   ```sh
   ssh warlock@$(terraform output -raw public_ip)
   gh auth login
   claude
   ```

   Logins happen on the box, not in Terraform. Anything passed through
   Terraform ends up in the state file and the instance metadata.

1. Optional: copy your local Claude Code setup (`CLAUDE.md`, settings, skills,
   plugins, and themes) to the box:

   ```sh
   ../scripts/sync-claude-config.sh warlock@$(terraform output -raw public_ip)
   ```

   The script never copies credentials, history, or project memory. Check your
   `settings.json` before you sync. Settings that describe your own machine,
   such as auto mode's environment notes, are copied as they are.

If you changed `username`, use that name instead of `warlock` in these
commands.

## Use the box

Every SSH login attaches to a tmux session named `main`. Start `claude` there
and close your laptop. The session keeps running.

| To | Do |
|---|---|
| Detach and leave Claude running | Press `Ctrl-b d` |
| Reattach | SSH in again |
| Resume an earlier conversation | Run `claude --resume` |
| Update warlock now | Run `warlock-update` |
| Update everything, including Claude Code | Run `box-update` |
| Check what's left to set up | Run `box-status` |

`warlock-update` moves warlock to the newest commit on `main` and rebuilds. A
timer runs it once a day. To turn the timer off, set `auto_update = false`.

`box-update` also updates nixpkgs, which brings new versions of Claude Code,
`gh`, and everything else. Claude Code's built-in updater doesn't work on
NixOS, so run `box-update` to get new releases.

To turn off the automatic tmux session, set `auto_tmux = false`.

## Manage cost

The instance bills for every hour it runs. To pay only for the disk and IP
while you aren't using it, stop the instance:

```sh
aws ec2 stop-instances --instance-ids $(terraform output -raw instance_id)
aws ec2 start-instances --instance-ids $(terraform output -raw instance_id)
```

The IP, disk, and logins survive a stop.

To cut cost further, use a Graviton instance. Set `instance_type = "t4g.medium"`
and `architecture = "arm64"`.

To delete everything, run `terraform destroy`.

## Change the box

Changes to the NixOS files or to the values in `box.json` (`git_user_*`,
`username`, `auto_*`, or the SSH key) replace the instance. A replacement
wipes the disk, so you must log in to `gh` and `claude` again.

To change a running box without replacing it, edit the files in `/etc/nixos`
on the box and run `sudo nixos-rebuild switch --flake /etc/nixos#box`. Copy
the change back to `terraform/nixos/` so the next rebuild keeps it.

New NixOS images don't trigger a replacement. The flake keeps the running
system current instead.

## Security notes

- Claude on this box can do anything your GitHub token allows. We recommend a
  fine-grained token limited to the repositories you want it to touch. To use
  one, run `gh auth login --with-token` and paste the token.
- The box has no AWS permissions, so it can't touch your AWS account.
- Keep `allowed_ssh_cidrs` tight. If your IP changes, update it and run
  `terraform apply`. This change doesn't replace the instance.
- Don't store anything on the box that you can't afford to lose or leak.

## License

Apache License 2.0. See [LICENSE](LICENSE).
