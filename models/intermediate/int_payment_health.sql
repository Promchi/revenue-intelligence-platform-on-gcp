with payments as (
    select * from {{ ref('stg_erp__payments') }}
    where account_id is not null
),

invoices as (
    select * from {{ ref('stg_erp__invoices') }}
    where account_id is not null
),

-- payment timeline per account
payment_timeline as (
    select
        account_id,
        payment_id,
        invoice_id,
        payment_method,
        payment_status,
        amount,
        payment_date,
        is_successful,
        is_failed,
        is_repeat_failure,
        failure_reason,
        retry_count,
        created_at,

        -- row number per account ordered by date
        row_number() over (
            partition by account_id
            order by created_at asc
        ) as payment_sequence,

        -- running total of failures per account
        sum(case when is_failed then 1 else 0 end) over (
            partition by account_id
            order by created_at asc
            rows between unbounded preceding and current row
        ) as cumulative_failures,

        -- consecutive failure flag
        -- checks if previous payment was also failed
        lag(is_failed) over (
            partition by account_id
            order by created_at asc
        ) as prev_payment_failed

    from payments
),

-- aggregate payment health per account
account_payment_health as (
    select
        account_id,
        count(payment_id)                         as total_payments,
        countif(is_successful)                    as successful_payments,
        countif(is_failed)                        as failed_payments,
        countif(is_repeat_failure)                as repeat_failures,
        max(cumulative_failures)                  as total_cumulative_failures,
        round(sum(case when is_successful
            then cast(amount as numeric) else 0 end), 2)  as total_collected,
        round(avg(case when is_successful
            then cast(amount as numeric) end), 2)         as avg_payment_amount,
        max(payment_date)                         as latest_payment_date,
        min(payment_date)                         as first_payment_date,

        -- consecutive failure indicator
        countif(is_failed = true
            and prev_payment_failed = true)       as consecutive_failure_count,

        -- most common failure reason
        max(failure_reason)                       as most_recent_failure_reason

    from payment_timeline
    group by account_id
),

-- join with invoice data for complete picture
joined as (
    select
        aph.*,

        -- invoice context
        inv.total_invoices,
        inv.overdue_invoices,
        round(cast(inv.total_billed as numeric), 2)      as total_billed,
        round(cast(inv.total_outstanding as numeric), 2) as total_outstanding,
        inv.max_days_overdue,

        -- payment health score (0-100, higher = healthier)
        round(
            100
            - least(cast(aph.failed_payments as numeric) * 5, 30)
            - least(cast(aph.consecutive_failure_count as numeric) * 10, 30)
            - least(cast(inv.overdue_invoices as numeric) * 3, 20)
            - least(cast(inv.max_days_overdue as numeric) * 0.5, 20)
        , 2) as payment_health_score,

        -- payment health band
        case
            when aph.consecutive_failure_count >= 3  then 'critical'
            when aph.failed_payments >= 5            then 'poor'
            when aph.failed_payments >= 2            then 'at_risk'
            else 'healthy'
        end as payment_health_band

    from account_payment_health aph
    left join (
        select
            account_id,
            count(invoice_id)        as total_invoices,
            countif(is_overdue)      as overdue_invoices,
            sum(amount_due)          as total_billed,
            sum(outstanding_amount)  as total_outstanding,
            max(days_overdue)        as max_days_overdue
        from invoices
        group by account_id
    ) inv on aph.account_id = inv.account_id
)

select * from joined
