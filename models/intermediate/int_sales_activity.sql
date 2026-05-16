with activities as (
    select * from {{ ref('stg_crm__activities') }}
    where is_date_missing = false
    and account_id is not null
),

opportunities as (
    select * from {{ ref('stg_crm__opportunities') }}
),

accounts as (
    select
        account_id,
        account_name,
        tier,
        tier_rank
    from {{ ref('stg_crm__accounts') }}
),

-- aggregate activity metrics per opportunity
opportunity_activities as (
    select
        opportunity_id,
        account_id,
        count(activity_id)                        as total_activities,
        countif(is_high_touch)                    as high_touch_activities,
        countif(is_positive_outcome)              as positive_outcomes,
        countif(activity_type = 'call')           as total_calls,
        countif(activity_type = 'meeting')        as total_meetings,
        countif(activity_type = 'demo')           as total_demos,
        countif(activity_type = 'email')          as total_emails,
        count(distinct assigned_rep)              as reps_involved,
        avg(duration_minutes)                     as avg_activity_duration,
        max(activity_date)                        as latest_activity_date,
        min(activity_date)                        as first_activity_date,

        -- engagement rate
        round(
            countif(is_positive_outcome) /
            nullif(count(activity_id), 0) * 100
        , 2) as positive_outcome_rate

    from activities
    where opportunity_id is not null
    group by opportunity_id, account_id
),

-- aggregate activity metrics per account (regardless of opportunity)
account_activities as (
    select
        account_id,
        count(activity_id)                        as total_account_activities,
        countif(is_high_touch)                    as account_high_touch_count,
        max(activity_date)                        as latest_account_activity_date,
        count(distinct assigned_rep)              as total_reps_engaged
    from activities
    group by account_id
),

-- join to opportunities
joined as (
    select
        o.opportunity_id,
        o.account_id,
        o.stage,
        round(cast(o.amount as numeric), 2)          as amount,
        round(cast(o.weighted_amount as numeric), 2) as weighted_amount,
        o.probability,
        o.is_won,
        o.is_lost,
        o.is_open,
        o.close_date,
        o.created_at                              as opportunity_created_at,

        -- account context
        a.account_name,
        a.tier,
        a.tier_rank,

        -- opportunity-level activity
        coalesce(oa.total_activities, 0)          as total_activities,
        coalesce(oa.high_touch_activities, 0)     as high_touch_activities,
        coalesce(oa.positive_outcomes, 0)         as positive_outcomes,
        coalesce(oa.total_calls, 0)               as total_calls,
        coalesce(oa.total_meetings, 0)            as total_meetings,
        coalesce(oa.total_demos, 0)               as total_demos,
        coalesce(oa.total_emails, 0)              as total_emails,
        coalesce(oa.reps_involved, 0)             as reps_involved,
        oa.avg_activity_duration,
        oa.positive_outcome_rate,
        oa.latest_activity_date,
        oa.first_activity_date,

        -- account-level activity
        coalesce(aa.total_account_activities, 0)  as total_account_activities,
        coalesce(aa.account_high_touch_count, 0)  as account_high_touch_count,
        aa.latest_account_activity_date,
        coalesce(aa.total_reps_engaged, 0)        as total_reps_engaged,

        -- days since last activity
        date_diff(
            current_date(),
            oa.latest_activity_date,
            day
        ) as days_since_last_activity,

        -- engagement quality band
        case
            when coalesce(oa.total_activities, 0) = 0      then 'no_engagement'
            when coalesce(oa.high_touch_activities, 0) >= 5 then 'high'
            when coalesce(oa.high_touch_activities, 0) >= 2 then 'medium'
            else 'low'
        end as engagement_quality

    from opportunities o
    left join account_activities aa  on o.account_id    = aa.account_id
    left join opportunity_activities oa on o.opportunity_id = oa.opportunity_id
    left join accounts a             on o.account_id    = a.account_id
)

select * from joined
    qualify row_number() over (
        partition by opportunity_id 
        order by latest_activity_date desc
        ) = 1
