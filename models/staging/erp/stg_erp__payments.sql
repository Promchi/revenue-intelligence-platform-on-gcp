with source as (
    select * from {{ source('erp', 'payments') }}
),

cleaned as (
    select
        -- primary key
        payment_id,

        -- foreign keys
        invoice_id,
        account_id,

        -- attributes
        lower(trim(payment_method))  as payment_method,
        lower(trim(payment_status))  as payment_status,
        failure_reason,
        gateway_ref,

        -- financials
        cast(amount as numeric) as amount,

        -- numerics
        cast(retry_count as int64) as retry_count,

        -- dates
        cast(payment_date as date)    as payment_date,
        cast(created_at as timestamp) as created_at,

        -- dirty data flags
        case
            when lower(trim(payment_status)) = 'successful'
            and payment_date is null then true
            else false
        end as is_payment_date_missing,

        -- derived
        case
            when lower(trim(payment_status)) = 'successful' then true
            else false
        end as is_successful,

        case
            when lower(trim(payment_status)) = 'failed' then true
            else false
        end as is_failed,

        case
            when cast(retry_count as int64) >= 2 then true
            else false
        end as is_repeat_failure

    from source
)

select * from cleaned
