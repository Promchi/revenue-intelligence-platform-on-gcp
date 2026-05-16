with leads_with_campaigns as (
    select * from {{ ref('int_leads_with_campaigns') }}
),

accounts as (
    select
        account_id,
        account_name,
        tier,
        tier_rank,
        industry,
    from {{ ref('stg_crm__accounts') }}
),

opportunity_activities as (
    select * from {{ ref('int_sales_activity') }}
),

lead_summary as (
    select
        -- lead grain
        lwc.lead_id,
        lwc.contact_id,
        lwc.account_id,

        -- campaign
        lwc.campaign_id,
        lwc.campaign_name,
        lwc.campaign_type,
        lwc.channel,

        -- lead attributes
        lwc.lead_source,
        lwc.lead_status,
        lwc.assigned_rep,
        lwc.attribution_type,
        lwc.lead_outcome,
        lwc.lead_created_at,
        lwc.converted_at,
        lwc.is_converted,
        lwc.is_conversion_date_missing,
        lwc.days_to_convert,

        -- qualification
        lwc.is_decision_maker,
        lwc.budget,
        lwc.actual_spend,
        lwc.budget_utilisation_pct,
        lwc.is_spend_missing,

        -- opportunity
        lwc.opportunity_id,
        lwc.opportunity_stage,
        lwc.opportunity_amount,
        lwc.weighted_amount,
        lwc.is_won,
        lwc.is_lost,
        lwc.is_open,
        lwc.close_date,
        lwc.probability,

        -- funnel stage
        case
            when lwc.is_won  then '4_closed_won'
            when lwc.is_lost then '4_closed_lost'
            when lwc.is_open then '3_in_pipeline'
            when lwc.is_converted then '2_converted'
            else '1_lead'
        end as funnel_stage

    from leads_with_campaigns lwc
),

funnel_with_engagement as (
    select
        -- base funnel
        acc.account_name,
        acc.tier,
        acc.tier_rank,
        acc.industry,
        ls.lead_id,
        ls.contact_id,
        ls.account_id,
        ls.campaign_id,
        ls.campaign_name,
        ls.campaign_type,
        ls.channel,
        ls.lead_source,
        ls.lead_status,
        ls.assigned_rep,
        ls.attribution_type,
        ls.lead_outcome,
        ls.lead_created_at,
        ls.converted_at,
        ls.is_converted,
        ls.days_to_convert,
        ls.is_decision_maker,
        ls.budget,
        ls.actual_spend,
        ls.budget_utilisation_pct,

        -- opportunity
        ls.opportunity_id,
        ls.opportunity_stage,
        ls.opportunity_amount,
        ls.weighted_amount,
        ls.is_won,
        ls.is_lost,
        ls.is_open,
        ls.close_date,
        ls.probability,
        ls.funnel_stage,

        -- engagement
        coalesce(oa.total_activities, 0)      as total_activities,
        coalesce(oa.high_touch_activities, 0) as high_touch_activities,
        coalesce(oa.positive_outcomes, 0)     as positive_outcomes,
        coalesce(oa.total_calls, 0)           as total_calls,
        coalesce(oa.total_meetings, 0)        as total_meetings,
        coalesce(oa.total_demos, 0)           as total_demos,
        coalesce(oa.total_emails, 0)          as total_emails,
        coalesce(oa.reps_involved, 0)         as reps_involved,
        oa.avg_activity_duration,
        oa.positive_outcome_rate,
        oa.engagement_quality,
        oa.days_since_last_activity,
        oa.latest_activity_date,
        oa.first_activity_date,

        -- deal velocity: days from lead creation to close
        case
            when ls.is_won = true 
            and ls.close_date is not null
            and date_diff(ls.close_date, cast(ls.lead_created_at as date), day) >= 0
            then date_diff(
                ls.close_date,
                cast(ls.lead_created_at as date),
                day
            )
        end as days_lead_to_close,

        -- velocity: conversion → close
        case
            when ls.is_won = true
            and ls.converted_at is not null
            and ls.close_date is not null
            and date_diff(ls.close_date, cast(ls.converted_at as date), day) >= 0
            then date_diff(
                ls.close_date,
                cast(ls.converted_at as date),
                day
            )
        end as days_convert_to_close,

        -- spend
        case
            when ls.actual_spend is not null
             and ls.actual_spend > 0
            then round(cast(ls.actual_spend as numeric), 2)
        end as campaign_spend,

        -- ROI
        case
            when ls.actual_spend is not null
             and ls.actual_spend > 0
             and ls.is_won = true
            then round(
                cast(ls.opportunity_amount as numeric) /
                nullif(cast(ls.actual_spend as numeric), 0)
            , 2)
        end as revenue_per_spend,

        current_timestamp() as mart_updated_at

    from lead_summary ls
    left join opportunity_activities oa
        on ls.opportunity_id = oa.opportunity_id
    left join accounts acc
        on ls.account_id = acc.account_id
)

select * from funnel_with_engagement
