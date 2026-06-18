# Shell Commands

The MicroShell virtual filesystem is accessible via SSH or the browser terminal.

## Commands

| Command | Description |
|---------|-------------|
| `help` | List all commands |
| `ls` | List directory contents |
| `cd <path>` | Change directory |
| `cat <file>` | Read file contents |
| `echo <text> > <file>` | Write to file |
| `reboot` | Reboot the device |
| `reset` | Reset shell state |
| `exit` | Close SSH session |
| `wifi-set <ssid> <password>` | Save WiFi credentials to NVS |
| `wifi-connect` | Connect to saved WiFi network |
| `ssh-exec <host> <user> <pass> <cmd>` | Execute command on remote host |
| `scp-get <host> <user> <pass> <remote> <local>` | Download file from remote host |
| `scp-put <host> <user> <pass> <local> <remote>` | Upload file to remote host |
| `ota <host> <user> <pass> <firmware-path>` | OTA firmware update via SCP |

## Virtual Filesystem

```
/
  bin/                  Commands (reboot, wifi-set, etc.)
  dev/
    null                Discard sink
    random              Hardware RNG (esp_random)
    uptime              System uptime
    heap                Heap memory usage
    time                Local time (NTP-synced)
    led                 Neopixel control (write: off/red/green/blue/yellow/magenta/cyan/white)
    bus/
      i2c0              I2C bus 0 scan
      i2c1              I2C bus 1 scan
      mux               TCA9548A mux scan (all channels)
    sensors/
      i2c_scan          Full I2C device scan
      rtc               DS3231 time + oscillator status
      temperature       DS3231 temperature
    sd/
      info              SD card mount info
    ssh/
      fingerprint       SSH host key fingerprint
    mem/                Memory info
  etc/
    hostname            Read/write hostname
    config              CPU, flash, SDK info
    wifi                Read/write WiFi credentials (ssid:password)
    user                Current SSH user
```

## Examples

```bash
cat /dev/heap           # Show heap memory
cat /dev/time           # Show current time
echo red > /dev/led     # Set neopixel to red
cat /dev/bus/mux        # Scan all mux channels
cat /etc/hostname       # Read hostname
echo ceratina > /etc/hostname  # Set hostname
```
