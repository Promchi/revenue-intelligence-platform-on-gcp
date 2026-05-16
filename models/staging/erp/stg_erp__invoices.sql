with source as (
    select * from {{ source('erp', 'invoices') }}
),

cleaned as (
    select
        -- primary key
        invoice_id,

        -- foreign keys
        subscription_id,
        account_id,

        -- financials
        cast(amount_due as numeric)  as amount_due,
        cast(amount_paid as numeric) as amount_paid,

        -- dates
        cast(due_date as date)  as due_date,
        cast(paid_date as date) as paid_date,

        -- attributes
        lower(trim(payment_status)) as payment_status,

        -- dirty data flags
        case
            when lower(trim(payment_status)) in ('overdue', 'unpaid')
            and amount_paid is null then true
            else false
        end as is_payment_null,

        -- derived
        case
            when lower(trim(payment_status)) = 'paid' then true
            else false
        end as is_paid,

        case
            when lower(trim(payment_status)) = 'overdue' then true
            else false
        end as is_overdue,

        -- outstanding balance
        case
            when amount_paid is not null
            then round(cast(amount_due as numeric) - cast(amount_paid as numeric), 2)
            else cast(amount_due as numeric)
        end as outstanding_amount,

        -- days overdue
        case
            when lower(trim(payment_status)) = 'overdue'
            then date_diff(current_date(), cast(due_date as date), day)
            else 0
        end as days_overdue

    from source
)

select * from cleaned
