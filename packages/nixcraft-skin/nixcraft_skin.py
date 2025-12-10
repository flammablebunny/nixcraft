#!/usr/bin/env python3
"""
nixcraft-skin: Skin and cape management for Nixcraft

This tool helps manage Minecraft skins and capes:
- Download skins from NameMC by username
- Download capes owned by a user
- Apply skins to your Minecraft account (requires auth)
- List available skins and capes
"""

import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import urljoin
import requests
import click

# Directories
DATA_DIR = Path.home() / ".local" / "share" / "nixcraft"
SKINS_DIR = DATA_DIR / "skins"
CAPES_DIR = SKINS_DIR / "capes"
AUTH_DIR = DATA_DIR / "auth"

# API endpoints
MOJANG_API = "https://api.mojang.com"
MC_SERVICES_API = "https://api.minecraftservices.com"
NAMEMC_SKIN_URL = "https://namemc.com/profile/{username}"
CRAFATAR_API = "https://crafatar.com"


def ensure_dirs():
    """Ensure all required directories exist."""
    SKINS_DIR.mkdir(parents=True, exist_ok=True)
    CAPES_DIR.mkdir(parents=True, exist_ok=True)


def get_uuid_from_username(username: str) -> str | None:
    """Get UUID from Minecraft username via Mojang API."""
    try:
        response = requests.get(f"{MOJANG_API}/users/profiles/minecraft/{username}")
        if response.status_code == 200:
            return response.json()["id"]
        return None
    except Exception:
        return None


def get_profile_from_uuid(uuid: str) -> dict | None:
    """Get full profile (including skin/cape) from UUID."""
    try:
        import base64
        response = requests.get(f"https://sessionserver.mojang.com/session/minecraft/profile/{uuid}")
        if response.status_code == 200:
            data = response.json()
            for prop in data.get("properties", []):
                if prop["name"] == "textures":
                    textures_json = base64.b64decode(prop["value"]).decode("utf-8")
                    return json.loads(textures_json)
        return None
    except Exception:
        return None


def download_skin_from_uuid(uuid: str, output_path: Path) -> bool:
    """Download skin image using Crafatar API."""
    try:
        # Get the raw skin (not rendered)
        url = f"{CRAFATAR_API}/skins/{uuid}"
        response = requests.get(url)
        if response.status_code == 200:
            with open(output_path, "wb") as f:
                f.write(response.content)
            return True
        return False
    except Exception:
        return False


def download_cape_from_uuid(uuid: str, output_path: Path) -> bool:
    """Download cape image using Crafatar API."""
    try:
        url = f"{CRAFATAR_API}/capes/{uuid}"
        response = requests.get(url)
        if response.status_code == 200:
            with open(output_path, "wb") as f:
                f.write(response.content)
            return True
        return False
    except Exception:
        return False


def get_skin_variant(uuid: str) -> str:
    """Determine if skin uses slim or classic model."""
    profile = get_profile_from_uuid(uuid)
    if profile:
        textures = profile.get("textures", {})
        skin_data = textures.get("SKIN", {})
        metadata = skin_data.get("metadata", {})
        if metadata.get("model") == "slim":
            return "slim"
    return "classic"


def load_access_token() -> str | None:
    """Load Minecraft access token from auth directory."""
    token_path = AUTH_DIR / "access_token"
    if token_path.exists():
        with open(token_path) as f:
            return f.read().strip()
    return None


def upload_skin(skin_path: Path, variant: str = "classic") -> bool:
    """Upload a skin to the authenticated Minecraft account."""
    token = load_access_token()
    if not token:
        click.echo("Error: Not authenticated. Run 'nixcraft-auth login' first.", err=True)
        return False

    try:
        headers = {
            "Authorization": f"Bearer {token}",
        }

        with open(skin_path, "rb") as f:
            files = {
                "file": (skin_path.name, f, "image/png"),
            }
            data = {
                "variant": variant,
            }

            response = requests.post(
                f"{MC_SERVICES_API}/minecraft/profile/skins",
                headers=headers,
                files=files,
                data=data,
            )

            if response.status_code in [200, 204]:
                return True
            else:
                click.echo(f"Upload failed: {response.status_code} - {response.text}", err=True)
                return False
    except Exception as e:
        click.echo(f"Error uploading skin: {e}", err=True)
        return False


def get_owned_capes(token: str) -> list:
    """Get list of capes owned by the authenticated user."""
    try:
        headers = {"Authorization": f"Bearer {token}"}
        response = requests.get(f"{MC_SERVICES_API}/minecraft/profile", headers=headers)
        if response.status_code == 200:
            profile = response.json()
            return profile.get("capes", [])
        return []
    except Exception:
        return []


