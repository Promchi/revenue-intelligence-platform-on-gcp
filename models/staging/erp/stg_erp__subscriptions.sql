with source as (
    select * from {{ source('erp', 'subscriptions') }}
),

cleaned as (
    select
        -- primary key
        subscription_id,

        -- foreign keys
        account_id,
        product_id,
        opportunity_id,

        -- attributes
        lower(trim(status))         as subscription_status,
        lower(trim(billing_cycle))  as billing_cycle,

        -- financials
        cast(mrr as numeric) as mrr,

        -- dates
        cast(start_date as date) as start_date,
        cast(end_date as date)   as end_date,

        -- dirty data flags
        case
            when cast(end_date as date) < cast(start_date as date)
            then true
            else false
        end as is_date_inverted,

        -- derived
        case
            when lower(trim(status)) = 'active' then true
            else false
        end as is_active,

        case
            when lower(trim(status)) = 'churned' then true
            else false
        end as is_churned,

        -- annualized revenue
        round(cast(mrr as numeric) * 12, 2) as arr,

        -- subscription duration in days (only for valid date ranges)
        case
            when cast(end_date as date) >= cast(start_date as date)
            then date_diff(
                cast(end_date as date),
                cast(start_date as date),
                day
            )
            else null
        end as subscription_duration_days

    from source
)

select * from cleaned
