# AaaS Platform - Comprehensive Design Review & Improvement Areas

**Review Date:** 2026-06-18  
**Platform Version:** Track in `/opt/aaas/platform/VERSION`  
**Status:** Production with harness engineering and recovery improvements

> Validation note: this review was reconciled against the repository on 2026-06-18.
> The bootstrap iptables-legacy enforcement already exists in `scripts/setup-prerequisites.sh`,
> so that item is no longer an open gap. `check-tenant.sh` performs structural checks plus
> best-effort runtime/network warnings.

---

## EXECUTIVE SUMMARY

The AaaS Platform is a well-architected Agent-as-a-Service operations system for managing Hermes tenant agents at scale. The platform implements **harness engineering** patterns to prove tenant benefit (brand recall, owner safety, data isolation) rather than just container management. 

**Overall Assessment:** ✅ **Strong design with clear operational practices.** Ready for production use with identified improvement areas below.

**Key Strengths:**
- Deterministic harness validation (check-tenant.sh)
- Structured Standard Operating Procedures (SOPs) with required checklists
- Versioned platform upgrades with asset backups
- Tenant data isolation and structured memory seeding (Mnemosyne integration)
- Comprehensive task reporting with AI-readable INDEX.jsonl summaries
- Critical infrastructure issue (iptables-nftables) identified and mitigated

**Key Gaps:**
- Recovery and rollback strategies need to keep improving as real incidents are observed
- Failure-mode documentation and diagnostic workflows have been added, but should mature with operator use
- Eval profiles exist for one vertical (fnb) only
- Pre-flight validation now exists as a managed platform helper

---

## DESIGN ASSESSMENT

### 1. CORE ARCHITECTURE ✅

**Strengths:**
- **Layered responsibility model**: Admin agent (OpenCode) → SOPs (skills) → Scripts → Checklists
- **Single source of truth**: All business metadata in `tenants.yaml`, all technical state in Docker Compose + tenant configs
- **Version-aware upgrades**: Platform VERSION file enables safe incremental upgrades with backups
- **Filesystem-based harness**: `harness.yaml` and `ACCEPTANCE.md` are portable tenant manifests proven by deterministic shell script

**What works well:**
- Each SOP explicitly reads its required checklist before execution (`onboard-tenant.required.json`, `monitor-health.required.json`)
- Tenant data split is clean: secrets in `.env`, config in `config.yaml`, memory seeds in `memories/`, business context in `tenants.yaml`
- Mnemosyne integration replaces native Hermes memory for privacy and consistency (`memory.provider: mnemosyne`, `memory_enabled: false`)
- Volume ownership enforced at provisioning time (UID 10000) to prevent permission issues in containers

**Assessment:** Architecture is sound and follows Unix principles (composition, clear boundaries, explicit dependency management).

---

### 2. HARNESS ENGINEERING IMPLEMENTATION ✅

**What is Harness Engineering Here?**
Harness engineering proves that a tenant agent provides **owner benefit** and maintains **operational safety**. It's not just "container is running" — it's "owner gets their personalized, private agent."

**Implemented Harness Layers:**

#### A. **Tenant Harness Manifest** (`harness.yaml`)
- **File**: `/opt/aaas/tenants/{tenant-id}/harness.yaml`
- **Purpose**: Portable tenant specification proving intent and design decisions
- **Tracks**: tenant ID, business name, agent role, channels enabled (Telegram), verification profile, required checks, tenant benefits
- **Strength**: Deterministic, machine-readable, version-stamped

#### B. **Acceptance Record** (`ACCEPTANCE.md`)
- **File**: `/opt/aaas/tenants/{tenant-id}/ACCEPTANCE.md`
- **Purpose**: Human audit trail of tenant setup validation
- **Tracks**: Owner benefit checks (brand recall, confirmation before posting, file isolation), platform checks (config, Docker, connectivity), verification timestamps
- **Strength**: Explicit checklist; operator fills in evidence; timestamp + verifier recorded