def set_active_cape(cape_id: str) -> bool:
    """Set the active cape for the authenticated user."""
    token = load_access_token()
    if not token:
        click.echo("Error: Not authenticated. Run 'nixcraft-auth login' first.", err=True)
        return False

    try:
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

        # To hide cape, use DELETE; to show cape, use PUT
        if cape_id.lower() == "none":
            response = requests.delete(
                f"{MC_SERVICES_API}/minecraft/profile/capes/active",
                headers=headers,
            )
        else:
            response = requests.put(
                f"{MC_SERVICES_API}/minecraft/profile/capes/active",
                headers=headers,
                json={"capeId": cape_id},
            )

        return response.status_code in [200, 204]
    except Exception as e:
        click.echo(f"Error setting cape: {e}", err=True)
        return False


def resolve_skin_path(path_str: str) -> Path | None:
    """Resolve skin path - check if it's in skins dir or absolute."""
    # Check if it's an absolute path
    path = Path(path_str)
    if path.is_absolute() and path.exists():
        return path

    # Check in skins directory
    skins_path = SKINS_DIR / path_str
    if skins_path.exists():
        return skins_path

    # Check with .png extension
    if not path_str.endswith(".png"):
        skins_path = SKINS_DIR / f"{path_str}.png"
        if skins_path.exists():
            return skins_path

    return None


def resolve_cape_path(path_str: str) -> Path | None:
    """Resolve cape path - check if it's in capes dir or absolute."""
    path = Path(path_str)
    if path.is_absolute() and path.exists():
        return path

    capes_path = CAPES_DIR / path_str
    if capes_path.exists():
        return capes_path

    if not path_str.endswith(".png"):
        capes_path = CAPES_DIR / f"{path_str}.png"
        if capes_path.exists():
            return capes_path

    return None


@click.group()
def cli():
    """Nixcraft Skin and Cape Manager"""
    ensure_dirs()


@cli.command()
@click.argument("username")
@click.option("--output", "-o", default=None, help="Output filename (default: username.png)")
def fetch(username: str, output: str | None):
    """Fetch a player's current skin from NameMC/Mojang."""
    click.echo(f"Looking up {username}...")

    uuid = get_uuid_from_username(username)
    if not uuid:
        click.echo(f"Error: Could not find player '{username}'", err=True)
        sys.exit(1)

    click.echo(f"Found UUID: {uuid}")

    # Determine output path
    if output:
        output_path = Path(output) if Path(output).is_absolute() else SKINS_DIR / output
    else:
        output_path = SKINS_DIR / f"{username}.png"

    # Ensure .png extension
    if not str(output_path).endswith(".png"):
        output_path = output_path.with_suffix(".png")

    click.echo(f"Downloading skin...")
    if download_skin_from_uuid(uuid, output_path):
        variant = get_skin_variant(uuid)
        click.echo(f"✓ Saved skin to {output_path}")
        click.echo(f"  Model: {variant}")
        click.echo(f"\n  Use in nixcraft config:")
        click.echo(f'    account.skin.file = "{output_path}";')
        click.echo(f'    account.skin.variant = "{variant}";')
    else:
        click.echo("Error: Failed to download skin", err=True)
        sys.exit(1)


@cli.command()
@click.argument("username")
def fetch_capes(username: str):
    """Fetch all capes visible on a player's profile (limited to equipped cape)."""
    click.echo(f"Looking up {username}...")

    uuid = get_uuid_from_username(username)
    if not uuid:
        click.echo(f"Error: Could not find player '{username}'", err=True)
        sys.exit(1)

    profile = get_profile_from_uuid(uuid)
    if not profile:
        click.echo("Error: Could not get profile data", err=True)
        sys.exit(1)

    textures = profile.get("textures", {})
    cape_data = textures.get("CAPE")

    if not cape_data:
        click.echo(f"{username} doesn't have a visible cape")
        return

    cape_url = cape_data.get("url")
    if cape_url:
        output_path = CAPES_DIR / f"{username}_cape.png"
        try:
            response = requests.get(cape_url)
            if response.status_code == 200:
                with open(output_path, "wb") as f:
                    f.write(response.content)
                click.echo(f"✓ Saved cape to {output_path}")
            else:
                click.echo("Error: Could not download cape", err=True)
        except Exception as e:
            click.echo(f"Error: {e}", err=True)


@cli.command()
@click.argument("skin_path")
@click.option("--variant", "-v", type=click.Choice(["classic", "slim"]), default="classic",
              help="Skin model variant (classic=Steve, slim=Alex)")
