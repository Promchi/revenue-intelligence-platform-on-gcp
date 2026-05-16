with source as (
    select * from {{ source('crm', 'activities') }}
),

cleaned as (
    select
        -- primary key
        activity_id,

        -- foreign keys
        contact_id,
        opportunity_id,
        account_id,

        -- attributes
        lower(trim(activity_type))  as activity_type,
        lower(trim(outcome))        as outcome,
        assigned_rep,
        notes,

        -- numerics
        cast(duration_minutes as int64) as duration_minutes,

        -- dates
        cast(activity_date as date)   as activity_date,
        cast(created_at as timestamp) as created_at,

        -- dirty data flags
        case
            when activity_date is null then true
            else false
        end as is_date_missing,

        -- derived
        case
            when lower(trim(outcome)) in (
                'meeting booked', 'interested', 'sent', 'opened'
            ) then true
            else false
        end as is_positive_outcome,

        case
            when lower(trim(activity_type)) in ('call', 'meeting', 'demo')
            then true
            else false
        end as is_high_touch

    from source
)

select * from cleaned
