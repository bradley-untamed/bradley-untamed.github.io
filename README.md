# Project 2: Self-Hosted Uptime Kuma with Docker Compose

**Bradley Titagwan | CYB 3353 | November 22, 2026**

## Introduction

I deployed Uptime Kuma on an Ubuntu server VM in Proxmox to monitor website availability, network connectivity and SSH service availability. I configured persistent storage, secured remote access, enabled automatic updates and tested backup and recovery. This guide reproduces the lab deployment, not a production configuration.

## 1. Environment and baseline snapshot

My VM was Bradley-Ubuntu, running Ubuntu 26.04.1 LTS (resolute), with hostname `ubuntubradley`, user `bradley`, and interface `ens18`. Its lab IP was `10.30.69.10/24`. Substitute your own username and VM IP throughout.

In Proxmox, select the VM, open Snapshots, click Take Snapshot and name it `pre-docker`. My actual snapshot was named `Pre-docker_snapshot`, created at 22:00:42 before installation.


![Baseline Proxmox snapshot.](screenshots/01-snapshot.png)

*Baseline Proxmox snapshot.*


```bash
ssh bradley@10.30.69.10 # Connect from the client
cat /etc/os-release # Identify the distribution
ip -br addr # Identify network addresses
```


![Ubuntu version and network interface.](screenshots/02-environment.png)

*Ubuntu version and network interface.*

## 2. Install Docker Engine and Compose

Use the official Docker repository rather than Ubuntu docker.io or Snap. Run the following on Ubuntu.


```bash
sudo apt update # Refresh package metadata
sudo apt install -y ca-certificates curl # Install prerequisites
sudo install -m 0755 -d /etc/apt/keyrings # Create keyring directory
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc # Download signing key
sudo chmod a+r /etc/apt/keyrings/docker.asc # Make key readable by APT
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update # Load Docker repository metadata
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin # Install Docker
sudo systemctl enable --now docker # Start Docker and enable at boot
systemctl is-enabled docker # Check boot configuration
sudo docker --version # Check engine version
sudo docker compose version # Check Compose version
sudo docker run --rm hello-world # Test container execution
```

The echo command registers the official repository for the installed architecture and Ubuntu codename. Docker 29.10.0 and Compose v5.8.0 were reported, and hello-world ran successfully.


![Successful Docker installation and verification.](screenshots/03-docker.png)

*Successful Docker installation and verification.*

## 3. Deploy Uptime Kuma

The actual project files are in `/home/bradley`, not a separate project subdirectory.


```bash
cd ~ # Enter project directory
mkdir -p data # Create persistent storage
nano compose.yaml # Create Compose configuration
```


```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:2
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - ./data:/app/data
```

The image uses the version 2 tag (the installed version was 2.5.12). The restart policy enables recovery after reboot. Port 3001 is published and the bind mount preserves the SQLite database outside the container. No Dockerfile is required.

Configuration: [compose.yaml](compose.yaml).


```bash
sudo docker compose config # Validate configuration
sudo docker compose up -d # Pull and launch the service
sudo docker compose ps # Check container health
sudo docker compose logs --tail=30 # Inspect startup logs
```


![Startup logs showing database setup waiting for user action.](screenshots/04-logs.png)

*Startup logs showing database setup waiting for user action.*


![Container running and healthy.](screenshots/05-container.png)

*Container running and healthy.*

Open `http://10.30.69.10:3001` from the course network. Select SQLite and create an administrator account. I used the username `bradley`; the password is not included.


![Initial dashboard after account setup.](screenshots/06-dashboard.png)

*Initial dashboard after account setup.*

## 4. Configure monitoring and test reboot persistence

Use Add New Monitor, configure each entry below and save. Use a 60-second heartbeat interval.

| Name | Type | Target |
|---|---|---|
| Google Website | HTTP(s) | https://www.google.com |
| Cloudflare DNS | Ping | 1.1.1.1 |
| Ubuntu SSH Server | TCP Port | 10.30.69.10:22 |

The Cloudflare monitor tests ICMP reachability, not DNS resolution itself.


![Dashboard showing the signed-in username and monitors.](screenshots/07-account.png)

*Dashboard showing the signed-in username and monitors.*


```bash
sudo reboot # Restart the VM
```


```bash
ssh bradley@10.30.69.10 # Reconnect from the client
uptime # Confirm recent reboot
systemctl is-active docker # Check Docker service
sudo docker ps # Check container health
```


![Docker active and container healthy after reboot.](screenshots/08-reboot.png)

