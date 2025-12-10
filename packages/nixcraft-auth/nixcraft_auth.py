#!/usr/bin/env python3
"""
nixcraft-auth: Microsoft authentication helper for Nixcraft

This tool handles the OAuth2 flow for Microsoft/Minecraft authentication,
allowing nixcraft instances to play on online servers.
"""

import json
import os
import sys
import time
import webbrowser
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlencode, parse_qs, urlparse
import requests
import click

# Microsoft OAuth settings
# Using the official Minecraft launcher client ID (public)
CLIENT_ID = "00000000402b5328"  # Official Minecraft launcher client ID
REDIRECT_URI = "https://login.live.com/oauth20_desktop.srf"

# API endpoints
MS_AUTH_URL = "https://login.live.com/oauth20_authorize.srf"
MS_TOKEN_URL = "https://login.live.com/oauth20_token.srf"
XBL_AUTH_URL = "https://user.auth.xboxlive.com/user/authenticate"
XSTS_AUTH_URL = "https://xsts.auth.xboxlive.com/xsts/authorize"
MC_AUTH_URL = "https://api.minecraftservices.com/authentication/login_with_xbox"
MC_PROFILE_URL = "https://api.minecraftservices.com/minecraft/profile"

# Data directory
DATA_DIR = Path.home() / ".local" / "share" / "nixcraft" / "auth"


