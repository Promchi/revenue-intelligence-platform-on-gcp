with source as (
    select * from {{ source('crm', 'campaigns') }}
),

cleaned as (
    select
        -- primary key
        campaign_id,

        -- attributes
        campaign_name,
        lower(trim(campaign_type))  as campaign_type,
        lower(trim(status))         as campaign_status,
        lower(trim(channel))        as channel,
        owner,

        -- financials
        cast(budget as numeric)       as budget,
        cast(actual_spend as numeric) as actual_spend,
        cast(target_leads as int64)   as target_leads,

        -- dates
        cast(start_date as date) as start_date,
        cast(end_date as date)   as end_date,

        -- dirty data flags
        case
            when actual_spend is null then true
            else false
        end as is_spend_missing,

        -- derived
        case
            when actual_spend is not null and budget > 0
            then round(cast(actual_spend as numeric) / cast(budget as numeric) * 100, 2)
            else null
        end as budget_utilisation_pct,

        case
            when cast(end_date as date) < current_date() then true
            else false
        end as is_completed

    from source
)

select * from cleaned
