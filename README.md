# shadowrealm — Paper server tools

Scripts for a Paper Minecraft server set up with the [linuxvox guide](https://linuxvox.com/blog/minecraft-server-install-ubuntu/): server in `/home/minecraft/minecraft_server`, user `minecraft`, `minecraft.service`, console in the `mcjava` screen session.

Run every script as yourself with `sudo` (not as `minecraft`, which has no sudo rights).

## Backing up

```bash
sudo ./scripts/backup.sh
```

Takes about 3 minutes. Steps:

1. **Pause autosave:** `save-off` + `save-all flush` through the console, so files don't change mid-copy. Skipped if the server is stopped.
2. **Archive:** writes `/home/minecraft/backups/shadowrealm-YYYY-MM-DD-HHMM.tar.gz` (about 260 MB). Skips `cache/`, `libraries/` and `versions/` (Paper re-downloads them) and `paper-server.jar.old`.
3. **Resume autosave:** `save-on`.
4. **Check:** the archive is readable and contains `shadowrealm/level.dat`.
5. **Upload:** to `Shadowrealm Backups` on Proton Drive.
6. **Clean up locally:** deletes local backups beyond the newest 5 (`KEEP_LOCAL`).
7. **Clean up on Proton:** permanently deletes Proton Drive backups beyond the newest 7 (`KEEP_REMOTE`). Only files named `shadowrealm-*.tar.gz` are touched. Proton only deletes from the trash, so each old file is trashed and then deleted from `/trash`.

**Check what's inside a backup:** `sudo tar -tzf /home/minecraft/backups/<file>.tar.gz | less`

## Updating Paper + plugins

1. **Plugins (optional):** put new plugin jars in `plugins/update/` with the **same filename** as the old jar in `plugins/`:
   ```bash
   sudo -u minecraft mkdir -p /home/minecraft/minecraft_server/plugins/update
   sudo -u minecraft curl -L -o /home/minecraft/minecraft_server/plugins/update/Geyser-Spigot.jar \
     https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
   ```
2. **Paper:** pass your Minecraft version:
   ```bash
   sudo ./scripts/update-paper.sh 26.2
   ```
   The script finds the newest **stable** build and downloads it, checking its checksum. It then **runs `backup.sh` and stops if the backup fails**. Finally it stops the server, swaps the jar (the old one is kept as `paper-server.jar.old`) and starts the server again. On startup, Paper swaps in the jars from `plugins/update/`.

   If Paper is already up to date and you only updated plugins, back up and restart instead:
   ```bash
   sudo ./scripts/backup.sh && sudo systemctl restart minecraft.service
   ```

**Check it worked:** `sudo tail -f /home/minecraft/minecraft_server/logs/latest.log`. Look for `Loading server plugin <name> v<version>` and `Done (`.

**Roll back Paper:** `sudo systemctl stop minecraft.service`, rename `paper-server.jar.old` back to `paper-server.jar`, then `sudo systemctl start minecraft.service`.

**New Minecraft version** (e.g. 26.2 → 26.3): first check that your plugins support it. A world can't be downgraded after it's been opened on a newer version. Then run `sudo ./scripts/update-paper.sh 26.3`. Afterwards you can delete the old version's folder in `versions/`.

## One-time setup

**Tools:**
```bash
sudo apt install curl jq pass gnupg
```

**Proton Drive CLI:** install it, then log in **as root**. Root is used so that the game server, which runs as `minecraft`, can't reach your Proton login.

1. Download it and check it. Compare the checksum with the linux/x64 SHA-512 on <https://proton.me/download/drive/cli/index.html>:
   ```bash
   curl -fLo /tmp/proton-drive https://proton.me/download/drive/cli/0.9.0/linux-x64/proton-drive
   sha512sum /tmp/proton-drive
   sudo install -m 755 /tmp/proton-drive /usr/local/bin/proton-drive
   ```
2. Switch to root with `sudo -i`. The prompt changes to `root@…#`.
3. Create a key and a password store for the login. The key has no passphrase, so scripts can use it unattended.
   ```bash
   gpg --batch --passphrase '' --quick-gen-key "root-proton" default default never
   pass init root-proton
   ```
4. Log in by opening the printed link on your phone or laptop. Then check it worked:
   ```bash
   PROTON_DRIVE_CREDENTIALS_STORE=pass proton-drive auth login
   PROTON_DRIVE_CREDENTIALS_STORE=pass proton-drive filesystem list /my-files
   ```
5. Type `exit` to leave root.

## Not simplified yet

- `scripts/restore.sh`, `scripts/lib.sh`, `config.env`: restoring a backup.
- `docker-compose.yml` + `.env`: running the server in Docker from a backup.

## Links

[Paper: updating](https://docs.papermc.io/paper/updating/) · [Paper downloads](https://papermc.io/downloads/paper) · [Geyser on Hangar](https://hangar.papermc.io/GeyserMC/Geyser) · [Proton Drive CLI](https://proton.me/support/drive-cli)
