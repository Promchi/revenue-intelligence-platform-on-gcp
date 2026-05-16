with accounts as (
    select * from {{ ref('stg_crm__accounts') }}
),

support_tickets as (
    select * from {{ ref('stg_crm__support_tickets') }}
    where account_id is not null
),

feature_usage as (
    select * from {{ ref('stg_web__feature_usage') }}
    where account_id is not null
    and is_date_missing = false
),

account_subscriptions as (
    select * from {{ ref('int_accounts_with_subscriptions') }}
),

-- aggregate support ticket metrics per account
ticket_metrics as (
    select
        account_id,
        count(ticket_id)                          as total_tickets,
        countif(is_high_priority)                 as high_priority_tickets,
        countif(is_low_csat)                      as low_csat_tickets,
        countif(ticket_status = 'escalated')      as escalated_tickets,
        countif(ticket_status = 'open')           as open_tickets,
        avg(case when csat_score is not null
            then csat_score end)                  as avg_csat_score,
        avg(resolution_hours)                     as avg_resolution_hours,
        avg(first_response_hours)                 as avg_first_response_hours,
        max(created_at)                           as latest_ticket_date
    from support_tickets
    group by account_id
),

-- aggregate feature usage metrics per account
usage_metrics as (
    select
        account_id,
        count(distinct feature_name)              as distinct_features_used,
        sum(usage_count)                          as total_usage_count,
        avg(usage_count)                          as avg_usage_count,
        countif(engagement_level = 'power')       as power_usage_days,
        countif(engagement_level = 'inactive')    as inactive_days,
        max(usage_date)                           as latest_usage_date,
        avg(session_duration_minutes)             as avg_session_duration_minutes
    from feature_usage
    group by account_id
),

-- join and score
joined as (
    select
        a.account_id,
        a.account_name,
        a.industry,
        a.tier,
        a.tier_rank,
        a.account_status,
        a.is_churned,

        -- subscription health from int_accounts_with_subscriptions
        round(cast(s.total_mrr as numeric), 2) as total_mrr,
        round(cast(s.total_arr as numeric), 2) as total_arr,
        s.active_subscriptions,
        s.collection_rate_pct,
        s.payment_failure_rate_pct,
        s.overdue_invoices,
        s.repeat_failures,

        -- support ticket signals
        coalesce(t.total_tickets, 0)              as total_tickets,
        coalesce(t.high_priority_tickets, 0)      as high_priority_tickets,
        coalesce(t.low_csat_tickets, 0)           as low_csat_tickets,
        coalesce(t.escalated_tickets, 0)          as escalated_tickets,
        coalesce(t.open_tickets, 0)               as open_tickets,
        t.avg_csat_score,
        t.avg_resolution_hours,
        t.latest_ticket_date,

        -- feature usage signals
        coalesce(u.distinct_features_used, 0)     as distinct_features_used,
        coalesce(u.total_usage_count, 0)          as total_usage_count,
        coalesce(u.power_usage_days, 0)           as power_usage_days,
        coalesce(u.inactive_days, 0)              as inactive_days,
        u.latest_usage_date,
        u.avg_session_duration_minutes,

        -- churn risk scoring (0-100, higher = more at risk)
        -- each signal contributes points toward churn risk
        round(
            -- payment health signals (max 35 points)
            least(s.payment_failure_rate_pct * 0.5, 15)
            + least(coalesce(s.overdue_invoices, 0) * 2, 10)
            + least(coalesce(s.repeat_failures, 0) * 5, 10)

            -- support signals (max 35 points)
            + least(coalesce(t.low_csat_tickets, 0) * 3, 15)
            + least(coalesce(t.high_priority_tickets, 0) * 2, 10)
            + least(coalesce(t.escalated_tickets, 0) * 5, 10)

            -- feature usage signals (max 30 points)
            + case
                when coalesce(u.total_usage_count, 0) = 0    then 30
                when coalesce(u.total_usage_count, 0) < 10   then 20
                when coalesce(u.total_usage_count, 0) < 50   then 10
                else 0
              end
        , 2) as churn_risk_score,

        -- churn risk band
        case
            when round(
                least(s.payment_failure_rate_pct * 0.5, 15)
                + least(coalesce(s.overdue_invoices, 0) * 2, 10)
                + least(coalesce(s.repeat_failures, 0) * 5, 10)
                + least(coalesce(t.low_csat_tickets, 0) * 3, 15)
                + least(coalesce(t.high_priority_tickets, 0) * 2, 10)
                + least(coalesce(t.escalated_tickets, 0) * 5, 10)
                + case
                    when coalesce(u.total_usage_count, 0) = 0  then 30
                    when coalesce(u.total_usage_count, 0) < 10 then 20
                    when coalesce(u.total_usage_count, 0) < 50 then 10
                    else 0
                  end
            , 2) >= 60 then 'critical'
            when round(
                least(s.payment_failure_rate_pct * 0.5, 15)
                + least(coalesce(s.overdue_invoices, 0) * 2, 10)
                + least(coalesce(s.repeat_failures, 0) * 5, 10)
                + least(coalesce(t.low_csat_tickets, 0) * 3, 15)
                + least(coalesce(t.high_priority_tickets, 0) * 2, 10)
                + least(coalesce(t.escalated_tickets, 0) * 5, 10)
                + case
                    when coalesce(u.total_usage_count, 0) = 0  then 30
                    when coalesce(u.total_usage_count, 0) < 10 then 20
                    when coalesce(u.total_usage_count, 0) < 50 then 10
                    else 0
                  end
            , 2) >= 40 then 'high'
            when round(
                least(s.payment_failure_rate_pct * 0.5, 15)
                + least(coalesce(s.overdue_invoices, 0) * 2, 10)
                + least(coalesce(s.repeat_failures, 0) * 5, 10)
                + least(coalesce(t.low_csat_tickets, 0) * 3, 15)
                + least(coalesce(t.high_priority_tickets, 0) * 2, 10)
                + least(coalesce(t.escalated_tickets, 0) * 5, 10)
                + case
                    when coalesce(u.total_usage_count, 0) = 0  then 30
                    when coalesce(u.total_usage_count, 0) < 10 then 20
                    when coalesce(u.total_usage_count, 0) < 50 then 10
                    else 0
                  end
            , 2) >= 20 then 'medium'
            else 'low'
        end as churn_risk_band

    from accounts a
    left join account_subscriptions s on a.account_id = s.account_id
    left join ticket_metrics t        on a.account_id = t.account_id
    left join usage_metrics u         on a.account_id = u.account_id
)

select * from joined
