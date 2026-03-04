---
name: verify-dashboard
description: Verify dashboard changes are live after any modification to the web app (app.py, templates, static files). Use this automatically after editing any file in the dashboard/ directory.
---

After ANY change to files in the `dashboard/` directory (app.py, templates/, static/), you MUST run this verification before considering the change done.

## Steps

### 1. Run the test client

Run the Flask test client to confirm the app doesn't crash and routes return 200:

```python
cd dashboard && source .venv/bin/activate && python3 -c "
import app as a
client = a.app.test_client()
routes = ['/', '/project/ai-progress-tracker', '/search?q=test']
for r in routes:
    resp = client.get(r)
    assert resp.status_code == 200, f'{r} returned {resp.status_code}'
    print(f'  {r} — {resp.status_code} OK')
print('All routes pass')
"
```

### 2. Restart the live server

The dashboard runs as a detached process on port 9847. After code changes, it must be restarted:

```bash
# Find and kill the old process
OLD_PID=$(lsof -ti :9847)
kill $OLD_PID

# Start the new one (detached)
cd dashboard && source .venv/bin/activate && python3 app.py
# (run detached so it persists)
```

### 3. Verify the live server is serving the new code

Hit the live dashboard and confirm the change is actually reflected:

```bash
# Check it's responding
curl -s -o /dev/null -w "%{http_code}" http://localhost:9847/

# Check for the specific change you just made
# (adapt the grep to match your change)
curl -s http://localhost:9847/ | grep "your-change-indicator"
```

### 4. Report to the user

Tell the user:
- What you changed
- That the test client passed
- That the live server was restarted
- That you confirmed the change is visible at `http://localhost:9847`

Do NOT say "done" without completing all 4 steps.
