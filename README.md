# aws-windows-vm

A Windows Server development box on EC2 that you reach over SSH, set up for running a coding agent, and stop when you are not using it.

Four vCPU and 8 GiB of RAM, rebuilt from this repository in one command from any machine.

## What it builds

| | |
|---|---|
| Instance | `c6i.xlarge`, 4 vCPU / 8 GiB, Windows Server 2025 |
| Disk | 100 GiB gp3, encrypted |
| Access | OpenSSH with your public key, PowerShell 7 as the login shell |
| Fallback access | SSM Session Manager, which needs neither port 22 nor an allow-listed address |
| Network | Dedicated VPC, security group open only to the addresses you name |
| Tooling | git, Node.js, GitHub CLI, ripgrep, fd, jq, fzf, bat, neovim, Python, and Claude Code |
| Cost control | Stops itself after 30 idle minutes, plus `vm up` and `vm down` |

## Cost

On-demand `c6i.xlarge` in `us-east-1` is roughly USD 0.35 per hour with the Windows licence included, against roughly USD 0.17 for the same hardware running Linux.
The licence is most of the difference.

Left running continuously that is about USD 250 per month.
At six hours a day on weekdays, which is what the idle watchdog is there to enforce, it is closer to USD 45 per month.
Stopped, you pay only for the 100 GiB volume and the Elastic IP, about USD 12 per month.

## Prerequisites

- An AWS account, and credentials with the permissions in [`docs/deployer-policy.json`](docs/deployer-policy.json).
- Terraform 1.10 or later.
- The AWS CLI, and the Session Manager plugin if you want `vm console`.
- An SSH key pair. The examples assume `~/.ssh/id_ed25519`.

## Build it

```sh
cd terraform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # public key, your address, repo URL
terraform init
terraform apply
```

First boot takes about ten minutes.
SSH answers within two or three of those, well before the tooling finishes installing.

```sh
export PATH="$PWD/../bin:$PATH"
vm status                          # watch the bootstrap field reach 'complete'
vm ssh
```

Then authenticate the tools that cannot be provisioned for you:

```powershell
gh auth login
claude
```

## Daily use

```sh
vm up          # start, print the address
vm ssh         # start if stopped, then connect
vm down        # stop
vm status      # state, address, bootstrap progress, allowed source ranges
vm allow-ip    # authorise the network you are on right now
vm console     # Session Manager shell, for when SSH will not answer
vm logs        # tail the first-boot log
vm password    # Administrator password, for RDP
```

`vm` finds the instance by its `Name` tag rather than through Terraform state, so it works from any machine with the AWS CLI and credentials.
No checkout, no Terraform, no state file.

Add it to your `PATH`, or symlink it:

```sh
ln -s "$PWD/bin/vm" ~/.local/bin/vm
```

## Working from a second machine

Clone the repository, and you have the `vm` CLI immediately.

To run Terraform as well, move the state somewhere shared first.
Copy [`terraform/backend.tf.example`](terraform/backend.tf.example) to `terraform/backend.tf`, create the bucket it describes, and run `terraform init -migrate-state`.
Until you do, the state lives only on the machine that built the box, and a second machine would try to build a second one.

## How the pieces fit

`terraform/` builds the infrastructure and renders `bootstrap/userdata.ps1.tftpl` into the instance user-data.

That script runs once, as SYSTEM, at first boot.
It does the things that must not fail first, in this order: install and start sshd, write your public key, generate an Administrator password and file it in Parameter Store, register the idle watchdog.
Only then does it reach the network for Chocolatey and packages.
The ordering is deliberate.
A failed package download should cost you a tool, never your way in.

It finishes by cloning this repository to `C:\setup` and running `bootstrap/setup.ps1`, which holds everything you are likely to want to change: the package list, the npm globals, the PowerShell profile, the Defender exclusions.
That script is idempotent, so after pushing a change you can apply it without rebuilding:

```powershell
cd C:\setup; git pull; pwsh -File .\bootstrap\setup.ps1
```

Editing `userdata.ps1.tftpl` is different.
User-data only runs at first boot, so those changes take effect on the next rebuild and not before.

## The idle watchdog

A scheduled task checks every five minutes for established connections on port 22 and 3389, for a Session Manager worker process, and for CPU above 15 percent.
When none of those hold for `idle_shutdown_minutes` consecutive minutes, it stops the instance.

The CPU check is what keeps a long build alive after you close the laptop.
There is also a fifteen minute grace period after boot, so first-boot provisioning is never interrupted.

Set `idle_shutdown_minutes = 0` to turn it off.

Check the counter from inside a session:

```powershell
Get-IdleShutdownState
```

## Notes and limits

**WSL2 does not work here.**
EC2 does not offer nested virtualisation outside bare metal instances, so anything that needs a hypervisor inside the guest, WSL2 and Docker Desktop's Linux backend included, will not run on `c6i.xlarge`.
Windows containers do work.
If you find yourself wanting WSL2, that is a sign the workload wants a Linux instance instead, at half the hourly cost.

**The AMI is pinned after the first build.**
`ignore_changes = [ami]` is set on the instance.
Without it, the monthly Windows AMI release would make an unrelated `terraform apply` destroy the box and everything on its disk.
To move to a newer AMI deliberately, `terraform apply -replace=aws_instance.this`, which rebuilds from scratch.

**Security group rules are split on purpose.**
Terraform manages the rules for `allowed_cidrs`.
`vm allow-ip` adds a separate rule tagged `vm-cli-dynamic` and removes the one it added last time.
Because the configuration uses standalone rule resources and no inline `ingress` block, Terraform leaves that rule alone rather than reverting it on the next apply.

**The Administrator password is never in Terraform state.**
The instance generates it at first boot and writes it to `/winvm/administrator-password` as a SecureString.
SSH does not use it. RDP does.
RDP is closed by default; set `enable_rdp = true` if you need the desktop.

## Tearing it down

```sh
cd terraform
terraform destroy
aws ssm delete-parameter --name /winvm/administrator-password --region us-east-1
aws ssm delete-parameter --name /winvm/bootstrap-status --region us-east-1
```

The Parameter Store entries are created by the instance rather than by Terraform, so `destroy` does not remove them.
