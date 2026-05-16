with source as (
    select * from {{ source('web', 'web_events') }}
),

cleaned as (
    select
        -- primary key
        event_id,

        -- foreign key
        contact_id,

        -- attributes
        lower(trim(event_type))    as event_type,
        page_url,
        session_id,

        -- fix utm casing inconsistency (google/Google/GOOGLE → google)
        lower(trim(utm_source))    as utm_source,
        lower(trim(utm_campaign))  as utm_campaign,

        -- timestamps
        cast(event_timestamp as timestamp) as event_timestamp,

        -- derived date parts for aggregation
        date(cast(event_timestamp as timestamp))                    as event_date,
        extract(hour from cast(event_timestamp as timestamp))       as event_hour,
        format_date('%Y-%m', date(cast(event_timestamp as timestamp))) as event_month,

        -- derived flags
        case
            when lower(trim(event_type)) = 'page_view' then true
            else false
        end as is_page_view,

        case
            when lower(trim(event_type)) in (
                'demo_request', 'form_submit'
            ) then true
            else false
        end as is_conversion_event,

        case
            when lower(trim(page_url)) = '/pricing' then true
            else false
        end as is_pricing_page

    from source
)

select * from cleaned