#### C. **Deterministic Harness Check** (`check-tenant.sh`)
- **File**: `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
- **Purpose**: Shell script that proves structural readiness (not runtime behavior)
- **Checks**:
  - Directory structure (memories, files/assets, files/uploads, files/generated)
  - Required files (config.yaml, .env, SOUL.md, harness.yaml, ACCEPTANCE.md)
  - Config constraints (mnemosyne provider, memory disabled, user profile disabled)
  - SOUL.md patterns (owner confirmation, file paths)
  - Manifest version
- **Output**: PASS/FAIL/WARN with detail for each check
- **Strength**: Repeatable structural validation with best-effort runtime warnings for container and outbound HTTPS state

#### D. **Tenant Evaluation Profiles** (`evals/tenant-agent/fnb-marketing-v1.yaml`)
- **File**: `/opt/aaas/platform/evals/tenant-agent/fnb-marketing-v1.yaml`
- **Purpose**: Behavioral verification (brand recall, owner-safe interactions)
- **Used in**: onboard-tenant.md (step 17), update-tenant.md (step 11)
- **Limitation**: Only one managed eval profile exists today (F&B)

#### E. **Task Reports with AI Index**
- **File**: `/opt/aaas/platform/reports/{sop-name}/{timestamp}_{tenant}_{status}.md`
- **Purpose**: Full Markdown report (for humans) + JSON summary (for AI analysis)
- **Index**: `/opt/aaas/platform/reports/INDEX.jsonl` (one JSON object per line)
- **Strength**: Operator can analyze trends without rereading every report; AI can quickly spot recurring issues
- **Used for**: Platform improvements via INDEX query (`tail -50` recent entries before proposing changes)

#### F. **Critical Infrastructure Validation**
- **Issue**: Docker 29.x + iptables-nftables causes bridge network isolation after daemon restart
- **Mitigation**: 
  - Pre-flight check in onboard-tenant.md (step 0)
  - Connectivity test after container start (step 10: ping + curl to api.telegram.org)
  - Health monitor can check iptables rules (monitor-health.md step 1)
- **Documentation**: prerequisites, monitor-health SOP, troubleshooting guide, and incident playbooks

**Assessment:** Harness engineering is well-designed. Execution is deterministic and auditable. **Main gap: Eval profiles need vertical expansion.**

---

### 3. STANDARD OPERATING PROCEDURES (SOPs) ✅

**SOP Quality Assessment:**

| SOP | Status | Coverage | Notes |
|-----|--------|----------|-------|
| **onboard-tenant** | ✅ | 19 steps | Pre-flight, template rendering, connectivity tests, Mnemosyne seeding, telegram, harness check, eval profile run, reporting. **Well structured.** |
| **build-image** | ✅ | 6 steps | Simple, clear. Tags with date for rollback. |
| **upgrade-tenants** | ✅ | 4 tenant steps | Iterates active tenants, verifies harness files, restarts, runs check, updates metadata. **Handles missing harness files gracefully.** |
| **monitor-health** | ✅ | 9 steps | Covers status, connectivity, pre-flight, iptables state, and targeted recovery guidance. |
| **suspend-tenant** | ✅ | 6 steps | Preserves data, updates metadata, sends notification. |
| **reactivate-tenant** | ✅ | 7 steps | Restarts suspended tenant, verifies running state, updates metadata, sends welcome-back message. |
| **offboard-tenant** | ✅ | 9 steps | **Excellent safety**: Requires operator to type tenant ID exactly to confirm deletion. Multi-stage confirmation. |
| **update-tenant** | ✅ | 13 steps | Covers secrets, config, memory re-seeding, channels, harness validation, restart, eval runs. Comprehensive. |
| **upgrade-platform** | ✅ | 13 steps | Preserves tenant data, validates setup, handles iptables/Docker restart implications. |
| **write-report** | ✅ | Full template | Markdown + JSON index format, root cause analysis, improvement signals section. **Excellent design for trend analysis.** |

**Strengths:**
- Every SOP reads its required checklist before executing
- Pre-flight and post-execution validation
- Confirmation gates before destructive operations
- Harness check always run before declaring SOP complete
- Task reports capture root cause, not just "what happened"

**Weaknesses:**
- Rollback and recovery procedures now exist for common tenant, platform, and incident cases; keep expanding them from reports
- Error handling varies between SOPs (some explicit, some implicit)
- Limited guidance on "what to do if this fails" recovery workflows

---

### 4. TEMPLATE SYSTEM ✅

**Structure:**
- Base templates: `/opt/aaas/platform/templates/_base/`
- Vertical overrides: `/opt/aaas/platform/templates/verticals/fnb/` today; add more managed verticals when product scope requires them

**Base Templates:**
- `config.yaml.template` — Mnemosyne-based (native memory disabled), gateway config, terminal settings
- `.env.template` — API keys, Telegram users, Mnemosyne data dir
- `SOUL.md.template` — Agent persona and instructions
- `USER.md.template` — Owner profile and preferences

**Assessment:**
- ✅ Config templates are well-structured and enforce correct patterns (no native memory)
- ✅ Tenant-facing prompts (SOUL.md) emphasize owner confirmation before posting
- ⚠️ Only F&B vertical templates are currently managed repo assets

---

### 5. REPORTING & OBSERVABILITY ✅

**Strong Points:**
- Task reports are mandatory before SOP completion (write-report.md enforces this)
- INDEX.jsonl enables AI-driven root cause analysis without rereading full reports
- Structured YAML frontmatter in reports (`report_version`, `platform_version`, `sop`, `status`, `tenant_id`)
- Root Cause Analysis section encourages deep diagnosis, not surface fixes
- "Improvement Signals" section explicitly captures platform learning opportunities

**Weaknesses:**
- No centralized log aggregation across tenants (logs in Docker only; not persisted to platform)
- No automated trend analysis (INDEX.jsonl query is manual: "tail -50 | grep...")
- No proactive alerting on patterns (e.g., "three Telegram failures in last 24h")
- Report index is append-only; no deduplication if same task written twice

---

## IMPROVEMENT AREAS

### ⚠️ CRITICAL GAPS

#### 1. **Bootstrap iptables-legacy Enforcement**
**Status:** ✅ Implemented  
**Current State:** `scripts/setup-prerequisites.sh` includes Step 5.5 to switch `iptables` and `ip6tables` to legacy mode when `nf_tables` is detected, then restarts Docker. `docs/prerequisites.md` also documents the requirement.

**Remaining Watch Item:** Keep the pre-flight and health checks strict, because host package upgrades can still change Docker or iptables behavior after bootstrap.

---

#### 2. **iptables Health Check Recovery Guidance**
**Status:** ✅ Improved  
**Current State:** `monitor-health.md` now calls `preflight-check.sh`, treats non-legacy iptables or Docker readiness failure as a stop-and-fix condition, and explicitly avoids broad `docker compose down` recovery.

**Remaining Watch Item:** If recurring bridge-rule loss appears in reports, promote the known recovery path into a script with explicit operator confirmation.

---

#### 3. **Error Recovery or Rollback Workflows**
**Status:** ✅ Improved  
**Current State:** Added `/opt/aaas/platform/sop/troubleshoot-tenant.md`, troubleshooting documentation, pre-flight/config validation scripts, and incident playbooks.

**Remaining Watch Item:** Use task reports to discover which recovery paths need more exact commands or automation.

---

#### 4. **Eval Profiles Only Cover F&B Vertical**
**Impact:** Medium - Other verticals cannot prove tenant benefit  
**Current State:** Only `fnb-marketing-v1.yaml` exists  
**Gap:** 
- Retail and services are not managed vertical assets yet
- onboard-tenant.md step 17 hardcodes fnb profile
- Vertical-specific brand check requirements differ (e.g., retail needs inventory recall, services needs appointment confirmation)

**Fix Proposal:**

1. **Create retail eval profile when retail is in scope**: `/opt/aaas/platform/evals/tenant-agent/retail-pos-v1.yaml`
   - Brand recall: Store location, product categories, pricing
   - Owner behavior: Inventory updates, promotion scheduling
   - Safety: No cross-store data leakage

2. **Create services eval profile**: `/opt/aaas/platform/evals/tenant-agent/services-booking-v1.yaml`
   - Brand recall: Service types, pricing, availability
   - Owner behavior: Appointment confirmation, cancellation handling
   - Safety: No cross-service customer leakage

3. **Update templates**: Create vertical-specific templates for SOUL.md, MEMORY.md
   ```
   /opt/aaas/platform/templates/verticals/retail/SOUL.md.template
   /opt/aaas/platform/templates/verticals/services/SOUL.md.template
   ```

4. **Update onboard-tenant.md step 17**:
   ```bash
   PROFILE="/opt/aaas/platform/evals/tenant-agent/${BUSINESS_TYPE}-${PROFILE_VERSION}.yaml"
   if [ ! -f "$PROFILE" ]; then
     echo "WARN: Eval profile not found for $BUSINESS_TYPE. Run manual checks."
     # Fallback: operator assists
   fi
   ```

---

### ⚠️ MEDIUM-PRIORITY IMPROVEMENTS

#### 5. **Documentation Gaps in Failure Modes**
**Status:** ✅ Improved  
**Current State:** `docs/troubleshooting.md`, `sop/troubleshoot-tenant.md`, and incident playbooks now cover common failure modes.

**Remaining Watch Item:** Expand examples as real report evidence accumulates.

---

#### 6. **Monitoring Not Automated**
**Impact:** Medium  
**Current State:** monitor-health.md requires manual execution via OpenCode  
**Gap:**
- No cron job or scheduled health check
- No alerting threshold (how many failures trigger alert?)
- No metric export for dashboarding

**Fix Proposal:**

Create optional monitoring systemd timer:

```bash
# /etc/systemd/system/aaas-health-check.service
[Unit]
Description=AaaS Platform Health Check
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/aaas/platform/sop/monitor-health.sh
StandardOutput=append:/opt/aaas/platform/reports/health-monitor.log
StandardError=append:/opt/aaas/platform/reports/health-monitor.log

