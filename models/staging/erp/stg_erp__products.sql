with source as (
    select * from {{ source('erp', 'products') }}
),

cleaned as (
    select
        -- primary key
        product_id,

        -- attributes
        product_name,
        lower(trim(category))      as category,
        lower(trim(billing_type))  as billing_type,

        -- financials
        cast(unit_price as numeric) as unit_price,

        -- derived
        case
            when lower(trim(billing_type)) = 'subscription' then true
            else false
        end as is_recurring,

        case
            when cast(unit_price as numeric) >= 5000  then 'enterprise'
            when cast(unit_price as numeric) >= 500   then 'mid-market'
            else 'smb'
        end as price_tier

    from source
)

select * from cleaned