*Docker active and container healthy after reboot.*


![All three monitors retained after reboot.](screenshots/09-persistence.png)

*All three monitors retained after reboot.*

## 5. Secure the VM

### SSH key-only authentication

From Windows PowerShell, generate a key if one does not already exist, then transfer only the public key.


```powershell
ssh-keygen -t ed25519 # Generate an SSH key pair
Get-Content ~/.ssh/id_ed25519.pub | ssh bradley@10.30.69.10 "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"
ssh -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no bradley@10.30.69.10 # Test key login
```

The Get-Content pipeline appends the public key to authorized_keys. Keep the existing session open and verify key login in another terminal before disabling passwords.


```bash
sudo nano /etc/ssh/sshd_config.d/00-key-only.conf # Create SSH configuration drop-in
```


```text
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
```


```bash
sudo sshd -t # Validate syntax
sudo sshd -T | grep -E 'pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication' # Verify effective settings
sudo systemctl restart ssh # Apply settings
```


```powershell
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password bradley@10.30.69.10 # Test password rejection
```


![SSH key generation, public key transfer and refused password login.](screenshots/10-ssh.png)

*SSH key generation, public key transfer and refused password login.*

The password-only attempt returned `Permission denied (publickey)`. The effective settings were public key authentication yes, password authentication no, and keyboard-interactive authentication no. [SSH configuration](00-key-only.conf). A separate successful key-only login screenshot was not captured.

### Firewall


```bash
sudo apt install -y ufw # Install firewall
sudo ufw default deny incoming # Deny unsolicited inbound traffic
sudo ufw default allow outgoing # Allow outbound traffic
sudo ufw allow 22/tcp # Permit SSH
sudo ufw allow 3001/tcp # Permit application port
sudo ufw enable # Activate firewall
sudo ufw status verbose # Verify rules
```


![Active firewall allowing SSH and application traffic.](screenshots/11-firewall.png)

*Active firewall allowing SSH and application traffic.*

Docker-published ports may bypass UFW filtering. Only the application port is published in this lab. For production, restrict access with appropriate Docker-aware or upstream firewall rules, HTTPS and access controls.

### Automatic security updates


```bash
sudo apt install -y unattended-upgrades # Install update service
sudo dpkg-reconfigure -plow unattended-upgrades # Enable automatic updates (select Yes)
cat /etc/apt/apt.conf.d/20auto-upgrades # Inspect configuration
systemctl list-timers apt-daily.timer apt-daily-upgrade.timer # Verify scheduled timers
```


```text
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```


![Scheduled APT update timers.](screenshots/12-timers.png)

*Scheduled APT update timers.*


![Effective SSH settings and automatic update configuration; an accidental duplicate cat argument also produced a harmless error.](screenshots/13-security-settings.png)

*Effective SSH settings and automatic update configuration; an accidental duplicate cat argument also produced a harmless error.*

Configuration file: [20auto-upgrades](20auto-upgrades). These timers cover configured OS package updates, not automatic Docker image updates.

## 6. Application backup

The backup script stops Uptime Kuma before archiving its data to ensure SQLite consistency, restarts it, and retains the seven newest archives. It is intended to run as the regular project user with sudo access.


```bash
pwd # Confirm project directory
ls -l ~/compose.yaml # Locate Compose file
sudo docker inspect uptime-kuma --format '{{range .Mounts}}{{println .Source .Destination}}{{end}}' # Confirm bind mount
mkdir -p ~/backups # Create archive directory
chmod 700 ~/backups # Restrict access
nano ~/backup-kuma.sh # Create backup script
```


![Actual Compose file location in the home directory.](screenshots/14-project-path.png)

*Actual Compose file location in the home directory.*


```bash
#!/bin/bash
set -euo pipefail
umask 077
PROJECT_DIR="$HOME"
BACKUP_DIR="$HOME/backups"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
ARCHIVE="$BACKUP_DIR/uptime-kuma-$TIMESTAMP.tar.gz"
mkdir -p "$BACKUP_DIR"
cd "$PROJECT_DIR"
trap 'sudo docker compose start' EXIT
sudo docker compose stop
sudo tar -czf "$ARCHIVE.tmp" -C "$PROJECT_DIR" data
sudo mv "$ARCHIVE.tmp" "$ARCHIVE"
sudo docker compose start
trap - EXIT
ls -1t "$BACKUP_DIR"/uptime-kuma-*.tar.gz |
    tail -n +8 |
    while IFS= read -r file; do
        sudo rm -- "$file"
    done
echo "Backup completed: $ARCHIVE"
```

