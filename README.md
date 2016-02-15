# VMware VM backup script -- backs up VMware Workstation VMs to FTP

This script scans your VMware Shared VMs folder and looks if there is a `vmbackup.conf` file in each VM folder. If it finds one, it assumes the machine has to be backed up to an external FTP according to the parameters defined in that file. 

This script is designed to be run once a day as root, via a crontab. The backup frequency can be defined in days in each VM's `vmbackup.conf` file.

To back up a machine, if it is running, the script stops it gracefully, copies it to a staging temporary folder and then restarts it again. Then it compresses the files and uploads them to the specified FTP space.

## How to install

0. Create a local user with the minimal privileges to start and stop VMs. See the next section for details.
1. Copy `vmbackup.sh` to `/usr/local/bin` and make it executable `chmod +x /usr/local/bin/vmbackup.sh` 
2. Create your global `/etc/vmbackup.conf` starting off the included `vmbackup.conf.global` file.
3. For each VM you want to back up, add a `vmbackup.conf` file in each VM folder under the Shared VMs folder. For example if you want to back up the 'gandalf' vm in `/var/lib/vmware/Shared VMs`, create a `vmbackup.conf` in `/var/lib/vmware/Shared VMs/gandalf` starting off the provided `vmbackup.conf`
4. Add the script to crontab. For example, this line runs the backup every day at 4am:

```
0 4 * * * vmbackup.sh
```
Although the script runs every day, it will check each VM's schedule to see if it has to actually execute the backup that day or not.

Trick: You can override gobal variables in each VM's backup configuration file, for example to back up a specific machine to a different FTP host.

## Creating a VMware user with the minimal permissions to just be able to start and stop VMs.

The script requires a local user that has privileges to stop and start the VMs to be backed up, and the password of this user needs to be in the `/etc/vmbackup.conf` file, so you can't use root for that!

1. Create a new UNIX user, e.g., `vmbackup`:

  * `adduser vmbackup`. Add a complex password but not too long, I have found out that very long passwords didn't work with `vmrun`. Remember this password for later.

2. Remove shell privileges for the new user:

  * `usermod -s /sbin/nologin vmbackup`

3. In the VMWare GUI, right click on "Shared VMs" and then "Roles...". Add a new role with name `vmbackupRole`

4. In the privileges tree on the right, uncheck everything and then check only the following:

  1. `[X] System` and descendants (`[X] Anonymous`, `[X] Read` and `[X] View`)

  2. Under Virtual Machine/Interaction:

    * `[X] Guest operating system management by VIX API`

    * `[X] Power off`

    * `[X] Power on`

    * `[X] Reset`

    * `[X] Suspend`

  3. Click OK.

5. Right click again on "Shared VMs" and then "Permissions...". Add the `vmbackup` user and assign it the `vmbackupRole` role on the right pane. Then click OK.


## License

Released under GPL!. Contributions welcome!

