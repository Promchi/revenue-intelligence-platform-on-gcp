with account_subscriptions as (
    select * from {{ ref('int_accounts_with_subscriptions') }}
),

payment_health as (
    select * from {{ ref('int_payment_health') }}
),

-- monthly mrr snapshot per account
-- uses account subscription data to build revenue timeline
monthly_revenue as (
    select
        account_id,
        account_name,
        industry,
        country,
        tier,
        tier_rank,
        account_status,
        is_churned,
        created_at,

        -- subscription revenue
        total_subscriptions,
        active_subscriptions,
        churned_subscriptions,
        total_mrr,
        total_arr,
        earliest_subscription_start,
        latest_subscription_start,
        avg_subscription_duration_days,

        -- billing metrics
        total_invoices,
        paid_invoices,
        overdue_invoices,
        total_billed,
        total_collected,
        total_outstanding,
        max_days_overdue,
        collection_rate_pct,
        payment_failure_rate_pct,

        -- payment transaction metrics
        total_payments,
        successful_payments,
        failed_payments,
        repeat_failures,
        total_payment_amount

    from account_subscriptions
),

-- join payment health for complete revenue picture
joined as (
    select
        mr.*,

        -- payment health enrichment
        ph.payment_health_score,
        ph.payment_health_band,
        ph.consecutive_failure_count,
        ph.total_cumulative_failures,
        ph.most_recent_failure_reason,
        ph.latest_payment_date,
        ph.first_payment_date,
        ph.avg_payment_amount,
        ph.consecutive_failure_count     as consec_failures,

        -- revenue health classification
        case
            when mr.active_subscriptions = 0             then 'no_revenue'
            when mr.collection_rate_pct >= 90
            and ph.payment_health_band = 'healthy'       then 'healthy'
            when mr.collection_rate_pct >= 70
            and ph.payment_health_band in (
                'healthy', 'at_risk')                    then 'stable'
            when mr.collection_rate_pct >= 50
            or ph.payment_health_band = 'at_risk'        then 'at_risk'
            else                                              'critical'
        end as revenue_health_band,

        -- annualised revenue at risk
        case
            when mr.collection_rate_pct < 50
            then mr.total_arr
            when mr.collection_rate_pct < 70
            then round(mr.total_arr * 0.50, 2)
            when mr.collection_rate_pct < 90
            then round(mr.total_arr * 0.20, 2)
            else 0
        end as arr_at_risk,

        -- net revenue (collected minus outstanding)
        round(
            cast(mr.total_collected as numeric) -
            cast(mr.total_outstanding as numeric)
        , 2) as net_revenue,

        -- outstanding as pct of total billed
        case
            when mr.total_billed > 0
            then round(
                cast(mr.total_outstanding as numeric) /
                nullif(cast(mr.total_billed as numeric), 0) * 100
            , 2)
            else 0
        end as outstanding_pct,

        -- customer lifetime value estimate (MRR * avg subscription duration in months)
        case
            when mr.avg_subscription_duration_days > 0
            then round(
                cast(mr.total_mrr as numeric) *
                (mr.avg_subscription_duration_days / 30.0)
            , 2)
            else 0
        end as estimated_clv,

        -- days since first subscription (customer tenure)
        date_diff(
            current_date(),
            mr.earliest_subscription_start,
            day
        ) as customer_tenure_days,

        -- days since last subscription started
        date_diff(
            current_date(),
            mr.latest_subscription_start,
            day
        ) as days_since_latest_subscription,

        -- expansion flag: multiple subscriptions started at different times
        case
            when mr.total_subscriptions > 1
            and mr.earliest_subscription_start != mr.latest_subscription_start
            then true
            else false
        end as has_expanded,

        -- contraction flag: churned subscriptions exist alongside active ones
        case
            when mr.churned_subscriptions > 0
            and mr.active_subscriptions > 0
            then true
            else false
        end as has_contracted,

        -- record metadata
        current_timestamp() as mart_updated_at

    from monthly_revenue mr
    left join payment_health ph on mr.account_id = ph.account_id
)

select * from joined
