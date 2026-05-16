# Revenue Intelligence Platform on GCP

An end-to-end analytics platform that unifies **CRM, ERP, and product-usage data** into a layered **dbt + BigQuery** warehouse and surfaces three executive dashboards in **Looker Studio**: Customer Churn, Revenue Health, and Sales Funnel.

The platform answers the questions a revenue team actually cares about every Monday morning:

- *Which accounts are most likely to churn, and how much revenue is at risk?*
- *How healthy is our revenue today — what's collected, what's outstanding, what's at risk?*
- *Where are leads falling out of the funnel, and which campaigns are returning real revenue?*

## Live dashboards

**[Open the live Looker Studio report](https://datastudio.google.com/reporting/c5270921-d001-40d0-8e88-46d3bea81199)**

### Customer Churn Dashboard

![Customer Churn Dashboard](images/customer_churn_dashboard.png)

Tracks 496 accounts across CSAT, support tickets, feature-usage decay, and payment failures to produce a single **churn risk score** and band per account. The dashboard surfaces the 166 accounts at risk, ranks the ~£2.6m MRR / £31.2m ARR exposed to churn, and pairs every account with a **recommended action** (immediate intervention, executive business review, proactive check-in, or monitor).

### Revenue Health Dashboard

![Revenue Health Dashboard](images/revenue_health_dashboard.png)

A finance-grade view of the book of business: £5.7m MRR / £68.1m ARR across 500 accounts, with a 69.6% collection rate and £18.2m outstanding. Accounts are classified into **revenue health bands** (Healthy, Stable, At Risk, Critical, No Revenue) by combining collection rate and payment health, with an **Estimated CLV** computed per account from MRR and average subscription duration.

### Sales Funnel Dashboard

![Sales Funnel Dashboard](images/sales_funnel_dashboard.png)

Lead-to-close visibility across 3,000 leads, 240 closed-won deals, and £32.4m in closed-won revenue. Tracks lead volume by funnel stage, monthly lead creation seasonality, **average days to close (399.9)**, and **revenue per £ spent (£12.39)** — broken down by lead source, channel, and campaign so marketing knows what's actually paying back.

## Architecture

```
                    ┌────────────────────────────────────────────┐
                    │            Raw data (BigQuery)             │
                    │   CRM   ·   ERP   ·   Web / product usage  │
                    └─────────────────────┬──────────────────────┘
                                          │
                                  dbt sources.yml
                                          │
                    ┌─────────────────────▼──────────────────────┐
                    │            staging (views)                 │
                    │   stg_crm__*  ·  stg_erp__*  ·  stg_web__* │
                    │   typed, cleaned, renamed                  │
                    └─────────────────────┬──────────────────────┘
                                          │
                    ┌─────────────────────▼──────────────────────┐
                    │           intermediate (views)             │
                    │   int_customer_health                      │
                    │   int_payment_health                       │
                    │   int_accounts_with_subscriptions          │
                    │   int_sales_activity                       │
                    │   int_leads_with_campaigns                 │
                    └─────────────────────┬──────────────────────┘
                                          │
                    ┌─────────────────────▼──────────────────────┐
                    │              marts (tables)                │
                    │   core/mart_customer_churn                 │
                    │   finance/mart_revenue                     │
                    │   marketing/mart_sales_funnel              │
                    └─────────────────────┬──────────────────────┘
                                          │
                    ┌─────────────────────▼──────────────────────┐
                    │   Looker Studio dashboards (3 reports)     │
                    └────────────────────────────────────────────┘
```

## Data sources

The platform ingests three source systems into the `raw` BigQuery schema:

| Source | Tables |
|---|---|
| **CRM** | accounts, contacts, leads, opportunities, campaigns, activities, support_tickets |
| **ERP** | products, orders, invoices, subscriptions, payments |
| **Web** | web_events, feature_usage |

## Model layers

**Staging (`models/staging/`)** — one model per source table, materialised as **views**. Renames columns to a consistent snake_case, casts types, and applies basic cleaning. Three subfolders: `crm/`, `erp/`, `web/`.

**Intermediate (`models/intermediate/`)** — business-logic building blocks, materialised as **views**:
- `int_accounts_with_subscriptions` — joins accounts to subscriptions, invoices, and payments to compute MRR, ARR, collection rate, and payment failure rate per account.
- `int_payment_health` — payment-level signals: consecutive failures, cumulative failures, payment health score and band.
- `int_customer_health` — account-level signals combining subscription, billing, support, and feature-usage data into a 0–100 **churn risk score** and band (critical / high / medium / low).
- `int_sales_activity` — opportunity-level engagement: call/meeting/demo/email counts, reps involved, positive-outcome rate, engagement quality.
- `int_leads_with_campaigns` — lead-to-opportunity-to-campaign join with attribution, budget utilisation, and conversion timing.

**Marts (`models/marts/`)** — analytics-ready tables consumed by Looker Studio:
- `core/mart_customer_churn` — one row per account with churn risk, MRR/ARR at risk, and recommended action.
- `finance/mart_revenue` — one row per account with revenue health band, ARR at risk, net revenue, outstanding %, and estimated CLV.
- `marketing/mart_sales_funnel` — one row per lead with funnel stage, deal velocity (days lead→close, convert→close), campaign spend, and revenue per £ spent.

## Tech stack

- **Warehouse:** Google BigQuery
- **Transformation:** dbt (data build tool) with `dbt_utils`
- **BI:** Looker Studio (formerly Google Data Studio)
- **Source control:** Git / GitHub

## Getting started

### Prerequisites

- Python 3.9+
- A Google Cloud project with BigQuery enabled
- A service-account key with BigQuery Data Editor + Job User roles
- dbt-bigquery installed: `pip install dbt-bigquery`

### Setup

```bash
# 1. Clone the repo
git clone https://github.com/Promchi/revenue-intelligence-platform-on-gcp.git
cd revenue-intelligence-platform-on-gcp

# 2. Install dbt packages (dbt_utils, etc.)
dbt deps

# 3. Configure your BigQuery connection in ~/.dbt/profiles.yml
#    Profile name must match: revenue_intelligence_platform

# 4. Test the connection
dbt debug

# 5. Build everything: staging → intermediate → marts
dbt build
```

### Example `profiles.yml`

```yaml
revenue_intelligence_platform:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: service-account
      project: your-gcp-project-id
      dataset: analytics_dev
      keyfile: /absolute/path/to/service-account-key.json
      threads: 4
      location: EU
```

## Project structure

```
revenue_intelligence_platform/
├── dbt_project.yml          # dbt project config + model materialisations
├── packages.yml             # dbt_utils dependency
├── models/
│   ├── staging/
│   │   ├── sources.yml      # raw source declarations
│   │   ├── schema.yml       # staging tests + docs
│   │   ├── crm/             # 7 staging models (accounts, leads, …)
│   │   ├── erp/             # 5 staging models (subscriptions, invoices, …)
│   │   └── web/             # 2 staging models (web_events, feature_usage)
│   ├── intermediate/
│   │   ├── schema.yml
│   │   └── int_*.sql        # 5 intermediate models
│   └── marts/
│       ├── schema.yml
│       ├── core/mart_customer_churn.sql
│       ├── finance/mart_revenue.sql
│       └── marketing/mart_sales_funnel.sql
├── seeds/                   # static reference data
├── snapshots/               # SCD2 history
├── tests/                   # singular tests
├── macros/                  # custom Jinja macros
├── analyses/                # ad-hoc analytical SQL
└── images/                  # dashboard screenshots used in this README
```

## Running selected models

```bash
# Run only staging models
dbt run --select staging

# Run only the marts and everything they depend on
dbt run --select +marts

# Run only finance-tagged models
dbt run --select tag:finance

# Run tests for the customer churn mart
dbt test --select mart_customer_churn
```

## License

This project is provided as-is for portfolio and educational purposes.
