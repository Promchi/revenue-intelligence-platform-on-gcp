with source as (
    select * from {{ source('crm', 'leads') }}
),

cleaned as (
    select
        -- primary key
        lead_id,

        -- foreign keys
        contact_id,
        campaign_id,

        -- attributes
        lower(trim(lead_source))  as lead_source,
        lower(trim(status))       as lead_status,
        assigned_rep,

        -- timestamps
        cast(created_at as timestamp)    as created_at,
        cast(converted_at as timestamp)  as converted_at,

        -- dirty data flags
        case
            when lower(trim(status)) = 'converted'
            and converted_at is null then true
            else false
        end as is_conversion_date_missing,

        -- derived
        case
            when lower(trim(status)) = 'converted' then true
            else false
        end as is_converted,

        case
            when converted_at is not null and created_at is not null
            then timestamp_diff(
                cast(converted_at as timestamp),
                cast(created_at as timestamp),
                day
            )
            else null
        end as days_to_convert

    from source
)

select * from cleaned
