# Incident: Telegram API Or Bot Delivery Change

## Detection
- Multiple tenants fail Telegram send or gateway connection while containers and outbound HTTPS are healthy.
- Errors are not normal `chat not found` or owner-not-started-bot cases.

## Immediate Actions
1. Verify outbound HTTPS to `https://api.telegram.org`.
2. Check one bot token with a redacted-safe method; never paste tokens into reports.
3. Review tenant logs for gateway errors.

## Recovery
- If owners have not started bots, ask them to send `/start`.
- If bot token is invalid, rotate the token in `.env` and restart only that tenant.
- If Telegram behavior changed globally, document error payloads without secrets and update SOP guidance.

## Post-Incident
- Update troubleshooting docs if the error message is new.
- Include redacted evidence in the task report.
