# Microsoft Authentication Design for Nixcraft

## Overview

This document outlines the design for adding Microsoft account authentication to Nixcraft, enabling online play on servers that require authentication (like MCSR Ranked).

## Authentication Flow

Microsoft authentication for Minecraft follows this flow:

```
1. User OAuth2 Login (Microsoft)
   └─> Microsoft Access Token

2. Xbox Live Authentication
   └─> XBL Token + User Hash

3. XSTS Authentication
   └─> XSTS Token

4. Minecraft Authentication
   └─> Minecraft Access Token + UUID + Username
```

## Implementation Options

### Option A: External Auth Helper (Recommended for MVP)

Create a separate CLI tool (`nixcraft-auth`) that handles the OAuth flow:

```bash
nixcraft-auth login    # Opens browser, handles OAuth, saves tokens
nixcraft-auth refresh  # Refreshes expired tokens
nixcraft-auth status   # Shows current auth status
nixcraft-auth logout   # Removes saved tokens
```

**Pros:**
- Simpler to implement
- Can be written in Python (using `msal` library)
- Tokens stored in `~/.local/share/nixcraft/auth/`
- Works with existing `accessTokenPath` option

**Cons:**
- Requires running a separate command before playing

### Option B: Integrated Auth (Future)

Build OAuth flow directly into the launch script with a local HTTP server for the callback.

## Proposed Module Changes

### New Account Options

```nix
account = {
  # Existing options
  username = "PlayerName";
  uuid = "...";
  accessTokenPath = "/path/to/token";
  offline = false;

  # New options
  microsoft = {
    enable = true;

    # Auto-refresh tokens before launch
    autoRefresh = true;

    # Path to store auth data (tokens, profile)
    dataDir = "~/.local/share/nixcraft/auth";

    # Client ID for OAuth (use default or custom Azure app)
    clientId = null;  # null = use nixcraft's registered app
  };
};
```

### Pre-launch Hook

When `account.microsoft.enable = true`:

1. Check if valid tokens exist in `dataDir`
2. If expired, attempt refresh
3. If refresh fails, prompt for re-authentication
4. Write current access token to `accessTokenPath`
5. Set `username` and `uuid` from profile

## Auth Helper Implementation

### `nixcraft-auth` CLI Tool

Written in Python using:
- `msal` - Microsoft Authentication Library
- `requests` - HTTP client
- `click` - CLI framework

```python
# Pseudocode structure
class MinecraftAuth:
    def microsoft_login(self) -> MicrosoftToken:
        """Device code flow or local server OAuth"""

    def xbox_live_auth(self, ms_token) -> XBLToken:
        """Authenticate with Xbox Live"""

    def xsts_auth(self, xbl_token) -> XSTSToken:
        """Get XSTS token"""

    def minecraft_auth(self, xsts_token) -> MinecraftToken:
        """Get Minecraft access token"""

    def get_profile(self, mc_token) -> MinecraftProfile:
        """Get username and UUID"""
```

### Token Storage

```
~/.local/share/nixcraft/auth/
├── microsoft_token.json    # MS OAuth tokens (encrypted)
├── minecraft_token.json    # MC access token + expiry
└── profile.json           # Username, UUID, skin URL
```

## API Endpoints

### Microsoft OAuth
- Auth URL: `https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize`
- Token URL: `https://login.microsoftonline.com/consumers/oauth2/v2.0/token`
- Scope: `XboxLive.signin offline_access`

### Xbox Live
- Auth URL: `https://user.auth.xboxlive.com/user/authenticate`

### XSTS
- Auth URL: `https://xsts.auth.xboxlive.com/xsts/authorize`

### Minecraft
- Auth URL: `https://api.minecraftservices.com/authentication/login_with_xbox`
- Profile URL: `https://api.minecraftservices.com/minecraft/profile`

## Skin Configuration (Bonus Feature)

Since we're fetching the profile, we can also expose skin information:

```nix
account = {
  microsoft.enable = true;

  # Read-only, populated after auth
  skin = {
    url = "https://...";  # Current skin URL
    variant = "slim";     # "classic" or "slim"
  };
};
```

## Implementation Phases

### Phase 1: Auth Helper Tool
1. Create `nixcraft-auth` Python package
2. Implement device code flow (no browser needed on headless)
3. Token storage with optional encryption
4. Add to nixcraft packages

### Phase 2: Module Integration
1. Add `account.microsoft` options
2. Pre-launch script integration
3. Auto-refresh logic

### Phase 3: Polish
1. Browser-based OAuth option
2. Skin display/management
3. Multiple account support

## Security Considerations

1. **Token Storage**: Tokens should be stored with restricted permissions (600)
2. **Client ID**: Using a registered Azure app client ID (can be hardcoded or user-provided)
3. **Refresh Tokens**: Store securely, refresh proactively
4. **No Password Storage**: OAuth flow never sees user's Microsoft password

## Dependencies

For the auth helper:
```nix
python3.withPackages (ps: with ps; [
  msal
  requests
  click
  cryptography  # optional, for token encryption
])
```

## Example Usage After Implementation

```nix
# nixcraft.nix
nixcraft.client.instances.Ranked = {
  enable = true;

  account = {
    microsoft.enable = true;
  };

  # ... rest of config
};
```

```bash
# First time setup
$ nixcraft-auth login
Opening browser for Microsoft login...
✓ Logged in as PlayerName (uuid: xxx-xxx)
Tokens saved to ~/.local/share/nixcraft/auth/

# Launch game (tokens auto-used)
$ ranked
```
