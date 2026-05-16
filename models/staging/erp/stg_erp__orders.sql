with source as (
    select * from {{ source('erp', 'orders') }}
),

cleaned as (
    select
        -- primary key
        order_id,

        -- foreign keys
        account_id,
        product_id,
        opportunity_id,

        -- attributes
        lower(trim(order_status))  as order_status,

        -- financials
        cast(quantity as int64)      as quantity,
        cast(unit_price as numeric)  as unit_price,
        cast(total_amount as numeric) as total_amount,

        -- dates
        cast(order_date as date) as order_date,

        -- dirty data flags
        case
            when cast(unit_price as numeric) < 0 then true
            else false
        end as is_refund,

        -- derived
        case
            when lower(trim(order_status)) = 'completed' then true
            else false
        end as is_completed,

        case
            when lower(trim(order_status)) = 'cancelled' then true
            else false
        end as is_cancelled,

        -- clean revenue (exclude refunds and cancellations)
        case
            when lower(trim(order_status)) = 'completed'
            and cast(unit_price as numeric) > 0
            then cast(total_amount as numeric)
            else 0
        end as recognised_revenue

    from source
)

select * from cleaned
