with source as (
    select * from {{ source('crm', 'contacts') }}
),

cleaned as (
    select
        -- primary key
        contact_id,

        -- foreign key
        account_id,

        -- attributes
        full_name,
        lower(trim(email))      as email,
        lower(trim(job_title))  as job_title,
        phone,

        -- metadata
        cast(created_at as timestamp) as created_at,

        -- dirty data flags
        case
            when account_id is null then true
            else false
        end as is_orphaned,

        -- derived
        case
            when lower(trim(job_title)) in (
                'ceo', 'cto', 'cfo', 'vp of sales',
                'head of operations', 'sales director'
            ) then true
            else false
        end as is_decision_maker

    from source
)

select * from cleaned
