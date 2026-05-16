with customer_health as (
    select * from {{ ref('int_customer_health') }}
),

payment_health as (
    select * from {{ ref('int_payment_health') }}
),

account_subscriptions as (
    select * from {{ ref('int_accounts_with_subscriptions') }}
),

-- join all signals into a single customer churn mart
joined as (
    select
        -- account identifiers
        ch.account_id,
        ch.account_name,
        ch.industry,
        ch.tier,
        ch.tier_rank,
        ch.account_status,
        ch.is_churned,

        -- revenue metrics
        ch.total_mrr,
        ch.total_arr,
        ch.active_subscriptions,
        s.total_subscriptions,
        s.churned_subscriptions,
        s.earliest_subscription_start,
        s.latest_subscription_start,
        s.avg_subscription_duration_days,

        -- billing health
        ch.collection_rate_pct,
        ch.payment_failure_rate_pct,
        ch.overdue_invoices,
        ch.repeat_failures,
        s.total_billed,
        s.total_collected,
        s.total_outstanding,
        s.max_days_overdue,

        -- payment health signals
        ph.payment_health_score,
        ph.payment_health_band,
        ph.consecutive_failure_count,
        ph.total_cumulative_failures,
        ph.most_recent_failure_reason,
        ph.latest_payment_date,
        ph.total_payments,
        ph.successful_payments,
        ph.failed_payments,

        -- support ticket signals
        ch.total_tickets,
        ch.high_priority_tickets,
        ch.low_csat_tickets,
        ch.escalated_tickets,
        ch.open_tickets,
        ch.avg_csat_score,
        ch.avg_resolution_hours,
        ch.latest_ticket_date,

        -- feature usage signals
        ch.distinct_features_used,
        ch.total_usage_count,
        ch.power_usage_days,
        ch.inactive_days,
        ch.latest_usage_date,
        ch.avg_session_duration_minutes,

        -- churn risk score and band from int_customer_health
        ch.churn_risk_score,
        ch.churn_risk_band,

        -- days since last engagement signals
        date_diff(current_date(), cast(ch.latest_ticket_date as date), day)   as days_since_last_ticket,
        date_diff(current_date(), cast(ch.latest_usage_date as date), day)    as days_since_last_usage,
        date_diff(current_date(), cast(ph.latest_payment_date as date), day)  as days_since_last_payment,

        -- revenue at risk — how much MRR is at risk based on churn band
        case
            when ch.churn_risk_band = 'critical' then ch.total_mrr
            when ch.churn_risk_band = 'high'     then round(ch.total_mrr * 0.75, 2)
            when ch.churn_risk_band = 'medium'   then round(ch.total_mrr * 0.40, 2)
            else 0
        end as mrr_at_risk,

        case
            when ch.churn_risk_band = 'critical' then ch.total_arr
            when ch.churn_risk_band = 'high'     then round(ch.total_arr * 0.75, 2)
            when ch.churn_risk_band = 'medium'   then round(ch.total_arr * 0.40, 2)
            else 0
        end as arr_at_risk,

        -- recommended action based on risk band
        case
            when ch.churn_risk_band = 'critical' then 'Immediate intervention — assign CSM, escalate to leadership'
            when ch.churn_risk_band = 'high'     then 'Urgent outreach — schedule executive business review'
            when ch.churn_risk_band = 'medium'   then 'Proactive check-in — review feature adoption and resolve tickets'
            else 'Monitor — maintain regular cadence'
        end as recommended_action,

        -- record metadata
        current_timestamp() as mart_updated_at

    from customer_health ch
    left join payment_health ph       on ch.account_id = ph.account_id
    left join account_subscriptions s on ch.account_id = s.account_id
)

select * from joined
