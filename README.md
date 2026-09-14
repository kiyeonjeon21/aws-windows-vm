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

On-demand `c6i.xlarge` in `us-east-1`, from the AWS Pricing API:

| | Per hour | Running 24/7 | Running 6h x 22d |
|---|---|---|---|
| Windows Server | USD 0.3540 | USD 258 / mo | USD 47 / mo |
| Linux, same hardware | USD 0.1700 | USD 124 / mo | USD 22 / mo |

The Windows licence is the whole of that difference, and it is charged per vCPU, so it scales with the instance rather than being a flat fee.

Stopped, you pay only for storage: about USD 8 per month for the 100 GiB gp3 volume, plus USD 3.60 for the Elastic IP, which AWS now bills whether or not it is attached to a running instance.
That floor of roughly USD 12 per month is the price of being able to stop the box and keep its disk.

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

If your credentials live in a named profile rather than the default one, export it first, and export the same value for the `vm` CLI later:

```sh
export AWS_PROFILE=your-profile
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

## Windows Server 2025 traps worth knowing

These each cost a debugging session when this was first built, and none of them announce themselves.

**The OpenSSH firewall rule is scoped to the Private profile.**
The AMI already ships an `OpenSSH-Server-In-TCP` rule, so the natural thing to write, create the rule when it is missing, silently does nothing.
The rule that is already there applies only to the Private network profile, and an EC2 network adapter is classified Public.
So sshd runs, listens on `0.0.0.0:22`, reports healthy, the rule exists and reports `Enabled: True`, and every packet is still dropped with nothing logged anywhere.
The bootstrap now sets `-Profile Any` explicitly rather than trusting a rule it did not create.

**The AWS CLI is not installed.**
Older Windows AMIs shipped it at `C:\Program Files\Amazon\AWSCLIV2\aws.exe`.
Server 2025 does not, so anything in user-data that shells out to `aws` fails.
The bootstrap installs it from its MSI, after sshd is already serving.

**The SSM agent may not register during first boot.**
While user-data is busy the agent can take far longer than its usual minute or two to appear in `describe-instance-information`, which makes a slow boot look like a broken network.
It registers normally once the box is idle.
If you need to tell the two apart, launch a throwaway Linux instance into the same subnet with the same security group and instance profile: if that one registers, your networking and IAM are fine.

**`Get-WindowsCapability -Online` with no `-Name` is a trap.**
It enumerates the whole Feature-on-Demand catalogue against Windows Update, which is slow and can hang.
Always ask for the capability you want by name.

**Set `DefaultShellCommandOption` when you set `DefaultShell`.**
Pointing sshd at PowerShell without it leaves sshd passing a cmd.exe style `/c`, which breaks `ssh host <command>` and scp while interactive logins keep working.

## Tearing it down

```sh
cd terraform
terraform destroy
aws ssm delete-parameter --name /winvm/administrator-password --region us-east-1
aws ssm delete-parameter --name /winvm/bootstrap-status --region us-east-1
```

The Parameter Store entries are created by the instance rather than by Terraform, so `destroy` does not remove them.
