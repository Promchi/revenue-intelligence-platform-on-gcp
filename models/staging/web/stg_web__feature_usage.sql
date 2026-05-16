with source as (
    select * from {{ source('web', 'feature_usage') }}
),

cleaned as (
    select
        -- primary key
        usage_id,

        -- foreign keys
        account_id,
        contact_id,

        -- attributes
        lower(trim(feature_name))  as feature_name,
        lower(trim(device_type))   as device_type,

        -- numerics
        cast(usage_count as int64)              as usage_count,
        cast(session_duration_seconds as int64) as session_duration_seconds,

        -- dates
        cast(usage_date as date)      as usage_date,
        cast(created_at as timestamp) as created_at,

        -- dirty data flags
        case
            when usage_date is null then true
            else false
        end as is_date_missing,

        -- derived
        case
            when cast(usage_count as int64) = 0 then true
            else false
        end as is_zero_usage,

        -- engagement level
        case
            when cast(usage_count as int64) >= 100 then 'power'
            when cast(usage_count as int64) >= 20  then 'regular'
            when cast(usage_count as int64) >= 1   then 'light'
            else 'inactive'
        end as engagement_level,

        -- session duration in minutes
        case
            when session_duration_seconds is not null
            then round(cast(session_duration_seconds as int64) / 60, 2)
            else null
        end as session_duration_minutes

    from source
)

select * from cleaned
