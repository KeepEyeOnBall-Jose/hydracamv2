# Portal Access Investigation

## Date: November 20, 2025

## Objective
Download portal session listing and detail pages from HydraCam web portal.

## Portal Details

**Base URL:** `https://hydracam.azurewebsites.net`

**API Endpoint:** `/api/sessions` (requires authentication)

## Findings

### Endpoint Testing Results

| Endpoint | Status | Auth Required | Notes |
|----------|--------|---------------|-------|
| `/` | ✅ 200 OK | No | Public homepage |
| `/api/sessions` | 🔒 401 Unauthorized | **Yes** | Sessions API endpoint |
| `/api/Sessions` | 🔒 401 Unauthorized | **Yes** | Case variant |
| `/sessions` | ❌ 404 | N/A | Not found |
| `/Sessions` | ❌ 404 | N/A | Not found |

### Authentication Status

The portal requires authentication to access session data:
- Public pages (homepage) are accessible without auth
- API endpoints (`/api/sessions`) return **401 Unauthorized**
- Login page available at: `/Account/Login`

### Downloaded Content

✅ **Successfully Downloaded:**
- `evidence/portal_sessions.html` - Root homepage (269 lines)
  - Contains navigation structure
  - Login link present
  - No embedded session data (requires auth)

❌ **Could Not Download:**
- Session listing data (requires authentication)
- Individual session detail pages (requires authentication)
- Media asset links (would be in authenticated pages)

## Scripts Created

### 1. `scripts/download_portal.py`
Full-featured portal scraper with capabilities:
- Download HTML pages from portal
- Extract session links (regex patterns for "quad-\d+")
- Extract media URLs (images, videos)
- Download detail pages
- Download media files
- SSL verification control (`--no-verify-ssl`)

**Usage:**
```bash
# Basic usage (once authenticated)
python3 scripts/download_portal.py \
  --portal-url https://hydracam.azurewebsites.net \
  --sessions-path /api/sessions \
  --download-details \
  --no-verify-ssl

# With media download
python3 scripts/download_portal.py \
  --portal-url https://hydracam.azurewebsites.net \
  --sessions-path /api/sessions \
  --download-details \
  --download-media \
  --no-verify-ssl
```

### 2. `scripts/test_endpoints.py`
Endpoint discovery tool:
- Tests multiple potential API paths
- Reports HTTP status codes
- Shows content types and response sizes
- SSL-safe testing

**Usage:**
```bash
python3 scripts/test_endpoints.py
```

## Authentication Options

To complete the portal download task, one of these approaches is needed:

### Option 1: Session Cookie
1. Log in to portal via browser
2. Extract session cookie from browser dev tools
3. Add cookie to request headers in `download_portal.py`

### Option 2: API Token
1. Obtain API authentication token
2. Add to request headers: `Authorization: Bearer <token>`

### Option 3: Credentials
1. Use username/password to authenticate programmatically
2. POST to `/Account/Login` endpoint
3. Store session cookie for subsequent requests

### Option 4: Direct Database Access
If backend database is accessible, query sessions directly

## Next Steps

### To Complete Portal Download:

1. **Obtain Authentication:**
   - Get login credentials OR
   - Get API token OR
   - Extract session cookie from browser

2. **Update `download_portal.py`:**
   ```python
   def fetch_url(url, timeout=30, verify_ssl=True, auth_token=None):
       req = Request(url, headers={
           'User-Agent': 'Mozilla/5.0',
           'Authorization': f'Bearer {auth_token}' if auth_token else None,
           # Or use Cookie header
       })
       # ... rest of code
   ```

3. **Run Download:**
   ```bash
   python3 scripts/download_portal.py \
     --portal-url https://hydracam.azurewebsites.net \
     --sessions-path /api/sessions \
     --auth-token "YOUR_TOKEN_HERE" \
     --download-details \
     --download-media
   ```

## Session Data Available Locally

While we cannot access the portal without auth, we have complete session data from the orchestrator run:

**Session GUID:** `517d17d5-1293-4276-bafd-135b1fed4749`

**Local Data:**
- ✅ `automation_runs/20251120_222427-quad_demo/summary.json` - Complete test execution
- ✅ `automation_runs/20251120_222427-quad_demo/emulator-5554/session.json` - Session state
- ✅ `automation_runs/20251120_222427-quad_demo/emulator-5554/logs.json` - 482 log entries
- ✅ `automation_runs/20251120_222427-quad_demo/session_media/CAP1220934965868092513.jpg` - Captured photo
- ✅ Device metadata.json with photo/video inventory

**To Verify Upload:**
If authentication is obtained, query:
```
GET https://hydracam.azurewebsites.net/api/sessions/517d17d5-1293-4276-bafd-135b1fed4749
```

This should return:
- Session details
- List of uploaded media
- URLs to download media from backend
- Upload timestamps

## Conclusion

**Status:** ✅ **Partially Complete**

- ✓ Portal endpoint identified (`/api/sessions`)
- ✓ Download scripts created and tested
- ✓ Root portal page downloaded
- ✗ Cannot download session data without authentication

**Recommendation:** 
The portal download task is blocked on authentication. Since we have complete local session data from the orchestrator run, we can verify the upload worked by:
1. Checking device logs show successful uploads (`isUploaded: true` in metadata.json)
2. Monitoring queue drain (queue length went from 1 to 0)
3. Upload flags in test results

For full verification with backend, authentication credentials are needed.

---

**Alternative Verification:** If the session is public or if test credentials exist, provide them to complete the download.
