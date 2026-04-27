# Loole

**Loole** is a modern, high-performance SOCKS5 tunnel designed to bypass network restrictions by leveraging Google Drive as a covert transport layer. It provides a premium macOS experience with an automated setup wizard.

<div align="center">
  <img src="macos-app/sc/1.png" width="32%" />
  <img src="macos-app/sc/2.png" width="32%" />
  <img src="macos-app/sc/3.png" width="32%" />
</div>

---


## Key Features
- **Easy Guided Setup**: A 3-step wizard that handles the complexity of Google Cloud Console for you with direct links and instructions.
- **Automatic Authorization**: No more copy-pasting URLs from the terminal. Loole handles the OAuth2 handshake directly in your browser.
- **Connection Health Checker**: Real-time feedback on your connection quality, including **ping latency** and **server location** (GeoIP).
- **One-Click System Proxy**: Toggle system-wide SOCKS5 proxy support instantly with passwordless privilege elevation (one-time setup).
- **Built-in Server Packager**: Automatically packages your customized server binary for **x86_64** or **ARM64** architectures, ready to be dropped onto your VPS.
- **Premium macOS UI**: Designed with native glassmorphism and modern aesthetics for a seamless desktop experience.

---

## Requirements
To use Loole, you will need:
1.  **A Linux Server (VPS)**: Any basic VPS (Ubuntu/Debian recommended) to host the server-side tunnel.
2.  **A Google Account**: To use Google Drive as the encrypted data channel.

---

## How it Works
Loole treats a hidden folder in your Google Drive as a bi-directional data queue:
1.  **Client (Mac)**: Packages your local network requests into a compact binary protocol and uploads them to Drive.
2.  **Server (VPS)**: Constantly polls the Drive folder, executes the requests, and uploads the responses back.

Since the traffic looks like legitimate Google API calls (Drive file movements), it is highly resistant to deep packet inspection (DPI) and blocking.

---

## Getting Started

1.  **Download the latest release** (or build from source using `./scripts/build-app.sh`).
2.  **Open Loole** and follow the Step 1 (Credentials) guide to get your Google Cloud JSON.
3.  **Authorize** the app with your Google account.
4.  **Deploy the Server**: Follow the built-in instructions to copy the automatically generated ZIP file to your Linux server and run it.
5.  **Connect** and enjoy your private tunnel!

---

## Python Client (No Mac App Required)

If you don't have a Mac or prefer a lightweight CLI setup, the Python client provides the same SOCKS5 tunnel using Google Drive as transport — no GUI needed.

### Prerequisites

- Python 3.8+
- A Linux/Mac/Windows machine to run the client
- A Linux VPS running the Loole server
- A Google account

---

### Step 1 — Set up Google Cloud credentials

The Python client needs an OAuth2 credentials file (`credentials.json`) to access Google Drive on your behalf.

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and sign in.
2. **Create a new project** (or select an existing one):
   Click the project dropdown at the top → **New Project** → give it a name (e.g. `loole`) → **Create**.
3. **Enable the Google Drive API**:
   - In the left sidebar go to **APIs & Services → Library**.
   - Search for **Google Drive API** and click **Enable**.
4. **Configure the OAuth consent screen**:
   - Go to **APIs & Services → OAuth consent screen**.
   - Select **External** → **Create**.
   - Fill in **App name** (anything), **User support email**, and **Developer contact email**.
   - Click **Save and Continue** through the remaining steps (no scopes or test users needed yet).
   - On the last page click **Back to Dashboard**.
5. **Create OAuth credentials**:
   - Go to **APIs & Services → Credentials** → **+ Create Credentials → OAuth client ID**.
   - Application type: **Desktop app**.
   - Name it anything → **Create**.
   - Click **Download JSON** on the confirmation dialog (or the ⬇ icon next to it in the credentials list).
   - Save the file as `credentials.json`.
6. **Add your Google account as a test user** (required while the app is in "Testing" mode):
   - Go back to **OAuth consent screen** → scroll down to **Test users** → **+ Add users**.
   - Enter the Gmail address you will use for Drive access → **Save**.

---

### Step 2 — Set up the Loole server on your VPS

