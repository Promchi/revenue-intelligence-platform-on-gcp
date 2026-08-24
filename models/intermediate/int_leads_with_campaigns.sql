with leads as (
    select * from {{ ref('stg_crm__leads') }}
),

campaigns as (
    select * from {{ ref('stg_crm__campaigns') }}
),

opportunities as (
    select * from {{ ref('stg_crm__opportunities') }}
),

contacts as (
    select
        contact_id,
        account_id,
        is_decision_maker
    from {{ ref('stg_crm__contacts') }}
    where is_orphaned = false
),

-- join leads to campaigns
leads_with_campaigns as (
    select
        l.lead_id,
        l.contact_id,
        l.campaign_id,
        l.lead_source,
        l.lead_status,
        l.assigned_rep,
        l.created_at                              as lead_created_at,
        l.converted_at,
        l.is_converted,
        l.is_conversion_date_missing,
        l.days_to_convert,

        -- campaign attribution
        c.campaign_name,
        c.campaign_type,
        c.campaign_status,
        c.channel,
        round(cast(c.budget as numeric), 2)       as budget,
        round(cast(c.actual_spend as numeric), 2) as actual_spend,
        c.budget_utilisation_pct,
        c.is_spend_missing,

        -- contact context
        ct.account_id,
        ct.is_decision_maker

    from leads l
    left join campaigns c  on l.campaign_id  = c.campaign_id
    left join contacts ct  on l.contact_id   = ct.contact_id
),

deduped_opportunities as (
    select *
    from (
        select *,
            row_number() over (
                partition by lead_id
                order by
                    case stage
                        when 'closed won'    then 1
                        when 'negotiation'   then 2
                        when 'proposal'      then 3
                        when 'qualification' then 4
                        when 'prospecting'   then 5
                        when 'closed lost'   then 6
                        else 7
                    end asc,
                    amount desc
            ) as rn
        from opportunities
    )
    where rn = 1
),

-- attach opportunity data to converted leads
leads_with_opportunities as (
    select
        lwc.*,

        -- opportunity details (only for converted leads)
        o.opportunity_id,
        o.stage                                   as opportunity_stage,
        round(cast(o.amount as numeric), 2)         as opportunity_amount,
        round(cast(o.weighted_amount as numeric), 2) as weighted_amount,
        o.is_won,
        o.is_lost,
        o.is_open,
        o.close_date,
        o.probability,

        -- derived
        case
            when lwc.campaign_id is not null then 'campaign'
            else 'organic'
        end as attribution_type,

        case
            when o.is_won = true then 'closed_won'
            when o.is_lost = true then 'closed_lost'
            when lwc.is_converted = true then 'in_pipeline'
            else 'not_converted'
        end as lead_outcome

    from leads_with_campaigns lwc
    left join deduped_opportunities o on lwc.lead_id = o.lead_id
)

select * from leads_with_opportunities
