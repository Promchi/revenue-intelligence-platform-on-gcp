with source as (
    select * from {{ source('crm', 'accounts') }}
),

cleaned as (
    select
        -- primary key
        account_id,

        -- attributes
        account_name,
        lower(trim(industry))        as industry,
        lower(trim(country))         as country,
        lower(trim(account_status))  as account_status,
        lower(trim(tier))            as tier,
        cast(employee_count as int64) as employee_count,

        -- metadata
        cast(created_at as timestamp) as created_at,

        -- derived flags
        case
            when lower(trim(account_status)) = 'churned' then true
            else false
        end as is_churned,

        case
            when lower(trim(tier)) = 'enterprise' then 3
            when lower(trim(tier)) = 'growth'     then 2
            when lower(trim(tier)) = 'starter'    then 1
            else 0
        end as tier_rank

    from source
)

select * from cleaned
