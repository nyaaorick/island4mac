# Update Metadata Format

This document describes the JSON format used by Mac灵动岛 for checking updates.

## Endpoint

The app fetches update metadata from a configurable URL (default example: `https://example.com/mac-lingdonggao/updates.json`).

You can modify the URL in `StatusBarController.swift` → `onCheckUpdates()` method.

## JSON Schema

```json
{
  "latestVersion": "1.1.0",
  "minimumVersion": "1.0.0",
  "releaseNotes": "- Fixed clipboard monitoring\n- Added dark mode support\n- Improved performance",
  "downloadUrl": "https://example.com/mac-lingdonggao/releases/v1.1.0.dmg",
  "releaseDate": "2026-01-15",
  "isMandatory": false
}
```

## Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `latestVersion` | String | ✓ | Semantic version of latest release (e.g., "1.1.0") |
| `minimumVersion` | String | ✗ | Minimum supported version. If user is below this, update is mandatory |
| `releaseNotes` | String | ✓ | Human-readable release notes. Support `\n` for line breaks |
| `downloadUrl` | String | ✓ | Direct download link to app bundle (DMG, ZIP, etc.) |
| `releaseDate` | String | ✗ | ISO 8601 date (YYYY-MM-DD) when release was published |
| `isMandatory` | Boolean | ✗ | If `true`, user cannot skip the update. Default: `false` |

## Version Comparison

The app uses semantic versioning (MAJOR.MINOR.PATCH) to determine if an update is available.

Example comparisons:
- `1.0.0` → `1.1.0` = Update available
- `2.0.0` → `1.9.9` = No update (already newer)
- `1.0.5` → `1.0.5` = No update (same version)

## Example Response

```json
{
  "latestVersion": "2.0.0",
  "minimumVersion": "1.5.0",
  "releaseNotes": "Major release:\n- Complete redesign\n- New tray interface\n- Multi-monitor improvements\n- 50+ bug fixes",
  "downloadUrl": "https://github.com/user/Mac-LingDongGao/releases/download/v2.0.0/Mac灵动岛-2.0.0.dmg",
  "releaseDate": "2026-02-01",
  "isMandatory": false
}
```

## Hosting Recommendations

1. **GitHub Releases** (Recommended for open source)
   - Upload DMG/ZIP to GitHub release
   - Serve JSON from a CDN or raw GitHub content URL

2. **Self-hosted** (Recommended for private releases)
   - Host JSON on your web server
   - Ensure HTTPS is enabled
   - Set appropriate cache headers

3. **Content Delivery Network (CDN)**
   - Use CloudFront, Fastly, or similar for global distribution
   - Ensure low latency for quick update checks

## Security Considerations

- **HTTPS Required**: Always serve metadata over HTTPS to prevent man-in-the-middle attacks
- **URL Pinning** (Optional): Consider hardcoding trusted URLs in the app
- **Signature Verification** (Future Enhancement): Sign JSON payload with private key; app verifies with public key

## Workflow

1. User clicks "Check for Updates…" in status bar menu
2. App fetches JSON from configured URL (async, doesn't block UI)
3. App compares local version with `latestVersion` from JSON
4. If update available:
   - Show alert with version, release notes, and download link
   - User can Download, Remind Later, or Skip
5. If no update:
   - Show "You are on the latest version" alert

## Configuration

To change the update metadata URL, edit:

**File**: `StatusBarController.swift`  
**Method**: `onCheckUpdates()`  
**Line**: Change `let metadataUrl = "https://example.com/mac-lingdonggao/updates.json"`

## Testing

To test locally without a real server:

1. Create a local `updates.json` file
2. Start a local HTTP server: `python3 -m http.server 8000`
3. Update URL in code to: `http://localhost:8000/updates.json`
4. Click "Check for Updates…" in the app

## Future Enhancements

- [ ] Automatic background update checks (with user consent)
- [ ] Delta/patch updates instead of full app download
- [ ] Staged rollout (gradually release to percentage of users)
- [ ] Rollback mechanism if critical bugs found
- [ ] Telemetry: Track which versions are actively used

