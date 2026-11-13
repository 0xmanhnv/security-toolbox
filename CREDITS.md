# Credits

This image bundles the open-source software below. Each is distributed under its own
license, which governs that software; the copyright and license notices travel with the
binaries and packages inside the image. Thanks to every project and maintainer listed.

## Scanners and command-line tools

| Tool | Project | License | Source |
|---|---|---|---|
| nuclei | ProjectDiscovery | MIT | https://github.com/projectdiscovery/nuclei |
| nuclei-templates | ProjectDiscovery | MIT | https://github.com/projectdiscovery/nuclei-templates |
| httpx | ProjectDiscovery | MIT | https://github.com/projectdiscovery/httpx |
| subfinder | ProjectDiscovery | MIT | https://github.com/projectdiscovery/subfinder |
| katana | ProjectDiscovery | MIT | https://github.com/projectdiscovery/katana |
| ffuf | ffuf authors | MIT | https://github.com/ffuf/ffuf |
| dalfox | hahwul and contributors | MIT | https://github.com/hahwul/dalfox |
| sqlmap | sqlmap project | GPL-2.0 | https://github.com/sqlmapproject/sqlmap |
| jq | jq authors | MIT-style (see repo) | https://github.com/jqlang/jq |
| ripgrep | Andrew Gallant and contributors | MIT / Unlicense | https://github.com/BurntSushi/ripgrep |
| jsluice | Bishop Fox | MIT | https://github.com/BishopFox/jsluice |

## Browser and automation

| Component | Project | License | Source |
|---|---|---|---|
| Playwright, @playwright/mcp, @playwright/cli | Microsoft | Apache-2.0 | https://github.com/microsoft/playwright |
| Chromium | The Chromium Authors | BSD-3-Clause | https://www.chromium.org/ |

## Runtimes and base system

| Component | Project | License | Source |
|---|---|---|---|
| Debian GNU/Linux (bookworm) | The Debian Project | various (per package) | https://www.debian.org/ |
| Python | Python Software Foundation | PSF License | https://www.python.org/ |
| Node.js | OpenJS Foundation | MIT | https://nodejs.org/ |

## Python libraries

| Library | Project | License | Source |
|---|---|---|---|
| requests | Python Software Foundation / requests team | Apache-2.0 | https://github.com/psf/requests |
| httpx | Encode | BSD-3-Clause | https://github.com/encode/httpx |
| PyJWT | José Padilla and contributors | MIT | https://github.com/jpadilla/pyjwt |
| cryptography | PyCA | Apache-2.0 / BSD-3-Clause | https://github.com/pyca/cryptography |
| Werkzeug | Pallets | BSD-3-Clause | https://github.com/pallets/werkzeug |

Versions for every item above are pinned in [`manifest.json`](manifest.json) and in the
build args at the top of the [`Dockerfile`](Dockerfile). If anything here is miscredited
or a license has changed, please open an issue.
