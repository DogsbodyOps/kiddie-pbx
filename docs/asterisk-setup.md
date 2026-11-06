# Asterisk setup on tiny01 (reverse-engineered)

Rebuilt on 2026-11-06 from the home server `tiny01`, using shell history, the build tree in
`~/asterisk-22.11.0`, and the installed files. The original work was done on 2026-09-05.
No sudo was used, so the journal, dnf history and audit log were not read.

## Deploying with Ansible

The playbook is `ansible/deploy-asterisk.yml`. Run these from `ansible/`:

```bash
cp inventory.example.ini inventory.ini        # then set the host and user
cp vault.example.yml group_vars/asterisk/vault.yml   # then set names and passwords
ansible-vault encrypt group_vars/asterisk/vault.yml
ansible-playbook deploy-asterisk.yml --ask-vault-pass --ask-become-pass
```

`inventory.ini` and `vault.yml` are gitignored because this repo is public, so keep your own
copies. SIP passwords were deliberately not copied from the server. To keep the phones working,
reuse the current ones from `/etc/asterisk/pjsip.conf`. If you set new ones, update each phone.

`ansible/files/asterisk/` holds copies of the server's config files. `pjsip.conf` is
`ansible/templates/pjsip.conf.j2`, with names and passwords replaced by vault variables.
The `.bak` files on the server were not copied.

### How the playbook differs from the original install

| Change | Why |
| --- | --- |
| `RuntimeDirectory=asterisk` is on in the unit | `/var/run/asterisk` is lost at reboot otherwise |
| Enables the service | It is disabled on the server |
| `/etc/asterisk` is 0750 and its files 0640 | SIP passwords were world-readable |
| Ownership is set recursively | The original `chown` only covered top-level directories |
| Logrotate creates files as `asterisk` | Rotated `queue_log` was owned by root |
| `asterisk` is a system user with no login shell | It was a normal user with bash |
| Pins 22.11.0 by checksum | `asterisk-22-current` changes over time. The checksum matches the server's tarball |
| Builds as root in `/usr/local/src` | It was built as a normal user in `~` |
| Skips `make samples`, `make basic-pbx` and `make config` | Config comes from this repo, and the unit does not use the init script |

The playbook keeps these as they are on the server, so they still need a decision: `allow=opus`
with no `codec_opus`, and `allow=alaw` with no `codec_alaw.so` loaded.

It does not open any firewall ports. The Azure VM's security group in Terraform only allows SSH,
so phones cannot reach it until SIP and RTP rules are added. `pjsip.conf` is written on the
assumption that it is not exposed to the internet, so plan for that before opening ports.

## What is installed

| Item | Value |
| --- | --- |
| OS | RHEL 9.8, gcc 11.5.0 |
| Asterisk | 22.11.0, built from source (no RPM) |
| Source | `asterisk-22-current.tar.gz`, unpacked in `~` |
| Configure flags | `--with-jansson-bundled` (only flag) |
| Bundled libraries | jansson, pjproject |
| Prefix | default: `/usr/sbin`, `/usr/lib/asterisk`, `/var/lib/asterisk` |
| Config base | `make basic-pbx`, not `make samples` |
| Run as | `asterisk:asterisk` (uid/gid 1001) |
| SIP | PJSIP, UDP 5060 on all interfaces |

### menuselect changes from defaults

- **Turned on:** `MOH-OPSOUND-G722`, `EXTRA-SOUNDS-EN-G722`
- **Turned off:** `app_followme`
- **Left at default:** `CORE-SOUNDS-EN-GSM`, `MOH-OPSOUND-WAV`, `BUILD_NATIVE`, `OPTIONAL_API`
- **Not built:** `codec_opus` (off by default), `res_srtp` (`HAVE_SRTP` undefined), and systemd
  notify support (`HAVE_SYSTEMD` undefined, no `systemd-devel`)

### Edits to files

- `/etc/asterisk/asterisk.conf`: uncommented `runuser = asterisk` and `rungroup = asterisk`.
- `/etc/asterisk/pjsip.conf`: hand-written, see below. Earlier version is `pjsip.conf.bak`.
- `/etc/asterisk/extensions.conf`: hand-written, see below. Earlier version is `extensions.conf.bak`.
- All other `/etc/asterisk` files are byte-identical to `configs/basic-pbx`.
- `/etc/systemd/system/asterisk.service`: copy of `contrib/systemd/asterisk.service` with two changes:
  - `Type=notify` changed to `Type=simple`, because this build has no systemd notify support
  - `StandardError=journal` added after `StandardOutput=null`

### PJSIP and dialplan

- `pjsip.conf` has templates `endpoint-internal`, `auth-internal` and `aor-internal`.
- Endpoint settings: context `internal`, codecs opus, g722 and alaw, `dtmf_mode=rfc4733`,
  `direct_media=no`, plus `rtp_symmetric`, `force_rport` and `rewrite_contact`.
