# SOP: Review Tenant Logs

## Steps
1. Ask operator which tenant, or `all` for platform-wide review.
2. For one tenant: `docker logs hermes_{tenant-id} --tail 100`.
3. For all tenants, read tenants.yaml and loop through active tenants with `docker logs hermes_{tenant-id} --tail 20`.
4. Look for ERROR/WARN messages, gateway disconnections, Mnemosyne memory errors, and LLM API errors.
5. Report findings and recommended actions to operator.
