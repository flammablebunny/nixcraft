#!/usr/bin/env python3
"""
nixcraft-cli: Command-line launcher for Nixcraft instances

Provides a unified interface to launch Minecraft instances with logging support.
Usage:
    nixcraft <instance-name>    - Launch instance with terminal output
    nixcraft list               - List available instances
    nixcraft logs <instance>    - View logs for an instance
"""

import os
import sys
import subprocess
import datetime
from pathlib import Path

# Directories
DATA_DIR = Path.home() / ".local" / "share" / "nixcraft"
CLIENT_DIR = DATA_DIR / "client" / "instances"
SERVER_DIR = DATA_DIR / "server" / "instances"
LOGS_DIR = DATA_DIR / "logs"


def ensure_dirs():
    """Ensure log directory exists."""
    LOGS_DIR.mkdir(parents=True, exist_ok=True)


def get_instance_bin(instance_name: str) -> Path | None:
    """Find the binary for an instance by searching PATH."""
    # Check common locations
    paths_to_check = [
        Path(f"/etc/profiles/per-user/{os.environ.get('USER', 'root')}/bin/{instance_name}"),
        Path(f"/run/current-system/sw/bin/{instance_name}"),
        Path.home() / ".nix-profile" / "bin" / instance_name,
    ]

    for path in paths_to_check:
        if path.exists():
            return path

    # Try which
    try:
        result = subprocess.run(["which", instance_name], capture_output=True, text=True)
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except Exception:
        pass

    return None


def list_instances():
    """List all available nixcraft instances."""
    print("Available instances:\n")

    # Find client instances
    if CLIENT_DIR.exists():
        print("Client instances:")
        for instance_dir in sorted(CLIENT_DIR.iterdir()):
            if instance_dir.is_dir():
                name = instance_dir.name
                # Check if there's a bin entry
                nixcraft_dir = instance_dir / ".nixcraft"
                status = "ready" if nixcraft_dir.exists() else "not configured"
                print(f"  {name} ({status})")

    # Find server instances
    if SERVER_DIR.exists():
        servers = list(SERVER_DIR.iterdir())
        if servers:
            print("\nServer instances:")
            for instance_dir in sorted(servers):
                if instance_dir.is_dir():
                    name = instance_dir.name
                    print(f"  {name}")

    print("\nUsage: nixcraft <instance-name>")


def view_logs(instance_name: str):
    """View logs for an instance."""
    instance_log_dir = LOGS_DIR / instance_name

    if not instance_log_dir.exists():
        print(f"No logs found for instance '{instance_name}'")
        return

    # Find most recent log
    logs = sorted(instance_log_dir.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)

    if not logs:
        print(f"No log files found for instance '{instance_name}'")
        return

    print(f"Available logs for '{instance_name}':")
    for i, log in enumerate(logs[:10]):  # Show last 10 logs
        mtime = datetime.datetime.fromtimestamp(log.stat().st_mtime)
        size = log.stat().st_size
        print(f"  [{i+1}] {log.name} ({size} bytes, {mtime.strftime('%Y-%m-%d %H:%M:%S')})")

    print(f"\nMost recent log ({logs[0].name}):")
    print("-" * 60)

    # Show last 100 lines of most recent log
    try:
        with open(logs[0], 'r') as f:
            lines = f.readlines()
            for line in lines[-100:]:
                print(line, end='')
    except Exception as e:
        print(f"Error reading log: {e}")


def launch_instance(instance_name: str, extra_args: list):
    """Launch an instance with logging."""
    ensure_dirs()

    # Normalize instance name (try lowercase first, then original)
    bin_path = get_instance_bin(instance_name.lower())
    if not bin_path:
        bin_path = get_instance_bin(instance_name)

    if not bin_path:
        print(f"Error: Instance '{instance_name}' not found.")
        print(f"Tried: {instance_name.lower()}, {instance_name}")
        print("\nAvailable instances:")
        list_instances()
        sys.exit(1)

    # Create log directory for this instance
    instance_log_dir = LOGS_DIR / instance_name.lower()
    instance_log_dir.mkdir(parents=True, exist_ok=True)

    # Create log file with timestamp
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    log_file = instance_log_dir / f"{timestamp}.log"

    print(f"Launching {instance_name}...")
    print(f"Binary: {bin_path}")
    print(f"Log file: {log_file}")
    print("-" * 60)

    # Open log file for writing
    with open(log_file, 'w') as log_f:
        # Write header
        log_f.write(f"=== Nixcraft Instance: {instance_name} ===\n")
        log_f.write(f"Started: {datetime.datetime.now().isoformat()}\n")
        log_f.write(f"Binary: {bin_path}\n")
        log_f.write(f"Arguments: {extra_args}\n")
        log_f.write("=" * 60 + "\n\n")
        log_f.flush()

        try:
            # Launch with output going to both terminal and log file
            process = subprocess.Popen(
                [str(bin_path)] + extra_args,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )

            # Stream output to both terminal and log file
            for line in process.stdout:
                print(line, end='')
                log_f.write(line)
                log_f.flush()

            process.wait()

            # Write footer
            log_f.write(f"\n{'=' * 60}\n")
            log_f.write(f"Exited with code: {process.returncode}\n")
            log_f.write(f"Ended: {datetime.datetime.now().isoformat()}\n")

            print("-" * 60)
            print(f"Instance exited with code: {process.returncode}")
            print(f"Log saved to: {log_file}")

            return process.returncode

        except KeyboardInterrupt:
            print("\nInterrupted by user")
            log_f.write("\n\nInterrupted by user\n")
            process.terminate()
            return 130
        except Exception as e:
            print(f"Error launching instance: {e}")
            log_f.write(f"\nError: {e}\n")
            return 1


def main():
    if len(sys.argv) < 2:
        print("nixcraft - Nixcraft Instance Launcher")
        print("\nUsage:")
        print("  nixcraft <instance>        Launch an instance with logging")
        print("  nixcraft list              List available instances")
        print("  nixcraft logs <instance>   View logs for an instance")
        print("\nExamples:")
        print("  nixcraft ranked            Launch the 'ranked' instance")
        print("  nixcraft rsg               Launch the 'rsg' instance")
        print("  nixcraft logs ranked       View logs for 'ranked'")
        sys.exit(0)

    command = sys.argv[1]

    if command == "list":
        list_instances()
    elif command == "logs":
        if len(sys.argv) < 3:
            print("Usage: nixcraft logs <instance-name>")
            sys.exit(1)
        view_logs(sys.argv[2])
    elif command in ["-h", "--help", "help"]:
        main()  # Show help
    else:
        # Treat as instance name
        extra_args = sys.argv[2:] if len(sys.argv) > 2 else []
        sys.exit(launch_instance(command, extra_args))


if __name__ == "__main__":
    main()
