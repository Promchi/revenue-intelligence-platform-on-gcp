with source as (
    select * from {{ source('crm', 'support_tickets') }}
),

cleaned as (
    select
        -- primary key
        ticket_id,

        -- foreign keys
        account_id,
        contact_id,

        -- attributes
        lower(trim(category))  as category,
        lower(trim(priority))  as priority,
        lower(trim(status))    as ticket_status,
        agent,

        -- numerics
        cast(csat_score as int64)             as csat_score,
        cast(first_response_hours as float64) as first_response_hours,

        -- timestamps
        cast(created_at as timestamp)   as created_at,
        cast(resolved_at as timestamp)  as resolved_at,

        -- dirty data flags
        case
            when lower(trim(status)) in ('resolved', 'closed')
            and csat_score is null then true
            else false
        end as is_csat_missing,

        -- derived
        case
            when csat_score is not null
            and csat_score <= 2 then true
            else false
        end as is_low_csat,

        case
            when lower(trim(priority)) in ('high', 'critical') then true
            else false
        end as is_high_priority,

        case
            when resolved_at is not null and created_at is not null
            then timestamp_diff(
                cast(resolved_at as timestamp),
                cast(created_at as timestamp),
                hour
            )
            else null
        end as resolution_hours

    from source
)

select * from cleaned