def apply(skin_path: str, variant: str):
    """Apply a skin to your Minecraft account (requires authentication)."""
    resolved_path = resolve_skin_path(skin_path)
    if not resolved_path:
        click.echo(f"Error: Skin file not found: {skin_path}", err=True)
        click.echo(f"  Checked: {skin_path}")
        click.echo(f"  Checked: {SKINS_DIR / skin_path}")
        sys.exit(1)

    click.echo(f"Uploading {resolved_path} (variant: {variant})...")

    if upload_skin(resolved_path, variant):
        click.echo("✓ Skin applied successfully!")
    else:
        click.echo("Error: Failed to apply skin", err=True)
        sys.exit(1)


@cli.command("list")
@click.option("--capes", "-c", is_flag=True, help="List capes instead of skins")
def list_files(capes: bool):
    """List available skins or capes."""
    if capes:
        directory = CAPES_DIR
        file_type = "capes"
    else:
        directory = SKINS_DIR
        file_type = "skins"

    if not directory.exists():
        click.echo(f"No {file_type} directory found")
        return

    files = list(directory.glob("*.png"))

    # Exclude capes subdirectory when listing skins
    if not capes:
        files = [f for f in files if f.parent == SKINS_DIR]

    if not files:
        click.echo(f"No {file_type} found in {directory}")
        return

    click.echo(f"Available {file_type} in {directory}:\n")
    for f in sorted(files):
        click.echo(f"  {f.name}")


@cli.command()
def my_capes():
    """List capes owned by your authenticated account."""
    token = load_access_token()
    if not token:
        click.echo("Error: Not authenticated. Run 'nixcraft-auth login' first.", err=True)
        sys.exit(1)

    click.echo("Fetching your capes...")
    capes = get_owned_capes(token)

    if not capes:
        click.echo("You don't own any capes.")
        return

    click.echo(f"\nYou own {len(capes)} cape(s):\n")
    for cape in capes:
        cape_id = cape.get("id", "unknown")
        alias = cape.get("alias", "Unknown")
        state = cape.get("state", "")
        active = " (active)" if state == "ACTIVE" else ""

        click.echo(f"  {alias}{active}")
        click.echo(f"    ID: {cape_id}")

        # Download cape image
        cape_url = cape.get("url")
        if cape_url:
            safe_alias = re.sub(r'[^\w\-]', '_', alias)
            output_path = CAPES_DIR / f"{safe_alias}.png"
            try:
                response = requests.get(cape_url)
                if response.status_code == 200:
                    with open(output_path, "wb") as f:
                        f.write(response.content)
                    click.echo(f"    Saved to: {output_path}")
            except Exception:
                pass

        click.echo()


@cli.command()
@click.argument("cape_id_or_name")
def set_cape(cape_id_or_name: str):
    """Set your active cape. Use 'none' to hide cape."""
    if cape_id_or_name.lower() == "none":
        click.echo("Hiding cape...")
        if set_active_cape("none"):
            click.echo("✓ Cape hidden")
        else:
            click.echo("Error: Failed to hide cape", err=True)
            sys.exit(1)
        return

    token = load_access_token()
    if not token:
        click.echo("Error: Not authenticated. Run 'nixcraft-auth login' first.", err=True)
        sys.exit(1)

    # Check if it's a cape ID or alias
    capes = get_owned_capes(token)
    cape_id = None

    for cape in capes:
        if cape.get("id") == cape_id_or_name or cape.get("alias", "").lower() == cape_id_or_name.lower():
            cape_id = cape.get("id")
            break

    if not cape_id:
        click.echo(f"Error: Cape '{cape_id_or_name}' not found in your owned capes", err=True)
        click.echo("Run 'nixcraft-skin my-capes' to see available capes")
        sys.exit(1)

    click.echo(f"Setting cape...")
    if set_active_cape(cape_id):
        click.echo("✓ Cape set successfully!")
    else:
        click.echo("Error: Failed to set cape", err=True)
        sys.exit(1)


@cli.command()
def info():
    """Show skin/cape directory paths."""
    click.echo(f"Skins directory: {SKINS_DIR}")
    click.echo(f"Capes directory: {CAPES_DIR}")
    click.echo(f"Auth directory:  {AUTH_DIR}")

    skin_count = len(list(SKINS_DIR.glob("*.png"))) if SKINS_DIR.exists() else 0
    cape_count = len(list(CAPES_DIR.glob("*.png"))) if CAPES_DIR.exists() else 0

    click.echo(f"\nSkins saved: {skin_count}")
    click.echo(f"Capes saved: {cape_count}")


if __name__ == "__main__":
    cli()
