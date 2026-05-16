with source as (
    select * from {{ source('crm', 'opportunities') }}
),

cleaned as (
    select
        -- primary key
        opportunity_id,

        -- foreign keys
        account_id,
        lead_id,

        -- attributes
        lower(trim(stage))     as stage,
        lower(trim(currency))  as currency,
        cast(amount as numeric)      as amount,
        cast(probability as float64) as probability,

        -- dates
        cast(close_date as date)      as close_date,
        cast(created_at as timestamp) as created_at,

        -- dirty data flags
        case
            when lower(trim(stage)) in ('closed won', 'closed lost')
            and close_date is null then true
            else false
        end as is_close_date_missing,

        -- derived
        case
            when lower(trim(stage)) = 'closed won'  then true
            else false
        end as is_won,

        case
            when lower(trim(stage)) = 'closed lost' then true
            else false
        end as is_lost,

        case
            when lower(trim(stage)) not in ('closed won', 'closed lost')
            then true
            else false
        end as is_open,

        -- weighted pipeline value
        round(
            cast(amount as numeric) * cast(probability as float64) / 100,
            2
        ) as weighted_amount

    from source
)

select * from cleaned