If you haven't already deployed the server:

1. On a machine that **has** the Loole macOS app (or build from source), use the built-in **Server Packager** to generate a `loole-server.zip` for your VPS architecture.
   Alternatively, build the server binary directly on your VPS:
   ```bash
   git clone <this-repo> && cd Loole
   go build -o loole-server ./cmd/server/
   ```
2. Copy `loole-server` and a `server_config.json` to your VPS.
   A minimal `server_config.json` (see `server_config.json.example`):
   ```json
   {
     "credentials_json": "credentials.json",
     "token_cache": "credentials.json.token",
     "google_folder_id": "<your-drive-folder-id>"
   }
   ```
3. Copy the same `credentials.json` (and the `.token` file after first auth) to the VPS.
4. Start the server:
   ```bash
   ./loole-server -c server_config.json
   ```
   On first run it will print an OAuth URL — open it in a browser, authorize, and the `.token` file is saved automatically.

---

### Step 3 — Find your Google Drive folder ID

The client and server must share the same Drive folder.

1. Open [Google Drive](https://drive.google.com) in your browser.
2. Create a new folder (e.g. `loole-tunnel`) or use an existing one.
3. Open the folder — the URL will look like:
   `https://drive.google.com/drive/folders/1WzXvCtnN7syaHs46q5cX-FguvJbi31rO`
   The long string after `/folders/` is your **folder ID**.
4. Put this ID in `config.json` as `google_folder_id`.

---

### Step 4 — Install the Python client

```bash
cd python-client
pip install requests google-auth google-auth-oauthlib google-auth-httplib2 urllib3
```

---

### Step 5 — Configure the client

Edit `python-client/config.json`:

```json
{
  "credentials_json": "credentials.json",
  "token_cache": "credentials.json.token",
  "google_folder_id": "<paste your folder ID here>",
  "socks_listen": "127.0.0.1:1080",
  "poll_interval_ms": 300,
  "flush_interval_ms": 200,
  "client_id": "",
  "domain_front": {
    "target_ip": "216.239.38.120",
    "sni": "google.com",
    "api_host": "www.googleapis.com"
  }
}
```

Place your `credentials.json` (downloaded in Step 1) in the `python-client/` directory.

---

### Step 6 — First-time OAuth authorization

On the **first run** the client will open a browser window asking you to authorize access to Google Drive. After you approve, a `credentials.json.token` file is saved next to `credentials.json` — this is your cached token and is reused on all future runs.

```bash
cd python-client
python loole_client.py
```

Follow the browser prompt, then come back to the terminal — you should see:

```
Authenticated with Google Drive
SOCKS5 proxy listening on 127.0.0.1:1080
```

---

### Step 7 — Use the proxy

Point any application at `socks5h://127.0.0.1:1080`.

**Quick test with curl:**
```bash
curl --proxy socks5h://127.0.0.1:1080 https://httpbin.org/ip
```

**Browser:** In Firefox → Settings → Network Settings → Manual proxy → SOCKS Host `127.0.0.1`, Port `1080`, SOCKS v5, check **Proxy DNS**.

**System-wide (macOS):**
```bash
networksetup -setsocksfirewallproxy Wi-Fi 127.0.0.1 1080
networksetup -setsocksfirewallproxystate Wi-Fi on
# To disable:
networksetup -setsocksfirewallproxystate Wi-Fi off
```

---

### Files in `python-client/`

| File | Description |
|------|-------------|
| `loole_client.py` | The client — run this |
| `config.json` | Configuration (folder ID, listen address, etc.) |
| `credentials.json` | Google OAuth client secret — **you provide this** |
| `credentials.json.token` | Cached OAuth token — auto-generated on first run |

---

## Donations

If you find Loole helpful, consider supporting the development. Every bit helps in maintaining and improving the project!

- **TON**: `UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx`
- **USDT (BEP20)**: `0x71F41696c60C4693305e67eE3Baa650a4E3dA796`
- **TRX (TRON)**: `TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV`

---

## Disclaimer
This project is intended for personal usage and research purposes only. Please do not use it for illegal purposes. The author is not responsible for any misuse of this tool.