- AOR settings: `max_contacts=1`, `remove_existing=yes`, `qualify_frequency=60`.
- Extensions: 101 and 102 (children), 201 (parent).
- `extensions.conf` `[internal]`: `_XXX` sets an `Alert-Info` header from the caller's first digit
  (1 sibling, 2 parent, 3 grandparent, otherwise default), then runs `Dial(PJSIP/${EXTEN},20)`.
  Busy and no-answer are handled.
- Extension 900 plays `hello-world`.

## What was done, in order

Trial and error removed. Times are file modification times from 2026-09-05.

```bash
sudo dnf update -y
sudo dnf install asterisk          # no asterisk RPM is installed, so this did not stick
wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-22-current.tar.gz
tar -xvf asterisk-22-current.tar.gz
cd asterisk-22.11.0/
sudo dnf install cmake gcc         # cmake was not needed for the final build
sudo ./contrib/scripts/install_prereq install
./configure --with-jansson-bundled # 09:43
make menuselect                    # 09:50
make
sudo make install                  # 10:15
sudo make samples                  # later wiped
sudo make config                   # init script and /etc/sysconfig/asterisk
sudo make basic-pbx
sudo rm -rf /etc/asterisk/*        # wiped samples, then reinstalled
sudo make install
sudo make basic-pbx

sudo adduser asterisk
sudo chown asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/spool/asterisk \
  /var/log/asterisk /var/run/asterisk   # not recursive
sudo chown asterisk:asterisk /etc/asterisk/*.conf

sudo nano /etc/asterisk/asterisk.conf   # runuser and rungroup
sudo nano /etc/systemd/system/asterisk.service   # from contrib/systemd/asterisk.service
sudo make install-logrotate             # 10:33
sudo setenforce 0                       # temporary, lost at reboot
sudo sed -i 's/^Type=notify/Type=simple/' /etc/systemd/system/asterisk.service
sudo sed -i '/^StandardOutput=null/a StandardError=journal' /etc/systemd/system/asterisk.service
sudo systemctl daemon-reload
sudo systemctl restart asterisk
```

`make progdocs`, `dnf install doxygen` and `systemctl disable firewalld` also appear in the history.
The first two are not needed for the build. firewalld is currently disabled.

## Clean rebuild (not yet tested)

This is the history above in a tidier order. `asterisk-22-current` will download a newer release
than 22.11.0, so keep the existing tarball if you need the exact version.

```bash
sudo dnf update -y
sudo dnf install -y gcc wget
wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-22-current.tar.gz
tar -xf asterisk-22-current.tar.gz
cd asterisk-22.*/
sudo ./contrib/scripts/install_prereq install
./configure --with-jansson-bundled
make menuselect.makeopts
menuselect/menuselect --disable app_followme \
  --enable MOH-OPSOUND-G722 --enable EXTRA-SOUNDS-EN-G722 menuselect.makeopts
make
sudo make install
sudo make basic-pbx
sudo make config
sudo make install-logrotate
sudo useradd asterisk
```

Then restore `asterisk.conf`, `pjsip.conf`, `extensions.conf` and the unit file, and fix ownership.

## Problems found on the box

Nothing has been changed. Asterisk is currently stopped and disabled, and nothing is listening on 5060.

| Problem | Evidence | Status |
| --- | --- | --- |
| `/var/run/asterisk` is gone after reboot | Directory is absent; `RuntimeDirectory=asterisk` is commented out in the unit | Confirmed. Effect on startup is inferred |
| SELinux is enforcing again | `setenforce 0` was temporary; `/etc/selinux/config` says enforcing; `/etc/asterisk`, `/var/lib/asterisk` and `/var/log/asterisk` have generic labels | Confirmed. That it blocks Asterisk is inferred, audit log not read |
| Service is disabled | History shows `systemctl enable asterisk`, but the unit is now `disabled` | Confirmed. Cause unknown |
| `allow=opus` does nothing | `codec_opus` was not built | Confirmed |
| alaw cannot be transcoded | `codec_alaw.so` is missing from `modules.conf`, which has `autoload = no` | Confirmed |
| `queue_log` is owned by root | Logrotate uses `create 640 root root`; the current file is `root:root` | Confirmed. Asterisk runs as `asterisk` |
| SIP passwords are world-readable | `pjsip.conf` is mode 644 | Confirmed |
| No encrypted media | `res_srtp` was not built, and transport is UDP only | Confirmed |

### Likely fixes (not tested)

```bash
# In the unit, uncomment: RuntimeDirectory=asterisk
sudo systemctl daemon-reload
sudo restorecon -Rv /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk /usr/lib/asterisk
sudo systemctl enable --now asterisk
sudo chmod 640 /etc/asterisk/pjsip.conf
sudo sed -i 's/create 640 root root/create 640 asterisk asterisk/' /etc/logrotate.d/asterisk
```

If SELinux still blocks it, check `sudo ausearch -m avc -ts recent`. Add `load = codec_alaw.so` to
`modules.conf` if any phone uses alaw. For opus, enable `codec_opus` in menuselect and rebuild.
