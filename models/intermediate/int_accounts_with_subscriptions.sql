with accounts as (
    select * from {{ ref('stg_crm__accounts') }}
),

subscriptions as (
    select * from {{ ref('stg_erp__subscriptions') }}
    where is_date_inverted = false  -- exclude dirty data
),

invoices as (
    select * from {{ ref('stg_erp__invoices') }}
),

payments as (
    select * from {{ ref('stg_erp__payments') }}
),

-- aggregate subscription metrics per account
account_subscriptions as (
    select
        account_id,
        count(subscription_id)                    as total_subscriptions,
        countif(is_active)                        as active_subscriptions,
        countif(is_churned)                       as churned_subscriptions,
        round(sum(cast(mrr as numeric)), 2)       as total_mrr,
        round(sum(cast(arr as numeric)), 2)       as total_arr,
        max(start_date)                           as latest_subscription_start,
        min(start_date)                           as earliest_subscription_start,
        avg(subscription_duration_days)           as avg_subscription_duration_days
    from subscriptions
    where account_id is not null
    group by account_id
),

-- aggregate invoice metrics per account
account_invoices as (
    select
        account_id,
        count(invoice_id)                         as total_invoices,
        countif(is_paid)                          as paid_invoices,
        countif(is_overdue)                       as overdue_invoices,
        round(sum(cast(amount_due as numeric)), 2)                    as total_billed,
        round(sum(coalesce(cast(amount_paid as numeric), 0)), 2)      as total_collected,
        round(sum(cast(outstanding_amount as numeric)), 2)            as total_outstanding,
        max(days_overdue)                         as max_days_overdue
    from invoices
    where account_id is not null
    group by account_id
),

-- aggregate payment metrics per account
account_payments as (
    select
        account_id,
        count(payment_id)                         as total_payments,
        countif(is_successful)                    as successful_payments,
        countif(is_failed)                        as failed_payments,
        countif(is_repeat_failure)                as repeat_failures,
        round(sum(case when is_successful then 
            cast(amount as numeric) else 0 end), 2)   as total_payment_amount
    from payments
    where account_id is not null
    group by account_id
),

-- join everything to accounts
joined as (
    select
        a.account_id,
        a.account_name,
        a.industry,
        a.country,
        a.account_status,
        a.tier,
        a.tier_rank,
        a.is_churned,
        a.created_at,

        -- subscription metrics
        coalesce(s.total_subscriptions, 0)        as total_subscriptions,
        coalesce(s.active_subscriptions, 0)       as active_subscriptions,
        coalesce(s.churned_subscriptions, 0)      as churned_subscriptions,
        coalesce(s.total_mrr, 0)                  as total_mrr,
        coalesce(s.total_arr, 0)                  as total_arr,
        s.latest_subscription_start,
        s.earliest_subscription_start,
        coalesce(s.avg_subscription_duration_days, 0) as avg_subscription_duration_days,

        -- invoice metrics
        coalesce(i.total_invoices, 0)             as total_invoices,
        coalesce(i.paid_invoices, 0)              as paid_invoices,
        coalesce(i.overdue_invoices, 0)           as overdue_invoices,
        coalesce(i.total_billed, 0)               as total_billed,
        coalesce(i.total_collected, 0)            as total_collected,
        coalesce(i.total_outstanding, 0)          as total_outstanding,
        coalesce(i.max_days_overdue, 0)           as max_days_overdue,

        -- payment metrics
        coalesce(p.total_payments, 0)             as total_payments,
        coalesce(p.successful_payments, 0)        as successful_payments,
        coalesce(p.failed_payments, 0)            as failed_payments,
        coalesce(p.repeat_failures, 0)            as repeat_failures,
        coalesce(p.total_payment_amount, 0)       as total_payment_amount,

        -- derived financial health
        case
            when coalesce(i.total_billed, 0) > 0
            then round(
                cast(coalesce(i.total_collected, 0) as numeric) / 
                cast(i.total_billed as numeric) * 100, 2)
            else 0
        end as collection_rate_pct,

        case
            when coalesce(p.total_payments, 0) > 0
            then round(
                coalesce(p.failed_payments, 0) / p.total_payments * 100, 2
            )
            else 0
        end as payment_failure_rate_pct

    from accounts a
    left join account_subscriptions s on a.account_id = s.account_id
    left join account_invoices i      on a.account_id = i.account_id
    left join account_payments p      on a.account_id = p.account_id
)

select * from joined
