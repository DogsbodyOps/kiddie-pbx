# kiddie-pbx

A private phone system for children. It's a Christmas present for my daughter and my nieces, so they can pick up a phone and talk to each other.

The idea came from Tin Can, a phone service for kids. I liked the concept but thought the pricing was too high, so this is a self-hosted version built on open source software.

It runs [Asterisk](https://www.asterisk.org/) on a small Azure VM. The system has no connection to the phone network, so the only people the children can call, or be called by, are the ones set up on it.

## Status

Not live yet. The target is Christmas 2026.

- [x] Dialplan and SIP config, carried over from the prototype
- [x] tofu for the VM and DNS record
- [x] Ansible playbook, written but not yet run on the target Ubuntu 24.04 VM
- [x] PJSIP over TLS and SRTP config, written but not yet tested with a real call
- [x] fail2ban config, written but not yet tested with a real failed login
- [ ] Add the firewall rules to the `simple-vm` tofu module (see [Connecting phones](#connecting-phones))
- [ ] Confirm the handsets support TLS and SRTP, and trust the certificate
- [ ] Set up the handsets and test them

## How it works

```text
Daughter's handset ──┐
Niece's handset ─────┼── TLS + SRTP ──> Asterisk on Azure VM
Parent's handset ────┘
```

Each handset registers with Asterisk using its own extension number and password. All audio passes through Asterisk instead of going directly between phones, which keeps things simple when the phones are in different homes. Call setup is encrypted with TLS, and audio with SRTP.

### Extensions

The first digit of an extension says who it belongs to. Asterisk sends that category to the phone being called, so a phone can be set up to use a different ringtone for each group.

| Range | Who | `Alert-Info` value |
| --- | --- | --- |
| `1XX` | Children | `family-sibling` |
| `2XX` | Parents | `family-parent` |
| `3XX` | Grandparents (planned) | `family-grandparent` |
| `900` | Test line, plays "hello world" | |

Any other caller sends `family-default`. A phone with no matching ringtone rule uses its normal ring.

Calls ring for 20 seconds, then the caller hears a busy or "didn't connect" tone.

## Repository layout

| Path | Purpose |
| --- | --- |
| `tofu/` | Azure VM, resource group and Cloudflare DNS record |
| `ansible/deploy-asterisk.yml` | Builds Asterisk 22.11.0 from source, and sets up the config, TLS certificate and fail2ban |
| `ansible/files/asterisk/` | Asterisk config, including the dialplan in `extensions.conf` |
| `ansible/files/fail2ban-asterisk.conf` | fail2ban jail |
| `ansible/files/certbot-deploy-asterisk.sh` | Copies renewed certificates to Asterisk and restarts it |
| `ansible/templates/pjsip.conf.j2` | SIP config, with extensions filled in from the vault |
| `docs/asterisk-setup.md` | How the original prototype was built, and how the playbook differs from it |

## Deploying

You'll need tofu, Ansible, and access to Azure, Cloudflare and the Backblaze B2 bucket that holds the tofu state.

### 1. Create the VM

```bash
cd tofu
az login
export CLOUDFLARE_API_TOKEN=...
export AWS_ACCESS_KEY_ID=...        # Backblaze B2 key for the tofu state
export AWS_SECRET_ACCESS_KEY=...
tofu init -backend-config=backend.tfbackend
tofu apply
```

### 2. Add the extensions and host

Real names and SIP passwords stay out of this repo because it's public. Both of these files are gitignored, so keep your own copies somewhere safe.

```bash
cd ../ansible
cp inventory.example.ini inventory.ini
cp vault.example.yml group_vars/asterisk/vault.yml
```

Set the VM's address, user, DNS name and certificate email in `inventory.ini`. Add the names, passwords and a Cloudflare API token to `vault.yml`. Give every extension its own strong password, and limit the token to Zone:DNS:Edit on this zone. Then encrypt the vault:

```bash
ansible-vault encrypt group_vars/asterisk/vault.yml
```

### 3. Install Asterisk

```bash
ansible-playbook deploy-asterisk.yml --ask-vault-pass --ask-become-pass
```

The first run compiles Asterisk and requests a Let's Encrypt certificate, so it takes a while, and the DNS record has to exist first. The playbook finishes by checking that Asterisk is listening for TLS and has loaded SRTP. Dial `900` from a registered handset to test audio.

### Adding someone

1. Pick a free number in the right range.
2. Add it with `ansible-vault edit group_vars/asterisk/vault.yml`.
3. Re-run the playbook.
4. On the handset, enter the extension number, password and server DNS name, using TLS on port 5061 with SRTP required.

## Connecting phones

Phones connect over the internet using PJSIP over TLS, with SRTP required for call audio. Plain SIP isn't offered, and a phone that can't do SRTP can't make calls.

The VM's Azure security group only allows SSH for now, so phones can't reach Asterisk until these inbound rules exist:

| Protocol | Ports | Purpose |
| --- | --- | --- |
| TCP | 5061 | SIP over TLS |
| UDP | 10000-10199 | SRTP call audio |

The `simple-vm` module defines its rules inline and doesn't output the security group's name, so these rules have to be added through a new release of the module.

Exposed SIP servers get scanned and attacked constantly, so check the setup works and use strong extension passwords before opening these ports.

### fail2ban

fail2ban watches Asterisk's security log and is set up to be aggressive. Three failed logins in a day bans an IP from SIP and call audio for a week, and the ban doubles for repeat offenders, up to a year. SSH isn't affected.

Everyone behind a home's public IP shares a ban, so one phone with a wrong password can cut off that whole home. Double-check passwords when setting up a handset. To check for bans and lift one:

```bash
sudo fail2ban-client status asterisk
sudo fail2ban-client set asterisk unbanip <ip>
```

Asterisk restarts when its certificate renews, about every 60 days, which drops any call in progress.

## Roadmap

### Grandparents

There are two ways to add them, and they can be mixed:

- **Their own handset:** give them a `3XX` extension, set up like any other phone. No dialplan changes needed.
- **SIP trunk:** connect the system to the phone network so grandparents can use their existing phones, limited to approved numbers.

### SIP trunk rules

A trunk connects a children's phone system to the outside world, so the restrictions have to be in place from the start:

- **Outbound:** children can only call numbers on an allow-list. Everything else is rejected.
- **Inbound:** only calls from approved numbers ring through. Everything else is rejected.
- **Separate dialplan contexts:** trunk calls get their own context, so an outside caller can't reach anything else on the system.
- **Spending cap:** use a prepaid or capped trunk account, so a compromised system can't run up a large bill.
- **Caller ID caveat:** caller ID can be spoofed, so the inbound allow-list helps but isn't proof of who's calling.

Other things to consider later:

- Quiet hours, so phones don't ring at bedtime or during school
- Voicemail, or a friendlier message when nobody answers

## Known gaps

- `allow=opus` has no effect yet because `codec_opus` isn't built. Calls will use G.722 for now.
- `allow=alaw` is listed, but `codec_alaw.so` isn't loaded, so alaw can't be transcoded.
- The inbound SIP and audio rules aren't in tofu yet, and the playbook doesn't manage firewall rules.