def get_data_dir():
    """Ensure data directory exists and return path."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    return DATA_DIR


def save_tokens(data: dict, filename: str):
    """Save tokens to file with restricted permissions."""
    path = get_data_dir() / filename
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    os.chmod(path, 0o600)


def load_tokens(filename: str) -> dict | None:
    """Load tokens from file."""
    path = get_data_dir() / filename
    if path.exists():
        with open(path) as f:
            return json.load(f)
    return None


def microsoft_oauth_url():
    """Generate Microsoft OAuth URL."""
    params = {
        "client_id": CLIENT_ID,
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "scope": "XboxLive.signin offline_access",
    }
    return f"{MS_AUTH_URL}?{urlencode(params)}"


def exchange_code_for_token(code: str) -> dict:
    """Exchange authorization code for access token."""
    data = {
        "client_id": CLIENT_ID,
        "code": code,
        "grant_type": "authorization_code",
        "redirect_uri": REDIRECT_URI,
    }
    response = requests.post(MS_TOKEN_URL, data=data)
    response.raise_for_status()
    return response.json()


def refresh_microsoft_token(refresh_token: str) -> dict:
    """Refresh Microsoft access token."""
    data = {
        "client_id": CLIENT_ID,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    }
    response = requests.post(MS_TOKEN_URL, data=data)
    response.raise_for_status()
    return response.json()


def xbox_live_auth(ms_access_token: str) -> dict:
    """Authenticate with Xbox Live."""
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    data = {
        "Properties": {
            "AuthMethod": "RPS",
            "SiteName": "user.auth.xboxlive.com",
            "RpsTicket": f"d={ms_access_token}",
        },
        "RelyingParty": "http://auth.xboxlive.com",
        "TokenType": "JWT",
    }
    response = requests.post(XBL_AUTH_URL, headers=headers, json=data)
    response.raise_for_status()
    return response.json()


def xsts_auth(xbl_token: str) -> dict:
    """Get XSTS token."""
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    data = {
        "Properties": {
            "SandboxId": "RETAIL",
            "UserTokens": [xbl_token],
        },
        "RelyingParty": "rp://api.minecraftservices.com/",
        "TokenType": "JWT",
    }
    response = requests.post(XSTS_AUTH_URL, headers=headers, json=data)
    response.raise_for_status()
    return response.json()


def minecraft_auth(xsts_token: str, user_hash: str) -> dict:
    """Authenticate with Minecraft services."""
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    data = {
        "identityToken": f"XBL3.0 x={user_hash};{xsts_token}",
    }
    response = requests.post(MC_AUTH_URL, headers=headers, json=data)
    response.raise_for_status()
    return response.json()


def get_minecraft_profile(mc_access_token: str) -> dict:
    """Get Minecraft profile (username, UUID, skin)."""
    headers = {
        "Authorization": f"Bearer {mc_access_token}",
    }
    response = requests.get(MC_PROFILE_URL, headers=headers)
    response.raise_for_status()
    return response.json()


def full_auth_flow(ms_access_token: str) -> dict:
    """Complete authentication flow from MS token to MC profile."""
    click.echo("Authenticating with Xbox Live...")
    xbl_response = xbox_live_auth(ms_access_token)
    xbl_token = xbl_response["Token"]
    xui_claims = xbl_response["DisplayClaims"]["xui"][0]
    user_hash = xui_claims["uhs"]
    # XUID is in the xid field of the Xbox Live response
    xuid = xui_claims.get("xid", "")

    click.echo("Getting XSTS token...")
    xsts_response = xsts_auth(xbl_token)
    xsts_token = xsts_response["Token"]
    # XUID might also be in XSTS response if not in XBL
    if not xuid:
        xsts_xui = xsts_response.get("DisplayClaims", {}).get("xui", [{}])[0]
        xuid = xsts_xui.get("xid", "")

    click.echo("Authenticating with Minecraft...")
    mc_response = minecraft_auth(xsts_token, user_hash)
    mc_access_token = mc_response["access_token"]
    mc_expires_in = mc_response.get("expires_in", 86400)

    click.echo("Fetching Minecraft profile...")
    profile = get_minecraft_profile(mc_access_token)

    return {
        "access_token": mc_access_token,
        "expires_at": int(time.time()) + mc_expires_in,
        "username": profile["name"],
        "uuid": profile["id"],
        "xuid": xuid,
        "skins": profile.get("skins", []),
    }


@click.group()
def cli():
    """Nixcraft Microsoft Authentication Helper"""
    pass


@cli.command()
def login():
    """Login with Microsoft account."""
    auth_url = microsoft_oauth_url()

    click.echo("Opening browser for Microsoft login...")
    click.echo(f"\nIf browser doesn't open, visit:\n{auth_url}\n")
    webbrowser.open(auth_url)

    click.echo("After logging in, you'll be redirected to a page that may show an error.")
    click.echo("Copy the ENTIRE URL from your browser's address bar and paste it here.\n")

    redirect_url = click.prompt("Paste the redirect URL")

    # Parse the authorization code from the URL
    parsed = urlparse(redirect_url)
    params = parse_qs(parsed.query)

    if "code" not in params:
        click.echo("Error: No authorization code found in URL.", err=True)
        click.echo("Make sure you copied the entire URL including 'code=' parameter.", err=True)
        sys.exit(1)

    code = params["code"][0]

    try:
        click.echo("\nExchanging code for tokens...")
        ms_tokens = exchange_code_for_token(code)

        # Save Microsoft tokens for refresh
        save_tokens({
            "access_token": ms_tokens["access_token"],
            "refresh_token": ms_tokens.get("refresh_token"),
            "expires_at": int(time.time()) + ms_tokens.get("expires_in", 3600),
        }, "microsoft_token.json")

        # Complete the auth flow
        mc_data = full_auth_flow(ms_tokens["access_token"])

        # Save Minecraft tokens and profile
        save_tokens(mc_data, "minecraft_token.json")

        # Write access token to file for nixcraft
        token_path = get_data_dir() / "access_token"
        with open(token_path, 'w') as f:
            f.write(mc_data["access_token"])
        os.chmod(token_path, 0o600)

        # Write UUID to file for nixcraft
        uuid_path = get_data_dir() / "uuid"
        with open(uuid_path, 'w') as f:
            f.write(mc_data["uuid"])
        os.chmod(uuid_path, 0o600)

        # Write username to file for nixcraft
        username_path = get_data_dir() / "username"
        with open(username_path, 'w') as f:
            f.write(mc_data["username"])
        os.chmod(username_path, 0o600)

        # Write XUID to file for nixcraft (required for Microsoft account auth)
        xuid_path = get_data_dir() / "xuid"
        with open(xuid_path, 'w') as f:
            f.write(mc_data.get("xuid", ""))
        os.chmod(xuid_path, 0o600)

        click.echo(f"\n✓ Logged in as {mc_data['username']} (UUID: {mc_data['uuid']})")
        click.echo(f"  Tokens saved to {get_data_dir()}")
        click.echo(f"\n  Use this in your nixcraft config:")
        click.echo(f'    accessTokenPath = "{token_path}";')

    except requests.HTTPError as e:
        click.echo(f"Authentication failed: {e}", err=True)
        if e.response is not None:
            click.echo(f"Response: {e.response.text}", err=True)
        sys.exit(1)


@cli.command()
def refresh():
    """Refresh authentication tokens."""
    ms_tokens = load_tokens("microsoft_token.json")

    if not ms_tokens or not ms_tokens.get("refresh_token"):
        click.echo("No refresh token found. Please run 'nixcraft-auth login' first.", err=True)
        sys.exit(1)

    try:
        click.echo("Refreshing Microsoft token...")
        new_ms_tokens = refresh_microsoft_token(ms_tokens["refresh_token"])

        save_tokens({
            "access_token": new_ms_tokens["access_token"],
            "refresh_token": new_ms_tokens.get("refresh_token", ms_tokens["refresh_token"]),
            "expires_at": int(time.time()) + new_ms_tokens.get("expires_in", 3600),
        }, "microsoft_token.json")

        mc_data = full_auth_flow(new_ms_tokens["access_token"])
        save_tokens(mc_data, "minecraft_token.json")

        token_path = get_data_dir() / "access_token"
        with open(token_path, 'w') as f:
            f.write(mc_data["access_token"])
        os.chmod(token_path, 0o600)

        # Write UUID to file for nixcraft
        uuid_path = get_data_dir() / "uuid"
        with open(uuid_path, 'w') as f:
            f.write(mc_data["uuid"])
        os.chmod(uuid_path, 0o600)

        # Write username to file for nixcraft
        username_path = get_data_dir() / "username"
        with open(username_path, 'w') as f:
            f.write(mc_data["username"])
        os.chmod(username_path, 0o600)

        # Write XUID to file for nixcraft
        xuid_path = get_data_dir() / "xuid"
        with open(xuid_path, 'w') as f:
            f.write(mc_data.get("xuid", ""))
        os.chmod(xuid_path, 0o600)

        click.echo(f"✓ Tokens refreshed for {mc_data['username']}")

    except requests.HTTPError as e:
        click.echo(f"Refresh failed: {e}", err=True)
        click.echo("You may need to run 'nixcraft-auth login' again.", err=True)
        sys.exit(1)


@cli.command()
def status():
    """Show current authentication status."""
    mc_tokens = load_tokens("minecraft_token.json")

    if not mc_tokens:
        click.echo("Not logged in. Run 'nixcraft-auth login' to authenticate.")
        return

    username = mc_tokens.get("username", "Unknown")
    uuid = mc_tokens.get("uuid", "Unknown")
    expires_at = mc_tokens.get("expires_at", 0)

    now = int(time.time())
    if expires_at > now:
        remaining = expires_at - now
        hours = remaining // 3600
        minutes = (remaining % 3600) // 60
        status = f"Valid ({hours}h {minutes}m remaining)"
    else:
        status = "Expired (run 'nixcraft-auth refresh')"

    click.echo(f"Username: {username}")
    click.echo(f"UUID: {uuid}")
    click.echo(f"Token: {status}")
    click.echo(f"Data dir: {get_data_dir()}")


@cli.command()
def logout():
    """Remove saved authentication data."""
    data_dir = get_data_dir()

    files = ["microsoft_token.json", "minecraft_token.json", "access_token", "uuid", "username", "xuid"]
    removed = 0

    for filename in files:
        path = data_dir / filename
        if path.exists():
            path.unlink()
            removed += 1

    if removed > 0:
        click.echo(f"✓ Removed {removed} auth file(s)")
    else:
        click.echo("No auth files to remove")


@cli.command()
def token_path():
    """Print the path to the access token file (for use in nixcraft config)."""
    click.echo(get_data_dir() / "access_token")


if __name__ == "__main__":
    cli()
