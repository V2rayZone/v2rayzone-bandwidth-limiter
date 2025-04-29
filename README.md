# V2RayZone Bandwidth Limiter

A script to limit bandwidth on Ubuntu VPS systems (version 20.04 and above) based on total bandwidth allocation and usage period.

## Features

- Automatically calculates recommended bandwidth limits based on total TB allocation and days running
- Interactive menu interface for easy management
- Systemd service for persistent bandwidth limiting
- Configurable speed limits with user confirmation
- Detailed logging of all operations
- Easy one-command installation
- Command shortcut (`v2bwl`) for quick access to the bandwidth limiter menu

## Requirements

- Ubuntu 20.04 or higher
- Root privileges
- Basic networking knowledge

## Installation

Install the V2RayZone Bandwidth Limiter with a single command:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/V2RayZone/v2rayzone-bandwidth-limiter/main/v2rayzone-bandwidth-limiter.sh)
```

After running the command, the script will guide you through the configuration process:

1. Enter the total TB allocation for your VPS
2. Specify how many days the VPS has been running
3. The script will calculate a recommended speed limit
4. Choose to accept the recommended limit or set your own

## Usage

After installation, the script provides an interactive menu with the following options:

- **Install**: Install the bandwidth limiter and configure it
- **Uninstall**: Remove the bandwidth limiter completely
- **View Current Settings**: Display the current bandwidth configuration
- **Start/Stop/Restart**: Control the bandwidth limiting service
- **Check Status**: View the current status of the bandwidth limiter
- **Logs Management**: View the logs of the bandwidth limiter
- **Enable/Disable Autostart**: Control whether the limiter starts automatically on boot

## How It Works

The script uses Linux Traffic Control (tc) to limit the bandwidth on your server's network interface. It calculates the appropriate speed limit based on:

1. The total bandwidth allocation (in TB)
2. How many days the VPS has been running
3. How many days remain in the month

This ensures you don't exceed your monthly bandwidth allocation while still maximizing available speed.

## Troubleshooting

If you encounter any issues:

1. Check the logs with option 15 from the main menu
2. Ensure your Ubuntu version is 20.04 or higher
3. Verify you have root privileges
4. Make sure the network interface was correctly detected

## License

This project is owned and maintained by V2RayZone.

## Disclaimer

This tool is provided as-is without any warranties. Always ensure you have proper authorization to modify network settings on any server you manage.