The trap restarts the service on failure; tar creates a compressed archive, mv finalizes it, and the ls/tail loop removes older archives beyond seven. [Download backup script](backup-kuma.sh).


```bash
chmod +x ~/backup-kuma.sh # Make script executable
~/backup-kuma.sh # Create first archive
sleep 2 # Ensure distinct timestamps
~/backup-kuma.sh # Create second archive
ls -lh ~/backups # List archives
sudo docker compose ps # Verify service restarted
```


![Two 35 KB archives and a healthy container.](screenshots/15-backups.png)

*Two 35 KB archives and a healthy container.*

Two archives were created successfully. Seven-archive retention is implemented in the script but was not tested with eight archives.

## 7. Full Proxmox VM backup

Select the VM, open Backup, click Backup now, choose available backup storage and Snapshot mode, then start the job. My backup completed in 48 seconds for a 32 GiB virtual disk. The log reported 3.59 GB and the UI listed 3.85 GB (different display units). The task ended with TASK OK.


![Successful Proxmox backup task.](screenshots/16-vm-backup-log.png)

*Successful Proxmox backup task.*


![VM backup listed in Proxmox storage.](screenshots/17-vm-backup-list.png)

*VM backup listed in Proxmox storage.*

## 8. Restore drill

First verify the newest archive before removing any data.


```bash
LATEST=$(ls -t ~/backups/uptime-kuma-*.tar.gz | head -n 1) # Select newest archive
echo "$LATEST" # Display selected archive
sudo gzip -t "$LATEST" && echo "Archive integrity verified" # Verify compression integrity
sudo tar -tzf "$LATEST" # List archived files
```


![Verified archive containing kuma.db and db-config.json.](screenshots/18-integrity.png)

*Verified archive containing kuma.db and db-config.json.*


![Dashboard before removal, with three monitors.](screenshots/19-before.png)

*Dashboard before removal, with three monitors.*

For safety I moved the original data out of the active bind mount instead of permanently deleting it. Only proceed if the archive is verified and the mount source is exactly the expected data directory. Ensure data-before-restore does not already exist.


```bash
cd ~ # Enter project directory
sudo docker compose stop # Stop database writes
sudo docker inspect uptime-kuma --format '{{range .Mounts}}{{println .Source .Destination}}{{end}}' # Verify mount
sudo mv /home/bradley/data /home/bradley/data-before-restore # Preserve original outside active mount
mkdir ~/data # Create empty active directory
sudo docker compose up -d # Start with empty data
```


![Original data moved away and container started with an empty directory.](screenshots/20-removal.png)

*Original data moved away and container started with an empty directory.*

The duplicate mkdir command reported File exists because the directory was already created. No separate browser screenshot of the empty setup screen was captured. Next, stop the test instance and restore from the verified archive. Run in the same shell so LATEST remains defined.


```bash
sudo docker compose stop # Stop test instance
sudo rm -rf /home/bradley/data # Delete only temporary test data
sudo tar -xzf "$LATEST" -C /home/bradley # Restore original data from archive
sudo docker compose up -d # Restart application
sudo docker compose ps # Check health
```


![Archive extraction and healthy restored container.](screenshots/21-restore.png)

*Archive extraction and healthy restored container.*


![Restored dashboard showing all three original monitors.](screenshots/22-after.png)

*Restored dashboard showing all three original monitors.*

The original dashboard returned with all three monitors reporting up. The original data was preserved separately during the drill; its later removal was not documented. The restored dashboard screenshot does not show the profile dropdown, but the earlier account screenshot identifies the user.

## 9. Conclusion

This project demonstrated container deployment, persistent storage, service monitoring, SSH hardening, firewall configuration, automatic updates and recovery from an application-level backup. The VM also has a baseline snapshot and full Proxmox backup. The application survived a reboot and the three monitors returned after restoring the SQLite data.

## References

- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [Uptime Kuma official repository](https://github.com/louislam/uptime-kuma)
- [Docker packet filtering and firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
- [Ubuntu OpenSSH server](https://documentation.ubuntu.com/server/how-to/security/openssh-server/)
- [Ubuntu automatic updates](https://documentation.ubuntu.com/server/how-to/software/automatic-updates/)
- [Proxmox backup and restore](https://pve.proxmox.com/pve-docs/chapter-vzdump.html)
- CYB 3353 Project 2 Kickoff slides, Fall 2026.