# /etc/systemd/system/aaas-health-check.timer
[Unit]
Description=Run AaaS health check hourly

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target

# Enable:
sudo systemctl enable aaas-health-check.timer
sudo systemctl start aaas-health-check.timer
```

---

#### 7. **Dependency Validation Before Major Operations**
**Status:** ✅ Implemented  
**Current State:** `/opt/aaas/platform/scripts/preflight-check.sh` is managed by setup and referenced by major SOPs.

**Remaining Watch Item:** Add operation-specific checks if build, upgrade, or troubleshooting reports reveal repeated missing prerequisites.

---

#### 8. **Config Version Management**
**Status:** ✅ Improved  
**Current State:** `/opt/aaas/platform/scripts/validate-tenant-config.sh` validates required tenant config and harness fields before risky operations.

**Remaining Watch Item:** Add migration logic if `_config_version` or `tenant_harness_version` changes.

---

#### 9. **Task Report INDEX Querying**
**Status:** ✅ Improved  
**Current State:** `/opt/aaas/platform/scripts/analyze-reports.sh` summarizes recent issues, improvement signals, partial/failed SOPs, and next actions.

**Remaining Watch Item:** Consider scheduled summaries only after there is enough report volume.

---

#### 10. **Incident Response Runbooks**
**Status:** ✅ Implemented  
**Current State:** `/opt/aaas/platform/incidents/` includes playbooks for all-tenants connectivity, Docker version issues, Telegram API changes, Mnemosyne seed issues, and platform backup recovery.

**Remaining Watch Item:** Add playbooks when new incident classes appear in reports.

---

### 🟡 LOW-PRIORITY IMPROVEMENTS

#### 11. **No Tenant Pagination in monitor-health.md**
**Impact:** Low (scales at ~100s of tenants)  
**Gap:** If 1000+ tenants exist, looping in step 3 could take minutes  
**Fix:** Add batch processing or async health checks for large deployments  

---

#### 12. **SOUL.md Not Syntax-Checked**
**Impact:** Low  
**Gap:** Agent could have typos in SOUL.md; not caught until runtime  
**Fix:** Add optional lint check in harness validator (warn on missing brand recall keywords)  

---

#### 13. **Template Vertical Expansion Incomplete**
**Impact:** Low (existing deployment works, new verticals blocked)  
**Current:** fnb has full templates; retail/services directories exist but empty  
**Fix:** (Covered in improvement area 4)  

---

## WORKING WELL - DON'T CHANGE

1. ✅ **Harness validation is deterministic** — no flaky network calls in check-tenant.sh
2. ✅ **Task reports capture improvement signals** — not just success/fail; enables platform evolution
3. ✅ **Checklist gates prevent incomplete operations** — operators must acknowledge each step
4. ✅ **Versioned platform upgrades** — backups stored, incremental updates safe
5. ✅ **Mnemosyne integration** — strong privacy model (no native Hermes memory leakage)
6. ✅ **Config constraints enforced** — SOUL.md patterns validated, secrets split from config
7. ✅ **Telegram UX** — chat_id empty until first message, user isolation by ALLOWED_USERS
8. ✅ **Offboard confirmation** — requires typed tenant ID to delete data; excellent safety
9. ✅ **Connectivity testing** — ping + curl before declaring tenant ready (catches iptables issues early)
10. ✅ **Operator-assisted eval profiles** — not automated; intentional human verification step

---

## PRIORITY IMPLEMENTATION ORDER

For building this on other platforms or extending:

1. **High (implement next):**
   - Expand eval profiles to additional verticals when those verticals are in product scope
   - Add optional monitoring timers after manual health reports stabilize

2. **Medium (nice to have):**
   - Add migration logic for future config/harness versions
   - Add scheduled report analysis once report volume justifies it

3. **Low (polish):**
   - Tenant pagination (area 11)
   - SOUL.md linting (area 12)
   - Template vertical expansion (area 13)

---

## IMPLEMENTED RECOVERY ASSETS

Use the managed platform files instead of copying snippets from this review:

- Bootstrap iptables enforcement: `scripts/setup-prerequisites.sh`
- Platform pre-flight: `platform/scripts/preflight-check.sh`
- Tenant config validation: `platform/scripts/validate-tenant-config.sh`
- Report analysis: `platform/scripts/analyze-reports.sh`
- Tenant troubleshooting: `platform/sop/troubleshoot-tenant.md`
- Incident playbooks: `platform/incidents/`

---

## CONCLUSION

The AaaS Platform is **production-ready** with strong harness engineering foundations. The platform moves beyond "container orchestration" to prove **tenant benefit** through deterministic validation, structured memory seeding, and multi-layer verification.

**Key wins:**
- Harness engineering provides operator confidence in tenant quality
- Task reports enable platform learning without manual log review
- SOP checklists enforce completeness; no skipped steps
- iptables issue identified and mitigated comprehensively

**Top 3 recommended fixes** (highest impact/effort ratio):
1. Expand eval profiles when non-F&B verticals become active
2. Add optional scheduled health monitoring after manual health checks settle
3. Use report analysis output to decide the next SOP or script improvement

**Next phase:** Automation of health monitoring (optional), report-driven platform improvements (medium complexity), and incident playbooks (operational maturity).

---

**Document prepared for:** Cross-team review and knowledge transfer to other AI models  
**Recommended sharing:** Copy sections 1-4 for design understanding; sections on improvement areas are self-contained and can be shared to AI models for implementation
